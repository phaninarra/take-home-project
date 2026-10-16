# Payouts platform — principal engineer assessment

Four services already run here. Your job is to put one API in front of them.

Start with [PROBLEM.md](PROBLEM.md). Send your work back using
[SUBMISSION.md](SUBMISSION.md).

## Start the stack

```
./preflight
```

That checks your machine, builds the four services, starts them, and calls each
one. It should finish with four green lines. If it does not, stop and email us —
see [SUBMISSION.md](SUBMISSION.md). Getting this running is our problem, not
yours, and it does not count against your time.

If you would rather do it by hand:

```
docker compose build
docker compose up -d
```

Stop everything with `docker compose down`.

## What is here

| Service                | Port   | Format          | Holds                                    |
| ---------------------- | ------ | --------------- | ---------------------------------------- |
| `payee-directory`      | `8081` | JSON            | Who gets paid, and their bank details    |
| `instruction-registry` | `8082` | XML             | Payout instructions, and the rules       |
| `payment-executor`     | `8083` | gRPC            | Whether a payout was actually sent       |
| `settlement-returns`   | `8084` | Fixed-width     | Bank rejections, which arrive days later |

Each service authenticates differently. [`examples/`](examples/) has a working
call against every one of them, including the signing and the token handling, so
you do not have to work any of it out from scratch. Read
[`examples/README.md`](examples/README.md) first.

```
sh examples/01-payee-directory.sh
sh examples/02-instruction-registry.sh
sh examples/03-payment-executor.sh
sh examples/04-settlement-returns.sh
```

## Layout

```
services/     the four services — do not change these
examples/     working calls against each service
scripts/      helpers
```

Your work goes wherever you think it belongs. That choice is yours to make and
to justify.

## Credentials

All of them are in `docker-compose.yml` and in the example scripts. They are
fake and local only.
