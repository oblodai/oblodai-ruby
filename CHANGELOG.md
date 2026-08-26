# Changelog

All notable changes to this gem. The format follows [Keep a Changelog](https://keepachangelog.com/),
versions follow [SemVer](https://semver.org/).

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

