#!/usr/bin/env sh
set -eu
BASE="${BASE:-http://localhost:8081}"
KEY="${API_KEY:-pd_live_7f3c9a2e5b81}"
fails=0
check() {
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (got %s, want %s)\n' "$1" "$2" "$3"; fails=$((fails+1)); fi
}
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

check "health needs no key"        "$(code "$BASE/health")" 200
check "payee needs a key"          "$(code "$BASE/payees/PY-00001")" 401
check "payee with a key"           "$(code -H "X-Api-Key: $KEY" "$BASE/payees/PY-00001")" 200
check "unknown payee is 404"       "$(code -H "X-Api-Key: $KEY" "$BASE/payees/PY-99999")" 404
check "wrong key is 401"           "$(code -H "X-Api-Key: nope" "$BASE/payees/PY-00001")" 401
check "list by program"            "$(code -H "X-Api-Key: $KEY" "$BASE/payees?program=PRG-ALPHA")" 200
check "post is rejected"           "$(code -X POST -H "X-Api-Key: $KEY" "$BASE/payees")" 405

count=$(curl -s -H "X-Api-Key: $KEY" "$BASE/payees" | grep -o '"id"' | grep -c .)
check "all payees present"         "$count" 200

exit "$fails"
