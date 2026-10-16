# payee-directory

Who is being paid, and the bank details to pay them with.

- **Port** 8081
- **Format** JSON
- **Auth** static key in an `X-Api-Key` header

## Endpoints

| Method | Path              | Notes                                     |
| ------ | ----------------- | ----------------------------------------- |
| `GET`  | `/health`         | No key required                           |
| `GET`  | `/payees/{id}`    | Payee ids look like `PY-00140`             |
| `GET`  | `/payees`         | Optional `?program=PRG-ALPHA` filter       |

Working calls: [`examples/01-payee-directory.sh`](../../examples/01-payee-directory.sh)
