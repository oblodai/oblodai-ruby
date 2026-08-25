# Migrating to the Oblodai Ruby SDK 1.3

There is no earlier Ruby gem: 1.3 is the first release, versioned in step with the other Oblodai
SDKs so the same version number means the same API surface in every language. If you are moving
from hand-rolled HTTP calls, or from an Oblodai SDK of the 1.x line in another language, this is
what changed.

## Signing (automatic)

Requests are signed `ts \n METHOD \n path+query \n Idempotency-Key \n body`, HMAC-SHA256, lowercase
hex. The 1.x line signed four fields; the gateway has answered 401 to that recipe ever since the
five-field one shipped. If you computed signatures yourself, drop that code and let the client sign,
or call `Oblodai::Signing.sign_request`.

## Vocabulary

| 1.x                                              | 1.3                                                                                                              |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `payment.payment_status`                         | `payment.status` (`created`, `confirm_check`, `paid`, `paid_over`, `wrong_amount`, `expired`, `cancelled`, `select`) |
| payout statuses `check/process/paid/fail/cancel` | `pending/approved/awaiting_cosign/broadcasting/sent/confirmed/failed/cancelled`                                     |
| `paginate.count`                                 | `paginate.total`, plus `has_pages`                                                                                  |
| `calculate` → `to_amount`, `merchant_amount`     | `amount`, `commission`, `payer_amount`, `fee_bearer`, `fee_type` (nullable when unpriceable)                        |
| batch items `{status, error}` / `{success}`      | `{idx, ok, order_id, result, message, error_code, http_status}`                                                     |
| payout link `expires_in_hours`                   | `expires_in_seconds`; new: `passcode`, `fee_bearer`, `title`, `note`                                                |
| payment link `amount_min/amount_max/expires_in`  | `min_amount`/`max_amount`/`expires_in_seconds`                                                                      |
| split `refund_hold_hours`                        | `refund_hold_seconds`                                                                                               |
| auto-withdraw `min`                              | `min_amount`                                                                                                        |
| `client.rates.currencies`                        | `client.catalog.currencies` / `client.catalog.exchange_rates`                                                       |
| `client.links.*`                                 | `client.payment_links.*`                                                                                            |

## Ruby specifics

- Amounts are `String`. `Oblodai::Money.add("10.000000", "0.5") # => "10.500000"`. Never `to_f`.
- Request fields are keyword arguments spelled exactly as the wire spells them (`order_id:`,
  `url_callback:`), so the API reference reads as Ruby without translation.
- Per-call options travel with them: `idempotency_key:`, `timeout_ms:`, `deadline_ms:`,
  `prefer_payout_key:`.
- List methods return a lazy `Oblodai::Page` (`each` walks every page, `first_page` fetches one).
- Failures raise `Oblodai::Error` subclasses; the machine-readable discriminator is always `#code`.
