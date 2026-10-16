# settlement-returns

Whether the bank sent a payout back. These records arrive days after the payment
was made.

- **Port** 8084
- **Format** fixed-width text, 91 characters per record
- **Auth** none

The service has no authentication. It returns records for whichever program you
name in the `X-Program-Id` header.

## Endpoints

| Method | Path                     | Notes                                    |
| ------ | ------------------------ | ---------------------------------------- |
| `GET`  | `/health`                |                                          |
| `GET`  | `/returns`               | `X-Program-Id` header is required         |
| `GET`  | `/returns?paymentId=...` | Narrows to one payment                    |

Record layout, field by field: [`examples/returns-layout.md`](../../examples/returns-layout.md)

Working calls: [`examples/04-settlement-returns.sh`](../../examples/04-settlement-returns.sh)
