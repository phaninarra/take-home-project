# Payouts platform

Four independent services that between them describe a payout. A unified API in
front of them is being built as part of this repository.

## Running things

```
./preflight              check the machine, build, start, verify
docker compose up -d     start
docker compose down      stop
docker compose logs <service>
```

## The services

Do not modify anything under `services/`. They stand in for systems owned by
other teams.

| Service                | Port          | Format      | Auth                                                   |
| ---------------------- | ------------- | ----------- | ------------------------------------------------------ |
| `payee-directory`      | 8081          | JSON        | `X-Api-Key` header                                     |
| `instruction-registry` | 8082          | XML         | HMAC-SHA256 signature, see `examples/02-*.sh`          |
| `payment-executor`     | 8083 gRPC     | protobuf    | Bearer token from `TokenService`, expires in 60 seconds |
|                        | 8093 HTTP     | JSON        | none, health only                                      |
| `settlement-returns`   | 8084          | Fixed width | none                                                   |

Credentials are in `docker-compose.yml`. They are fake.

## How a payout hangs together

```
payee-directory        PY-nnnnn      who is being paid
instruction-registry   E2E-xxxxxxxx  what was asked for, and the rules
payment-executor       PAY-xxxxxxxx  whether it went out
settlement-returns     15-digit trace  whether the bank sent it back
```

Nothing shares an identifier. Each service carries one field that lets you reach
the next: an instruction names its payee, the executor can be asked for an
execution by end-to-end id, and a return record names its payment.

The executor and the returns file contradict each other on some payouts. That is
deliberate, not a bug.

## Conventions

- Runnable things live in `services/<name>/`, shared code in `lib/<name>/`,
  helpers in `scripts/`.
- Tests sit inside the component they test, in `<component>/tests/`.
- No language manifests at the repository root. Each component owns its own.

## Where to look first

- `PROBLEM.md` — what is being built and why
- `examples/` — a working call against every service
- `examples/returns-layout.md` — the fixed-width record layout
