#!/usr/bin/env sh
# payment-executor — gRPC. Tokens last 60 seconds.
#
# Needs grpcurl:
#   macOS        brew install grpcurl
#   Go toolchain go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
#   anything     see the docker fallback at the bottom of this file
#
# Server reflection is on, so you can explore without the .proto:
#   grpcurl -plaintext localhost:8083 list
#   grpcurl -plaintext localhost:8083 describe executor.v1.ExecutionService
#
# The .proto is in ./executor.proto if you would rather generate a client.
set -eu

TARGET="${TARGET:-localhost:8083}"
CLIENT_ID="${CLIENT_ID:-orchestrator}"
CLIENT_SECRET="${CLIENT_SECRET:-ex_secret_4d9b1c7a}"

if ! command -v grpcurl >/dev/null 2>&1; then
  cat <<'MISSING'
grpcurl is not installed, so this script cannot run.

  macOS          brew install grpcurl
  Go toolchain   go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
  anywhere       docker run --rm fullstorydev/grpcurl:latest -plaintext host.docker.internal:8083 list

You do not need grpcurl to complete the assessment. It is a convenience for
poking at the service by hand. The service definition is in ./executor.proto if
you would rather generate a client.
MISSING
  exit 0
fi

echo "--- what is on this server ---"
grpcurl -plaintext "$TARGET" list

echo "--- health (no token required) ---"
grpcurl -plaintext "$TARGET" grpc.health.v1.Health/Check

echo "--- calling without a token ---"
grpcurl -plaintext -d '{"end_to_end_id":"E2E-C4DAE8D4"}' \
  "$TARGET" executor.v1.ExecutionService/LookupByEndToEndId || true

echo "--- get a token ---"
TOKEN="$(grpcurl -plaintext \
  -d "{\"client_id\":\"$CLIENT_ID\",\"client_secret\":\"$CLIENT_SECRET\"}" \
  "$TARGET" executor.v1.TokenService/IssueToken \
  | sed -n 's/.*"token": "\([^"]*\)".*/\1/p')"
echo "token acquired, ${#TOKEN} characters, valid for 60 seconds"

echo "--- look up an execution by the instruction's end-to-end id ---"
grpcurl -plaintext -H "authorization: Bearer $TOKEN" \
  -d '{"end_to_end_id":"E2E-C4DAE8D4"}' \
  "$TARGET" executor.v1.ExecutionService/LookupByEndToEndId

echo "--- submit a payment (idempotency_key is required) ---"
grpcurl -plaintext -H "authorization: Bearer $TOKEN" \
  -d '{"end_to_end_id":"E2E-DEADBEEF","program_id":"PRG-ALPHA","amount_minor":125000,"idempotency_key":"demo-key-1"}' \
  "$TARGET" executor.v1.ExecutionService/SubmitPayment

echo "--- the same idempotency_key returns the same payment, it does not create a second one ---"
grpcurl -plaintext -H "authorization: Bearer $TOKEN" \
  -d '{"end_to_end_id":"E2E-DEADBEEF","program_id":"PRG-ALPHA","amount_minor":125000,"idempotency_key":"demo-key-1"}' \
  "$TARGET" executor.v1.ExecutionService/SubmitPayment

# Docker fallback, if you would rather not install grpcurl. Note that
# host.docker.internal is how a container reaches your host.
#
#   docker run --rm fullstorydev/grpcurl:latest \
#     -plaintext host.docker.internal:8083 list
