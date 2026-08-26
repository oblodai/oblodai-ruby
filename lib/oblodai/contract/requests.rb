# frozen_string_literal: true

# GENERATED FILE — do not edit. Source: contract/contract.json (core 7ec04293c426).
# Regenerate with: rake codegen

require_relative "enums"

module Oblodai
  module Contract
    # Request bodies by route, generated from the core's documented DTOs: field names, required
    # flags, value vocabularies, examples and the English description of every field.
    #
    # Every entry is `{ field_name => { type:, required:, money:, enum:, values:, example:, doc:,
    # fields: } }`; `fields:` recurses into object and array-of-object members. Amounts marked
    # `money: true` are decimal strings — never floats.
    #
    # @example What the core accepts on an invoice
    #   Oblodai::Contract::REQUESTS["POST /v1/payment"][:amount][:doc]
    #   # => "Amount to pay, in currency."
    #
    # @return [Hash{String => Hash{Symbol => Hash}}]
    REQUESTS = {
      "POST /v1/api-allowlist/add" => {
        cidr: { type: :string, required: true, example: "203.0.113.0/24", doc: "IP or subnet in CIDR notation (203.0.113.7 or 203.0.113.0/24)." }.freeze
      }.freeze,
      "POST /v1/api-allowlist/enable" => {
        enabled: { type: :boolean, required: true, example: true, doc: "true — accept API calls only from listed addresses; false — the list is kept but not enforced." }.freeze
      }.freeze,
      "POST /v1/api-allowlist/remove" => {
        cidr: { type: :string, required: true, example: "203.0.113.0/24", doc: "IP or subnet in CIDR notation (203.0.113.7 or 203.0.113.0/24)." }.freeze
      }.freeze,
      "POST /v1/auto-withdraw/delete" => {
        currency: { type: :string, required: true, example: "USDT", doc: "Asset whose auto-withdrawal to switch off." }.freeze
      }.freeze,
      "POST /v1/auto-withdraw/set" => {
        address: { type: :string, required: true, example: "TQrY8bkbpXKPt2LZbU8jqfnpFbUSF15sbx", doc: "Destination address (the merchant's external wallet)." }.freeze,
        currency: { type: :string, required: true, example: "USDT", doc: "Asset to withdraw automatically." }.freeze,
        min_amount: { type: :string, money: true, example: "100", doc: "Threshold: the sweep runs once the available balance of the asset reaches this amount; empty uses the network minimum." }.freeze,
        network: { type: :string, required: true, enum: Enums::NETWORKS, example: "tron", doc: "Network of the destination address." }.freeze
      }.freeze,
      "POST /v1/batch/info" => {
        batch_id: { type: :string, required: true, example: "9f4c1a2b-77de-4a55-9c1f-0e2b3d4a5f60", doc: "Batch id from the submit response." }.freeze,
        limit: { type: :integer, example: 100, doc: "How many items to return in items (pagination)." }.freeze,
        offset: { type: :integer, example: 0, doc: "Offset over items." }.freeze
      }.freeze,
      "POST /v1/claim/{token}" => {
        address: { type: :string, required: true, doc: "Recipient address in the payout network." }.freeze,
        memo: { type: :string, doc: "Memo/tag — only for networks where it is required." }.freeze,
        passcode: { type: :string, doc: "Claim code — if the sender set one on the link. After 10 incorrect attempts the link is locked." }.freeze
      }.freeze,
      "POST /v1/documents/jobs" => {
        format: { type: :string, example: "csv", doc: "File format: pdf (default) or csv. CSV is generated without layout — cheaper for large statements and loads into Excel/1C." }.freeze,
        from: { type: :string, example: "2025-01-01", doc: "Start of the period, YYYY-MM-DD (defaults to the first day of the current month)." }.freeze,
        kind: { type: :string, required: true, example: "statement", doc: "Report type: statement (operations), fees (commissions) or ledger (balance movements)." }.freeze,
        lang: { type: :string, example: "ru", doc: "Document language (default en)." }.freeze,
        to: { type: :string, example: "2026-08-19", doc: "End of the period, inclusive, YYYY-MM-DD (defaults to today). The period may span up to two years." }.freeze
      }.freeze,
      "POST /v1/documents/jobs/info" => {
        job_id: { type: :string, required: true, doc: "Job id from the creation response." }.freeze
      }.freeze,
      "POST /v1/exchange-rate/list" => {
        currency_from: { type: :string, example: "ETH", doc: "Currency code. If set, only its rate is returned. If empty or the body is {}, rates for all currencies are returned." }.freeze,
        currency_to: { type: :string, doc: "Quote currency: USDT by default; any pricing asset, including fiats with a direct feed (EUR, RUB, …)." }.freeze,
        limit: { type: :integer, doc: "Page size, 1–100; default 25." }.freeze,
        offset: { type: :integer, doc: "Offset from the start of the list; default 0." }.freeze
      }.freeze,
      "POST /v1/link/{id}/checkout" => {
        amount: { type: :string, money: true, example: "10.00", doc: "Amount entered by the buyer, in the link's price currency; required for open and range, ignored for fixed." }.freeze,
        currency: { type: :string, example: "USDT", doc: "Settlement currency — the coin the buyer pays with; needed only if the link did not pin pinned_currency." }.freeze,
        network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Settlement network; needed only if the link did not pin pinned_network." }.freeze,
        order_id: { type: :string, doc: "Shop order number from the embedded widget (data-oblodai-order-id); carried over to the invoice and to the webhook for matching with the order; not an idempotency key." }.freeze,
        payer_email: { type: :string, example: "buyer@example.com", doc: "Buyer email — the cheque is sent there automatically after payment." }.freeze
      }.freeze,
      "POST /v1/merchants" => {
        email: { type: :string, required: true, example: "owner@shop.example", doc: "Owner email; must be unique across merchants." }.freeze,
        name: { type: :string, example: "Acme", doc: "Display name of the merchant." }.freeze
      }.freeze,
      "POST /v1/pay/{id}/select" => {
        currency: { type: :string, required: true, example: "USDT", doc: "Selected payment currency." }.freeze,
        network: { type: :string, required: true, enum: Enums::NETWORKS, example: "tron", doc: "Selected network." }.freeze
      }.freeze,
      "POST /v1/payment" => {
        accuracy_payment_percent: { type: :number, doc: "Under/overpayment tolerance, 0–5 %. Overrides the merchant setting." }.freeze,
        additional_data: { type: :string, doc: "Private merchant data, echoed back in webhooks (not visible to the buyer)." }.freeze,
        amount: { type: :string, required: true, money: true, example: "10", doc: "Amount to pay, in currency." }.freeze,
        currency: { type: :string, required: true, example: "USD", doc: "Price currency code: any of the 23 fiats (USD, EUR, RUB, …) or any coin (USDT, BTC, …). JPY and KRW have zero decimal places." }.freeze,
        is_payment_multiple: { type: :boolean, doc: "Allow paying up the remaining amount." }.freeze,
        is_refresh: { type: :boolean, doc: "Revive an expired invoice by order_id instead of creating a new one." }.freeze,
        lifetime_seconds: { type: :integer, example: 3600, doc: "Invoice lifetime in seconds, 300–43200; default 3600. Values outside the range are clamped to the nearest bound." }.freeze,
        network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Settlement network (e.g. tron, ethereum). Optional — see the currency and network selection modes." }.freeze,
        order_id: { type: :string, example: "order-1", doc: "Merchant reference; idempotency key. Strongly recommended." }.freeze,
        payer_email: { type: :string, doc: "Payer email. If set, a cheque is sent there automatically after payment; it is also the default recipient for POST /v1/payment/send-email." }.freeze,
        subtract: { type: :integer, doc: "Deprecated: % of the network markup charged to the payer (0–100); payer-facing markups are configured via discount." }.freeze,
        theme: { type: :string, example: "dark", doc: "Payment page theme: dark | light." }.freeze,
        to_currency: { type: :string, example: "USDT", doc: "Settlement currency — the crypto used for payment. Defaults to currency (only if currency is a coin); with a fiat price set it explicitly or omit it together with network." }.freeze,
        url_callback: { type: :string, doc: "Per-invoice webhook. Requires a registered endpoint (POST /v1/webhooks): delivery is signed with its secret." }.freeze,
        url_return: { type: :string, doc: "\"Back to shop\" link on the payment page." }.freeze,
        url_success: { type: :string, doc: "Redirect after successful payment." }.freeze
      }.freeze,
      "POST /v1/payment/accepted/list" => {
        limit: { type: :integer, example: 25, doc: "Page size, 1–100; out of range falls back to 25." }.freeze,
        offset: { type: :integer, example: 0, doc: "Offset from the start of the list (newest first)." }.freeze
      }.freeze,
      "POST /v1/payment/accepted/set" => {
        accepted: { type: :array, required: true, doc: "The full list of currency+network pairs payers may use; an empty list accepts everything in the catalog.", fields: {
          currency: { type: :string, required: true, example: "USDT", doc: "Asset code." }.freeze,
          network: { type: :string, required: true, enum: Enums::NETWORKS, example: "tron", doc: "Asset network." }.freeze
        } }.freeze
      }.freeze,
      "POST /v1/payment/accuracy/set" => {
        accuracy_percent: { type: :integer, example: 2, doc: "Tolerance in percent, 1–5. Required when enabled: true; ignored when enabled: false (reset to 0). Capped at 5 %." }.freeze,
        enabled: { type: :boolean, required: true, example: true, doc: "Enable/disable the tolerance." }.freeze
      }.freeze,
      "POST /v1/payment/autorefund/set" => {
        overpay: { type: :boolean, required: true, example: true, doc: "Refund the excess on overpayment (paid_over)." }.freeze,
        underpay: { type: :boolean, required: true, example: true, doc: "Refund the funds on an expired underpayment (wrong_amount)." }.freeze
      }.freeze,
      "POST /v1/payment/batch" => {
        on_error: { type: :string, enum: Enums::BATCH_ON_ERRORS, example: "continue", doc: "What to do when an item fails: continue (default) — process the rest; stop — halt processing after the first error." }.freeze,
        payments: { type: :array, required: true, doc: "Array of 1 to 5000 items — the same fields as POST /v1/payment; set order_id on every item: results are matched by it and it protects against duplicates.", fields: {
          accuracy_payment_percent: { type: :number, doc: "Under/overpayment tolerance, 0–5 %. Overrides the merchant setting." }.freeze,
          additional_data: { type: :string, doc: "Private merchant data, echoed back in webhooks (not visible to the buyer)." }.freeze,
          amount: { type: :string, required: true, money: true, example: "10", doc: "Amount to pay, in currency." }.freeze,
          currency: { type: :string, required: true, example: "USD", doc: "Price currency code: any of the 23 fiats (USD, EUR, RUB, …) or any coin (USDT, BTC, …). JPY and KRW have zero decimal places." }.freeze,
          is_payment_multiple: { type: :boolean, doc: "Allow paying up the remaining amount." }.freeze,
          is_refresh: { type: :boolean, doc: "Revive an expired invoice by order_id instead of creating a new one." }.freeze,
          lifetime_seconds: { type: :integer, example: 3600, doc: "Invoice lifetime in seconds, 300–43200; default 3600. Values outside the range are clamped to the nearest bound." }.freeze,
          network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Settlement network (e.g. tron, ethereum). Optional — see the currency and network selection modes." }.freeze,
          order_id: { type: :string, required: true, example: "order-1", doc: "Merchant reference; idempotency key. Strongly recommended." }.freeze,
          payer_email: { type: :string, doc: "Payer email. If set, a cheque is sent there automatically after payment; it is also the default recipient for POST /v1/payment/send-email." }.freeze,
          subtract: { type: :integer, doc: "Deprecated: % of the network markup charged to the payer (0–100); payer-facing markups are configured via discount." }.freeze,
          theme: { type: :string, example: "dark", doc: "Payment page theme: dark | light." }.freeze,
          to_currency: { type: :string, example: "USDT", doc: "Settlement currency — the crypto used for payment. Defaults to currency (only if currency is a coin); with a fiat price set it explicitly or omit it together with network." }.freeze,
          url_callback: { type: :string, doc: "Per-invoice webhook. Requires a registered endpoint (POST /v1/webhooks): delivery is signed with its secret." }.freeze,
          url_return: { type: :string, doc: "\"Back to shop\" link on the payment page." }.freeze,
          url_success: { type: :string, doc: "Redirect after successful payment." }.freeze
        } }.freeze
      }.freeze,
      "POST /v1/payment/cancel" => {
        order_id: { type: :string, example: "order-1", doc: "Your order reference." }.freeze,
        uuid: { type: :string, doc: "Invoice id in Oblodai. Either uuid or order_id is required; uuid takes priority." }.freeze
      }.freeze,
      "POST /v1/payment/discount/list" => {
        limit: { type: :integer, example: 25, doc: "Page size, 1–100; out of range falls back to 25." }.freeze,
        offset: { type: :integer, example: 0, doc: "Offset from the start of the list (newest first)." }.freeze
      }.freeze,
      "POST /v1/payment/discount/set" => {
        currency: { type: :string, example: "USDT", doc: "Currency. Empty = global default for all coins." }.freeze,
        discount_percent: { type: :integer, required: true, example: 3, doc: "Percentage, from -99 to 99. Positive is a discount, negative is a markup." }.freeze,
        network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Network. Empty = any network of this currency." }.freeze
      }.freeze,
      "POST /v1/payment/fee-config/set" => {
        payer_pays_percent: { type: :integer, required: true, example: 100, doc: "Share of OUR commission paid by the buyer: 0 — the merchant pays (current behaviour), 100 — the buyer pays and the invoice is issued with a markup. Applies to invoices created AFTER the change." }.freeze
      }.freeze,
      "POST /v1/payment/history" => {
        kind: { type: :string, example: "payout", doc: "Ignored on this route (payout history only)." }.freeze,
        limit: { type: :integer, example: 25, doc: "Page size, 1–100; out of range falls back to 25." }.freeze,
        offset: { type: :integer, example: 0, doc: "Offset from the start of the list (newest first)." }.freeze,
        status: { type: :string, enum: Enums::PAYMENT_STATUSES, example: "paid", doc: "Filter by status (an exact value from the status vocabulary); empty returns all." }.freeze
      }.freeze,
      "POST /v1/payment/info" => {
        order_id: { type: :string, example: "order-1", doc: "Your order reference." }.freeze,
        uuid: { type: :string, doc: "Invoice id in Oblodai. Either uuid or order_id is required; uuid takes priority." }.freeze
      }.freeze,
      "POST /v1/payment/link" => {
        amount_fixed: { type: :string, money: true, example: "25.00", doc: "Amount — for fixed mode; required in this mode." }.freeze,
        amount_mode: { type: :string, required: true, enum: Enums::AMOUNT_MODES, example: "open", doc: "Amount mode: fixed | open | range." }.freeze,
        currency: { type: :string, required: true, example: "USD", doc: "Price currency — fiat (USD, EUR, RUB, …) or a coin; see pricing_currencies from GET /v1/currencies." }.freeze,
        description: { type: :string, doc: "Description on the payment page." }.freeze,
        expires_in_seconds: { type: :integer, doc: "Link lifetime in seconds from creation; 0 (default) — the link never expires." }.freeze,
        max_amount: { type: :string, money: true, example: "1000.00", doc: "Upper bound — for range; required in this mode." }.freeze,
        min_amount: { type: :string, money: true, example: "1.00", doc: "Lower bound: an optional floor for open, a required minimum for range." }.freeze,
        pinned_currency: { type: :string, example: "USDT", doc: "Settlement currency (coin) pinned to the link; empty — the buyer chooses the coin." }.freeze,
        pinned_network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Settlement network pinned to the link; empty — the buyer chooses the network." }.freeze,
        title: { type: :string, doc: "Title on the payment page." }.freeze
      }.freeze,
      "POST /v1/payment/link/info" => {
        limit: { type: :integer, example: 25, doc: "Page size for the link's payments, 1–100; out of range falls back to 25." }.freeze,
        link_id: { type: :string, required: true, example: "5d3f2a71-9c84-4b0e-8d17-3e6a2c9f1b40", doc: "Payment link identifier." }.freeze,
        offset: { type: :integer, example: 0, doc: "Offset within the link's payments." }.freeze
      }.freeze,
      "POST /v1/payment/link/list" => {
        limit: { type: :integer, example: 25, doc: "Page size, 1–100; out of range falls back to 25." }.freeze,
        offset: { type: :integer, example: 0, doc: "Offset from the start of the list (newest first)." }.freeze
      }.freeze,
      "POST /v1/payment/link/toggle" => {
        active: { type: :boolean, required: true, example: false, doc: "true — the link accepts payments; false — disabled (the page shows the link as inactive)." }.freeze,
        link_id: { type: :string, required: true, example: "5d3f2a71-9c84-4b0e-8d17-3e6a2c9f1b40", doc: "Payment link identifier." }.freeze
      }.freeze,
      "POST /v1/payment/qr" => {
        order_id: { type: :string, example: "order-1", doc: "Your order reference." }.freeze,
        uuid: { type: :string, doc: "Invoice id in Oblodai. Either uuid or order_id is required; uuid takes priority." }.freeze
      }.freeze,
      "POST /v1/payment/refund" => {
        address: { type: :string, doc: "Refund destination address. Defaults to the payment's payer_address; required only for Bitcoin/UTXO." }.freeze,
        amount: { type: :string, money: true, example: "10", doc: "Partial amount. Defaults to the full amount received." }.freeze,
        network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Network." }.freeze,
        order_id: { type: :string, example: "order-1", doc: "Your order reference for the payment. Either uuid or order_id is required." }.freeze,
        reference: { type: :string, doc: "Optional refund idempotency key: distinguishes two different refunds with the same (payment, address, amount); a repeat with the same value is deduplicated. This is not order_id." }.freeze,
        uuid: { type: :string, doc: "Payment id. Either uuid or order_id is required." }.freeze
      }.freeze,
      "POST /v1/payment/resend" => {
        order_id: { type: :string, example: "order-1", doc: "Your order reference." }.freeze,
        uuid: { type: :string, doc: "Invoice id in Oblodai. Either uuid or order_id is required; uuid takes priority." }.freeze
      }.freeze,
      "POST /v1/payment/resolve" => {
        action: { type: :string, required: true, values: %w[accept refund].freeze, example: "accept", doc: "accept — accept the partial payment, refund — return it to the payer." }.freeze,
        address: { type: :string, doc: "refund only: refund address. Defaults to the payment's recorded payer_address; if it is empty (Bitcoin/UTXO) the address is required, otherwise refund.no_address." }.freeze,
        network: { type: :string, enum: Enums::NETWORKS, doc: "refund only: refund network, defaults to the payment network." }.freeze,
        order_id: { type: :string, example: "ord-1001", doc: "Your payment identifier." }.freeze,
        reference: { type: :string, doc: "refund only: your refund deduplication key." }.freeze,
        uuid: { type: :string, doc: "Payment UUID. Either uuid or order_id is required." }.freeze
      }.freeze,
      "POST /v1/payment/send-email" => {
        email: { type: :string, example: "buyer@example.com", doc: "Where to send it. Defaults to the payer_email set on the payment." }.freeze,
        order_id: { type: :string, example: "order-1", doc: "Your order reference." }.freeze,
        uuid: { type: :string, doc: "Payment id in Oblodai. Either uuid or order_id is required." }.freeze
      }.freeze,
      "POST /v1/payment/services" => {
        limit: { type: :integer, example: 25, doc: "Page size, 1–100; out of range falls back to 25." }.freeze,
        offset: { type: :integer, example: 0, doc: "Offset from the start of the list (newest first)." }.freeze
      }.freeze,
      "POST /v1/payment/testing-webhook" => {
        status: { type: :string, enum: Enums::PAYMENT_STATUSES, example: "paid", doc: "Status in the body. Default paid." }.freeze,
        url: { type: :string, example: "https://shop.example/hook", doc: "Where to send the test body. If not provided, delivery goes to the project's registered endpoint; without an endpoint it fails with webhook.no_endpoint. Signed with the project endpoint's secret, including when url is passed explicitly." }.freeze
      }.freeze,
      "POST /v1/payout" => {
        address: { type: :string, required: true, doc: "Recipient address." }.freeze,
        amount: { type: :string, required: true, money: true, example: "25", doc: "Payout amount, in currency." }.freeze,
        currency: { type: :string, required: true, example: "USDT", doc: "Currency code (for example USDT)." }.freeze,
        from_currency: { type: :string, example: "USDT", doc: "Fund the payout by converting the balance. USDT → currency only." }.freeze,
        is_subtract: { type: :boolean, doc: "Who pays the network fee: true — amount+fee is debited from the balance and the recipient receives amount; false — the recipient receives amount-fee; not provided — the project fee-config." }.freeze,
        memo: { type: :string, doc: "Destination tag/memo (TON Jetton). Maximum 120 characters." }.freeze,
        network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Network (tron, ethereum, …). Required for coins with several networks." }.freeze,
        order_id: { type: :string, required: true, example: "payout-1", doc: "Your payout number; idempotency key." }.freeze,
        source: { type: :string, doc: "Origin label: api (default) or manual." }.freeze,
        url_callback: { type: :string, doc: "Custom webhook URL for this payout (passes the SSRF check). Requires a registered endpoint (POST /v1/webhooks): delivery is signed with its secret." }.freeze
      }.freeze,
      "POST /v1/payout/approve" => {
        uuid: { type: :string, required: true, doc: "Payout id." }.freeze
      }.freeze,
      "POST /v1/payout/batch" => {
        on_error: { type: :string, enum: Enums::BATCH_ON_ERRORS, example: "continue", doc: "What to do when an item fails: continue (default) — process the rest; stop — halt processing after the first error." }.freeze,
        payouts: { type: :array, required: true, doc: "Array of 1 to 5000 items — the same fields as POST /v1/payout; order_id is required on every item and serves as the idempotency key: a repeat returns the already created payout.", fields: {
          address: { type: :string, required: true, doc: "Recipient address." }.freeze,
          amount: { type: :string, required: true, money: true, example: "25", doc: "Payout amount, in currency." }.freeze,
          currency: { type: :string, required: true, example: "USDT", doc: "Currency code (for example USDT)." }.freeze,
          from_currency: { type: :string, example: "USDT", doc: "Fund the payout by converting the balance. USDT → currency only." }.freeze,
          is_subtract: { type: :boolean, doc: "Who pays the network fee: true — amount+fee is debited from the balance and the recipient receives amount; false — the recipient receives amount-fee; not provided — the project fee-config." }.freeze,
          memo: { type: :string, doc: "Destination tag/memo (TON Jetton). Maximum 120 characters." }.freeze,
          network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Network (tron, ethereum, …). Required for coins with several networks." }.freeze,
          order_id: { type: :string, required: true, example: "payout-1", doc: "Your payout number; idempotency key." }.freeze,
          source: { type: :string, doc: "Origin label: api (default) or manual." }.freeze,
          url_callback: { type: :string, doc: "Custom webhook URL for this payout (passes the SSRF check). Requires a registered endpoint (POST /v1/webhooks): delivery is signed with its secret." }.freeze
        } }.freeze
      }.freeze,
      "POST /v1/payout/calculate" => {
        amount: { type: :string, required: true, money: true, example: "10", doc: "Payout amount as a decimal string." }.freeze,
        currency: { type: :string, required: true, example: "USDT", doc: "Payout asset (USDT, BTC, …)." }.freeze,
        is_subtract: { type: :boolean, doc: "true — the fee is debited from the balance on top of the amount (the recipient gets exactly amount); false — the fee is taken out of the payout." }.freeze,
        network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Payout network; required when the asset lives on several networks." }.freeze
      }.freeze,
      "POST /v1/payout/cancel" => {
        uuid: { type: :string, required: true, doc: "Id of the payout (or refund) to cancel." }.freeze
      }.freeze,
      "POST /v1/payout/fee-config/set" => {
        fee_on_recipient: { type: :boolean, required: true, example: true, doc: "true — the recipient pays the network fee (receives less); false — the merchant bears the fee." }.freeze
      }.freeze,
      "POST /v1/payout/history" => {
        kind: { type: :string, values: %w[payout refund].freeze, example: "payout", doc: "payout — ordinary payouts, refund — refunds; empty returns both." }.freeze,
        limit: { type: :integer, example: 25, doc: "Page size, 1–100; out of range falls back to 25." }.freeze,
        offset: { type: :integer, example: 0, doc: "Offset from the start of the list (newest first)." }.freeze,
        status: { type: :string, enum: Enums::PAYOUT_STATUSES, example: "paid", doc: "Filter by status (an exact value from the status vocabulary); empty returns all." }.freeze
      }.freeze,
      "POST /v1/payout/info" => {
        order_id: { type: :string, example: "order-1", doc: "Your order reference." }.freeze,
        uuid: { type: :string, doc: "Invoice id in Oblodai. Either uuid or order_id is required; uuid takes priority." }.freeze
      }.freeze,
      "POST /v1/payout/link" => {
        amount: { type: :string, required: true, money: true, example: "25", doc: "Amount in currency, as a string; greater than zero." }.freeze,
        currency: { type: :string, required: true, example: "USDT", doc: "Payout crypto asset (USDT, BTC, …); fiat is not possible." }.freeze,
        email: { type: :string, example: "user@example.com", doc: "If set, the recipient receives an email with a \"Claim funds\" button; a delivery failure does not cancel link creation." }.freeze,
        expires_in_seconds: { type: :integer, example: 604800, doc: "Link lifetime in seconds, clamped to 3600–2592000 (one hour to 30 days); without the field or with 0 the link lives 1 hour, not the maximum — set it explicitly." }.freeze,
        fee_bearer: { type: :string, enum: Enums::FEE_BEARERS, example: "merchant", doc: "Who pays the network fee: \"recipient\" (default — deducted from the amount, the recipient receives less) or \"merchant\" (the amount plus the fee is reserved, the recipient receives exactly amount)." }.freeze,
        network: { type: :string, required: true, enum: Enums::NETWORKS, example: "tron", doc: "Payout network for the recipient (tron, bitcoin, …)." }.freeze,
        note: { type: :string, doc: "Message to the recipient (shown on the claim page and in the email)." }.freeze,
        passcode: { type: :string, example: "auto", doc: "Claim code — a second factor for the link: \"auto\" — we generate it and return it ONCE in the response, or your own (6–64 visible characters), empty — no code. Pass the code to the recipient over a channel SEPARATE from the link (it is not put into the email); after 10 incorrect attempts the link is locked." }.freeze,
        reference: { type: :string, example: "bonus-42", doc: "Your deduplication key, unique per merchant; the Idempotency-Key header has no effect on this endpoint." }.freeze,
        title: { type: :string, doc: "Title — shown to the recipient on the claim page." }.freeze
      }.freeze,
      "POST /v1/payout/link/batch" => {
        items: { type: :array, required: true, doc: "Up to 500 links per call; each one succeeds or fails independently, the response is aligned with the request indexes.", fields: {
          amount: { type: :string, required: true, money: true, example: "25", doc: "Amount in currency, as a string; greater than zero." }.freeze,
          currency: { type: :string, required: true, example: "USDT", doc: "Payout crypto asset (USDT, BTC, …); fiat is not possible." }.freeze,
          email: { type: :string, example: "user@example.com", doc: "If set, the recipient receives an email with a \"Claim funds\" button; a delivery failure does not cancel link creation." }.freeze,
          expires_in_seconds: { type: :integer, example: 604800, doc: "Link lifetime in seconds, clamped to 3600–2592000 (one hour to 30 days); without the field or with 0 the link lives 1 hour, not the maximum — set it explicitly." }.freeze,
          fee_bearer: { type: :string, enum: Enums::FEE_BEARERS, example: "merchant", doc: "Who pays the network fee: \"recipient\" (default — deducted from the amount, the recipient receives less) or \"merchant\" (the amount plus the fee is reserved, the recipient receives exactly amount)." }.freeze,
          network: { type: :string, required: true, enum: Enums::NETWORKS, example: "tron", doc: "Payout network for the recipient (tron, bitcoin, …)." }.freeze,
          note: { type: :string, doc: "Message to the recipient (shown on the claim page and in the email)." }.freeze,
          passcode: { type: :string, example: "auto", doc: "Claim code — a second factor for the link: \"auto\" — we generate it and return it ONCE in the response, or your own (6–64 visible characters), empty — no code. Pass the code to the recipient over a channel SEPARATE from the link (it is not put into the email); after 10 incorrect attempts the link is locked." }.freeze,
          reference: { type: :string, required: true, example: "bonus-42", doc: "Your deduplication key, unique per merchant; the Idempotency-Key header has no effect on this endpoint." }.freeze,
          title: { type: :string, doc: "Title — shown to the recipient on the claim page." }.freeze
        } }.freeze
      }.freeze,
      "POST /v1/payout/link/cancel" => {
        link_id: { type: :string, required: true, doc: "Payout link id (link_id from the creation response)." }.freeze
      }.freeze,
      "POST /v1/payout/link/cheque" => {
        claim_token: { type: :string, required: true, doc: "Claim secret from the payout link creation response. Stored only as a hash and never reissued — the cheque can be printed only while you still hold the token." }.freeze,
        lang: { type: :string, example: "ru", doc: "Document language — one of the 41 supported codes (en by default); the full list is in the document.unknown_lang error." }.freeze
      }.freeze,
      "POST /v1/payout/link/info" => {
        link_id: { type: :string, required: true, doc: "Payout link id (link_id from the creation response)." }.freeze
      }.freeze,
      "POST /v1/payout/link/list" => {
        limit: { type: :integer, example: 50, doc: "How many links to return per page." }.freeze,
        offset: { type: :integer, example: 0, doc: "Offset from the start of the list (paging)." }.freeze
      }.freeze,
      "POST /v1/payout/mass" => {
        payouts: { type: :array, required: true, doc: "Array of up to 100 items; the fields of each are as in POST /v1/payout.", fields: {
          address: { type: :string, required: true, doc: "Recipient address." }.freeze,
          amount: { type: :string, required: true, money: true, example: "25", doc: "Payout amount, in currency." }.freeze,
          currency: { type: :string, required: true, example: "USDT", doc: "Currency code (for example USDT)." }.freeze,
          from_currency: { type: :string, example: "USDT", doc: "Fund the payout by converting the balance. USDT → currency only." }.freeze,
          is_subtract: { type: :boolean, doc: "Who pays the network fee: true — amount+fee is debited from the balance and the recipient receives amount; false — the recipient receives amount-fee; not provided — the project fee-config." }.freeze,
          memo: { type: :string, doc: "Destination tag/memo (TON Jetton). Maximum 120 characters." }.freeze,
          network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Network (tron, ethereum, …). Required for coins with several networks." }.freeze,
          order_id: { type: :string, required: true, example: "payout-1", doc: "Your payout number; idempotency key." }.freeze,
          source: { type: :string, doc: "Origin label: api (default) or manual." }.freeze,
          url_callback: { type: :string, doc: "Custom webhook URL for this payout (passes the SSRF check). Requires a registered endpoint (POST /v1/webhooks): delivery is signed with its secret." }.freeze
        } }.freeze,
        source: { type: :string, doc: "Origin label, applied to every item without its own source." }.freeze
      }.freeze,
      "POST /v1/payout/refund-fee-config/set" => {
        fee_on_customer: { type: :boolean, required: true, example: true, doc: "true — the customer receives net (the customer pays the fee); false — the merchant pays the fee and the customer receives gross." }.freeze
      }.freeze,
      "POST /v1/payout/services" => {
        limit: { type: :integer, example: 25, doc: "Page size, 1–100; out of range falls back to 25." }.freeze,
        offset: { type: :integer, example: 0, doc: "Offset from the start of the list (newest first)." }.freeze
      }.freeze,
      "POST /v1/payout/validate" => {
        address: { type: :string, required: true, doc: "Recipient address." }.freeze,
        amount: { type: :string, required: true, money: true, example: "25", doc: "Payout amount, in currency." }.freeze,
        currency: { type: :string, required: true, example: "USDT", doc: "Currency code (for example USDT)." }.freeze,
        from_currency: { type: :string, example: "USDT", doc: "Fund the payout by converting the balance. USDT → currency only." }.freeze,
        is_subtract: { type: :boolean, doc: "Who pays the network fee: true — amount+fee is debited from the balance and the recipient receives amount; false — the recipient receives amount-fee; not provided — the project fee-config." }.freeze,
        memo: { type: :string, doc: "Destination tag/memo (TON Jetton). Maximum 120 characters." }.freeze,
        network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Network (tron, ethereum, …). Required for coins with several networks." }.freeze,
        order_id: { type: :string, required: true, example: "payout-1", doc: "Your payout number; idempotency key." }.freeze,
        source: { type: :string, doc: "Origin label: api (default) or manual." }.freeze,
        url_callback: { type: :string, doc: "Custom webhook URL for this payout (passes the SSRF check). Requires a registered endpoint (POST /v1/webhooks): delivery is signed with its secret." }.freeze
      }.freeze,
      "POST /v1/refund/batch" => {
        on_error: { type: :string, enum: Enums::BATCH_ON_ERRORS, example: "continue", doc: "What to do when an item fails: continue (default) — process the rest; stop — halt processing after the first error." }.freeze,
        refunds: { type: :array, required: true, doc: "Array of 1 to 5000 items — the same fields as POST /v1/payment/refund; every item requires reference (idempotency key) and either uuid or order_id of the payment.", fields: {
          address: { type: :string, doc: "Refund destination address. Defaults to the payment's payer_address; required only for Bitcoin/UTXO." }.freeze,
          amount: { type: :string, money: true, example: "10", doc: "Partial amount. Defaults to the full amount received." }.freeze,
          network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Network." }.freeze,
          order_id: { type: :string, example: "order-1", doc: "Your order reference for the payment. Either uuid or order_id is required." }.freeze,
          reference: { type: :string, required: true, doc: "Optional refund idempotency key: distinguishes two different refunds with the same (payment, address, amount); a repeat with the same value is deduplicated. This is not order_id." }.freeze,
          uuid: { type: :string, doc: "Payment id. Either uuid or order_id is required." }.freeze
        } }.freeze
      }.freeze,
      "POST /v1/sandbox/deposit" => {
        amount: { type: :string, money: true, example: "10", doc: "Amount in the invoice currency; empty — pay exactly what is due, anything else is a way to produce an under/overpayment." }.freeze,
        confirmations: { type: :integer, example: 0, doc: "How many confirmations the deposit arrived with; 0 — fully confirmed; fewer than required — a way to test the pending→confirmed transition (repeat the same txid with a higher number)." }.freeze,
        invoice_id: { type: :string, required: true, doc: "UUID of the test invoice being \"paid\"." }.freeze,
        txid: { type: :string, doc: "Repeating the same txid tests your idempotency; empty — a new txid." }.freeze
      }.freeze,
      "POST /v1/sandbox/faucet" => {
        amount: { type: :string, required: true, money: true, example: "1000", doc: "Amount of test money, as a string; capped at 1000000 per call." }.freeze,
        asset: { type: :string, required: true, example: "USDT", doc: "Top-up asset (USDT, BTC, …)." }.freeze,
        idempotency_key: { type: :string, doc: "Safe-retry key; empty — every call creates a new top-up." }.freeze
      }.freeze,
      "POST /v1/sandbox/webhooks/replay" => {
        delivery_id: { type: :string, required: true, doc: "Delivery id from GET /v1/sandbox/webhooks." }.freeze
      }.freeze,
      "POST /v1/split/config/set" => {
        refund_hold_seconds: { type: :integer, required: true, example: 172800, doc: "How many seconds to defer split settlement; range 0–7776000 (up to 90 days). 0 — send the shares immediately: you take on the risk that a refund becomes impossible." }.freeze
      }.freeze,
      "POST /v1/split/recipient/optin" => {
        enabled: { type: :boolean, required: true, example: true, doc: "Allow other merchants to route split shares to your balance. true — enable receiving, false — disable (new rules targeting you stop being created; existing ones keep executing)." }.freeze
      }.freeze,
      "POST /v1/split/rule" => {
        address: { type: :string, doc: "External crypto address of the partner; the share leaves as a real on-chain transaction — irreversible. Exactly one recipient option: either address+network or merchant_id." }.freeze,
        merchant_id: { type: :string, example: "b4c1f0e2-5a77-4d31-9f08-2c6e7a1b3d94", doc: "Id of the partner merchant inside Oblodai; the share moves through internal accounting and is clawed back on a refund." }.freeze,
        network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Address network. Required together with address." }.freeze,
        note: { type: :string, doc: "Comment for yourself (shown in the rule list)." }.freeze,
        percent: { type: :string, required: true, example: "10", doc: "Share of every payment, as a string: \"10\" = 10 %, \"2.5\" = 2.5 %. Greater than 0 and at most 100, step 0.01 %; the sum of all rules cannot exceed 100 %." }.freeze
      }.freeze,
      "POST /v1/split/rule/delete" => {
        rule_id: { type: :string, required: true, example: "9f4c1a2b-77de-4a55-9c1f-0e2b3d4a5f60", doc: "Rule identifier from POST /v1/split/rule or the list." }.freeze
      }.freeze,
      "POST /v1/split/rule/list" => {
        limit: { type: :integer, example: 25, doc: "Page size, 1–100; out of range falls back to 25." }.freeze,
        offset: { type: :integer, example: 0, doc: "Offset from the start of the list (newest first)." }.freeze
      }.freeze,
      "POST /v1/test-webhook/payment" => {
        currency: { type: :string, example: "USDT", doc: "Currency in the body." }.freeze,
        network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Network in the body." }.freeze,
        order_id: { type: :string, doc: "Your order_id, which is put into the test event body." }.freeze,
        status: { type: :string, enum: Enums::PAYMENT_STATUSES, example: "paid", doc: "Status in the body — from the status dictionary of this event type. Default paid (confirmed for a payout)." }.freeze,
        url_callback: { type: :string, required: true, example: "https://shop.example/oblodai/callback", doc: "Where to send the test body." }.freeze,
        uuid: { type: :string, doc: "UUID of the object (payment, wallet or payout) put into the test event body." }.freeze
      }.freeze,
      "POST /v1/test-webhook/payout" => {
        currency: { type: :string, example: "USDT", doc: "Currency in the body." }.freeze,
        network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Network in the body." }.freeze,
        order_id: { type: :string, doc: "Your order_id, which is put into the test event body." }.freeze,
        status: { type: :string, enum: Enums::PAYOUT_STATUSES, example: "paid", doc: "Status in the body — from the status dictionary of this event type. Default paid (confirmed for a payout)." }.freeze,
        url_callback: { type: :string, required: true, example: "https://shop.example/oblodai/callback", doc: "Where to send the test body." }.freeze,
        uuid: { type: :string, doc: "UUID of the object (payment, wallet or payout) put into the test event body." }.freeze
      }.freeze,
      "POST /v1/test-webhook/wallet" => {
        currency: { type: :string, example: "USDT", doc: "Currency in the body." }.freeze,
        network: { type: :string, enum: Enums::NETWORKS, example: "tron", doc: "Network in the body." }.freeze,
        order_id: { type: :string, doc: "Your order_id, which is put into the test event body." }.freeze,
        status: { type: :string, values: %w[paid].freeze, example: "paid", doc: "Status in the body — from the status dictionary of this event type. Default paid (confirmed for a payout)." }.freeze,
        url_callback: { type: :string, required: true, example: "https://shop.example/oblodai/callback", doc: "Where to send the test body." }.freeze,
        uuid: { type: :string, doc: "UUID of the object (payment, wallet or payout) put into the test event body." }.freeze
      }.freeze,
      "POST /v1/transfer/batch" => {
        on_error: { type: :string, enum: Enums::BATCH_ON_ERRORS, example: "continue", doc: "What to do when an item fails: continue (default) — process the rest; stop — halt processing after the first error." }.freeze,
        transfers: { type: :array, doc: "Array of 1 to 5000 items — the same fields as POST /v1/transfer/to-user; every item requires order_id (idempotency key) and to_user_id (user UUID).", fields: {
          amount: { type: :string, required: true, money: true, example: "50", doc: "Transfer amount in currency." }.freeze,
          currency: { type: :string, required: true, example: "USDT", doc: "Currency code (cryptocurrency)." }.freeze,
          order_id: { type: :string, required: true, doc: "Idempotency key: a repeat with the same order_id is a no-op; required in a transfer batch." }.freeze,
          to_user_id: { type: :string, required: true, doc: "Platform user id of the recipient (UUID, not username); a username is resolved to an id via the cabinet public profile /public/users/{username}." }.freeze
        } }.freeze
      }.freeze,
      "POST /v1/transfer/to-personal" => {
        amount: { type: :string, required: true, money: true, example: "50", doc: "Transfer amount in currency." }.freeze,
        currency: { type: :string, required: true, example: "USDT", doc: "Currency code (cryptocurrency)." }.freeze,
        order_id: { type: :string, example: "transfer-1", doc: "Idempotency key: a repeat with the same order_id is a no-op. Always send it, otherwise retrying the request after a network timeout creates a second transfer." }.freeze
      }.freeze,
      "POST /v1/transfer/to-user" => {
        amount: { type: :string, required: true, money: true, example: "50", doc: "Transfer amount in currency." }.freeze,
        currency: { type: :string, required: true, example: "USDT", doc: "Currency code (cryptocurrency)." }.freeze,
        order_id: { type: :string, doc: "Idempotency key: a repeat with the same order_id is a no-op; required in a transfer batch." }.freeze,
        to_user_id: { type: :string, required: true, doc: "Platform user id of the recipient (UUID, not username); a username is resolved to an id via the cabinet public profile /public/users/{username}." }.freeze
      }.freeze,
      "POST /v1/vrcs" => {
        enabled: { type: :boolean, example: true, doc: "true — enable auto-conversion of volatile deposits to USDT, false — disable; omit to read the current state." }.freeze
      }.freeze,
      "POST /v1/wallet" => {
        currency: { type: :string, required: true, example: "USDT", doc: "Symbol of the receiving currency (USDT, BTC, ETH, …)." }.freeze,
        network: { type: :string, required: true, enum: Enums::NETWORKS, example: "tron", doc: "Receiving network (tron, ethereum, bitcoin, …)." }.freeze,
        order_id: { type: :string, example: "client-42", doc: "Your customer/order identifier. Pins a dedicated permanent address to the customer." }.freeze
      }.freeze,
      "POST /v1/wallet/block" => {
        address: { type: :string, required: true, example: "TXk9...c3Fd", doc: "Static wallet address." }.freeze,
        is_force_block: { type: :boolean, doc: "true — block (the default when the field is omitted); false — unblock." }.freeze
      }.freeze,
      "POST /v1/wallet/blocked-address-refund" => {
        address: { type: :string, required: true, doc: "Refund destination address." }.freeze,
        memo: { type: :string, doc: "Destination tag/memo (XRP destination tag, XLM memo id, TON comment). Required for a classic address on a tag/memo network if the tag is not embedded in the X-/M-address." }.freeze,
        uuid: { type: :string, required: true, doc: "Static wallet id (from the /v1/wallet response)." }.freeze
      }.freeze,
      "POST /v1/wallet/qr" => {
        address: { type: :string, required: true, doc: "Arbitrary address to render into a QR code (PNG as a data: URI)." }.freeze
      }.freeze,
      "POST /v1/webhooks" => {
        url: { type: :string, required: true, example: "https://shop.example/oblodai/callback", doc: "HTTPS callback URL. SSRF check: private and local addresses are rejected." }.freeze
      }.freeze,
      "POST /v1/webhooks/deliveries" => {
        limit: { type: :integer, example: 25, doc: "Page size, 1–100; out of range falls back to 25." }.freeze,
        offset: { type: :integer, example: 0, doc: "Offset from the start of the list (newest first)." }.freeze
      }.freeze,
    }.freeze
  end
end
