# Security Policy

> **⚠️ This is sample/demonstration code, not production-ready.**
> It intentionally omits several production controls and deliberately injects a
> failure for teaching purposes. Do not deploy it to a production account without
> the hardening described below.

## Reporting a Vulnerability

If you discover a potential security issue in this project, please notify the project
maintainers privately. Please do **not** create a public GitHub issue for security
vulnerabilities. We will work with you to verify and address the issue.

## Known Exposures and Trade-offs

### Unauthenticated HTTP API (intentional for the demo)

The compute stack exposes an HTTP API (`POST /items`, `GET /items`, `GET /items/{id}`)
with **no authorizer**. Anyone with the endpoint URL can read from and write to the
DynamoDB table. This is deliberate to keep the demo simple to exercise.

Mitigation applied in this sample: the API `$default` stage sets bounded throttling
(`throttling_burst_limit = 10`, `throttling_rate_limit = 5`) to limit abuse and
denial-of-wallet exposure. Both Lambdas also set `reserved_concurrent_executions = 10`
to bound blast radius.

**For production:** attach a JWT, IAM, or Lambda authorizer to the routes before
exposing the API.

## Accepted Security Debt

The following items are known gaps, acceptable for a demo, that should be addressed
within 90 days if this pattern is promoted toward production.

| # | Item | Files | If unaddressed | Production recommendation |
|---|------|-------|----------------|---------------------------|
| SD-1 | CloudWatch Logs use AWS-managed key, not a CMK | compute / networking / devops-agent `main.tf` | Cannot enforce key rotation/revocation on the log-group key | Create a CMK (rotation on); set `kms_key_id` on each log group |
| SD-2 | Lambda env vars not CMK-encrypted | compute / devops-agent `main.tf` | Non-secret config only; low risk | Set `kms_key_arn` if env vars ever hold secrets |
| SD-3 | DynamoDB uses AWS-owned key, not a CMK | data-monitoring `main.tf` | Encrypted, but not customer-controlled | Add `server_side_encryption { kms_key_arn }` for sensitive data |
| SD-4 | SSM params use default SecureString key | devops-agent `main.tf` | Secrets encrypted with AWS-managed key (fine for demo) | Set `key_id` to a dedicated CMK; scope key policy to the bridge role |
| SD-5 | No DLQ / on-failure destination on webhook-bridge Lambda | devops-agent `main.tf` | A transient webhook failure silently drops an alarm notification | Add an SQS DLQ / on-failure destination (or SNS redrive policy) |
| SD-6 | CloudWatch log retention = 14 days | 3 log groups | Logs older than 14 days unavailable for forensics | Set `retention_in_days` to your compliance value (e.g., 365) |
| SD-7 | VPC Flow Log IAM uses `Resource: "*"` | networking `main.tf` | Role can write to any log group (wider blast radius) | Scope `CreateLogStream`/`PutLogEvents` to the flow-log group ARN |

## Known False Positive

- **Bandit B310 / Semgrep dynamic-urllib** on `devops-agent/webhook-bridge/handler.py`:
  the request URL comes from an SSM SecureString set by the account operator, not from
  user or event input, so the SSRF/scheme-abuse premise does not apply. As
  defense-in-depth, the handler may additionally validate that the URL uses `https://`.
