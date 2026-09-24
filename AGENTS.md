# Oblodai Ruby SDK — guide for coding agents

Gem `oblodai` (2.0), Ruby ≥ 3.2, one runtime dependency (`bigdecimal`). Methods, models, enums and
the route table are generated from the gateway's OpenAPI contract into `lib/oblodai/generated/`
(never edit it by hand); the runtime around it is hand-written.

## Non-negotiables

- Amounts: a decimal **String** (`amount: "25"`) or a **BigDecimal** in requests, `BigDecimal` in
  responses. A `Float` is refused with `sdk.float_amount` before anything is sent. Never `to_f` an
  amount; order string amounts with `Oblodai::Money.compare` / `.equals?`.
- Methods are `client.<resource>.<method>` — the operation's `operationId` without the resource name,
  in snake_case (`createPayout` → `payouts.create`). `names.lock` lists all 120.
- Request fields are keyword arguments spelled as the wire spells them (`order_id:`, `url_callback:`);
  a body may also be a Hash with the wire names or a request model, with keywords added on top. A
  keyword that clashes with Ruby gets `_` (`format_:`). Path parameters are positional
  (`checkout.get(id)`), query parameters of GET routes are keywords.
- Call options on every method: `idempotency_key:`, `timeout:` (seconds, per attempt),
  `max_retries:`, `extra_headers:`, `request_id:` (sent as `X-Request-ID`). A misspelled keyword is
  Ruby's own `ArgumentError`.
- One API key. `public_id:`/`secret:` (or `OBLODAI_PUBLIC_ID`/`OBLODAI_SECRET`) sign every signed
  route. `admin_token:` (or `OBLODAI_ADMIN_TOKEN`) is the gateway operator's token and reaches only
  the unsigned onboarding route (`sandbox.onboard_store`).
- List methods return a lazy `Oblodai::Page`: `each` walks every item, `each_page`/`by_page` every
  page, `first_page` one page (`items`, `total`, `has_pages?`), `all(max)` collects.
- Batches (`batches.create_payment/create_payout/create_refund`, `payouts.create_transfer_batch`) and
  `documents.create_job` return an `Oblodai::Job`: `job.result`, `job.wait(timeout:, interval:)`,
  `job.download` (document jobs).
- Idempotency keys are generated automatically on the routes the gateway deduplicates and reused
  across retries. Passing `idempotency_key:` to a route that does not deduplicate raises
  `sdk.idempotency_unsupported` — except `sandbox.faucet`, whose own body field it fills.
- Whether a request may be repeated after a transport failure comes from the contract's
  `x-retry-safe` (`Oblodai::Generated::ROUTES[op].safe`), never from the shape of the path.
- Models `inspect` without secrets; `to_h`/`to_json` are the wire form and carry one-time secrets
  (`RegisterWebhookResult#secret`, `PayoutLinkCreated#claim_token`/`#passcode`) — do not log them.

## Errors

`rescue Oblodai::Error => e` → `e.code` (`family.reason`), `e.message` (`[code] text
(request_id=…)`), `e.text`, `e.http_status`, `e.retryable?` (authoritative — the SDK already retried
what it should), `e.retry_after`, `e.request_id` (quote to support), `e.field` (400s), `e.synthetic?`
(a proxy answered, not the API). Subclasses: `ValidationError` 400, `AuthenticationError` 401,
`PermissionError` 403, `NotFoundError` 404, `ConflictError`/`IdempotencyConflictError` 409,
`RateLimitError` 429, `UnavailableError` 503, `InternalError` other 5xx, `TransportError` (no
response), `ConfigError` (before sending), `SignatureError` (a webhook that is not authentic),
`WebhookPayloadError` (`webhook.bad_payload` — authentic but unreadable, do NOT answer 401),
`ContractError` (an answer that is not the documented envelope).

Codes worth handling: `payout.insufficient_funds` (retryable), `payout.funds_maturing` (retryable),
`idempotency.key_reused`, `payment.not_found`, `merchant.bad_signature`, `request.rate_limited`.
Full list: `Oblodai::Enums::ErrorCode::VALUES`; each method's YARD lists the codes it can answer with.

## Statuses

- Payment: `select → created → confirm_check → paid | paid_over | wrong_amount | expired | cancelled`.
  `Oblodai::Status.payment_paid?(status)` = paid/paid_over. `wrong_amount` needs
  `payments.resolve(uuid:, action:)`.
- Payout: `pending → approved → awaiting_cosign → broadcasting → sent → confirmed | failed | cancelled`.
- Constants: `Oblodai::Enums::PaymentStatus::PAID`, `Oblodai::Enums::PayoutStatus::VALUES`, …; an
  unknown value is still a String.

## Webhooks

```ruby
require "oblodai/webhooks"
delivery = Oblodai::Webhooks.verify_delivery(raw_body, headers, secret: secret)
```

Verify over the **raw** bytes. Order of checks: headers → HMAC → freshness → body. The event is an
`Oblodai::Models::PaymentWebhook`, `PayoutWebhook`, `WalletWebhook` or `ConversionWebhook`; an
unknown kind is the frozen parsed Hash (`Oblodai::Webhooks.known_event?`). `delivery.test?` is true
for rehearsal deliveries — never treat one as money. Deduplicate on `delivery.id`; drop out-of-order
events with `Oblodai::Webhooks.stale?(event, last_sequence)`. During a rotation pass
`previous_secret:` for ≥26 h.

## Machine-readable surface

`Oblodai::Generated::ROUTES` (120 routes by `operationId`: method, path, auth, idempotent, safe,
bare, list_kind), `Oblodai::Models::*` (`REQUIRED`, `FIELDS`, `from_h`, `to_h`), `Oblodai::Enums::*`
(`VALUES` per enumeration), `Oblodai::LRO` (long-running operations and how they are polled),
`names.lock`.
