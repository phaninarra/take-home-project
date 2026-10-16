# Examples

Runnable calls against each service, so you do not have to work out the wire
formats or the auth schemes from scratch. Start the stack first:

```
docker compose up --build -d
```

Then run any of these:

```
sh examples/01-payee-directory.sh
sh examples/02-instruction-registry.sh
sh examples/03-payment-executor.sh
sh examples/04-settlement-returns.sh
```

| File                          | Service              | Format      | Auth                            |
| ----------------------------- | -------------------- | ----------- | ------------------------------- |
| `01-payee-directory.sh`       | payee-directory      | JSON        | Static key in `X-Api-Key`       |
| `02-instruction-registry.sh`  | instruction-registry | XML         | HMAC-SHA256 request signature   |
| `03-payment-executor.sh`      | payment-executor     | gRPC        | Bearer token, expires after 60s |
| `04-settlement-returns.sh`    | settlement-returns   | Fixed width | None                            |

Also here:

- `executor.proto` — the gRPC service definition, if you would rather generate
  a typed client than use reflection.
- `returns-layout.md` — the fixed-width record layout, field by field, with a
  worked example.

`02-instruction-registry.sh` is worth reading before you write your own signing
code. The comment at the top of it states the signing rules, and the `sign`
function is a working implementation in about six lines of shell.

Requirements: `curl` and `openssl` for three of the four scripts, and `grpcurl`
for the executor. Installation notes are at the top of `03-payment-executor.sh`.
