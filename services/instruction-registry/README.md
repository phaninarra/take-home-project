# instruction-registry

What was asked for, and the rules that govern whether it is acceptable.

- **Port** 8082
- **Format** XML
- **Auth** every request must carry an HMAC-SHA256 signature

## Endpoints

| Method | Path                   | Notes                                          |
| ------ | ---------------------- | ---------------------------------------------- |
| `GET`  | `/health`              | No signature required                          |
| `GET`  | `/instructions/{id}`   | Instruction ids look like `E2E-C4DAE8D4`        |
| `POST` | `/instructions`        | Creates one, subject to its validation rules    |

A `POST` that fails validation comes back as a `<Fault>` with a code naming the
rule that rejected it. The rules are not documented here — the service will tell
you.

Signing rules and a working implementation:
[`examples/02-instruction-registry.sh`](../../examples/02-instruction-registry.sh)
