#!/usr/bin/env bash
# Flips the security group egress rule in the networking stack to the
# "restricted" mode — blocking Lambda's path to the DynamoDB VPC endpoint.
#
# This is the breaking change the blog post centers on.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Tightening security group egress in stacks/networking (restrict_egress=true)"
cd "$ROOT/stacks/networking"
terraform apply -auto-approve -var "restrict_egress=true"

echo ""
echo "Done. Egress rule now restricted to VPC CIDR — Lambda cannot reach DynamoDB VPC endpoint."
echo "Generate traffic against the API and wait ~1-2 minutes for CloudWatch alarms to fire."
