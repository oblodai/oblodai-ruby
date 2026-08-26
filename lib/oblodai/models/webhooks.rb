# frozen_string_literal: true

require_relative "common"

module Oblodai
  module Models
    # `POST /v1/webhooks` — the merchant's endpoint.
    class WebhookEndpoint < Model
      # @return [String]
      field :endpoint_id
      # @return [String] where deliveries go
      field :url
      # @return [String, nil] shown once: at first registration and at rotation. Kept out of
      #   `to_h`, `to_json` and `inspect` — read it here, store it in a secret manager.
      field :secret, optional: true, secret: true
    end

    # `POST /v1/webhooks/rotate-secret`.
    class WebhookSecretRotated < Model
      # @return [String]
      field :endpoint_id
      # @return [String]
      field :url
      # @return [String] the new signing secret, shown once. Kept out of `to_h`, `to_json` and
      #   `inspect` — read it here, store it in a secret manager.
      field :secret, secret: true
      # @return [String] until then deliveries also carry `X-Webhook-Signature-Prev`
      field :previous_secret_valid_until
    end

    # Item of `/v1/webhooks/deliveries` and `GET /v1/sandbox/webhooks` (which adds `payload` and
    # drops `sequence`).
    class WebhookDelivery < Model
      # @return [String] stable per delivery, identical across retries — your idempotency key
      field :id
      # @return [String]
      field :url
      # @return [String] `invoice.<status>` | `payout.<status>` | `wallet.paid`
      field :event_type
      # @return [String] pending | delivered | dead
      field :status
      # @return [Integer] attempts made so far
      field :attempts
      # @return [String] last transport or HTTP error
      field :last_error
      # @return [Integer] global, increasing; a lower sequence arriving later is stale
      field :sequence
      # @return [String]
      field :created_at
      # @return [String]
      field :updated_at
      # @return [Hash, nil] sandbox inspector only: the delivered body
      field :payload, optional: true
    end

    # `/v1/test-webhook/*` and `/v1/payment/testing-webhook`.
    class WebhookTestResult < Model
      # @return [Boolean] the receiver answered 2xx
      field :ok
      # @return [Boolean] the delivery carried a signature
      field :signed
      # @return [Integer] status the receiver answered with
      field :status_code
      # @return [String, nil] set when the receiver could not be reached
      field :error, optional: true
      # @return [String, nil] `/v1/payment/testing-webhook` only
      field :url, optional: true
      # @return [Integer, nil] `/v1/payment/testing-webhook` only
      field :duration_ms, optional: true
    end

    # `invoice.<status>` — an invoice changed state.
    class PaymentEvent < Model
      # @return [String] "payment"
      field :type
      # @return [String]
      field :uuid
      # @return [String, nil]
      field :order_id
      # @return [String] one of {Oblodai::Enums::PAYMENT_STATUSES}
      field :status
      # @return [Boolean]
      field :is_final
      # @return [String]
      field :amount
      # @return [String]
      field :currency
      # @return [String]
      field :network
      # @return [String]
      field :payer_amount
      # @return [String]
      field :payer_currency
      # @return [String] what actually landed on the address, in `payer_currency`
      field :payment_amount
      # @return [String]
      field :payer_address
      # @return [Boolean]
      field :payer_address_is_refundable
      # @return [String] your private data, echoed from the invoice
      field :additional_data
      # @return [String]
      field :txid
      # @return [String] when the state change was committed
      field :event_at
      # @return [Integer] global, increasing (gaps are normal)
      field :sequence
      # @return [Boolean, nil] present and true ONLY on rehearsal deliveries (`webhooks.test`,
      #   sandbox). The body is signed exactly like a live one, so a handler must check this flag
      #   (or the `X-Webhook-Test` header) and never act on a test event as if money moved.
      field :test, optional: true
    end

    # `payout.<status>` — a payout (or refund) changed state; the body is the payout itself.
    class PayoutEvent < Model
      # @return [String] "payout"
      field :type
      # @return [String]
      field :uuid
      # @return [String, nil] null on refund payouts
      field :order_id
      # @return [String] one of {Oblodai::Enums::PAYOUT_STATUSES}
      field :status
      # @return [Boolean]
      field :is_final
      # @return [String]
      field :amount
      # @return [String]
      field :currency
      # @return [String]
      field :network
      # @return [String]
      field :address
      # @return [String]
      field :memo
      # @return [String]
      field :payer_amount
      # @return [String]
      field :commission
      # @return [String]
      field :fee_bearer
      # @return [String] api | manual
      field :source
      # @return [Boolean]
      field :approval_required
      # @return [Boolean]
      field :is_refund
      # @return [String, nil]
      field :refund_for
      # @return [String, nil]
      field :payment_order_id
      # @return [String]
      field :txid
      # @return [String]
      field :document_url
      # @return [String]
      field :created_at
      # @return [String]
      field :updated_at
      # @return [String] when the state change was committed
      field :event_at
      # @return [Integer]
      field :sequence
      # @return [Boolean, nil] present and true ONLY on rehearsal deliveries (`webhooks.test`,
      #   sandbox). The body is signed exactly like a live one, so a handler must check this flag
      #   (or the `X-Webhook-Test` header) and never act on a test event as if money moved.
      field :test, optional: true
    end

    # `wallet.paid` — a deposit landed on a static wallet.
    class WalletEvent < Model
      # @return [String] "wallet"
      field :type
      # @return [String] the wallet
      field :uuid
      # @return [String, nil] the wallet's order_id
      field :order_id
      # @return [String] "paid"
      field :status
      # @return [Boolean]
      field :is_final
      # @return [String] the address that received the deposit
      field :address
      # @return [String]
      field :currency
      # @return [String]
      field :network
      # @return [String]
      field :payer_currency
      # @return [String] what landed
      field :payment_amount
      # @return [String]
      field :txid
      # @return [String]
      field :event_at
      # @return [Integer]
      field :sequence
      # @return [Boolean, nil] present and true ONLY on rehearsal deliveries (`webhooks.test`,
      #   sandbox). The body is signed exactly like a live one, so a handler must check this flag
      #   (or the `X-Webhook-Test` header) and never act on a test event as if money moved.
      field :test, optional: true
    end

    # A verified delivery whose `type` this SDK release does not model. The core adds event types
    # without asking, and a receiver that raises on one it has not heard of turns a new gateway
    # feature into an outage — so an unknown type comes back verbatim, with its raw `type` string
    # and every other field readable through `event[:name]` and {Model#to_h}.
    #
    # Use {Oblodai::Webhooks.known_event?} before switching on `type`.
    class UnknownEvent < Model
      # @return [String] the raw type string, exactly as the core sent it
      field :type
      # @return [String, nil]
      field :uuid, optional: true
      # @return [Integer, nil]
      field :sequence, optional: true
      # @return [String, nil]
      field :event_at, optional: true
      # @return [Boolean, nil] a rehearsal delivery — see {Oblodai::Webhooks.test_event?}
      field :test, optional: true
    end
  end
end
