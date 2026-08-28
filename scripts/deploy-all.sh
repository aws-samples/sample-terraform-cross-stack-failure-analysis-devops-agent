#!/usr/bin/env bash
# Deploys all four stacks in dependency order.
# Requires: AWS creds configured, S3 backend buckets/locks created, terraform >= 1.6.
#
# Usage:
#   TF_STATE_BUCKET=my-state-bucket scripts/deploy-all.sh
#
# Optional:
#   SKIP_DEVOPS_AGENT=1  — skip the DevOps Agent stack (useful if webhook URL isn't ready yet)

set -euo pipefail

if [[ -z "${TF_STATE_BUCKET:-}" ]]; then
  echo "TF_STATE_BUCKET env var is required (the S3 bucket holding remote state files)."
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> [1/4] Networking"
cd "$ROOT/stacks/networking"
terraform init -reconfigure
terraform apply -auto-approve

echo "==> [2/4] Data + Monitoring"
cd "$ROOT/stacks/data-monitoring"
terraform init -reconfigure
terraform apply -auto-approve

echo "==> [3/4] Compute (Lambda + API Gateway)"
cd "$ROOT/stacks/compute"
terraform init -reconfigure
terraform apply -auto-approve -var "tf_state_bucket=${TF_STATE_BUCKET}"

if [[ "${SKIP_DEVOPS_AGENT:-0}" == "1" ]]; then
  echo ""
  echo "==> [4/4] DevOps Agent — SKIPPED (SKIP_DEVOPS_AGENT=1)"
else
  echo "==> [4/4] DevOps Agent (Agent Space + Webhook Bridge)"
  if ! ALARMS_SNS_ARN=$(terraform -chdir="$ROOT/stacks/data-monitoring" output -raw alarms_sns_topic_arn 2>/dev/null); then
    echo "ERROR: Failed to retrieve alarms_sns_topic_arn from data-monitoring stack."
    echo "Ensure the data-monitoring stack was deployed successfully."
    exit 1
  fi
  cd "$ROOT/devops-agent"
  terraform init -reconfigure
  terraform apply -auto-approve -var "alarms_sns_topic_arn=${ALARMS_SNS_ARN}"
fi

echo ""
echo "========================================="
echo "API endpoint:"
if ! terraform -chdir="$ROOT/stacks/compute" output -raw api_endpoint 2>/dev/null; then
  echo "ERROR: Failed to retrieve API endpoint from compute stack."
fi
echo ""
echo "========================================="
echo ""
echo "NEXT STEPS (if DevOps Agent was deployed):"
echo "  1. Open the Agent Space in the AWS console"
echo "  2. Go to Capabilities → Webhook → Generate"
echo "  3. Update SSM parameters with the generated values:"
echo "     aws ssm put-parameter --name /devops-agent/cross-stack-demo/webhook-url --value <URL> --type SecureString --overwrite"
echo "     aws ssm put-parameter --name /devops-agent/cross-stack-demo/hmac-secret --value <SECRET> --type SecureString --overwrite"
echo "  4. Configure tag filters in Agent Space:"
echo "     devops-agent = cross-stack-demo"
echo "     devops-agent-app = cross-stack-failure-demo"
echo ""
