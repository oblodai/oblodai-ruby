# Oblodai Ruby SDK — guide for coding agents

Gem `oblodai` (1.3), Ruby ≥ 3.1, no runtime dependencies. Everything below is verified against the
gateway's contract snapshot in `contract/contract.json`, which ships with the gem.

## Non-negotiables

- Amounts are decimal **strings**: `amount: "25"`, never `25` or `25.0`. Do not `to_f`; use
  `Oblodai::Money.add` / `.compare`.
- Request fields are keyword arguments spelled exactly as the wire spells them (`order_id:`,
  `url_callback:`, `payer_email:`). The same keyword list also accepts `idempotency_key:`,
  `timeout_ms:`, `deadline_ms:`, `prefer_payout_key:`.
- Two key kinds. The **payout key** is required for: `payouts.*`, `refunds.*`, `payout_links.*`,
  `transfers.*`, `splits.*`, `wallets.refund_blocked_deposit`, `settings.*_auto_withdraw`,
  `settings.*_api_allowlist`, `webhooks.rotate_secret`, `webhooks.test("payout", …)`,
  `sandbox.faucet`, `sandbox.reset`. Configure it with `payout_public_id:`/`payout_secret:` (or
  `OBLODAI_PAYOUT_*`); a wrong kind is a 403 `merchant.wrong_key_kind`.
- List methods return a lazy `Oblodai::Page`: `each` walks every page, `first_page` fetches one page
  (`items` + `paginate`), `all(max)` collects. Nothing is requested until it is consumed.
- Idempotency keys are generated automatically on create routes and reused across retries. Passing
  `idempotency_key:` to a route the gateway does not deduplicate raises `sdk.idempotency_unsupported`.

## Naming

| intent            | call                                                                                                  |
| ----------------- | ------------------------------------------------------------------------------------------------------- |
| fetch one         | `.info(uuid)` or `.info(order_id: …)` (alias `.get`)                                                   |
| fetch many        | `.history(**params)` on payments/payouts (alias `.list`), `.list(**params)` elsewhere                  |
| create            | `.create(**params)`; webhooks: `.register(url)`                                                        |
| many, synchronous | `payouts.mass`, `payout_links.batch` — ≤100, per-element `{idx, ok, result, message}`                  |
| many, async       | `payments.batch`, `payouts.batch`, `refunds.batch`, `transfers.batch` — ≤5000, poll `batches.info(id)` |
| documents         | `documents.*_report / statement / fee_schedule / balance_certificate` → `Oblodai::FileResult`          |
| provisioning      | `merchants.create(email:, name:)`, `merchants.create_sandbox(id)` — unsigned; `admin_token:` option    |
| payer-facing      | `payments.public_view/select/public_qr`, `payment_links.public_view/checkout`,                         |
|                   | `payout_links.claim_preview/claim` — no credentials                                                    |

## Errors

`rescue Oblodai::Error => e` → `e.code` (`family.reason`), `e.http_status`, `e.retryable?`
(authoritative — the SDK already retried what it should), `e.retry_after`, `e.request_id` (quote to
support), `e.field` (400s), `e.synthetic?` (a proxy answered, not the API). Subclasses:
`ValidationError` 400, `AuthenticationError` 401, `PermissionError` 403, `NotFoundError` 404,
`ConflictError`/`IdempotencyConflictError` 409, `RateLimitError` 429, `UnavailableError` 503,
`InternalError` other 5xx, `TransportError` (no response), `ConfigError` (before sending),
`SignatureError` (webhooks). `e.to_h`/`e.to_json` keep the message and drop the raw body.

Codes worth handling: `payout.insufficient_funds` (retryable), `payout.funds_maturing` (retryable),
`idempotency.key_reused`, `invoice.not_payable`, `payment.not_found`, `merchant.wrong_key_kind`,
`merchant.bad_signature`, `request.rate_limited`. Full list: `Oblodai::Enums::ERROR_CODES`.

## Statuses

- Payment: `select → created → confirm_check → paid | paid_over | wrong_amount | expired | cancelled`.
  `payment.paid?` = paid/paid_over. `wrong_amount` needs `refunds.resolve(uuid:, action:)`.
- Payout: `pending → approved → awaiting_cosign → broadcasting → sent → confirmed | failed | cancelled`.
- Webhook event types: `invoice.<status>`, `payout.<status>`, `wallet.paid`; the body's `type` is
  `"payment" | "payout" | "wallet"` and selects the event model.

## Webhooks

```ruby
require "oblodai/webhooks"
delivery = Oblodai::Webhooks.verify_delivery(raw_body, headers, secret: secret)
```

Verify over the **raw** bytes. Deduplicate on `delivery.id` (`X-Webhook-Id`); drop out-of-order
events with `Oblodai::Webhooks.stale?(event, last_sequence)`. During a rotation pass
`previous_secret:` for ≥26 h.

## Machine-readable surface

`Oblodai::Contract::ROUTES` (107 routes: path, auth, idempotent, safe, bare, list),
`Oblodai::Contract::REQUESTS` (documented request fields per route, with English descriptions),
`Oblodai::Enums::*` (`ERROR_CODES`, `NETWORKS`, `PAYMENT_STATUSES`, `PAYOUT_STATUSES`,
`EVENT_TYPES`, …), and `contract/` on disk (`Oblodai.contract_path`): schemas, golden response
bodies per route, error samples, signed webhook samples.
