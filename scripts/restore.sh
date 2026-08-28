#!/usr/bin/env bash
# Reverts the networking stack to the working egress rule.
# Useful while iterating; in the blog flow you'd do this via Kiro-generated diff.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Restoring security group egress in stacks/networking (restrict_egress=false)"
cd "$ROOT/stacks/networking"
terraform apply -auto-approve -var "restrict_egress=false"

echo ""
echo "Egress rule restored. Lambda can now reach DynamoDB via VPC endpoint."
