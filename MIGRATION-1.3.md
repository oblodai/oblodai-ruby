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
- List methods refuse an `idempotency_key:` (`sdk.idempotency_unsupported`) rather than dropping it,
  and a client-side key rejection is a `ConfigError` (`sdk.bad_idempotency_key`), never a
  `ValidationError` claiming the API answered 400.
- Every id argument also accepts the model the SDK returned, and the `uuid`/`order_id` lookups
  accept `uuid:` as a keyword as well as positionally: `payments.info("u")`, `payments.info(uuid:
  "u")`, `payments.info(order_id: "o-1")`, `payments.info(invoice)`.

## Things worth knowing before the first release

- **`merchants` and the admin token.** `merchants.create(email:, name:)` and
  `merchants.create_sandbox(id)` provision merchants on a self-hosted gateway. They are unsigned and
  gated by `admin_token:` (or `OBLODAI_ADMIN_TOKEN`), which is sent as `X-Admin-Token` on those two
  routes and on nothing else — a caller header of that name is dropped.
- **Rehearsal webhooks carry a flag.** `webhooks.test` and the sandbox deliver events signed exactly
  like live ones, with `test: true` in the signed body and `X-Webhook-Test: true`. Check
  `delivery.test?` (or `Oblodai::Webhooks.test_event?(event)`) and never settle money on one.
- **The wallet model carries `blocked`**, and `wallets.refund_blocked_deposit` documents the codes it
  answers with (`wallet.bad_uuid`, `refund.no_address`, `refund.nothing_to_refund`, `refund.dust`,
  `refund.destination_internal`).
- **Retry safety is the contract's `safe` flag**, exported per route by the gateway;
  `Oblodai::Contract::ROUTES[key].safe` is what decides whether a failed request may be repeated.
  Nothing is inferred from the shape of a path.
- **`webhook.bad_payload`.** An authentic delivery whose body cannot be read raises
  `Oblodai::WebhookPayloadError`, in the contract family — not `SignatureError`. Answer 401 to
  `SignatureError` only; a `WebhookPayloadError` deserves a 400 and a look at the payload. An event
  `type` this release does not model arrives as `Oblodai::Models::UnknownEvent` instead of raising;
  narrow with `Oblodai::Webhooks.known_event?(event)`.
- **Secrets are redacted in every automatic rendering.** `WebhookEndpoint#secret`,
  `WebhookSecretRotated#secret`, `ApiKeyPair#secret`, `PayoutLink#claim_token` and
  `PayoutLink#passcode` read normally through their accessor and print as `[redacted]` in `to_h`,
  `to_json` and `inspect`. If you were storing `endpoint.to_h[:secret]`, read `endpoint.secret`.
- **Model corrections.** Models freeze the arrays and hashes they decoded and compare on their
  values; a field the gateway adds after this release stays readable through `model[:name]` and
  `to_h`.
- **`Money.equal?` is now `Money.equals?`** — the old name redefined `Object#equal?` with two
  arguments. Bad input raises `Oblodai::ConfigError` (`sdk.bad_amount`), not `TypeError`.

