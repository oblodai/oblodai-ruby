# frozen_string_literal: true

require_relative "common"

module Oblodai
  module Models
    # One on-chain deposit attributed to an invoice.
    class PaymentTx < Model
      # @return [String] transaction hash
      field :txid
      # @return [String] amount credited by this transaction, in the payer asset
      field :amount
      # @return [String] settlement network
      field :network
      # @return [Integer] block height the transaction landed in
      field :height
      # @return [String] when the core saw it (RFC 3339)
      field :created_at
    end

    # A refund issued against an invoice (a payout in disguise; full detail via `payouts.info`).
    class PaymentRefund < Model
      # @return [String] uuid of the refund payout
      field :uuid
      # @return [String] address the refund was sent to
      field :address
      # @return [String] refunded amount
      field :amount
      # @return [String] payout status of the refund
      field :status
      # @return [Boolean] whether the refund reached a final state
      field :is_final
      # @return [String] transaction hash once broadcast
      field :txid
      # @return [String] when the refund was created
      field :created_at
    end

    # Invoice as `/v1/payment`, `/v1/payment/info`, `/v1/payment/history` and `/v1/payment/cancel`
    # render it (core `paymentResult`). `refunds`/`refund_status` are present on `info` only.
    class Payment < Model
      # @return [String] invoice id
      field :uuid
      # @return [String] your reference
      field :order_id
      # @return [String] one of {Oblodai::Enums::PAYMENT_STATUSES}
      field :status
      # @return [Boolean] nothing else can happen to this invoice
      field :is_final
      # @return [String] priced amount in `currency`
      field :amount
      # @return [String] price currency (a fiat or a coin)
      field :currency
      # @return [String] settlement network; empty until the payer selects one on a multi-network invoice
      field :network
      # @return [String] amount due in the payer asset (`payer_currency`)
      field :payer_amount
      # @return [String] the asset the payer sends
      field :payer_currency
      # @return [String] how much has been confirmed as paid
      field :amount_paid
      # @return [String] how much is still left to pay
      field :amount_remaining
      # @return [String] address the customer sends the funds to
      field :address
      # @return [String] XRP destination tag, when the network needs one
      field :destination_tag
      # @return [String] Stellar/TON memo, when the network needs one
      field :memo
      # @return [String] XRP only: address and tag in one X-address string
      field :address_xaddress
      # @return [String] XLM only: address and memo in one muxed address
      field :address_muxed
      # @return [String] address QR as a `data:image/png;base64,…` URI
      field :address_qr_code
      # @return [Boolean] the payer may top the invoice up with several transfers
      field :is_multi
      # @return [String] hosted pay page
      field :url
      # @return [String] where the pay page sends the payer back
      field :url_return
      # @return [String] where the pay page sends the payer after payment
      field :url_success
      # @return [String] when the invoice expires
      field :expired_at
      # @return [String] when the locked exchange rate expires
      field :rate_expires_at
      # @return [String] rate the invoice was priced at
      field :exchange_rate
      # @return [Integer] confirmations seen so far
      field :confirmations
      # @return [Integer] confirmations needed before the invoice is paid
      field :required_confirmations
      # @return [String] hash of the deposit transaction
      field :txid
      # @return [Array<Oblodai::Models::PaymentTx>] every deposit attributed to the invoice
      field :tx_list, model: PaymentTx, list: true
      # @return [String, nil] when the invoice was paid
      field :paid_at
      # @return [String] address the deposit came from, when the network reveals it
      field :payer_address
      # @return [Boolean] whether a refund to `payer_address` is possible
      field :payer_address_is_refundable
      # @return [String] payer email, when collected
      field :payer_email
      # @return [String] your private data, echoed back in webhooks
      field :additional_data
      # @return [String] our commission on this payment
      field :commission
      # @return [String] what the merchant receives after commission
      field :merchant_amount
      # @return [String] signed link to the invoice PDF
      field :document_url
      # @return [Boolean] created with a sandbox key
      field :is_test
      # @return [String] creation time
      field :created_at
      # @return [String] last state change
      field :updated_at
      # @return [Array<Oblodai::Models::PaymentRefund>] `info` only: refunds issued against it
      field :refunds, model: PaymentRefund, list: true, optional: true
      # @return [String] `info` only: aggregate refund state
      field :refund_status, optional: true

      # @return [Boolean] `paid` or `paid_over` — the merchant has the money
      def paid?
        Oblodai::Status.payment_paid?(status)
      end

      # @return [Boolean] the invoice reached a final state
      def final?
        Oblodai::Status.payment_final?(status)
      end

      # @return [Boolean] underpaid: waiting for `refunds.resolve`
      def underpaid?
        status == "wrong_amount"
      end
    end

    # The payer-facing view (`GET /v1/pay/{id}`, `/select`, link checkout): no merchant-only fields.
    class PublicPayment < Model
      fields :uuid, :order_id, :status, :is_final, :amount, :currency, :network, :payer_amount,
             :payer_currency, :amount_paid, :amount_remaining, :address, :destination_tag, :memo,
             :address_xaddress, :address_muxed, :address_qr_code, :is_multi, :url, :url_return,
             :url_success, :expired_at, :rate_expires_at, :confirmations, :required_confirmations,
             :txid, :created_at, :updated_at

      # @return [Boolean] `paid` or `paid_over`
      def paid?
        Oblodai::Status.payment_paid?(status)
      end
    end

    # `/v1/payment/qr` and `GET /v1/pay/{id}/qr`. All fields are empty while the invoice has no real
    # address: sandbox invoices (synthetic `sandbox:` address) and `select` invoices awaiting a network.
    class QrCode < Model
      # @return [String] `data:image/png;base64,…`
      field :image
      # @return [String] what the QR encodes: a payment URI when `is_uri`, else the bare address
      field :payload
      # @return [Boolean]
      field :is_uri
      # @return [String]
      field :address
    end

    # `/v1/payment/resolve` with `action: "accept"` — the underpayment was kept as full settlement.
    # With `action: "refund"` the body is the refund {Oblodai::Models::Payout} plus `resolution`.
    class ResolutionAccepted < Model
      # @return [String] "accepted"
      field :resolution
      # @return [String] the invoice that was resolved
      field :payment_uuid
      # @return [String] your reference
      field :order_id
      # @return [String]
      field :currency
      # @return [String] what was kept as settlement
      field :amount_kept
    end

    # `/v1/payment/send-email`.
    class EmailSent < Model
      # @return [Boolean]
      field :ok
      # @return [String] address the receipt went to
      field :email
      # @return [String] the invoice
      field :uuid
    end

    # Amount limits of one payment method. Null when the asset cannot be priced right now.
    class ServiceLimit < Model
      # @return [String, nil]
      field :currency, optional: true
      # @return [String, nil]
      field :min_amount
      # @return [String, nil]
      field :max_amount
    end

    # Commission of one payment method.
    class ServiceCommission < Model
      # @return [String]
      field :currency
      # @return [String, nil] flat part of the fee
      field :fee_amount
      # @return [String, nil] percentage part of the fee
      field :percent
      # @return [String] pricing mode
      field :fee_type
    end

    # Item of `/v1/payment/services` and `/v1/payout/services`.
    class ServiceMethod < Model
      # @return [String]
      field :currency
      # @return [String]
      field :network
      # @return [Boolean] usable right now
      field :is_available
      # @return [Oblodai::Models::ServiceLimit]
      field :limit, model: ServiceLimit
      # @return [Oblodai::Models::ServiceCommission]
      field :commission, model: ServiceCommission
    end

    # `/v1/payment/batch`, `/v1/refund/batch`, `/v1/payout/batch`, `/v1/transfer/batch`
    # acknowledgement — poll `batches.info` with the `batch_id`.
    class BatchSubmitted < Model
      # @return [String]
      field :batch_id
      # @return [String] payment | payout | refund | transfer | payout_link
      field :kind
      # @return [String] queued | processing | done | stopped
      field :status
      # @return [Integer] how many elements were accepted
      field :count
    end

    # `/v1/batch/info` — progress and per-row outcomes of an asynchronous batch.
    class BatchInfo < Model
      # @return [String]
      field :batch_id
      # @return [String] payment | payout | refund | transfer | payout_link
      field :kind
      # @return [String] queued | processing | done | stopped
      field :status
      # @return [String] what the batch does when an element fails
      field :on_error
      # @return [Integer]
      field :total
      # @return [Integer]
      field :succeeded
      # @return [Integer]
      field :failed
      # @return [Array<Oblodai::Models::BatchElement>]
      field :items, model: BatchElement, list: true
      # @return [String]
      field :created_at
      # @return [String]
      field :updated_at
    end
  end
end
