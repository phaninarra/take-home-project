#!/usr/bin/env sh
# settlement-returns — fixed-width text over HTTP.
#
# There is no authentication. The service returns whatever program you name
# in the X-Program-Id header.
#
# Record layout is 91 characters, described in ./returns-layout.md.
set -eu

BASE="${BASE:-http://localhost:8084}"

echo "--- health ---"
curl -sS "$BASE/health"

echo "--- returns for one program (first three records) ---"
curl -sS -H "X-Program-Id: PRG-ALPHA" "$BASE/returns" | head -3

echo "--- one payment's return ---"
curl -sS -H "X-Program-Id: PRG-ALPHA" "$BASE/returns?paymentId=PAY-CAE5E8DC"

echo "--- pulling the fields out of a record with cut ---"
curl -sS -H "X-Program-Id: PRG-ALPHA" "$BASE/returns" | head -1 | while read -r line; do
  printf 'trace       %s\n' "$(printf '%s' "$line" | cut -c1-15)"
  printf 'payment     %s\n' "$(printf '%s' "$line" | cut -c16-27)"
  printf 'program     %s\n' "$(printf '%s' "$line" | cut -c28-38)"
  printf 'return code %s\n' "$(printf '%s' "$line" | cut -c39-41)"
  printf 'return date %s\n' "$(printf '%s' "$line" | cut -c42-49)"
  printf 'amount      %s\n' "$(printf '%s' "$line" | cut -c50-61)"
  printf 'reason      %s\n' "$(printf '%s' "$line" | cut -c62-91)"
done

echo "--- missing the header ---"
curl -sS "$BASE/returns"
