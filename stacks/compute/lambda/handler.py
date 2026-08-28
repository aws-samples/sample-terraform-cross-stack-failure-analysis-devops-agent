import json
import os

import boto3
from botocore.config import Config

# Short timeouts so the failure surfaces quickly in logs.
_config = Config(
    connect_timeout=5,
    read_timeout=10,
    retries={"max_attempts": 2},
)

_dynamodb = boto3.resource("dynamodb", config=_config)
_table = _dynamodb.Table(os.environ["TABLE_NAME"])


def handler(event, context):
    method = event.get("httpMethod") or event.get("requestContext", {}).get("http", {}).get("method", "")
    path = event.get("path") or event.get("rawPath", "")

    try:
        if method == "POST" and path.endswith("/items"):
            body = json.loads(event.get("body") or "{}")
            if not body.get("id"):
                return _resp(400, {"error": "Missing required field: id"})
            _table.put_item(Item=body)
            return _ok({"message": "Item created", "id": body.get("id")})

        if method == "GET" and path.endswith("/items"):
            response = _table.scan(Limit=25)
            return _ok(response.get("Items", []))

        if method == "GET" and "/items/" in path:
            item_id = path.rsplit("/", 1)[-1]
            response = _table.get_item(Key={"id": item_id})
            return _ok(response.get("Item", {}))

        return _resp(404, {"message": "Not found"})

    except Exception as exc:  # noqa: BLE001 — we want everything surfaced in logs
        print(f"ERROR: {exc!r}")
        return _resp(500, {"error": str(exc)})


def _ok(payload):
    return _resp(200, payload)


def _resp(status, payload):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(payload, default=str),
    }
