# Changelog

All notable changes to this gem. The format follows [Keep a Changelog](https://keepachangelog.com/),
versions follow [SemVer](https://semver.org/).

## 1.3.0 — 2026-08-25

First release of the Ruby SDK, generated from the gateway's contract snapshot and verified against it.

- Added: every merchant route the gateway declares (107) across `payments`, `refunds`, `payouts`,
  `payout_links`, `payment_links`, `batches`, `transfers`, `wallets`, `webhooks`, `documents`,
  `splits`, `settings`, `account`, `catalog`, `sandbox` and `merchants`.
- Added: request signing with the gateway's five-field recipe
  (`ts \n METHOD \n path+query \n Idempotency-Key \n body`), verified against the core's own signing
  vectors — the four-field recipe of the 1.x SDKs is rejected by the gateway with 401.
- Added: models for every documented response body, with the English description of each field and a
  contract suite that compares their key sets with golden bodies recorded from a live gateway.
- Added: retries driven by the API's authoritative `retryable` flag, never re-sending a write the
  gateway does not deduplicate; automatic idempotency keys reused across retries; `Retry-After`,
  exponential backoff with jitter, per-attempt timeout and per-call deadline.
- Added: clock-skew correction from the response `Date`, reverted when the re-signed attempt is
  still rejected.
- Added: lazy `Oblodai::Page` — `Enumerable` across pages, `first_page` for one page, nothing
  requested until consumed.
- Added: `Oblodai::Webhooks` — `verify`, `verify_delivery`, `parse` and `stale?`, with rotation
  support (`previous_secret:`) and a ±300 s freshness window; verified against real signed deliveries.
- Added: `Oblodai::Money` for exact decimal arithmetic on the string amounts the API uses.
- Added: the contract snapshot (`contract/`), the code generator (`rake codegen`) and the drift gate
  (`rake drift`); `Oblodai::Contract::ROUTES`, `Oblodai::Contract::REQUESTS` and `Oblodai::Enums::*`
  ship as a machine-readable surface.
