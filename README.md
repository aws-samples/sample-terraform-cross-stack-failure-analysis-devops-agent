# Cross-Stack Failure Diagnosis with Terraform and AWS DevOps Agent

This sample demonstrates how [AWS DevOps Agent](https://aws.amazon.com/devops/) traces
a root cause across independent Terraform state boundaries. It deploys a small
serverless application split into three separate Terraform stacks, then deliberately
injects a failure where a networking change in one stack silently breaks the
application running in another. DevOps Agent correlates the resulting alarms, maps the
dependency chain, and pinpoints the networking change as the root cause.

> **⚠️ Disclaimer — sample code, not for production.**
> This is demonstration code. It intentionally omits production controls and
> deliberately injects a failure for teaching purposes. It also exposes an
> **unauthenticated** HTTP API. Do not deploy it as-is to a production account without
> additional hardening (authentication, customer-managed KMS keys, longer log
> retention, dead-letter queues, and tighter IAM scoping). See [SECURITY.md](SECURITY.md)
> for the known gaps and recommended hardening steps.

## What this sample demonstrates

- **Multi-stack Terraform** with separate state files, mirroring real-world team
  ownership boundaries (a platform team owns networking; an application team owns
  compute and data).
- **A realistic cross-stack failure**: tightening a security group egress rule in the
  networking stack blocks the application Lambda's path to DynamoDB through a Gateway
  VPC endpoint. The application team sees timeouts and misleading alarms, but the root
  cause lives in a stack they don't own.
- **AWS DevOps Agent setup with Terraform**: Agent Space, IAM trust policy, tag-based
  resource discovery, and a webhook bridge Lambda that forwards CloudWatch alarms with
  HMAC-signed payloads.
- **An end-to-end detect-to-remediate flow**: inject the failure, let DevOps Agent
  diagnose it, then apply the corrected Terraform to restore connectivity.

## Architecture

Three independent Terraform stacks, each with its own state file:

```
stacks/
  networking/        # Stack 1 — VPC, private subnets, Lambda security group,
                     #           DynamoDB Gateway VPC endpoint
  compute/           # Stack 2 — Lambda (in VPC) + HTTP API Gateway
  data-monitoring/   # Stack 3 — DynamoDB table, SNS topic, CloudWatch alarms
devops-agent/        # Optional — Agent Space, IAM role, webhook bridge Lambda
scripts/
  deploy-all.sh
  introduce-failure.sh
  restore.sh
  test-api.sh
```

Request flow when healthy:

```
Client → API Gateway → Lambda (in VPC) → Security Group → DynamoDB VPC endpoint → DynamoDB
```

The compute stack reads the networking stack's outputs (VPC, subnets, security group)
and the data stack's outputs (table name and ARN) via `terraform_remote_state`.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.6
- AWS credentials with permission to create VPC, IAM, Lambda, API Gateway, DynamoDB,
  and CloudWatch resources
- An S3 bucket and a DynamoDB lock table for Terraform remote state (each stack uses
  its own state key in the same bucket)
- To use AWS DevOps Agent: access in `us-east-1` (the agent runs there but can monitor
  resources in any region)

Lambda packaging needs nothing extra — the `archive_file` data source zips the
`lambda/` folder automatically.

## Setup

### 1. Configure the Terraform backend

Update each stack's `backend.tf` with your own S3 bucket and DynamoDB lock table names
before running `terraform init`. Each stack uses a distinct state key.

### 2. Provide networking values

The networking stack ships no default VPC/subnet/AZ values, so you don't collide with
existing CIDRs or pick availability zones that don't exist in your account:

```bash
cd stacks/networking
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set region, vpc_cidr, private_subnet_cidrs, azs
```

The compute and data-monitoring stacks have safe defaults; override them with their
own `terraform.tfvars` only if you want to change the region, table name, or wire up
an SNS email subscription.

## Deploy

The deploy script provisions the stacks in dependency order:

```bash
chmod +x scripts/*.sh
TF_STATE_BUCKET=your-tf-state-bucket scripts/deploy-all.sh
```

Manual order, if you prefer:

1. `stacks/networking` — VPC, subnets, security group, DynamoDB VPC endpoint
2. `stacks/data-monitoring` — DynamoDB table, SNS topic, alarms
3. `stacks/compute` — Lambda + API Gateway

## Verify the working state

```bash
API_URL=$(terraform -chdir=stacks/compute output -raw api_endpoint)
scripts/test-api.sh "$API_URL"
```

A `POST` should return `{"message":"Item created"}`, and a `GET` should return the item.

## Inject the failure

```bash
scripts/introduce-failure.sh
```

This re-applies the networking stack with `restrict_egress=true`, which:

- Removes the security group egress rule allowing TCP/443 to the DynamoDB VPC endpoint
  prefix list, and
- Replaces it with an egress rule scoped to the VPC CIDR (it looks like a routine
  "security tightening" change).

Send traffic again with `scripts/test-api.sh`. Requests now hang and time out at the
30-second Lambda limit. Within about one to two minutes, two CloudWatch alarms fire:

- **Lambda error-rate alarm** — the real symptom.
- **DynamoDB consumed-capacity alarm** — a red herring. Capacity drops because requests
  never reach DynamoDB (blocked at the network layer), not because DynamoDB is broken.

Both alarms publish to an SNS topic that the DevOps Agent webhook bridge Lambda
subscribes to.

## Connect AWS DevOps Agent

The `devops-agent/` stack provisions the Agent Space, IAM trust role, and webhook
bridge Lambda. The webhook URL itself is generated in the DevOps Agent console
(Agent Space → Capabilities → Webhook → Generate). Once you have it:

1. Store the webhook URL and HMAC signing secret in SSM Parameter Store as
   `SecureString` parameters.
2. Deploy the bridge Lambda and subscribe it to the alarms SNS topic.
3. Configure the Agent Space tag filters to match the resource tags used across the
   stacks:
   - `devops-agent = cross-stack-demo`
   - `devops-agent-app = cross-stack-failure-demo`

DevOps Agent then correlates both alarms, walks the dependency chain, inspects
CloudTrail for the recent security group change, and reports the networking change as
the root cause — including a mitigation suggestion to restore the egress rule.

## Restore

```bash
scripts/restore.sh
```

Re-applies the networking stack with `restrict_egress=false`, restoring the egress
rule and returning the application to a healthy state.

## Cleanup

Destroy the stacks in reverse deploy order to avoid dependency errors:

```bash
terraform -chdir=stacks/compute destroy
terraform -chdir=stacks/data-monitoring destroy
terraform -chdir=stacks/networking destroy
```

If you deployed the DevOps Agent stack, destroy it as well:

```bash
terraform -chdir=devops-agent destroy
```

## Security

See [SECURITY.md](SECURITY.md) for the intentional exposures, documented security
debt, and production-hardening recommendations. To report a security issue, follow the
process described in that file — please do not open a public GitHub issue for security
vulnerabilities.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT-0 License. See [LICENSE](LICENSE) for details.
