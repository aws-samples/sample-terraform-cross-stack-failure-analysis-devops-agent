"""
Webhook Bridge Lambda

Receives CloudWatch alarm events via SNS, constructs an incident payload
matching the DevOps Agent webhook schema, signs it with HMAC-SHA256, and
POSTs it to the DevOps Agent webhook endpoint.

Signing method (from DevOps Agent docs):
1. Create HMAC-SHA256 with the secret key
2. Update with "timestamp:payload" (UTF-8)
3. Digest as Base64
4. Send as x-amzn-event-signature header with x-amzn-event-timestamp
"""

import base64
import hashlib
import hmac
import json
import os
import urllib.request
import uuid
from datetime import datetime, timezone

import boto3

ssm = boto3.client("ssm")

# Cache params across warm invocations
_webhook_url = None
_hmac_secret = None


def _get_param(name):
    """Fetch a SecureString parameter from SSM Parameter Store."""
    try:
        resp = ssm.get_parameter(Name=name, WithDecryption=True)
        return resp["Parameter"]["Value"]
    except ssm.exceptions.ParameterNotFound:
        raise ValueError(f"Required SSM parameter not found: {name}")
    except Exception as e:
        raise RuntimeError(f"Failed to retrieve SSM parameter {name}: {e}")


def _load_secrets():
    """Load webhook URL and HMAC secret, caching for Lambda reuse."""
    global _webhook_url, _hmac_secret
    if _webhook_url is None:
        if "WEBHOOK_URL_PARAM" not in os.environ:
            raise ValueError("Missing required environment variable: WEBHOOK_URL_PARAM")
        _webhook_url = _get_param(os.environ["WEBHOOK_URL_PARAM"])
        # Defense-in-depth: guard against a mis-set parameter (only allow HTTPS)
        if not _webhook_url.startswith("https://"):
            raise ValueError("Webhook URL must use https://")
    if _hmac_secret is None:
        if "HMAC_SECRET_PARAM" not in os.environ:
            raise ValueError("Missing required environment variable: HMAC_SECRET_PARAM")
        _hmac_secret = _get_param(os.environ["HMAC_SECRET_PARAM"])
    return _webhook_url, _hmac_secret


def _map_alarm_to_action(new_state):
    """Map CloudWatch alarm state to DevOps Agent incident action."""
    if new_state == "ALARM":
        return "created"
    elif new_state == "OK":
        return "resolved"
    else:
        return "updated"


def _sign_payload(secret, timestamp, payload_str):
    """
    Sign using DevOps Agent's expected method:
    HMAC-SHA256(secret, "timestamp:payload") → Base64
    """
    message = f"{timestamp}:{payload_str}"
    sig = hmac.new(
        secret.encode("utf-8"),
        message.encode("utf-8"),
        hashlib.sha256,
    ).digest()
    return base64.b64encode(sig).decode("utf-8")


def handler(event, context):
    """Lambda entry point — processes one or more SNS records."""
    webhook_url, hmac_secret = _load_secrets()

    # Safely extract account ID from Lambda ARN
    arn_parts = context.invoked_function_arn.split(":")
    account_id = arn_parts[4] if len(arn_parts) > 4 else "unknown"

    for record in event.get("Records", []):
        try:
            sns_message = json.loads(record["Sns"]["Message"])
        except (json.JSONDecodeError, KeyError) as e:
            print(f"ERROR: Invalid SNS message format: {e!r}")
            continue

        alarm_name = sns_message.get("AlarmName", "Unknown Alarm")
        new_state = sns_message.get("NewStateValue", "ALARM")
        reason = sns_message.get("NewStateReason", "")
        region = sns_message.get("Region", "us-east-1")
        alarm_timestamp = sns_message.get("StateChangeTime", "")

        # Construct incident payload matching DevOps Agent schema
        payload_dict = {
            "eventType": "incident",
            "incidentId": f"{alarm_name}-{uuid.uuid4().hex[:8]}",
            "action": _map_alarm_to_action(new_state),
            "priority": "HIGH",
            "title": f"CloudWatch Alarm: {alarm_name} is in {new_state} state",
            "description": reason,
            "timestamp": alarm_timestamp,
            "service": "cloudwatch",
            "data": {
                "alarmName": alarm_name,
                "state": new_state,
                "reason": reason,
                "region": region,
                "accountId": account_id,
                "source": "cloudwatch-alarm",
            },
        }

        payload_str = json.dumps(payload_dict)
        payload_bytes = payload_str.encode("utf-8")

        # Generate ISO timestamp and sign
        timestamp = datetime.now(timezone.utc).isoformat()
        signature = _sign_payload(hmac_secret, timestamp, payload_str)

        # POST to DevOps Agent webhook
        req = urllib.request.Request(
            webhook_url,
            data=payload_bytes,
            headers={
                "Content-Type": "application/json",
                "x-amzn-event-timestamp": timestamp,
                "x-amzn-event-signature": signature,
            },
            method="POST",
        )

        try:
            resp = urllib.request.urlopen(req, timeout=10)
            print(f"Webhook response: {resp.status} for alarm={alarm_name}")
        except Exception as exc:
            print(f"ERROR posting to webhook: {exc!r}")
            raise

    return {"statusCode": 200, "body": json.dumps({"message": "Webhook(s) triggered"})}
