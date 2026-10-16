#!/usr/bin/env sh
set -eu
HEALTH="${HEALTH:-http://localhost:8093}"
fails=0
check() {
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (got %s, want %s)\n' "$1" "$2" "$3"; fails=$((fails+1)); fi
}

check "http health" "$(curl -s -o /dev/null -w '%{http_code}' "$HEALTH/health")" 200

if command -v grpcurl >/dev/null 2>&1; then
  TARGET="${TARGET:-localhost:8083}"
  services=$(grpcurl -plaintext "$TARGET" list | grep -c 'executor.v1')
  check "grpc services advertised" "$services" 2

  no_token=$(grpcurl -plaintext -d '{"end_to_end_id":"E2E-C4DAE8D4"}' \
    "$TARGET" executor.v1.ExecutionService/LookupByEndToEndId 2>&1 | grep -c 'Unauthenticated' || true)
  check "unauthenticated is rejected" "$no_token" 1

  token=$(grpcurl -plaintext -d '{"client_id":"orchestrator","client_secret":"ex_secret_4d9b1c7a"}' \
    "$TARGET" executor.v1.TokenService/IssueToken | sed -n 's/.*"token": "\([^"]*\)".*/\1/p')
  found=$(grpcurl -plaintext -H "authorization: Bearer $token" -d '{"end_to_end_id":"E2E-C4DAE8D4"}' \
    "$TARGET" executor.v1.ExecutionService/LookupByEndToEndId | grep -c 'PAY-' || true)
  check "authenticated lookup" "$found" 1

  bad=$(grpcurl -plaintext -H "authorization: Bearer deadbeef" -d '{"end_to_end_id":"E2E-C4DAE8D4"}' \
    "$TARGET" executor.v1.ExecutionService/LookupByEndToEndId 2>&1 | grep -c 'Unauthenticated' || true)
  check "invalid token is rejected" "$bad" 1
else
  printf 'skip grpc checks — grpcurl not installed\n'
fi

exit "$fails"
