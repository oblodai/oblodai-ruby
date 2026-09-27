# Changelog

All notable changes to this gem. The format follows [Keep a Changelog](https://keepachangelog.com/),
versions follow [SemVer](https://semver.org/).

## Unreleased

### Security

- Webhooks: every decision now comes from the signed body. `Delivery#event_key` (and
  `Oblodai::Webhooks.event_key(event)`) is the dedupe key: dedupe on `event_id` (fallback
  `type:id:sequence`), read from the signed body. The body's `event_id`
  (`Oblodai::Webhooks::EVENT_ID_FIELD`) is the same across retries and resends of one state; a
  delivery from an older core without it keys on `"<type>:<object id>:<sequence>"`. The webhook
  models gain an optional `event_id`; a present but empty or non-string one is
  `webhook.bad_payload`; `Delivery#test?` is the body's `test: true` only. The unsigned headers moved
  to `unverified_delivery_id`, `unverified_event_id`, `unverified_event_type`,
  `unverified_event_time` and `unverified_test_header` (breaking: `id`, `event_id`, `event_type` and
  `event_time` are gone). A captured delivery replayed with a new `X-Webhook-Event-Id` no longer
  passes header-based dedupe, and an `X-Webhook-Test: true` header can no longer make a real payment
  look like a rehearsal. README, AGENTS.md and the receiver example dedupe on the signed key and
  always ignore test deliveries.

- Clock skew: a `Date` header can move the signing clock by at most ±900 s (was ±24 h), and the
  offset is installed for the client only after the re-signed attempt succeeds (2xx); any other
  outcome discards it. Before, one 401 answer could shift every later signature up to a day into
  the future, and the shift stuck after any non-signature answer.

- The SDK never sends a raw admin token (`X-Admin-Token`) any more. The core accepts only its
  operator HMAC channel on the onboarding routes, which the SDK does not implement:
  `sandbox.onboard_store` now raises `Oblodai::ConfigError` (`sdk.operator_channel_unsupported`,
  "operator channel is not supported by the SDK; use the dashboard") before any request. The
  `admin_token:` option is deprecated and ignored (a one-time warning on stderr, and a warning to
  the configured logger); `OBLODAI_ADMIN_TOKEN` is no longer read, and `Config#admin_token` is gone.

- Base URL: `user:password@`, a query and a fragment are refused with `ConfigError` (and never
  echoed; no config error repeats the URL any more); before, the userinfo was silently dropped.
  Plain `http://` now needs `allow_insecure_base_url: true` / `OBLODAI_ALLOW_INSECURE=1` for
  loopback hosts too.

- `RequestBuilder::Credentials` no longer prints its secret through `pp` / `pretty_inspect` (how
  IRB and the Rails console show values): `pretty_print`, `to_a`/`deconstruct` and
  `deconstruct_keys` are redacted like `inspect` already was.
- Redaction: hook `RequestInfo#url` and every error message show the claim `{token}` of
  `/v1/claim/{token}` and `/v1/aml/{token}` and a signed link's `sig`/`exp` as `[redacted]` (the
  wire keeps the real values); a redirect names only the target's scheme and host; the Net::HTTP
  adapter's size and network errors name the redacted URL (adapters get it as
  `HTTP::Request#display_url`). Hook request and response headers mask every credential-like header
  (`Authorization`, `X-Api-Key`, `X-Claim-Passcode`, cookies, …), not only the signature.
  `device_code` and `api_key`/`X-Api-Key` join the redacted names in model `inspect` and logs, and
  `RequestBuilder::Built` / `HTTP::Request` `inspect`/`pp` show only the method and the redacted URL.

- `FileResult#save` never clobbers: an existing file or a symlink at the target (the server-chosen
  name in the working directory included — a `.bashrc`, a `Gemfile`) is `Errno::EEXIST` unless
  `overwrite: true`, and the file is created with `0600` permissions. `FileResult#filename` is now
  the safe basename itself (no directories, no control characters, never `.`/`..`).

- Request bodies are refused above the contract's `MAX_BODY` (1 MiB) with `ConfigError`
  `sdk.body_too_large` before anything is signed or sent; a `BigDecimal` with a huge exponent
  (`BigDecimal("1e200000000")`) is refused before `to_s("F")` expands it into a 200 MB string, and
  the money helpers bound a `BigDecimal`'s rendered length the same way (64 characters).

- Pagination stops only on an empty page or once the offset reaches `paginate.total` (the
  `has_pages` flag decides only when an answer carries no `total`), the rule every Oblodai SDK now
  shares; a page shorter than the requested `limit` never ends the walk.

- The recorded onboarding fixtures no longer carry real-format captured keys: their
  `oblodai_live_…` / `oblodai_test_…` secrets and public ids are all-zero placeholders of the same
  format.

- CI and release: GitHub Actions are pinned to full commit SHAs, checkouts do not persist the
  token, CI runs with a read-only token, and the release is split into a read-only gate job (all
  specs) and a publish job that holds the RubyGems key and the write token but installs no
  development gem. The backend's `openapi.json` and conformance suite are vendored in
  `contract/snapshot` (not shipped in the gem), so public CI runs the signing vectors and the
  conformance suite without the private backend; the drift check fails when the snapshot differs
  from the backend. The gem ships only git-tracked files, and `.env` files are git-ignored.

### Added

- `client.cli_login` — `start`, `poll`, `logout`: the browser login of the `oblodai` CLI (OAuth
  2.0 device authorization) and logout of its key.
- `Oblodai::Error#details`: the machine-readable facts of an error envelope's new `details` object
  (for example `cli.permission_denied` carries `required_role` and `role`); only string values are
  kept.
- Every method's documentation names the minimum team role a CLI key needs to call it;
  money-out operations (payouts, refunds, transfers, auto-withdrawal, split rules) take only the
  store owner's own CLI key.
- `client.refunds.calculate` (POST /v1/payment/refund/calculate): dry-run a refund and get back a
  `Models::RefundCalculation` — `amount`, `currency`, `network`, `address`, `amount_paid`,
  `surcharge`, `commission`/`commission_bearer`, `credited`, `refundable`, `refunded`, `remaining`,
  and, with `from_currency` set, the estimated `from_amount`. Runs the same checks as
  `refunds.payment` and reserves/sends nothing.

### Changed

- `Models::PayoutValidateResult` (`payouts.validate`) gains `address` (the destination), and, for
  a `from_currency` payout, `from_amount` and `rate` alongside the existing `funded_by`.
- `PayoutRequest#memo` / `PayoutValidateRequest#memo` docs are now network-specific: the XRP
  destination tag, the Stellar memo id, a TON comment (at most 64 bytes), and at most 120 bytes on
  every other network.
- **Breaking:** `payments.list_history` takes its own request model `Models::PaymentHistoryRequest`
  (`limit`, `offset`, `status`) instead of the shared `Models::HistoryRequest`;
  `Models::HistoryRequest` now serves `payouts.list_history` only. The payment feed never honoured
  `kind`/`include_refunds`, so the new model drops them, and `status` filters by the payment status
  vocabulary. Migration: pass only `limit:`, `offset:` and `status:` to `payments.list_history`, or
  build `Models::PaymentHistoryRequest`.
- Method docs: the payout calculation lists `payout.unsupported_network` for an unknown network;
  lookup, test-webhook (`ok` / `status_code`) and refund amount fields are described more precisely.
  The webhook signing constants already carry the event-id and delivery-id header names that the
  contract now names as `event_id_header` / `delivery_id_header`.

- Method docs: refunds explicitly follow the store's refund fee setting (`getRefundFeeConfig`)
  — when the merchant bears the Oblodai commission, refunds debit more than the payment
  credited, paid from the merchant's balance. `refunds.calculate` docs now list
  `payout.insufficient_funds` and `payout.convert_insufficient` among the errors it can return.

## [2.0.0] — 2026-09-25

The SDK is generated from the gateway's OpenAPI contract (`services/core/api/openapi.json`) by the
backend's `tools/sdkgen`, on top of a hand-written runtime. Breaking: method names, options, models
and the minimum Ruby change — every old name and its new one is in [MIGRATION-2.0.md](MIGRATION-2.0.md).

### Added

- a `Float` amount is `sdk.float_amount` before anything is sent; `BigDecimal` goes to the wire as
  its decimal string; `Oblodai::Money` takes `BigDecimal`.
- `X-Request-ID` on every call (yours via `request_id:`, else a UUID), the same on every attempt.
- `resource.with_raw_response.<method>` (status, headers, request id, `parse`),
  `client.with_options(...)`, `Oblodai::Hooks` on request and response.
- `Page#each_page` / `#by_page`, `PageResult#total` / `#has_pages?`.
- `Oblodai::Job` for batches and document jobs: `wait`, `download`; which operations are long
  and how to poll them comes from the contract (`x-sdk-poll`, `Oblodai::Generated::LRO`).
- facts of the API generated from the contract rather than kept by hand: status classes
  (`Oblodai::Enums::PaymentStatus.final?` / `.success?`, behind `Oblodai::Status`), webhook kinds
  and their models (`Oblodai::Generated::WEBHOOK_MODELS`), non-money numbers of requests.
- `Delivery#event_id` (`X-Webhook-Event-Id`): the id of the state a delivery carries, the same
  across retries and resends — the key to deduplicate on (`Delivery#id` changes on a resend);
  `Oblodai::Webhooks.subject_id(event)` — the object's id by kind (`Generated::WEBHOOK_ID_FIELDS`).
- the signing protocol from the contract (`x-oblodai-signing`, `Oblodai::Generated::SigningProtocol`):
  request and webhook header names, the order and separators of the canonical strings, the skew
  window and the idempotency key limit. `Oblodai::Signing::HEADER_*`, `SKEW_SECONDS`,
  `Oblodai::Webhooks::HEADER_*` (the rehearsal header `HEADER_TEST` too, from
  `webhook.test_header`), `DEFAULT_TOLERANCE` and `Oblodai::Idempotency::MAX_KEY_LENGTH` stay, now as
  the generated values; the conformance suite checks the request a signed call actually sends —
  method, path and query, body and the headers under the contract's names.
- the shared conformance suite of the backend (`spec/conformance`), README and example snippets run
  in the specs, and a drift check of the generated code in `make ci`.

### Changed

- every method is `client.<resource>.<method>`, one per operation, named after its
  `operationId`; `names.lock` pins the public names: the generator adds new ones itself and refuses
  to drop one silently.
  16 namespaces: `payments`, `payment_links`, `refunds`, `payouts`, `payout_links`, `batches`,
  `splits`, `wallets`, `account`, `webhooks`, `settings`, `api_allowlist`, `referrals`,
  `documents`, `checkout`, `sandbox`.
- request bodies: keyword arguments, a Hash with the wire names, or a request model; path
  parameters positional, query parameters keywords. A field given both in the Hash (or model) and
  as a keyword — the sandbox faucet's `idempotency_key` too — is `Oblodai::ConfigError`
  `sdk.bad_config` before anything is sent, as in every Oblodai SDK.
- responses are generated frozen models with `BigDecimal` amounts, unknown fields in `extra` and
  unknown enum values kept as strings; enumerations are `Oblodai::Enums::<Name>` constants.
- call options are explicit: `idempotency_key:`, `timeout:` (seconds), `max_retries:`,
  `extra_headers:`, `request_id:`; client timeouts `timeout:` / `deadline:` in seconds; the HTTP
  adapter seam is `call(request, timeout:)`.
- `e.message` is `[code] text (request_id=…)`; the bare text is `e.text`.
- webhooks parse into the generated model of their kind (`PaymentWebhook`, `PayoutWebhook`,
  `WalletWebhook`, `ConversionWebhook`); an unknown kind is the frozen parsed body.
- `Oblodai::Generated::ROUTES` (keyed by `operationId`) replaces `Oblodai::Contract::ROUTES`; the
  retry-safe flag comes from the contract's `x-retry-safe`.
- Ruby ≥ 3.2; runtime dependency `bigdecimal`.

### Removed

- the contract snapshot as a runtime artefact (`Oblodai.contract_path`, `Contract::REQUESTS`,
  `Enums::ERROR_CODES`; the catalogue is `Oblodai::Enums::ErrorCode::VALUES`), the Ruby code
  generator `script/codegen.rb`, `merchants.create`, the 1.x method aliases.

## [1.3.0] — 2026-08-26

First release of the Ruby SDK, generated from the gateway's contract snapshot (core `2cc44c1`) and
verified against it. Migration notes: [MIGRATION-1.3.md](MIGRATION-1.3.md).

### Added

- every merchant route the gateway declares (107) across `payments`, `refunds`, `payouts`,
  `payout_links`, `payment_links`, `batches`, `transfers`, `wallets`, `webhooks`, `documents`,
  `splits`, `settings`, `account`, `catalog`, `sandbox` and `merchants`.
- request signing with the gateway's five-field recipe
  (`ts \n METHOD \n path+query \n Idempotency-Key \n body`), verified against the core's own signing
  vectors — the four-field recipe of the 1.x SDKs is rejected by the gateway with 401.
- models for every documented response body, with the English description of each field and a
  contract suite that compares their key sets with golden bodies recorded from a live gateway.
- retries driven by the API's authoritative `retryable` flag, never re-sending a write the
  gateway does not deduplicate; automatic idempotency keys reused across retries; `Retry-After`,
  exponential backoff with jitter, per-attempt timeout and per-call deadline.
- clock-skew correction from the response `Date`, reverted when the re-signed attempt is
  still rejected.
- lazy `Oblodai::Page` — `Enumerable` across pages, `first_page` for one page, nothing
  requested until consumed.
- `Oblodai::Webhooks` — `verify`, `verify_delivery`, `parse` and `stale?`, with rotation
  support (`previous_secret:`) and a ±300 s freshness window; verified against real signed deliveries.
- `Oblodai::Money` for exact decimal arithmetic on the string amounts the API uses.
- the contract snapshot (`contract/`), the code generator (`rake codegen`) and the drift gate
  (`rake drift`); `Oblodai::Contract::ROUTES`, `Oblodai::Contract::REQUESTS` and `Oblodai::Enums::*`
  ship as a machine-readable surface.
- `merchants` namespace — `create` and `create_sandbox` provision merchants on a self-hosted
  gateway. Both are unsigned and gated by an admin token: `admin_token:` or `OBLODAI_ADMIN_TOKEN`,
  sent as `X-Admin-Token` on those two routes and nowhere else.
- rehearsal deliveries are flagged — `delivery.test?` / `Oblodai::Webhooks.test_event?` is
  true for `webhooks.test` and sandbox events (`test: true` in the signed body, `X-Webhook-Test`
  header). They are signed exactly like live ones, so a handler must check the flag and never act as
  if money moved.
- the wallet model carries `blocked`, and `wallets.refund_blocked_deposit` documents the
  refund-family codes it can answer with.
- `Oblodai::Models::UnknownEvent` and `Oblodai::Webhooks.known_event?` — a webhook `type` a
  newer gateway invented comes back verbatim instead of raising.
- `Oblodai::WebhookPayloadError` (`webhook.bad_payload`).
- `Oblodai::Money.equals?`, `.valid?`, `.negative?`.
- `batches.info(id, limit:, offset:)` — the per-row `items` of a big batch are paged by the
  gateway and can now be walked; `payment_links.info` already exposed the same pair.
- every id argument also accepts the model the SDK returned (`payout_links.info(link)`,
  `batches.info(batch)`, `splits.delete_rule(rule)`, `payments.info(invoice)`), and every
  uuid-or-order_id lookup accepts `uuid:` as a keyword as well as positionally.

### Fixed

- **A 2xx body without a usable `state` is a `ContractError`, not a `NoMethodError`.** The decoder
  called `#zero?` on whatever `state` happened to be; a proxy answering `200 {"result":{}}` raised a
  Ruby exception outside the `Oblodai::Error` family, past every `rescue Oblodai::Error` in the
  caller's code.
- **Retry safety comes from the contract, not from the shape of a path.** `ROUTES[key].safe` is the
  gateway's own hand-written read-only classification, exported in `contract.json`; the codegen fails
  if any route lacks it. The previous path-suffix heuristic would have mis-classified the first new
  route whose name happened to end in `/info`, `/list` or `/get`.
- **The route registry is frozen down to each route.** The `ROUTES` hash was frozen but the `Route`
  structs inside it were not: any caller could have flipped `safe` or `auth` for the whole process.
- **The error envelope is decoded field by field.** A peer that answers with the envelope's shape and
  the wrong types can no longer steer the SDK: a non-string `code` demotes the body to "no envelope"
  (keeping `request_id`), a non-string `message` falls back to `HTTP <status>`, only a literal
  `true`/`false` is accepted for `retryable`, and `retry_after` (and the `Retry-After` header,
  delta-seconds or HTTP-date) is clamped to `[0, 86400]` seconds — never negative, never a wait
  computed from garbage. The retry loop still sleeps at most `max_retry_after_ms`.
- **Concurrent calls survive a clock-skew correction.** Each attempt remembers the offset it was
  signed with and compares the server's time against that, not against the shared offset a sibling
  call may already have fixed; a correction is reverted only if the shared offset is still the one
  this call installed. The offset and the retry jitter source are guarded by a mutex, so the
  documented thread safety of a client is real.
- **Webhook verification order and inputs.** An empty `secret` (or an empty `previous_secret`) is a
  `ConfigError` before any hashing, instead of verifying with the empty key; a negative or
  non-integer `tolerance` is a `ConfigError` and `0` disables the freshness check. The HMAC is
  checked **before** the timestamp, so the freshness window is not an oracle for an unauthenticated
  caller. Signature headers tolerate surrounding whitespace and upper-case hex and reject a `0x`
  prefix; `X-Webhook-Test` is recognised whatever its case.
- **An authentic delivery with an unreadable body is `webhook.bad_payload`**, a
  `WebhookPayloadError` in the contract family — not a `SignatureError`. A receiver that answers 401
  to forged deliveries no longer answers 401 to a genuine one it simply could not parse.
- **An unknown event `type` no longer raises**, and `Oblodai::Webhooks.stale?` returns `false`
  instead of raising when `sequence` is missing or not an integer. `test_event?` reads a
  string-keyed body as well as a symbol-keyed one.
- **Secrets never print.** The client, its config, its transport, the resolved credentials and every
  secret-bearing model (`WebhookEndpoint#secret`, `WebhookSecretRotated#secret`, `ApiKeyPair#secret`,
  `PayoutLink#claim_token`/`#passcode`) render as `[redacted]` in `inspect`, `to_h` and `to_json`
  while still reading normally through their own accessor. A logger passed as `logger:` is wrapped,
  so it receives fields that were redacted before it saw them.
- **Header rules.** The headers the SDK owns (`Accept`, `Content-Type`, `User-Agent`, `X-Public-Id`,
  `X-Signature`, `X-Timestamp`, `Idempotency-Key`, `X-Admin-Token`) beat a caller header of the same
  name whatever its casing; a caller value containing CR/LF or a non-ASCII character is refused with
  `sdk.bad_header` before anything is sent.
- **Response bodies are bounded**: 8 MiB for JSON routes, 64 MiB for document routes, refused as
  `sdk.response_too_large` rather than buffered — the Net::HTTP adapter stops reading at the cap. A
  redirect is never followed, and one an injected adapter followed is detected and reported.
- **`Net::HTTP#max_retries = 0`.** Net::HTTP silently replays an idempotent request once when the
  connection drops before the answer; every GET was leaving the process twice per attempt, and the
  decision about what may be repeated belongs to the SDK.
- **`FileResult#save` writes a basename, never a path.** A `Content-Disposition` of
  `filename="../../etc/cron.d/x"` chose where the file landed; the suggested name is now reduced to
  a single segment (`#safe_filename`), and an unusable one asks the caller for a path.
- **Money helpers refuse what they cannot compute**: `-?digits[.digits]`, at most 64 characters —
  anything else raises `Oblodai::ConfigError` / `sdk.bad_amount` instead of a native `TypeError`.
  `Money.equal?` (which redefined `Object#equal?` with two arguments) is now `Money.equals?`.
- **An `idempotency_key:` passed to a list method** raises `sdk.idempotency_unsupported` instead of
  being silently dropped, and a client-side key rejection is a `ConfigError`, not a `ValidationError`
  claiming the API answered 400.
- `webhooks.test` refuses a kind the gateway has no route for (`sdk.bad_config`) instead of raising
  `KeyError` from inside the route registry; a misspelled per-call option is named the same way
  instead of surfacing as an `ArgumentError` from the transport.
- Models freeze the arrays and hashes they decoded, not just their top-level attribute hash, and
  compare on their values rather than on their redacted rendering.
- Empty-string credentials and base URLs are treated as unset rather than signed with; a `base_url`
  without a scheme or host is refused up front.
- Generated code is English only: the codegen no longer copies a non-ASCII example string out of the
  core's own annotations.
- Removed dead surface: `Oblodai::Util.compact`, `Oblodai::Util.symbolize`.

### Changed

- The contract snapshot is core `2cc44c1`: 107 routes, 469 error codes (`autopilot.freeze_unknown`
  and `autopilot.frozen` are new), and every route now declares `safe`.
- One API key: the payout credential pair (`payout_public_id:`/`payout_secret:`,
  `OBLODAI_PAYOUT_PUBLIC_ID`/`OBLODAI_PAYOUT_SECRET`) and the `prefer_payout_key:` per-call option
  are gone. `public_id:`/`secret:` signs every signed route, `admin_token:` gates the two onboarding
  routes, public routes carry no credential. Route auth is now `public` | `key` | `onboard`;
  onboarding answers with `api_key` alone (no `payment_key`/`payout_key`), and the catalogue no
  longer lists `merchant.wrong_key_kind` — only a legacy `oblodai_pk_`/`oblodai_wk_` pair can still
  provoke it.

