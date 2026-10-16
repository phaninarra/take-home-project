# settlement-returns record layout

Every record is exactly 91 characters, newline terminated. Text fields are
left justified and padded with spaces. Numeric fields are right justified and
padded with zeros.

| Columns | Length | Field         | Notes                                  |
| ------- | ------ | ------------- | -------------------------------------- |
| 1–15    | 15     | Trace number  | Digits, zero padded                    |
| 16–27   | 12     | Payment id    | Matches `payment_id` from the executor |
| 28–38   | 11     | Program id    |                                        |
| 39–41   | 3      | Return code   | See below                              |
| 42–49   | 8      | Return date   | `YYYYMMDD`                             |
| 50–61   | 12     | Amount        | Minor units, zero padded               |
| 62–91   | 30     | Return reason | Free text                              |

## Worked example

```
207064087609975PAY-CAE5E8DCPRG-ALPHA  R2920260622000001797669CORPORATE ENTRY NOT AUTHORIZED
```

| Field         | Value                            |
| ------------- | -------------------------------- |
| Trace number  | `207064087609975`                |
| Payment id    | `PAY-CAE5E8DC`                   |
| Program id    | `PRG-ALPHA`                      |
| Return code   | `R29`                            |
| Return date   | `20260622`                       |
| Amount        | `1797669` minor units            |
| Return reason | `CORPORATE ENTRY NOT AUTHORIZED` |

## Return codes

| Code  | Meaning                        |
| ----- | ------------------------------ |
| `R01` | Insufficient funds             |
| `R02` | Account closed                 |
| `R03` | No account on file             |
| `R04` | Invalid account number         |
| `R07` | Authorization revoked          |
| `R16` | Account frozen                 |
| `R20` | Non transaction account        |
| `R29` | Corporate entry not authorized |

## Rate limit

The service allows 300 requests per rolling minute and answers `429` with a
`Retry-After` header beyond that.
