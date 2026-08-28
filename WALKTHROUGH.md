# End-to-End Walkthrough

This guide takes you from a fresh clone to a completed DevOps Agent
investigation. Follow it in order. It includes the gotchas we hit so you
don't have to rediscover them.

Estimated time: ~45 minutes (most of it waiting on Terraform + alarms).

---

## 0. Prerequisites

- An AWS account (this demo was validated on `us-east-1` — DevOps Agent is
  only available there)
- AWS CLI and Terraform installed:
  ```bash
  brew install awscli terraform
  aws --version         # any recent v2
  terraform --version   # >= 1.6
  ```
- AWS credentials configured for an IAM user/role with admin-ish rights:
  ```bash
  aws configure          # or aws configure sso
  aws sts get-caller-identity   # confirm it works
  ```
- DevOps Agent access. On internal Amazon accounts you may see a banner
  asking you to onboard — your account is likely already onboarded, so you
  can ignore "Account already onboarded" errors.

---

## 1. Clone and inspect

```bash
git clone https://github.com/aws-samples/sample-terraform-cross-stack-failure-analysis-devops-agent.git
cd sample-terraform-cross-stack-failure-analysis-devops-agent
```

Structure:
- `stacks/networking` — VPC, subnets, DynamoDB VPC endpoint, Lambda SG (the SG is what breaks)
- `stacks/data-monitoring` — DynamoDB table, SNS topic, two CloudWatch alarms
- `stacks/compute` — Lambda + HTTP API Gateway
- `devops-agent` — Agent Space, IAM role, webhook bridge Lambda
- `scripts` — deploy / test / introduce-failure / restore

---

## 2. Create remote state backend

Terraform needs an S3 bucket and a DynamoDB lock table. Use unique names
(bucket names are globally unique — append your account ID):

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="cross-stack-demo-tf-state-${ACCOUNT_ID}"
LOCKS="cross-stack-demo-tf-locks"

aws s3api create-bucket --bucket "$BUCKET" --region us-east-1
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws dynamodb create-table --table-name "$LOCKS" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1
```

---

## 3. Wire up backends

In each of these files, replace the `REPLACE-ME-tf-state-bucket` and lock table
placeholders with your own bucket and DynamoDB lock table names:
- `stacks/networking/backend.tf`
- `stacks/data-monitoring/backend.tf`
- `stacks/compute/backend.tf`
- `devops-agent/backend.tf`

> Gotcha: the backend values ship as placeholders. You MUST swap them for your
> own bucket/table or `terraform init` will fail.

---

## 4. Set networking values

```bash
cd stacks/networking
cp terraform.tfvars.example terraform.tfvars
```

Confirm the AZs exist in your account:
```bash
aws ec2 describe-availability-zones --region us-east-1 \
  --query "AvailabilityZones[].ZoneName" --output text
```
Edit `terraform.tfvars` if `us-east-1a`/`us-east-1b` aren't valid for you.
Return to repo root: `cd ../..`

---

## 5. Deploy the three application stacks

Deploy in order. Skip the DevOps Agent stack for now (you need to generate
the webhook first).

```bash
# 1. Networking
terraform -chdir=stacks/networking init -reconfigure
terraform -chdir=stacks/networking apply -auto-approve -var-file=terraform.tfvars

# 2. Data + Monitoring
terraform -chdir=stacks/data-monitoring init -reconfigure
terraform -chdir=stacks/data-monitoring apply -auto-approve

# 3. Compute (needs the state bucket name)
terraform -chdir=stacks/compute init -reconfigure
terraform -chdir=stacks/compute apply -auto-approve -var "tf_state_bucket=${BUCKET}"
```

> Gotcha: the VPC-attached Lambda takes 1-2 minutes to create (ENI setup).
> If your terminal times out mid-apply, just re-run the same apply command —
> Terraform picks up where it left off. If you hit a state-lock error from a
> killed run, `terraform -chdir=stacks/compute force-unlock <LOCK_ID>`.

Grab the API URL:
```bash
API_URL=$(terraform -chdir=stacks/compute output -raw api_endpoint)
echo "$API_URL"
```

---

## 6. Smoke test (confirm the happy path)

```bash
curl -sS -X POST "$API_URL/items" \
  -H "Content-Type: application/json" \
  -d '{"id":"item-001","name":"Test Item","price":"29.99"}'

curl -sS "$API_URL/items/item-001"
```

You should get `{"message": "Item created", ...}` then the item back.

> Gotcha: `price` is a STRING (`"29.99"`), not a number. DynamoDB via boto3
> rejects Python floats. The provided `test-api.sh` already uses a string.

---

## 7. Deploy the DevOps Agent stack

```bash
ALARMS_SNS_ARN=$(terraform -chdir=stacks/data-monitoring output -raw alarms_sns_topic_arn)
terraform -chdir=devops-agent init -reconfigure
terraform -chdir=devops-agent apply -auto-approve -var "alarms_sns_topic_arn=${ALARMS_SNS_ARN}"
```

> Gotcha: the account association can fail on first apply with "Invalid STS
> role configuration" — this is a race between the IAM trust policy
> propagating and the association being created. Just re-run the same apply
> command and it succeeds.

---

## 8. Generate the webhook and store credentials

1. Open the AWS console → **DevOps Agent** → your Agent Space
   (`cross-stack-failure-demo`)
2. Go to **Configure webhook** → step through with defaults →
   **Generate URL and credentials**
3. Copy the **Webhook URL** and **Secret key** (download the .csv — they're
   not retrievable after you leave the page)
4. Store them in SSM:

```bash
aws ssm put-parameter --name /devops-agent/cross-stack-demo/webhook-url \
  --value "<WEBHOOK_URL>" --type SecureString --overwrite --region us-east-1

aws ssm put-parameter --name /devops-agent/cross-stack-demo/hmac-secret \
  --value "<SECRET_KEY>" --type SecureString --overwrite --region us-east-1
```

5. Force the bridge Lambda to pick up the new values (it caches on cold
   start, so bump an env var to force a fresh container):

```bash
aws lambda update-function-configuration \
  --function-name cross-stack-demo-webhook-bridge \
  --environment 'Variables={WEBHOOK_URL_PARAM=/devops-agent/cross-stack-demo/webhook-url,HMAC_SECRET_PARAM=/devops-agent/cross-stack-demo/hmac-secret,CACHE_BUST=1}' \
  --region us-east-1
```

> Gotcha: if you skip step 5, the Lambda keeps the old placeholder value and
> you'll see `unknown url type: 'PLACEHOLDER-...'` in its logs.

---

## 9. Configure the web app (first time only)

In the Agent Space console:
1. Go to the **Access** tab → **Configure web app**
2. Leave "Auto-create a new DevOps Agent role" selected → **Configure web app**
3. **Launch via IAM** to open the DevOps Agent web app

You don't need to configure tag filters — the agent discovers resources
automatically via the account association (you'll see "Relationships mapped"
climbing on the Agent Space page).

---

## 10. Inject the failure

```bash
./scripts/introduce-failure.sh
```

This flips the Lambda SG egress rule from "allow to DynamoDB prefix list" to
"allow to VPC CIDR only", blocking the path to DynamoDB.

Confirm it's broken:
```bash
curl -sS --max-time 35 "$API_URL/items/item-001"
# => {"error": "Connect timeout on endpoint URL: https://dynamodb.us-east-1.amazonaws.com/"}
```

Drive a bit of traffic:
```bash
for i in 1 2 3 4 5 6; do ./scripts/test-api.sh "$API_URL"; done
```

---

## 11. Trigger the alarm → webhook → investigation

The DynamoDB read-capacity-drop alarm fires on its own within a few minutes
of low traffic. To trigger it immediately for a demo:

```bash
aws cloudwatch set-alarm-state \
  --alarm-name cross-stack-demo-dynamodb-read-capacity-drop \
  --state-value OK --state-reason "reset" --region us-east-1
sleep 5
aws cloudwatch set-alarm-state \
  --alarm-name cross-stack-demo-dynamodb-read-capacity-drop \
  --state-value ALARM --state-reason "DynamoDB reads dropped to zero" --region us-east-1
```

Confirm the bridge Lambda delivered it (look for `Webhook response: 200`):
```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/cross-stack-demo-webhook-bridge \
  --start-time $(($(date +%s) * 1000 - 120000)) \
  --region us-east-1 --query 'events[].message' --output text
```

> Gotcha: the Lambda **error-rate** alarm often stays OK. That's expected —
> our function catches the DynamoDB timeout and returns HTTP 500, which does
> NOT increment the Lambda `Errors` metric (that only counts unhandled
> crashes/timeouts). The DynamoDB capacity alarm is enough to drive the demo.

---

## 12. Watch the investigation

In the DevOps Agent web app → **Incidents**, you'll see the investigation
triggered by "Event Channel". Open it and watch the timeline:
- 5 parallel subagents (Lambda metrics, DynamoDB metrics, Lambda logs,
  CloudTrail, VPC networking)
- It identifies the security group egress change as the root cause
- Check the **Root cause**, **Mitigation plan**, and **Summary** tabs
- The **Copy spec** button on the Mitigation plan gives the agent-ready spec
  you can hand to Kiro

---

## 13. Restore and (optionally) tear down

Restore to working state:
```bash
./scripts/restore.sh
curl -sS "$API_URL/items/item-001"   # should return the item again
```

Tear everything down when finished:
```bash
terraform -chdir=devops-agent destroy -auto-approve \
  -var "alarms_sns_topic_arn=$(terraform -chdir=stacks/data-monitoring output -raw alarms_sns_topic_arn)"
terraform -chdir=stacks/compute destroy -auto-approve -var "tf_state_bucket=${BUCKET}"
terraform -chdir=stacks/data-monitoring destroy -auto-approve
terraform -chdir=stacks/networking destroy -auto-approve
```

---

## Quick gotcha reference

| Symptom | Cause / Fix |
|---------|-------------|
| `terraform init` uses wrong state | You didn't swap bucket/table in `backend.tf` |
| Compute apply times out | VPC Lambda ENI setup is slow — re-run apply |
| State lock error after a killed run | `terraform force-unlock <LOCK_ID>` |
| POST /items returns float error | Use a string price, not a number |
| Association fails: "Invalid STS role" | IAM trust policy race — re-run apply |
| Webhook log: `unknown url type: PLACEHOLDER` | Update SSM params + bump a Lambda env var to force cold start |
| Webhook returns 403 | Signing must be HMAC-SHA256 over `timestamp:payload`, Base64, headers `x-amzn-event-signature` + `x-amzn-event-timestamp` |
| Lambda error-rate alarm stays OK | Expected — handled 500s don't count as Lambda `Errors`; rely on the DynamoDB capacity alarm |
