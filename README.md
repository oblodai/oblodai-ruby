<div align="center">

<a href="https://oblodai.com">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/oblodai/.github/main/brand/logo-white.svg">
    <img src="https://raw.githubusercontent.com/oblodai/.github/main/brand/logo-black.svg" alt="oblodai" height="52">
  </picture>
</a>

<h3>Official Ruby SDK for the <a href="https://oblodai.com">oblodai</a> payment gateway</h3>

Payments, payouts, payment links, splits, static wallets, webhooks — one API key.

<img src="https://img.shields.io/badge/gem-oblodai%202.0.0-E9573F?style=flat-square" alt="gem">
<a href="https://github.com/oblodai/oblodai-ruby/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/oblodai/oblodai-ruby/ci.yml?branch=main&style=flat-square&label=CI" alt="CI"></a>
<img src="https://img.shields.io/badge/ruby-%E2%89%A5%203.2-CC342D?style=flat-square" alt="Ruby version">
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-000000?style=flat-square" alt="License: MIT"></a>

[Documentation](https://docs.oblodai.com) · [Dashboard](https://my.oblodai.com) · [Read in Russian →](README.ru.md)

</div>

---

The official Ruby SDK for the **Oblodai** payment gateway: accepting payments, payouts, bulk
operations (batches), payment links, payout links (crypto cheques), splits, static wallets,
transfers, webhooks, documents. Request signing, typed models, typed errors, idempotency and safe
retries — out of the box. Ruby ≥ 3.2; the one runtime dependency is `bigdecimal` (amounts are
`BigDecimal`), everything else is the standard library.

Every method, model and enumeration is **generated from the gateway's OpenAPI contract** — one per
API operation, 120 of them — on top of a small hand-written runtime (transport, signing, retries,
pagination, webhooks). `names.lock` pins the public names; a name can only disappear on purpose.

> **Base URL.** Defaults to `https://api.oblodai.com`. Override `base_url:` and supply your own keys
> at initialisation if needed. The scheme must be `https://`; plain `http://` is accepted only for
> loopback (`http://127.0.0.1:8095`) or with the explicit allow-insecure option
> (`allow_insecure_base_url: true`, or `OBLODAI_ALLOW_INSECURE=1`).

## Installation

```bash
gem install oblodai
# or, in a Gemfile: gem "oblodai", "~> 2.0"
```

Ruby ≥ 3.2. Webhook verification lives in `oblodai/webhooks` and needs no client and no API key.
Coming from 1.x? Read [MIGRATION-2.0.md](MIGRATION-2.0.md): every old method name and its new one.

## Where to get keys

A merchant has **one API key**, issued in the [dashboard](https://my.oblodai.com) → **API keys**: a
public id `oblodai_<hex>` and a secret `oblodai_live_<hex>`. It signs every signed route there is —
invoices, payouts, refunds, links, splits, wallets, settings, documents, the sandbox. The sandbox
pair (`test_oblodai_<hex>` / `oblodai_test_<hex>`) drives a chainless copy of the gateway. The
**onboarding admin token** is a different thing — it belongs to the gateway operator and reaches only
the unsigned provisioning route (`sandbox.onboard_store`).

```ruby
require "oblodai"

client = Oblodai::Client.new(
  public_id: ENV["OBLODAI_PUBLIC_ID"],
  secret: ENV["OBLODAI_SECRET"]
)
```

Every option falls back to the environment, so the same two variables configure a deployment
without touching code.

## Quick start

Methods are `client.<resource>.<method>`; request fields are keyword arguments named as the API
names them. Create an invoice:

```ruby
invoice = client.payments.create(
  amount: "25",            # a decimal String or a BigDecimal — a Float is refused
  currency: "USDT",        # what you price in — a fiat (USD, EUR, …) or a crypto asset
  network: "tron",         # omit to let the payer choose the network on the pay page
  order_id: "order-1001",  # your reference; idempotent per order_id
  url_callback: "https://shop.example/oblodai/webhook"
)
invoice.url      # the hosted pay page
invoice.address  # where the customer sends the funds
invoice.amount   # a BigDecimal
invoice.status   # "created"
```

To price in fiat, pass `amount: "25", currency: "USD", to_currency: "USDT"` — `currency` is what you
charge, `to_currency` the asset the payer sends. Send money out with the same key:

```ruby
payout = client.payouts.create(
  address: "TQn9Y2khEsLJW1ChVWFMSMeRDow5KNbBav",
  amount: BigDecimal("10"),
  currency: "USDT",
  network: "tron",
  order_id: "payout-1",        # your reference; idempotent per order_id
  idempotency_key: "payout-1"  # your own key survives a process restart
)
payout.uuid
payout.status    # "pending" → … → "confirmed"
```

Runnable scripts live in [`examples/`](examples): `accept_payment.rb`, `payout.rb`, `sandbox.rb`,
`webhook_receiver.rb`. They, and every code block of this README, run in the test suite.

## Sandbox / testing

A sandbox key drives a chainless copy of the gateway: fake balance from a faucet, simulated
deposits, real webhooks. The business endpoints behave exactly as they do live — only the key
changes.

```ruby
sandbox = Oblodai::Client.new(public_id: ENV["OBLODAI_PUBLIC_ID"], secret: ENV["OBLODAI_SECRET"])
sandbox.sandbox.faucet(asset: "USDT", amount: "1000", idempotency_key: "topup-1")

test_invoice = sandbox.payments.create(amount: "25", currency: "USDT", network: "tron", order_id: "sandbox-1")
# No amount pays exactly what is due; repeating a txid adds confirmations instead of paying twice.
deposit = sandbox.sandbox.simulate_deposit(invoice_id: test_invoice.uuid)
deposit.txid
deposit.confirmations
```

- `sandbox.faucet` credits test money. Its `idempotency_key:` goes into the request body (the route
  deduplicates on it), so a retry never tops up twice.
- `sandbox.simulate_deposit` pays an invoice: no `amount:` pays exactly what is due, anything else
  produces an under- or overpayment, and fewer `confirmations:` than required exercises the pending →
  confirmed transition.
- `sandbox.list_webhooks` lists the deliveries with their payloads, `sandbox.replay_webhook` re-sends
  one, `sandbox.reset` cancels the store's open invoices and zeroes its balances.
- `webhooks.send_test_payment` / `send_test_payout` / `send_test_wallet` / `send_test_conversion`
  rehearse a delivery against any receiver: signed like a real event, with `test: true` in the body.

## Method overview

One method per operation of the contract. A method name is the operation's `operationId` without
the resource name, in snake_case (`createPayout` → `payouts.create`, `getBatchInfo` →
`batches.get_info`); `Oblodai::Generated::ROUTES` lists every operation by its `operationId`. The
table below is written by the generator from the contract.

<!-- sdkgen:methods -->
17 resources, 123 methods.

| Resource | Methods |
| --- | --- |
| `payments` | `create` · `get_info` · `get_qr` · `list_history` · `list_services` · `cancel` · `send_email` · `set_checkout_config` · `get_checkout_config` · `get_aml_links` · `resolve` |
| `payment_links` | `create` · `list` · `get` · `toggle` |
| `refunds` | `payment` · `blocked_wallet` |
| `payouts` | `create` · `create_mass` · `get_info` · `list_history` · `calculate` · `validate` · `cancel` · `approve` · `list_services` · `transfer_to_personal` · `transfer_to_user` · `create_transfer_batch` |
| `payout_links` | `create` · `create_batch` · `list` · `get` · `cancel` · `get_payout_claim` · `claim_payout` |
| `batches` | `create_payment` · `create_refund` · `create_payout` · `get_info` |
| `splits` | `create_rule` · `list_rules` · `delete_rule` · `set_config` · `get_config` · `set_recipient_opt_in` · `get_recipient_opt_in` |
| `wallets` | `create` · `block` · `get_qr` |
| `account` | `get_balance` · `get_summary` · `list_exchange_rates` |
| `webhooks` | `resend_payment` · `register` · `list_deliveries` · `requeue_delivery` · `send_legacy_test` · `send_test_payment` · `send_test_wallet` · `send_test_payout` · `send_test_conversion` · `rotate_secret` · `set_active` |
| `settings` | `set_accuracy` · `get_accuracy` · `set_auto_refund` · `get_auto_refund` · `set_discount` · `list_discounts` · `list_api_log` · `get_auto_convert` · `set_auto_convert` · `set_accepted_currencies` · `list_accepted_currencies` · `set_payout_fee_config` · `get_payout_fee_config` · `set_refund_fee_config` · `get_refund_fee_config` · `set_payment_fee_config` · `get_payment_fee_config` · `set_auto_withdraw_rule` · `list_auto_withdraw_rules` · `delete_auto_withdraw_rule` · `configure_vrcs` |
| `api_allowlist` | `list` · `add_entry` · `remove_entry` · `set_enabled` |
| `referrals` | `get_info` |
| `documents` | `get_signed` · `get_balance` · `get_fees` · `get_ledger` · `get_split` · `get_payout_link_cheque` · `get_statement` · `get_batch` · `get_payment_link` · `get_wallet_statement` · `get_referrals` · `create_job` · `get_job` · `download_job_file` |
| `checkout` | `get_source_of_funds_form` · `submit_source_of_funds` · `get_public_payment_link` · `payment_link` · `list_currencies` · `get` · `select_method` · `start_onramp` · `get_onramp` · `get_qr` |
| `sandbox` | `onboard_store` · `faucet` · `simulate_deposit` · `reset` · `list_webhooks` · `replay_webhook` |
| `cli_login` | `start` · `poll` · `logout` |
<!-- /sdkgen:methods -->

The request body of a method comes three ways — keywords, a Hash with the wire names, or a request
model — and keywords add to a Hash or a model. Path parameters are positional (`checkout.get(id)`),
query parameters of the `GET` routes are keywords. Every method also takes the five **call options**:
`idempotency_key:`, `timeout:` (seconds, per attempt), `max_retries:`, `extra_headers:` and
`request_id:` (sent as `X-Request-ID`; a UUID is generated per call otherwise).

```ruby
client.payments.get_info(uuid: invoice.uuid)                                    # keywords
client.payments.get_info({ "order_id" => "order-1001" })                        # a Hash, wire names
client.payments.get_info(Oblodai::Models::LookupRequest.new(order_id: "order-1001")) # a request model
client.payments.get_info(order_id: "order-1001", timeout: 5, max_retries: 0, request_id: "checkout-42")
```

A misspelled keyword is Ruby's own `ArgumentError`, raised before anything is sent. A keyword left at
`nil` is not sent; the few fields where `null` means something (documented as "An explicit nil sends
null") send `null` when you pass `nil` explicitly.

### Models

Responses are frozen `Oblodai::Models::*` objects with one reader per field. Amounts are
`BigDecimal`; enumerations are plain Strings with their values named in `Oblodai::Enums::*`, so a
value this release does not know yet parses like any other; fields newer than this release are kept
in `extra`. `to_h` is the wire form, `inspect` is short and never shows a secret.

```ruby
payment = client.payments.get_info(order_id: "order-1001")
payment.status                                  # "paid"
payment.status == Oblodai::Enums::PaymentStatus::PAID
Oblodai::Status.payment_paid?(payment.status)   # true for paid / paid_over
payment.amount                                  # BigDecimal
payment.extra                                   # fields newer than this release, as sent
payment.to_h                                    # the wire form, amounts as decimal strings
```

### Lists

List methods return a lazy `Oblodai::Page`. `each` walks every item of every page, `each_page` (or
`by_page`) every page, and `first_page` fetches one page with its counters. Nothing is requested
until you consume it.

```ruby
client.payments.list_history(limit: 50).each { |item| puts item.uuid }       # every item
client.payouts.list_history(limit: 50).each_page { |page| puts page.size }  # every page
page = client.payouts.list_history(status: "confirmed", limit: 50).first_page # one request
page.items.size
page.total
page.has_pages?
client.payouts.list_history(kind: "refund").all(1000) # at most 1000 items
```

### Long-running operations

Batches and document jobs return an `Oblodai::Job`: the create answer is `job.result`, and
`job.wait` polls until the job is finished — `completed` or `stopped` for a batch, `done`, `failed`
or `expired` for a document job — and returns the last answer. A document job's file is
`job.download`.

```ruby
job = client.batches.create_payout(
  payouts: [{ address: "TQn9Y2khEsLJW1ChVWFMSMeRDow5KNbBav", amount: "5", currency: "USDT",
              network: "tron", order_id: "batch-1-a" }]
)
job.id
info = job.wait(timeout: 600, interval: 5)
info.status # "completed"

report = client.documents.create_job(kind: "ledger", from: "2026-01-01", to: "2026-02-01", format_: "csv")
report.wait
report.download.save("ledger.csv")
```

### Raw responses, per-client options, hooks

```ruby
raw = client.payments.with_raw_response.create(amount: "25", currency: "USDT", order_id: "order-1002")
raw.status      # 200
raw.request_id  # the response's X-Request-ID, else the one the SDK sent
raw.parse       # the PaymentView the method returns otherwise

patient = client.with_options(timeout: 120, max_retries: 5) # a copy; the original is unchanged
patient.documents.get_ledger(from: "2026-01-01", to: "2026-12-31")

hooks = Oblodai::Hooks.new(
  on_request: ->(info) { puts "-> #{info.method} #{info.url} (#{info.request_id})" },
  on_response: ->(info) { puts "<- #{info.status} in #{info.elapsed.round(3)}s" }
)
observed = Oblodai::Client.new(hooks: hooks)
observed.account.get_balance
```

Hooks run once per attempt, on the calling thread; the signature and the admin token are redacted in
the headers they see.

### Statuses

- Payment: `select → created → confirm_check → paid | paid_over | wrong_amount | expired | cancelled`.
  `Oblodai::Status.payment_paid?` is true for `paid`/`paid_over`; `wrong_amount` (underpaid) waits
  for `payments.resolve(uuid:, action: "accept" | "refund")`.
- Payout: `pending → approved → awaiting_cosign → broadcasting → sent → confirmed | failed | cancelled`.
- Which statuses are final and which of them a success comes from the contract:
  `Oblodai::Enums::PaymentStatus.final?` / `.success?` and `FINAL` / `SUCCESS` (the same for
  `PayoutStatus`), which `Oblodai::Status` uses.

Prefer webhooks for state changes; poll `get_info` only as a fallback.

### Money helpers

Amounts are `BigDecimal` in the models and a decimal String or a `BigDecimal` in requests — a
`Float` anywhere a number is money is `sdk.float_amount`, raised before anything is sent.
`Oblodai::Money.add`, `.subtract`, `.compare`, `.equals?`, `.zero?`, `.negative?` work on either and
keep the widest scale:

```ruby
Oblodai::Money.add("10.000000", BigDecimal("0.5")) # => "10.500000"
Oblodai::Money.compare("9", "10")                  # => -1 (as strings "9" > "10")
```

## Webhooks

`webhooks.register(url:)` sets (or replaces) the endpoint and returns the signing secret — shown
once, so store it where the receiver can read it. Verification needs no client and no API key, and
always runs over the **raw** bytes: a re-serialized parse will not verify.

```ruby
require "oblodai/webhooks"

# The raw body and the request headers in, an HTTP status out.
def receive(body, headers, secret)
  delivery = Oblodai::Webhooks.verify_delivery(body, headers, secret: secret)
  return 200 if delivery.test? # a rehearsal: signed like a live one, but no money moved

  case (event = delivery.event)
  when Oblodai::Models::PaymentWebhook then puts "order #{event.order_id}: #{event.status}"
  when Oblodai::Models::PayoutWebhook then puts "payout #{event.uuid}: #{event.status}"
  when Oblodai::Models::WalletWebhook then puts "wallet #{event.address}: +#{event.payment_amount}"
  end
  200
rescue Oblodai::SignatureError
  401 # forged or stale
rescue Oblodai::WebhookPayloadError
  400 # authentic, but unreadable — never 401
end
```

The checks run in one order: headers, then the HMAC (the current secret, then `previous_secret:`),
then freshness, then the body — the MAC before the clock, so the freshness window is not an oracle
for an unauthenticated caller. Deliveries older or newer than ±300 s are rejected (`tolerance:`
changes the window, `0` disables it).

**The receiver's status-code rule.** Answer 401 **only** when verification failed — a forged or
stale delivery raises `SignatureError`. An authentic delivery whose body this release cannot read is
a `WebhookPayloadError` (`webhook.bad_payload`): the event is real and the gateway will retry it. An
event `type` a newer gateway invented does not raise either: it arrives as the parsed body (a frozen
Hash) — `Oblodai::Webhooks.known_event?(event)` tells the two apart.

Rehearsal deliveries carry `test: true` in the signed body (and `X-Webhook-Test: true`): check
`delivery.test?` and never act on one as if money moved. Deduplicate on `delivery.event_id`
(`X-Webhook-Event-Id`): it names the state and is the same for every retry and every resend of it.
`delivery.id` (`X-Webhook-Id`) names one delivery and changes on a resend (`webhooks.resend_payment`,
a sandbox replay), so a handler keyed on it processes a resent `invoice.paid` twice.
`Oblodai::Webhooks.stale?(event, last_sequence)` drops an out-of-order retry — keep the last
sequence per object, `Oblodai::Webhooks.subject_id(event)` (the `uuid`, or `id` of a conversion). After `webhooks.rotate_secret` pass `previous_secret:` for at least 26 hours.

## Errors

Every failure is an `Oblodai::Error` carrying the API's error envelope; its message reads
`[code] text (request_id=…)`, ready for a log line. Branch on `code` — a stable `family.reason`
string — never on the message.

| Class                       | HTTP          | When                                                              |
| --------------------------- | ------------- | ----------------------------------------------------------------- |
| `ValidationError`           | 400           | malformed request or a business rule; `field` names the culprit   |
| `AuthenticationError`       | 401           | bad signature, unknown key, clock skew, IP not allow-listed       |
| `PermissionError`           | 403           | valid key, not allowed here (feature off, IP not allow-listed)    |
| `NotFoundError`             | 404           | no such object for this merchant                                  |
| `ConflictError`             | 409           | a state conflict                                                  |
| `IdempotencyConflictError`  | 409           | `idempotency.key_reused`: same key, different body                |
| `RateLimitError`            | 429           | `retry_after` is set                                              |
| `UnavailableError`          | 503           | an upstream dependency is down; safe to retry after a pause       |
| `InternalError`             | other 5xx     | the gateway failed                                                |
| `ApiError`                  | anything else | an error status that still carried an envelope                    |
| `TransportError`            | —             | no response at all: DNS, TCP, TLS, timeout, deadline              |
| `ConfigError`               | —             | refused before sending: bad options, a Float amount, no credentials |
| `ContractError`             | —             | the answer could not be read as the documented envelope           |
| `WebhookPayloadError`       | —             | an authentic webhook whose body cannot be read — do not answer 401 |
| `SignatureError`            | —             | a webhook that is not authentic                                   |

Fields: `code`, `text` (the bare description), `http_status`, `retryable?` (authoritative — the SDK
has already retried what it should), `retry_after` (seconds), `request_id` (quote it to support),
`field` (on 400s), `synthetic?` (the answer came from a proxy, not the API).

```ruby
begin
  client.payouts.create(address: "TQn9Y2khEsLJW1ChVWFMSMeRDow5KNbBav", amount: "10", currency: "USDT",
                        network: "tron", order_id: "payout-2")
rescue Oblodai::Error => e
  warn e.message # "[payout.insufficient_funds] … (request_id=…)"
  raise unless e.retryable?
end
```

The catalogue is `Oblodai::Enums::ErrorCode::VALUES`, and every method's documentation lists the
codes it can answer with. Codes worth handling first: `payout.insufficient_funds` and
`payout.funds_maturing` (both retryable), `idempotency.key_reused`, `payment.not_found`,
`merchant.bad_signature`, `request.rate_limited`.

The SDK raises its own families on top, all before or instead of a request: `sdk.missing_credentials`,
`sdk.bad_config`, `sdk.float_amount`, `sdk.bad_amount`, `sdk.bad_body`, `sdk.bad_idempotency_key`,
`sdk.idempotency_unsupported`, `sdk.bad_path_param`, `sdk.bad_header`, `sdk.response_too_large`,
`sdk.bad_envelope`; plus `transport.timeout`, `transport.network`, `transport.deadline` and the
webhook family `webhook.missing_header`, `webhook.bad_signature`, `webhook.stale_timestamp`,
`webhook.bad_payload`. `e.to_h` / `e.to_json` drop the raw response body; `e.raw_body` returns it.

## Retries, idempotency and timeouts

- **Safe to repeat** is not guessed: `Oblodai::Generated::ROUTES[op].safe` comes from the contract's
  `x-retry-safe` (read-only operations).
- An error is retried only when the API says `retryable: true`. Answers without an API envelope (a
  proxy 502/503) and transport failures are retried only on safe routes and on keyed writes.
  `Retry-After` is honoured over the computed backoff.
- **Idempotency keys** are attached automatically on the routes the gateway deduplicates — one per
  call, reused on every retry — so a timeout can never produce a second payout. Pass your own
  `idempotency_key:` to make retries safe across process restarts; on routes the gateway does not
  deduplicate the SDK refuses a key with `sdk.idempotency_unsupported`.
- **Timeouts are seconds.** Per call: `timeout:` (per attempt). Per client: `timeout:` (per attempt,
  30), `deadline:` (the whole call with retries and pauses, 90),
  `retry_policy: { max_retries:, base_delay_ms:, max_delay_ms:, max_retry_after_ms: }`
  (`{ max_retries: 0 }` disables retries); `max_retries:` per call overrides it.
- **Clock skew.** On a 401 that reports a bad signature or timestamp the SDK reads the server `Date`,
  re-signs once, and keeps the offset only if that attempt got past authentication.
- **Redirects are never followed**, **bodies are capped** (8 MiB JSON, 64 MiB documents), and the
  SDK's own headers (`X-Public-Id`, `X-Signature`, `X-Timestamp`, `Idempotency-Key`,
  `X-Request-ID`, `X-Admin-Token`, `Accept`, `User-Agent`, `Content-Type`, `Content-Length`, `Host`)
  win over a caller's; a header with a line break or a non-ASCII byte is `sdk.bad_header`.

## Configuration

```ruby
configured = Oblodai::Client.new(
  base_url: "https://api.oblodai.com",
  timeout: 30,                          # seconds per attempt
  deadline: 90,                         # seconds for the whole call
  retry_policy: { max_retries: 2 },
  headers: { "X-Team" => "checkout" }
)
configured.base_url
```

| Option                          | What it does                                                                   |
| ------------------------------- | ------------------------------------------------------------------------------ |
| `public_id:` / `secret:`        | the merchant's API key; it signs every signed route                            |
| `base_url:`                     | the API origin; a path prefix is kept                                          |
| `allow_insecure_base_url:`      | permit plain `http://` for a non-loopback host                                 |
| `admin_token:`                  | onboarding admin token of a self-hosted gateway (provisioning only)            |
| `http:`                         | your own HTTP adapter: anything answering `call(request, timeout:)`            |
| `timeout:` / `deadline:`        | seconds per attempt (30) / for the whole call (90)                             |
| `retry_policy:`                 | retry policy overrides; `{ max_retries: 0 }` disables retries                  |
| `logger:`                       | anything with `debug/info/warn/error(message, fields)`                         |
| `headers:`                      | extra headers on every request (reserved names are ignored)                    |
| `hooks:`                        | `Oblodai::Hooks.new(on_request:, on_response:)`                                |

| Environment variable       | Meaning                                                            |
| -------------------------- | ------------------------------------------------------------------ |
| `OBLODAI_PUBLIC_ID`        | API key public id                                                  |
| `OBLODAI_SECRET`           | API key secret                                                     |
| `OBLODAI_ADMIN_TOKEN`      | onboarding admin token of a self-hosted gateway                    |
| `OBLODAI_BASE_URL`         | API origin (default `https://api.oblodai.com`)                     |
| `OBLODAI_LOG`              | `debug` \| `info` \| `warn` \| `error` — enables a stderr logger    |
| `OBLODAI_ALLOW_INSECURE`   | `1` permits a plain `http://` base URL                             |

Explicit options win over the environment, and an empty variable counts as unset. Half a key pair is
refused at construction with `sdk.bad_config`. The client, its config, its transport and its
credentials never print a secret, and log fields whose name looks like a secret are redacted before
any logger sees them.

## Generated code

`lib/oblodai/generated/` — routes, enums with their status classes, models, resources and the facts
of the API (long-running operations, webhook kinds, non-money numbers) — is written by `tools/sdkgen`
of the backend repository from the gateway's `services/core/api/openapi.json`, and is never edited
by hand; so are the method table of this README and `names.lock`, the list of every public
`resource.method` (the generator adds new names itself and refuses to drop one unless told to).
`make ci` regenerates into a temporary directory and fails when the committed code differs.

## Development

```bash
git clone https://github.com/oblodai/oblodai-ruby && cd oblodai-ruby
make ci      # drift check, rubocop, unit + contract + conformance specs, gem build (Ruby in docker if absent)
OBLODAI_BACKEND=../oblodai-backend make ci   # the backend checkout with tools/sdkgen and the conformance suite
OBLODAI_LIVE_URL=http://127.0.0.1:8095 bundle exec rake spec:live   # the live journeys against a real gateway
```

Read [AGENTS.md](AGENTS.md) for the same surface in one page, written for coding agents;
[CHANGELOG.md](CHANGELOG.md) for what changed; [MIGRATION-2.0.md](MIGRATION-2.0.md) for the move from
1.x.

## License

MIT — see [LICENSE](LICENSE).
