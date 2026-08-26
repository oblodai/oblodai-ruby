<div align="center">

<a href="https://oblodai.com">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/oblodai/.github/main/brand/logo-white.svg">
    <img src="https://raw.githubusercontent.com/oblodai/.github/main/brand/logo-black.svg" alt="oblodai" height="52">
  </picture>
</a>

<h3>Official Ruby SDK for the <a href="https://oblodai.com">oblodai</a> payment gateway</h3>

Payments, payouts, payment links, splits, static wallets, webhooks — one API key.

<img src="https://img.shields.io/badge/gem-oblodai%201.3.0-E9573F?style=flat-square" alt="gem">
<a href="https://github.com/oblodai/oblodai-ruby/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/oblodai/oblodai-ruby/ci.yml?branch=main&style=flat-square&label=CI" alt="CI"></a>
<img src="https://img.shields.io/badge/ruby-%E2%89%A5%203.1-CC342D?style=flat-square" alt="Ruby version">
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-000000?style=flat-square" alt="License: MIT"></a>

[Documentation](https://docs.oblodai.com) · [Dashboard](https://my.oblodai.com) · [Читать по-русски →](README.ru.md)

</div>

---

The official Ruby SDK for the **Oblodai** payment gateway: accepting payments, payouts, bulk
operations (batches), payment links, payout links (crypto cheques), splits, static wallets,
transfers, webhooks. Request signing, response parsing, typed errors, idempotency and retries — out
of the box. Ruby ≥ 3.1 and **zero runtime dependencies** — `Net::HTTP`, `OpenSSL`, `JSON` and
`SecureRandom` from the standard library are all it uses; every route the gateway exposes has a
method here, generated from the gateway's own contract snapshot and verified against golden
responses recorded from a live core.

> **Base URL.** Defaults to `https://api.oblodai.com`. Override `base_url:` and supply your own keys
> at initialisation if needed. The scheme must be `https://`; plain `http://` is accepted only for
> loopback (`http://127.0.0.1:8095`) or with the explicit allow-insecure option
> (`allow_insecure_base_url: true`, or `OBLODAI_ALLOW_INSECURE=1`).

## Installation

```bash
gem install oblodai
```

Or in a `Gemfile`:

```ruby
gem "oblodai", "~> 1.3"
```

Ruby ≥ 3.1. Webhook verification lives in `oblodai/webhooks` and needs no client and no API key.
Nothing else is pulled in: the gem and its test suite use the standard library only.

## Where to get keys

Keys are issued in the [dashboard](https://my.oblodai.com) → **API keys**. A live pair is a public
id `oblodai_<hex>` and a secret `oblodai_live_<hex>` — one unified API key that opens both the
payment and the payout side. Older merchants may still hold the two kinds separately, as
`oblodai_pk_<hex>` (payment) and `oblodai_wk_<hex>` (payout):

- the **payment key** signs invoices, payment links, wallets, the catalogue, settings and documents;
- the **payout key** signs everything that moves money out: `payouts.*`, `refunds.*` (`resolve`
  included), `payout_links.*`, `transfers.*`, `splits.*`, `wallets.refund_blocked_deposit`,
  `settings.*_auto_withdraw`, `settings.*_api_allowlist`, `webhooks.rotate_secret`,
  `webhooks.test("payout", …)`, `sandbox.faucet`, `sandbox.reset`.

A sandbox pair is a public id `test_oblodai_<hex>` and a secret `oblodai_test_<hex>`; it drives a
chainless copy of the gateway and serves **both** key kinds at once, so one pair is all a sandbox
integration needs. When you do hold two live pairs, pass both and the client picks the right one per
call:

```ruby
client = Oblodai::Client.new(
  public_id: ENV["OBLODAI_PUBLIC_ID"],
  secret: ENV["OBLODAI_SECRET"],
  payout_public_id: ENV["OBLODAI_PAYOUT_PUBLIC_ID"],
  payout_secret: ENV["OBLODAI_PAYOUT_SECRET"]
)
```

Every option falls back to the environment, so the same four variables configure a deployment
without touching code. A call made with the wrong kind is a 403 `merchant.wrong_key_kind`; on a
route that accepts either kind, `prefer_payout_key: true` picks the payout one for that call.
Merchant provisioning (`merchants.create`, `merchants.create_sandbox`) is unsigned — a self-hosted
gateway gates it with an **onboarding admin token** (`admin_token:`, or `OBLODAI_ADMIN_TOKEN`).

## Quick start

Request fields are keyword arguments named exactly as the API names them. Create an invoice:

```ruby
require "oblodai"

client = Oblodai::Client.new # credentials from the environment

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

To price in fiat, pass `amount: "25", currency: "USD", to_currency: "USDT"` — `currency` is what you
charge, `to_currency` the asset the payer sends. Send money out with the payout key:

```ruby
payout = client.payouts.create(
  address: "TQn9Y2khEsLJW1ChVWFMSMeRDow5KNbBav",
  amount: "10",
  currency: "USDT",
  network: "tron",
  order_id: "payout-1",              # your reference; idempotent per order_id
  idempotency_key: "payout-1"        # your own key survives a process restart
)
payout.uuid
payout.status    # "pending" → … → "confirmed"
```

Runnable scripts live in [`examples/`](examples): `accept_payment.rb`, `payout.rb`,
`webhook_receiver.rb`.

## Sandbox / testing

A sandbox key drives a chainless copy of the gateway: fake balance from a faucet, simulated
deposits, real webhooks. The business endpoints behave exactly as they do live — only the key
changes, and a live key on a sandbox route is refused.

```ruby
sandbox = Oblodai::Client.new(public_id: test_public_id, secret: test_secret)
sandbox.sandbox.faucet(asset: "USDT", amount: "1000")

invoice = sandbox.payments.create(amount: "25", currency: "USDT", network: "tron", order_id: "sandbox-1")

# No amount pays exactly what is due; repeating a txid adds confirmations instead of paying twice.
deposit = sandbox.sandbox.deposit(invoice_id: invoice.uuid)
deposit.txid
deposit.confirmations
```

- `sandbox.faucet` credits test money, capped at 1000000 per call (payout key). Give it an
  `idempotency_key:` when a retry must not top up twice.
- `sandbox.deposit` pays an invoice: no `amount:` pays exactly what is due, anything else produces
  an under- or overpayment, and fewer `confirmations:` than required exercises the pending →
  confirmed transition. Repeating a `txid:` adds confirmations instead of paying twice.
- `sandbox.webhooks` lists the deliveries with their payloads — what your receiver would have been
  sent — and `sandbox.replay(delivery_id)` re-sends a terminal one.
- `webhooks.test(kind, **params)` rehearses a delivery against any receiver, sandbox or live: it is
  signed exactly like a real event and carries `test: true` in the signed body (and
  `X-Webhook-Test: true`). Check `delivery.test?` and never act on one as if money moved.
- `sandbox.reset` cancels the store's open invoices and zeroes its balances (payout key).

## Method overview

16 namespaces, 107 routes — the whole merchant surface.

| Namespace       | Methods                                                                                                                                                                                                  | Routes |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| `payments`      | create · info/get · cancel · history/list · batch · qr · services · send_email · resend · public_view · select · public_qr                                                                                | 12     |
| `refunds`       | create · resolve · batch                                                                                                                                                                                  | 3      |
| `payouts`       | create · validate · calculate · info/get · cancel · approve · history/list · mass · batch · services · get/set_fee_config · get/set_refund_fee_config                                                     | 14     |
| `payout_links`  | create · info/get · list · cancel · batch · cheque · claim_preview · claim                                                                                                                                | 8      |
| `payment_links` | create · info/get · list · toggle · public_view · checkout                                                                                                                                                | 6      |
| `transfers`     | to_personal · to_user · batch                                                                                                                                                                             | 3      |
| `batches`       | info/get (asynchronous batch progress)                                                                                                                                                                    | 1      |
| `wallets`       | create · qr · block · refund_blocked_deposit                                                                                                                                                              | 4      |
| `webhooks`      | register · rotate_secret · deliveries · test · test_legacy                                                                                                                                                | 7      |
| `documents`     | statement · ledger · balance_certificate · fee_schedule · split_report · batch_report · link_report · wallet_statement · referrals_report · create_job · job_info · job_file · download                    | 13     |
| `splits`        | create_rule · list_rules · delete_rule · get/set_config · get/set_opt_in                                                                                                                                  | 7      |
| `settings`      | set_discount · list_discounts · get/set_accuracy · get/set_auto_refund · list_accepted · set_accepted · get/set_payment_fee_config · list/set/delete_auto_withdraw · list/add/remove/enable_api_allowlist | 17     |
| `account`       | balance · referral · vrcs (read and set)                                                                                                                                                                  | 3      |
| `catalog`       | currencies · exchange_rates                                                                                                                                                                               | 2      |
| `sandbox`       | faucet · deposit · webhooks · replay · reset                                                                                                                                                              | 5      |
| `merchants`     | create · create_sandbox (provisioning; `admin_token:` on a self-hosted gateway)                                                                                                                           | 2      |

A keyword left at `nil` is omitted from the body rather than sent as an explicit `null` (the gateway
reads both as "not supplied"). Alongside the request fields every method accepts `idempotency_key:`,
`timeout_ms:`, `deadline_ms:` and `prefer_payout_key:`; a misspelled option is refused by name
(`sdk.bad_config`) instead of failing deep inside the SDK.

Lookups take a bare uuid, either keyword, or the model the SDK returned:
`payments.info("uuid")`, `payments.info(uuid: "uuid")`, `payments.info(order_id: "o-1")`,
`payments.info(invoice)`. The same holds for every id argument (`payout_links.info(link)`,
`batches.info(batch)`, `splits.delete_rule(rule)`).

Synchronous batches are capped by the gateway — `payouts.mass` at 100 elements and
`payout_links.batch` at 500 — with each element reporting its own `{idx, ok, result, message}`.
The asynchronous ones (`payments.batch`, `payouts.batch`, `refunds.batch`, `transfers.batch`) take
up to 5000 and are polled with `batches.info(id, limit:, offset:)`. Document routes answer outside the JSON envelope
and return an `Oblodai::FileResult`.

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

### Money helpers

`Oblodai::Money.add`, `.subtract`, `.compare`, `.equals?`, `.zero?`, `.negative?`, `.valid?` — exact
decimal arithmetic on the string amounts the API uses. Never `to_f` an amount, and never order
amounts with `<`, `sort` or `max`: `"9" < "10"` is true as strings and false as money. Anything that
is not `-?digits[.digits]` of at most 64 characters raises `Oblodai::ConfigError` (`sdk.bad_amount`)
rather than a `TypeError` from inside a helper.

## Webhooks

`webhooks.register(url)` sets (or replaces) the endpoint and returns the signing secret — shown
once, so store it where the receiver can read it. Verification needs no client and no API key, and
always runs over the **raw** bytes: a re-serialized parse will not verify.

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

The checks run in one order: headers, then the HMAC (the current secret, then `previous_secret:`),
then freshness, then the body — the MAC before the clock, so the freshness window is not an oracle
for an unauthenticated caller. Deliveries older or newer than ±300 s are rejected (`tolerance:`
changes the window, `0` disables it; a negative one is a `ConfigError`, as is an empty `secret:` or
`previous_secret:`).

**The receiver's status-code rule.** Answer 401 **only** when verification failed — a forged or
stale delivery raises `SignatureError`. An authentic delivery whose body this release cannot read is
a `WebhookPayloadError` (`webhook.bad_payload`) instead, a contract error rather than a signature
one: the event is real and the gateway will retry it, so a 401-on-signature-failure receiver does
not reject a genuine event it merely could not parse. An event `type` a newer gateway invented does
not raise either: it arrives as `Oblodai::Models::UnknownEvent` with its raw `type` and fields —
narrow with `Oblodai::Webhooks.known_event?(event)` before switching on `type`.

Rehearsal deliveries (`webhooks.test`, sandbox) are signed exactly like live ones and carry
`test: true` in the body (and `X-Webhook-Test: true`): check `delivery.test?` — or
`Oblodai::Webhooks.test_event?(event)` when you only have the parsed event — and never act on one as
if money moved. `delivery.id` (`X-Webhook-Id`) is stable across retries — deduplicate on it;
`event.sequence` orders events (`Oblodai::Webhooks.stale?(event, last_sequence)`, false whenever the
sequence is missing). After `webhooks.rotate_secret` pass `previous_secret:` for at least 26 hours:
deliveries queued before the rotation stay signed with the old secret for their whole retry life.

## Errors

Every failure is an `Oblodai::Error` carrying the API's error envelope. Branch on `code` — a stable
`family.reason` string — never on the message.

| Class                       | HTTP          | When                                                            |
| --------------------------- | ------------- | ---------------------------------------------------------------- |
| `ValidationError`           | 400           | malformed request or a business rule; `field` names the culprit   |
| `AuthenticationError`       | 401           | bad signature, unknown key, clock skew, IP not allow-listed       |
| `PermissionError`           | 403           | valid key, not allowed here (wrong key kind, feature off)         |
| `NotFoundError`             | 404           | no such object for this merchant                                  |
| `ConflictError`             | 409           | a state conflict                                                  |
| `IdempotencyConflictError`  | 409           | `idempotency.key_reused`: same key, different body                |
| `RateLimitError`            | 429           | `retry_after` is set                                              |
| `UnavailableError`          | 503           | an upstream dependency is down; safe to retry after a pause       |
| `InternalError`             | other 5xx     | the gateway failed                                                |
| `ApiError`                  | anything else | an error status that still carried an envelope                    |
| `TransportError`            | —             | no response at all: DNS, TCP, TLS, timeout, deadline              |
| `ConfigError`               | —             | refused before sending: bad options, missing credentials          |
| `ContractError`             | —             | the answer could not be read as the documented envelope           |
| `WebhookPayloadError`       | —             | an authentic webhook whose body cannot be read — do not answer 401 |
| `SignatureError`            | —             | a webhook that is not authentic                                   |

Fields: `code`, `message`, `http_status`, `retryable?` (authoritative — the SDK has already retried
what it should), `retry_after` (seconds), `request_id` (quote it to support), `field` (on 400s),
`synthetic?` (the answer came from a proxy, not the API).

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

The catalogue is `Oblodai::Enums::ERROR_CODES` — all 471 error codes the gateway can answer with,
shipped in the contract snapshot. Codes worth handling first: `payout.insufficient_funds` and
`payout.funds_maturing` (both retryable), `idempotency.key_reused`, `invoice.not_payable`,
`payment.not_found`, `merchant.wrong_key_kind`, `merchant.bad_signature`, `request.rate_limited`.
The SDK raises its own families on top, all before or instead of a request:
`sdk.missing_credentials`, `sdk.bad_config`, `sdk.bad_idempotency_key`,
`sdk.idempotency_unsupported`, `sdk.bad_path_param`, `sdk.bad_header`, `sdk.bad_amount`,
`sdk.response_too_large`, `sdk.bad_envelope`; plus `transport.timeout`, `transport.network`,
`transport.deadline` and the webhook family `webhook.missing_header`, `webhook.bad_signature`,
`webhook.stale_timestamp`, `webhook.bad_payload`.

`e.to_h` / `e.to_json` keep the message and drop the raw response body, so a structured log never
prints an API payload; `e.raw_body` still returns it for debugging.

## Retries, idempotency and timeouts

- **Safe to repeat** is not guessed: `Oblodai::Contract::ROUTES[key].safe` is the gateway's own
  read-only classification, shipped in the contract snapshot.
- An error is retried only when the API says `retryable: true`. Answers without an API envelope (a
  proxy 502/503) and transport failures are retried only on read routes and on keyed writes.
  `Retry-After` is honoured over the computed backoff.
- **Idempotency keys** are attached automatically on create-type routes — one per logical call,
  reused on every retry — so a timeout can never produce a second payout. Pass your own
  `idempotency_key:` to make retries safe across process restarts; on routes the gateway does not
  deduplicate (list routes included) the SDK refuses a key with `sdk.idempotency_unsupported`
  rather than let you believe a re-send is safe, and an unusable key is `sdk.bad_idempotency_key`.
- **Per call:** `idempotency_key:`, `timeout_ms:`, `deadline_ms:`, `prefer_payout_key:`.
  **Per client:** `timeout_ms:` (per attempt, 30 s), `deadline_ms:` (attempts plus pauses, 90 s),
  `retry_policy: { max_retries:, base_delay_ms:, max_delay_ms:, max_retry_after_ms: }`
  (`{ max_retries: 0 }` disables retries). A `retry_after` hint is reported up to 24 h and slept for
  at most `max_retry_after_ms` (30 s).
- **Clock skew.** On a 401 that reports a bad signature or timestamp the SDK reads the server `Date`,
  re-signs once, and keeps the offset only if that attempt got past authentication. The offset is
  shared safely between threads: a correction is reverted only while no other call has moved it.
- **Redirects are never followed**: a signed request must not be replayed against another origin, so
  a redirect is reported as an error — including one an injected HTTP adapter followed on its own.
- **Body size caps**: 8 MiB on JSON routes, 64 MiB on document routes — a larger answer is
  `sdk.response_too_large` rather than something buffered into memory.
- **Reserved headers** win over a caller's `headers:`, compared case-insensitively: `X-Public-Id`,
  `X-Signature`, `X-Timestamp`, `Idempotency-Key`, `X-Admin-Token`, `Accept`, `User-Agent`,
  `Content-Type`, `Content-Length`, `Host`. A header carrying a line break or a non-ASCII byte is
  refused with `sdk.bad_header` before anything is sent.

## Configuration

| Option                          | What it does                                                                   |
| ------------------------------- | -------------------------------------------------------------------------------- |
| `public_id:` / `secret:`        | the payment key pair (also used for payout routes when no payout pair is set)     |
| `payout_public_id:` / `payout_secret:` | the dedicated payout key pair                                              |
| `base_url:`                     | the API origin; a path prefix is kept                                             |
| `allow_insecure_base_url:`      | permit plain `http://` for a non-loopback host                                    |
| `admin_token:`                  | onboarding admin token of a self-hosted gateway (provisioning routes only)        |
| `http:`                         | your own HTTP adapter: proxy, instrumentation, a recorded fake                    |
| `timeout_ms:`                   | per-attempt timeout (default 30 000)                                              |
| `deadline_ms:`                  | budget for one call including retries and pauses (default 90 000)                 |
| `retry_policy:`                 | retry policy overrides; `{ max_retries: 0 }` disables retries                     |
| `logger:`                       | anything with `debug/info/warn/error(message, fields)`                            |
| `headers:`                      | extra headers on every request (reserved names are ignored)                       |

| Environment variable       | Meaning                                                          |
| -------------------------- | ------------------------------------------------------------------ |
| `OBLODAI_PUBLIC_ID`        | payment key public id                                              |
| `OBLODAI_SECRET`           | payment key secret                                                 |
| `OBLODAI_PAYOUT_PUBLIC_ID` | payout key public id                                               |
| `OBLODAI_PAYOUT_SECRET`    | payout key secret                                                  |
| `OBLODAI_ADMIN_TOKEN`      | onboarding admin token of a self-hosted gateway                    |
| `OBLODAI_BASE_URL`         | API origin (default `https://api.oblodai.com`)                     |
| `OBLODAI_LOG`              | `debug` \| `info` \| `warn` \| `error` — enables a stderr logger    |
| `OBLODAI_ALLOW_INSECURE`   | `1` permits a plain `http://` base URL                             |

Explicit options win over the environment, and an empty variable counts as unset. Half a key pair
(an id without its secret, or the other way round) is refused at construction with `sdk.bad_config`;
missing credentials surface later, on the first call that needs them.

**Secrets never print.** `WebhookEndpoint#secret`, `WebhookSecretRotated#secret`, `ApiKeyPair#secret`,
`PayoutLink#claim_token` and `PayoutLink#passcode` read normally through their own accessor and
render as `"[redacted]"` in `to_h`, `to_json` and `inspect`, so a debug log or an audit record
cannot carry them — store them by reading the accessor, not by serialising the model. The same holds
for the client, its config, its transport and its credentials, and log fields whose name looks like
a secret are redacted before the value reaches any logger.

**Self-hosted or local gateway.** `base_url: "http://127.0.0.1:8095"` works out of the box; any
other plain-http host needs `allow_insecure_base_url: true` (or `OBLODAI_ALLOW_INSECURE=1`). A path
prefix in the base URL is kept, so `https://gw.corp/oblodai` reaches
`https://gw.corp/oblodai/v1/payment` — and the signature covers the prefixed path. Need a different
HTTP stack? Pass `http:` — anything answering `call(request, timeout_ms:)` with an
`Oblodai::HTTP::Response`. The request carries `max_bytes` (the ceiling for that route) and the
response may carry the `url` it was answered from; an adapter that followed a redirect is detected
and refused.

## The contract snapshot

`contract/` is exported by the gateway's own test suite: the route registry (107 routes, each with
the gateway's own `safe` flag, auth gate, idempotency behaviour and list kind), request DTO schemas
with English field docs, every vocabulary and all 471 error codes, signing vectors, golden response
bodies recorded from a live gateway and 43 real signed webhook deliveries. It ships with the gem and
is readable at `Oblodai.contract_path`. `lib/oblodai/contract/` is generated from it and is never
edited by hand; `Oblodai::Contract::CORE_COMMIT`, `EXPORTED_AT` and `CONTRACT_HASH` identify the
snapshot in use (core commit `7ec04293`).

```bash
rake codegen   # regenerate routes.rb, enums.rb, requests.rb after refreshing contract/
rake drift     # CI gate: fail when the committed code is not what codegen produces
```

The machine-readable surface ships with the gem too: `Oblodai::Contract::ROUTES` (107 routes),
`Oblodai::Contract::REQUESTS` (every documented request field with its type, vocabulary and English
description) and `Oblodai::Enums::*` (statuses, networks, fee bearers, event types, error codes).
The contract tier of the suite is a completeness gate, not a sample: every route must have a method
wired to the right path, auth gate and idempotency behaviour, and every recorded response body must
decode into a model whose fields match the wire key for key.

## Development

```bash
git clone https://github.com/oblodai/oblodai-ruby && cd oblodai-ruby
bundle install
rake ci          # rubocop + contract drift + unit and contract specs
rake yard        # the YARD reference into doc/
OBLODAI_LIVE_URL=http://127.0.0.1:8095 rake spec:live   # the live journeys against a real gateway
gem build oblodai.gemspec
```

Source files stay under ~400 lines, and specs live next to what they test. Read
[AGENTS.md](AGENTS.md) for the same surface in one page, written for coding agents;
[CHANGELOG.md](CHANGELOG.md) for what changed; [MIGRATION-1.3.md](MIGRATION-1.3.md) for the move
from 1.2.

## License

MIT — see [LICENSE](LICENSE).
