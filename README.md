# Oblodai Ruby SDK

Official Ruby client for the [Oblodai](https://oblodai.com) crypto payment gateway: invoices,
payouts, refunds, payout links, static wallets, webhooks, documents — the whole merchant API,
generated from the gateway's own contract snapshot and verified against it.

- Ruby ≥ 3.1, **zero runtime dependencies** (`Net::HTTP`, `OpenSSL`, `JSON`, `SecureRandom`).
- Every route the gateway exposes (107) has a method here; every response body has a model.
- Retries driven by the API's own `retryable` flag, automatic idempotency keys, clock-skew correction.
- `Oblodai::Webhooks` verifies signatures with no client and no API key.

```bash
gem install oblodai
```

```ruby
gem "oblodai", "~> 1.3"
```

## Start in the sandbox

Get your keys in the Oblodai dashboard. A **sandbox key** (`test_…`) drives a chainless copy of the
gateway — fake balance from a faucet, simulated deposits, real webhooks — so integrate against it first.

```ruby
require "oblodai"

client = Oblodai::Client.new(
  public_id: ENV["OBLODAI_PUBLIC_ID"],
  secret: ENV["OBLODAI_SECRET"]
)

invoice = client.payments.create(
  amount: "25",            # amounts are decimal strings, never floats
  currency: "USDT",        # what you price in — a fiat (USD, EUR, …) or a crypto asset
  network: "tron",         # omit to let the payer choose the network on the pay page
  order_id: "order-1001",  # your reference; idempotent per order_id
  url_callback: "https://shop.example/oblodai/webhook"
)
invoice.url      # the hosted pay page
invoice.address  # where the customer sends the funds
invoice.status   # "created"
```

Prices in fiat: `amount: "25", currency: "USD", to_currency: "USDT"` — `currency` is what you charge,
`to_currency` the asset the payer sends. See [`examples/`](examples).

Credentials fall back to the environment: `OBLODAI_PUBLIC_ID`, `OBLODAI_SECRET`,
`OBLODAI_PAYOUT_PUBLIC_ID`, `OBLODAI_PAYOUT_SECRET`, `OBLODAI_BASE_URL`, `OBLODAI_ADMIN_TOKEN`.

### Two keys

The gateway issues a **payment key** (`pk_…`) and a **payout key** (`wk_…`). Sandbox keys are both at
once; live keys are separate, and money-out routes need the payout one: `payouts.*`, `refunds.*`,
`payout_links.*`, `transfers.*`, `splits.*`, `wallets.refund_blocked_deposit`, auto-withdraw, the IP
allow-list, `webhooks.rotate_secret`, `sandbox.faucet`/`reset`. Pass both pairs and the SDK picks the
right one per call:

```ruby
Oblodai::Client.new(public_id:, secret:, payout_public_id:, payout_secret:)
```

A call with the wrong kind is a 403 `merchant.wrong_key_kind`.

## Resources

| Namespace                 | Methods                                                                                                                                                                                                      |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `payments`                | create · info/get · cancel · history/list · batch · qr · services · send_email · resend · public_view · select · public_qr                                                                                   |
| `refunds`                 | create · resolve · batch                                                                                                                                                                                     |
| `payouts`                 | create · validate · calculate · info/get · cancel · approve · history/list · mass · batch · services · get/set_fee_config · get/set_refund_fee_config                                                        |
| `payout_links`            | create · info/get · list · cancel · batch · cheque · claim_preview · claim                                                                                                                                   |
| `payment_links`           | create · info/get · list · toggle · public_view · checkout                                                                                                                                                   |
| `batches` / `transfers`   | info · to_personal · to_user · batch                                                                                                                                                                         |
| `wallets`                 | create · qr · block · refund_blocked_deposit                                                                                                                                                                 |
| `webhooks`                | register · rotate_secret · deliveries · test                                                                                                                                                                 |
| `documents`               | statement · ledger · balance_certificate · fee_schedule · split_report · batch_report · link_report · wallet_statement · referrals_report · create_job · job_info · job_file · download                       |
| `splits`                  | create_rule · list_rules · delete_rule · get/set_config · get/set_opt_in                                                                                                                                     |
| `settings`                | set_discount · list_discounts · get/set_accuracy · get/set_auto_refund · list_accepted · set_accepted · get/set_payment_fee_config · list/set/delete_auto_withdraw · list/add/remove/enable_api_allowlist    |
| `account` / `catalog`     | balance · referral · vrcs · currencies · exchange_rates                                                                                                                                                      |
| `sandbox`                 | faucet · deposit · webhooks · replay · reset                                                                                                                                                                 |
| `merchants`               | create · create_sandbox (provisioning; `admin_token:` on a self-hosted gateway)                                                                                                                              |

Request fields are keyword arguments named exactly as the API names them. Alongside them every
method accepts `idempotency_key:`, `timeout_ms:`, `deadline_ms:` and `prefer_payout_key:`.
Lookups take a bare uuid or the keyword: `payments.info("uuid")`, `payments.info(order_id: "o-1")`.

### Models

Responses come back as frozen model objects whose attributes are the wire's own snake_case names,
plus `to_h` for the raw shape. A field the gateway adds after this release is not lost — it stays
readable through `model[:new_field]` and `to_h`.

```ruby
payment = client.payments.info(order_id: "order-1001")
payment.status        # "paid"
payment.paid?         # true for paid / paid_over
payment.amount_paid   # "25.000000" — a String
payment.tx_list.first.txid
payment.to_h          # the exact JSON object the gateway sent, symbol-keyed
```

### Lists

List methods return a lazy `Oblodai::Page`. It is `Enumerable` over every item of every page, and
`first_page` gives one page with its counters. Nothing is requested until you consume it.

```ruby
client.payments.history(limit: 50).each { |payment| puts payment.uuid }   # walks all pages
page = client.payouts.history(status: "confirmed", limit: 50).first_page  # one request
page.items.size
page.paginate.total
page.paginate.has_pages
client.payouts.history(kind: "refund").all(1000)   # at most 1000 items
client.payments.history(limit: 10).first(3)        # stops after the first page
```

### Statuses

- Payment: `select → created → confirm_check → paid | paid_over | wrong_amount | expired | cancelled`.
  `payment.paid?` is true for `paid`/`paid_over`; `wrong_amount` (underpaid) waits for
  `refunds.resolve(uuid:, action: "accept" | "refund")`; `payment.final?` covers the rest.
- Payout: `pending → approved → awaiting_cosign → broadcasting → sent → confirmed | failed | cancelled`.

Prefer webhooks for state changes; poll `info` only as a fallback.

### Errors

Every failure is an `Oblodai::Error` carrying the API's error envelope: `code`
(`payout.insufficient_funds`), `http_status`, `retryable?`, `retry_after`, `request_id`, `field`.
Subclasses for `rescue`: `ValidationError` (400), `AuthenticationError` (401), `PermissionError`
(403), `NotFoundError` (404), `ConflictError` / `IdempotencyConflictError` (409), `RateLimitError`
(429), `UnavailableError` (503), `InternalError` (other 5xx), `TransportError` (no response),
`ConfigError` (rejected before sending), `SignatureError` (webhooks). Quote `request_id` to support.

```ruby
begin
  client.payouts.create(**params)
rescue Oblodai::Error => e
  case e.code
  when "payout.insufficient_funds", "payout.funds_maturing" # retryable — the balance may still arrive
    schedule_retry(e.retry_after || 60)
  else
    raise # the SDK already retried what was safe to retry
  end
end
```

`e.to_h` / `e.to_json` keep the message and drop the raw response body, so a structured log never
prints an API payload.

### Retries and idempotency

- Create-type routes get an `Idempotency-Key` automatically (one per logical call, reused on every
  retry), so a timeout can never produce a second payout. Pass your own `idempotency_key:` to make
  retries safe across process restarts; on routes the gateway does not deduplicate the SDK refuses a
  key (`sdk.idempotency_unsupported`) rather than let you believe a re-send is safe.
- An error is retried only when the API says `retryable: true`. Answers without an API envelope (a
  proxy 502/503) and transport failures are retried only on read routes and on keyed writes.
  `Retry-After` is honoured.
- `retry_policy: { max_retries:, base_delay_ms:, max_delay_ms:, max_retry_after_ms: }`,
  `timeout_ms:` per attempt, `deadline_ms:` per call (both also settable per request).
- On a 401 that reports a bad signature or timestamp the SDK reads the server `Date`, re-signs once,
  and keeps the offset only if that attempt got past authentication.

### Webhooks

```ruby
require "oblodai/webhooks"

post "/oblodai/webhook" do
  body = request.body.read # the RAW bytes — a re-serialized parse will not verify
  delivery = Oblodai::Webhooks.verify_delivery(body, request.env, secret: ENV["OBLODAI_WEBHOOK_SECRET"])
  halt 200 if delivery.test? # a rehearsal: signed like a live one, but no money moved
  event = delivery.event

  case event.type
  when "payment" then mark_order_paid(event.order_id) if event.status == "paid"
  when "payout"  then record_payout(event.uuid, event.status)
  when "wallet"  then credit_customer(event.address, event.payment_amount)
  end
  status 200
end
```

Rehearsal deliveries (`webhooks.test`, sandbox) are signed exactly like live ones and carry
`test: true` in the body (and `X-Webhook-Test: true`): check `delivery.test?` — or
`Oblodai::Webhooks.test_event?(event)` when you only have the parsed event — and never act on one as
if money moved. `delivery.id` (`X-Webhook-Id`) is stable across retries — deduplicate on it; `event.sequence` orders
events (`Oblodai::Webhooks.stale?(event, last_sequence)`). After `webhooks.rotate_secret` pass
`previous_secret:` for at least 26 hours. Deliveries older or newer than ±300 s are rejected
(`tolerance:` changes the window, `0` disables it).

### Money helpers

`Oblodai::Money.add`, `.subtract`, `.compare`, `.zero?` — exact decimal arithmetic on the string
amounts the API uses. Never `to_f` an amount.

### Self-hosted or local gateway

`base_url: "http://127.0.0.1:8095"` works out of the box; other plain-http hosts need
`allow_insecure_base_url: true` (or `OBLODAI_ALLOW_INSECURE=1`). A path prefix in `base_url` is kept
(`https://gw.corp/oblodai` → `https://gw.corp/oblodai/v1/payment`).

Need a different HTTP stack (a proxy, instrumentation, a recorded fake)? Pass `http:` — anything
answering `call(request, timeout_ms:)` with an `Oblodai::HTTP::Response`.

## The contract snapshot

`contract/` is exported by the gateway's own test suite: the route registry, request DTO schemas with
English field docs, enums, all 468 error codes, signing vectors, golden response bodies recorded from
a live gateway and real signed webhook deliveries. `lib/oblodai/contract/` is generated from it:

```bash
rake codegen   # regenerate routes.rb, enums.rb, requests.rb
rake drift     # CI gate: fail when the committed code is not what codegen produces
```

The machine-readable surface ships with the gem: `Oblodai::Contract::ROUTES` (107 routes with auth,
idempotency, safety and list kind), `Oblodai::Contract::REQUESTS` (every documented request field
with its type, vocabulary and English description), `Oblodai::Enums::*` (statuses, networks, fee
bearers, event types, error codes).

## Development

```bash
bundle install
rake ci          # rubocop + contract drift + unit and contract specs
rake spec:live   # the live journeys against a real gateway (OBLODAI_LIVE_URL, default http://127.0.0.1:8095)
```

License: MIT.
