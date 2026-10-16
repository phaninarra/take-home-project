#!/usr/bin/env sh
# instruction-registry — XML over HTTP, every request must be signed.
#
# The signature is HMAC-SHA256 over four lines joined by \n:
#
#   <HTTP METHOD>
#   <request path>
#   <unix timestamp>
#   <hex sha256 of the request body, or of the empty string for GET>
#
# Send the result base64 encoded, plus the key id and the same timestamp:
#
#   X-Key-Id: ir_key_01
#   X-Timestamp: 1757342400
#   Authorization: HMAC-SHA256 <base64 signature>
#
# Timestamps more than 300 seconds from the server clock are rejected.
set -eu

BASE="${BASE:-http://localhost:8082}"
KEY_ID="${KEY_ID:-ir_key_01}"
SECRET="${SHARED_SECRET:-ir_secret_b82f1e6d}"

sign() {
  method="$1"
  path="$2"
  body="$3"
  timestamp="$(date +%s)"
  body_hash="$(printf '%s' "$body" | openssl dgst -sha256 | awk '{print $NF}')"
  to_sign="$(printf '%s\n%s\n%s\n%s' "$method" "$path" "$timestamp" "$body_hash")"
  signature="$(printf '%s' "$to_sign" | openssl dgst -sha256 -hmac "$SECRET" -binary | openssl base64 -A)"
  printf '%s\t%s' "$timestamp" "$signature"
}

echo "--- health (no signature required) ---"
curl -sS "$BASE/health"

echo "--- signed GET ---"
path="/instructions/E2E-C4DAE8D4"
signed="$(sign GET "$path" "")"
timestamp="$(printf '%s' "$signed" | cut -f1)"
signature="$(printf '%s' "$signed" | cut -f2)"
curl -sS \
  -H "X-Key-Id: $KEY_ID" \
  -H "X-Timestamp: $timestamp" \
  -H "Authorization: HMAC-SHA256 $signature" \
  "$BASE$path"

echo "--- signed POST that creates an instruction ---"
body='<?xml version="1.0" encoding="UTF-8"?><Instruction><EndToEndId>E2E-DEADBEEF</EndToEndId><PayeeId>PY-00042</PayeeId><ProgramId>PRG-ALPHA</ProgramId><Amount Ccy="USD">125000</Amount><RequestedDate>2026-09-08</RequestedDate></Instruction>'
signed="$(sign POST /instructions "$body")"
timestamp="$(printf '%s' "$signed" | cut -f1)"
signature="$(printf '%s' "$signed" | cut -f2)"
curl -sS -X POST \
  -H "X-Key-Id: $KEY_ID" \
  -H "X-Timestamp: $timestamp" \
  -H "Authorization: HMAC-SHA256 $signature" \
  -H "Content-Type: application/xml" \
  --data-binary "$body" \
  "$BASE/instructions"

echo "--- what a bad signature looks like ---"
curl -sS \
  -H "X-Key-Id: $KEY_ID" \
  -H "X-Timestamp: $(date +%s)" \
  -H "Authorization: HMAC-SHA256 not-a-real-signature" \
  "$BASE$path"
