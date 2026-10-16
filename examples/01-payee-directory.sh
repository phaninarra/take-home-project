#!/usr/bin/env sh
# payee-directory — JSON over HTTP, static API key in a header.
set -eu

BASE="${BASE:-http://localhost:8081}"
API_KEY="${API_KEY:-pd_live_7f3c9a2e5b81}"

echo "--- health (no auth required) ---"
curl -sS "$BASE/health"
echo

echo "--- one payee ---"
curl -sS -H "X-Api-Key: $API_KEY" "$BASE/payees/PY-00140"
echo

echo "--- payees on one program (truncated, it is a long list) ---"
curl -sS -H "X-Api-Key: $API_KEY" "$BASE/payees?program=PRG-ALPHA" | cut -c1-200
echo "..."

echo "--- what a rejected call looks like ---"
curl -sS "$BASE/payees/PY-00140"
echo
