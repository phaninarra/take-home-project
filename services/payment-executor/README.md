# payment-executor

Whether a payout actually went out, and the means to send one.

- **Port** 8083 for gRPC, 8093 for an HTTP health endpoint
- **Format** protobuf over gRPC
- **Auth** bearer token from `TokenService`, valid for 60 seconds

Server reflection is enabled, so `grpcurl -plaintext localhost:8083 list` works
without the schema. The schema is at [`proto/executor.proto`](proto/executor.proto)
if you would rather generate a client.

## Methods

| Service            | Method               | Notes                                    |
| ------------------ | -------------------- | ---------------------------------------- |
| `TokenService`     | `IssueToken`         | Needs client id and secret, not a token   |
| `ExecutionService` | `LookupByEndToEndId` | Find an execution from an instruction id  |
| `ExecutionService` | `GetExecution`       | Payment ids look like `PAY-EBB2DD91`      |
| `ExecutionService` | `SubmitPayment`      | Requires an `idempotency_key`             |

Working calls: [`examples/03-payment-executor.sh`](../../examples/03-payment-executor.sh)
