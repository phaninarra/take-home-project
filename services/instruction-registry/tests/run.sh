#!/usr/bin/env sh
set -eu
BASE="${BASE:-http://localhost:8082}"
KEY_ID="${KEY_ID:-ir_key_01}"
SECRET="${SHARED_SECRET:-ir_secret_b82f1e6d}"
fails=0
check() {
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (got %s, want %s)\n' "$1" "$2" "$3"; fails=$((fails+1)); fi
}
signed_code() {
  method="$1"; path="$2"; body="$3"; ts="${4:-$(date +%s)}"
  hash="$(printf '%s' "$body" | openssl dgst -sha256 | awk '{print $NF}')"
  sig="$(printf '%s\n%s\n%s\n%s' "$method" "$path" "$ts" "$hash" \
    | openssl dgst -sha256 -hmac "$SECRET" -binary | openssl base64 -A)"
  if [ "$method" = "POST" ]; then
    curl -s -o /dev/null -w '%{http_code}' -X POST \
      -H "X-Key-Id: $KEY_ID" -H "X-Timestamp: $ts" -H "Authorization: HMAC-SHA256 $sig" \
      -H 'Content-Type: application/xml' --data-binary "$body" "$BASE$path"
  else
    curl -s -o /dev/null -w '%{http_code}' \
      -H "X-Key-Id: $KEY_ID" -H "X-Timestamp: $ts" -H "Authorization: HMAC-SHA256 $sig" "$BASE$path"
  fi
}
instruction() {
  printf '<?xml version="1.0"?><Instruction><EndToEndId>%s</EndToEndId><PayeeId>%s</PayeeId><ProgramId>PRG-ALPHA</ProgramId><Amount Ccy="%s">%s</Amount><RequestedDate>2026-09-08</RequestedDate></Instruction>' "$1" "$2" "$3" "$4"
}

check "health needs no signature" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/health")" 200
check "unsigned get is 401"       "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/instructions/E2E-C4DAE8D4")" 401
check "signed get"               "$(signed_code GET /instructions/E2E-C4DAE8D4 '')" 200
check "unknown id is 404"        "$(signed_code GET /instructions/E2E-00000000 '')" 404
check "stale timestamp is 401"   "$(signed_code GET /instructions/E2E-C4DAE8D4 '' "$(( $(date +%s) - 4000 ))")" 401

now="$(date +%s)"
id_a="E2E-$(printf '%08X' "$now")"
id_b="E2E-$(printf '%08X' "$(( now + 1 ))")"
check "create"                   "$(signed_code POST /instructions "$(instruction "$id_a" PY-00042 USD 125000)")" 201
check "duplicate is 409"         "$(signed_code POST /instructions "$(instruction "$id_a" PY-00042 USD 125000)")" 409
check "bad payee is 422"         "$(signed_code POST /instructions "$(instruction "$id_b" bogus USD 125000)")" 422
check "zero amount is 422"       "$(signed_code POST /instructions "$(instruction "$id_b" PY-00042 USD 0)")" 422
check "over ceiling is 422"      "$(signed_code POST /instructions "$(instruction "$id_b" PY-00042 USD 9999999)")" 422
check "non-usd is 422"           "$(signed_code POST /instructions "$(instruction "$id_b" PY-00042 EUR 125000)")" 422
check "malformed xml is 400"     "$(signed_code POST /instructions 'not xml at all')" 400

exit "$fails"
