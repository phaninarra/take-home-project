#!/usr/bin/env sh
set -eu
BASE="${BASE:-http://localhost:8084}"
fails=0
check() {
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (got %s, want %s)\n' "$1" "$2" "$3"; fails=$((fails+1)); fi
}
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

check "health"                  "$(code "$BASE/health")" 200
check "missing program is 400"  "$(code "$BASE/returns")" 400
check "program returns 200"     "$(code -H 'X-Program-Id: PRG-ALPHA' "$BASE/returns")" 200

total=0
for p in PRG-ALPHA PRG-BRAVO PRG-CHARLIE; do
  n=$(curl -s -H "X-Program-Id: $p" "$BASE/returns" | grep -c . || true)
  total=$((total + n))
done
check "all records across programs" "$total" 220

width=$(curl -s -H 'X-Program-Id: PRG-ALPHA' "$BASE/returns" | head -1 | awk '{print length($0)}')
check "record width"            "$width" 91

check "unknown program is empty" "$(curl -s -o /dev/null -w '%{size_download}' -H 'X-Program-Id: PRG-NOPE' "$BASE/returns")" 0

exit "$fails"
