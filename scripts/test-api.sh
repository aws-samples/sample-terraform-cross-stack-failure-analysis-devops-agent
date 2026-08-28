#!/usr/bin/env bash
# Smoke-tests the API. Pass the API URL as the first arg, or set API_URL.
# Run repeatedly to drive Lambda invocations after the fault is injected,
# so the error-rate alarm crosses threshold.

set -euo pipefail

API_URL="${1:-${API_URL:-}}"
if [[ -z "$API_URL" ]]; then
  echo "Usage: $0 <api_url>   (or set API_URL env var)"
  exit 1
fi

echo "=== POST /items ==="
curl -sS -X POST "$API_URL/items" \
  -H "Content-Type: application/json" \
  -d '{"id":"item-001","name":"Test Item","price":"29.99"}'
echo

echo "=== GET /items/item-001 ==="
curl -sS "$API_URL/items/item-001"
echo

echo "=== GET /items ==="
curl -sS "$API_URL/items"
echo
