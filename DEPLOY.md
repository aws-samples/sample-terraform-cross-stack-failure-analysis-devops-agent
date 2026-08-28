# Deploy Guide

Short, copy-paste-friendly steps to stand up the three Terraform stacks, inject
the failure, and tear it back down.

## 0. Prereqs

- AWS account + creds (`aws configure` or `AWS_PROFILE`) with admin-ish rights
- Terraform >= 1.6 (`terraform version`)
- An S3 bucket and a DynamoDB lock table for remote state

If you don't have a state bucket yet:

```bash
aws s3api create-bucket --bucket <your-tf-state-bucket> --region us-east-1
aws s3api put-bucket-versioning --bucket <your-tf-state-bucket> \
  --versioning-configuration Status=Enabled

aws dynamodb create-table --table-name <your-tf-locks> \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1
```

## 1. Wire up backends

In each of these files, replace `REPLACE-ME-tf-state-bucket` and
`REPLACE-ME-tf-locks` with your bucket and lock table:

- `stacks/networking/backend.tf`
- `stacks/data-monitoring/backend.tf`
- `stacks/compute/backend.tf`
- `devops-agent/backend.tf`

## 2. Set networking values

```bash
cd stacks/networking
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set `region`, `vpc_cidr`, `private_subnet_cidrs`,
`azs`. Confirm AZs exist in your account:

```bash
aws ec2 describe-availability-zones --region us-east-1 \
  --query "AvailabilityZones[].ZoneName" --output text
```

Return to repo root: `cd ../..`

## 3. Deploy all three stacks

```bash
chmod +x scripts/*.sh
TF_STATE_BUCKET=<your-tf-state-bucket> ./scripts/deploy-all.sh
```

The script applies networking → data-monitoring → compute and prints the API
URL at the end.

## 4. Smoke test

```bash
API_URL=$(terraform -chdir=stacks/compute output -raw api_endpoint)
./scripts/test-api.sh "$API_URL"
```

You should see a created item, a single-item read, and a scan. If anything
fails here, fix it before injecting the fault.

## 5. Deploy DevOps Agent stack

The deploy script handles this automatically (step 4/4), but if running
manually:

```bash
ALARMS_SNS_ARN=$(terraform -chdir=stacks/data-monitoring output -raw alarms_sns_topic_arn)
cd devops-agent
terraform init -reconfigure
terraform apply -var "alarms_sns_topic_arn=$ALARMS_SNS_ARN"
```

Then complete the manual console steps:

1. Open the Agent Space (`cross-stack-failure-demo`) in the AWS console
2. Go to **Capabilities → Webhook → Generate** to create a webhook URL and HMAC secret
3. Store them in SSM:

```bash
aws ssm put-parameter --name /devops-agent/cross-stack-demo/webhook-url \
  --value "<WEBHOOK_URL>" --type SecureString --overwrite

aws ssm put-parameter --name /devops-agent/cross-stack-demo/hmac-secret \
  --value "<HMAC_SECRET>" --type SecureString --overwrite
```

4. Configure tag filters in the Agent Space so it discovers your resources:
   - `devops-agent = cross-stack-demo`
   - `devops-agent-app = cross-stack-failure-demo`

## 6. Inject the failure

```bash
./scripts/introduce-failure.sh
```

Re-applies the networking stack with `restrict_egress=true`. The Lambda SG
egress rule flips from "allow to DynamoDB prefix list" to "allow to VPC CIDR
only", which kills the path to DynamoDB.

Drive traffic so the Lambda error alarm crosses threshold:

```bash
for i in 1 2 3 4 5 6; do ./scripts/test-api.sh "$API_URL"; done
```

Within ~1–2 minutes both alarms (`*-lambda-error-rate` and
`*-dynamodb-read-capacity-drop`) should go ALARM and notify DevOps Agent.

## 7. Restore

Quick path while iterating:

```bash
./scripts/restore.sh
```

Blog-flow path: take the DevOps Agent mitigation spec into Kiro, let it
generate the Terraform diff, then `terraform apply`.

## 8. Tear down

```bash
terraform -chdir=devops-agent destroy -auto-approve \
  -var "alarms_sns_topic_arn=$(terraform -chdir=stacks/data-monitoring output -raw alarms_sns_topic_arn)"
terraform -chdir=stacks/compute destroy -auto-approve \
  -var "tf_state_bucket=<your-tf-state-bucket>"
terraform -chdir=stacks/data-monitoring destroy -auto-approve
terraform -chdir=stacks/networking destroy -auto-approve
```

## Common snags

- **`terraform init` fails on backend** — you forgot to swap the placeholder bucket/table names in `backend.tf`.
- **AZ doesn't exist** — older accounts have different AZ letters; run the `describe-availability-zones` command above and update `azs` in `terraform.tfvars`.
- **Compute apply can't read remote state** — make sure you passed `TF_STATE_BUCKET` to `deploy-all.sh`; the compute stack uses it for `terraform_remote_state` lookups.
- **Alarms never fire** — the DynamoDB capacity alarm needs ~3 minutes of low traffic; keep hitting the API or wait it out.
