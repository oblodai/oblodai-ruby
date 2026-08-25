# frozen_string_literal: true

require_relative "base"
require_relative "../models/payouts"
require_relative "../models/payments"

module Oblodai
  module Resources
    # Outgoing transfers to external addresses. Every route here needs the payout key.
    class Payouts < Base
      # `POST /v1/payout` — create and (for API keys) auto-approve a payout. Idempotent by
      # `order_id` and by Idempotency-Key.
      #
      # Errors worth handling: `payout.insufficient_funds` (retryable), `payout.funds_maturing`,
      # `payout.bad_address`, `payout.memo_required`.
      #
      # @example
      #   client.payouts.create(amount: "10", currency: "USDT", network: "tron",
      #                         address: "T…", order_id: "po-1")
      # @return [Oblodai::Models::Payout]
      def create(**params)
        options = Base.take_options!(params)
        call("POST /v1/payout", params, model: Models::Payout, **options)
      end

      # `POST /v1/payout/validate` — dry run: every check of {#create}, nothing reserved or sent.
      # @return [Oblodai::Models::PayoutValidation]
      def validate(**params)
        options = Base.take_options!(params)
        call("POST /v1/payout/validate", params, model: Models::PayoutValidation, **options)
      end

      # `POST /v1/payout/calculate` — commission and net amount without creating anything.
      # @return [Oblodai::Models::PayoutCalculation]
      def calculate(**params)
        options = Base.take_options!(params)
        call("POST /v1/payout/calculate", params, model: Models::PayoutCalculation, **options)
      end

      # `POST /v1/payout/info` — by `uuid` or `order_id`. Refunds are payouts too (`is_refund`).
      # @return [Oblodai::Models::Payout]
      def info(uuid = nil, order_id: nil, **options)
        body = { uuid: uuid, order_id: order_id }.compact
        call("POST /v1/payout/info", body, model: Models::Payout, **options)
      end
      alias get info

      # `POST /v1/payout/cancel` — cancel while not yet broadcast (pending/approved/awaiting_cosign);
      # 409 `payout.not_pending` after.
      # @return [Oblodai::Models::Payout]
      def cancel(uuid, **options)
        call("POST /v1/payout/cancel", { uuid: uuid }, model: Models::Payout, **options)
      end

      # `POST /v1/payout/approve` — approve a payout awaiting manual approval.
      # @return [Oblodai::Models::Payout]
      def approve(uuid, **options)
        call("POST /v1/payout/approve", { uuid: uuid }, model: Models::Payout, **options)
      end

      # `POST /v1/payout/history` — newest first. `kind: "refund"` lists refunds only.
      # @return [Oblodai::Page<Oblodai::Models::Payout>]
      def history(**params)
        options = Base.take_options!(params)
        page("POST /v1/payout/history", model: Models::Payout, params: params, **options)
      end
      alias list history

      # `POST /v1/payout/mass` — SYNCHRONOUS batch (≤100): each element reports its own outcome.
      # @return [Array<Oblodai::Models::PayoutBatchElement>]
      def mass(**params)
        options = Base.take_options!(params)
        plain_list("POST /v1/payout/mass", params, model: Models::PayoutBatchElement, **options)
      end

      # `POST /v1/payout/batch` — ASYNCHRONOUS batch (≤5000): returns a ticket; poll `batches.info`.
      # `order_id` is required on every item.
      # @return [Oblodai::Models::BatchSubmitted]
      def batch(**params)
        options = Base.take_options!(params)
        call("POST /v1/payout/batch", params, model: Models::BatchSubmitted, **options)
      end

      # `POST /v1/payout/services` — currencies/networks available for payouts.
      # @return [Oblodai::Page<Oblodai::Models::ServiceMethod>]
      def services(**params)
        options = Base.take_options!(params)
        page("POST /v1/payout/services", model: Models::ServiceMethod, params: params, **options)
      end

      # `POST /v1/payout/fee-config/get`.
      # @return [Oblodai::Models::PayoutFeeConfig]
      def get_fee_config(**options)
        call("POST /v1/payout/fee-config/get", nil, model: Models::PayoutFeeConfig, **options)
      end

      # `POST /v1/payout/fee-config/set` — who bears the network fee by default.
      # @return [Oblodai::Models::PayoutFeeConfig]
      def set_fee_config(**params)
        options = Base.take_options!(params)
        call("POST /v1/payout/fee-config/set", params, model: Models::PayoutFeeConfig, **options)
      end

      # `POST /v1/payout/refund-fee-config/get`.
      # @return [Oblodai::Models::RefundFeeConfig]
      def get_refund_fee_config(**options)
        call("POST /v1/payout/refund-fee-config/get", nil, model: Models::RefundFeeConfig, **options)
      end

      # `POST /v1/payout/refund-fee-config/set` — who bears the fee on refunds.
      # @return [Oblodai::Models::RefundFeeConfig]
      def set_refund_fee_config(**params)
        options = Base.take_options!(params)
        call("POST /v1/payout/refund-fee-config/set", params, model: Models::RefundFeeConfig, **options)
      end
    end

    # Refunds are payouts in the invoice's own asset; underpayments are resolved (accept or refund).
    class Refunds < Base
      # `POST /v1/payment/refund` — refund a paid invoice, fully or partially. Payout key.
      # @return [Oblodai::Models::Payout]
      def create(**params)
        options = Base.take_options!(params)
        call("POST /v1/payment/refund", params, model: Models::Payout, **options)
      end

      # `POST /v1/payment/resolve` — settle an underpaid (`wrong_amount`) invoice.
      #
      # With `action: "accept"` the answer is a {Oblodai::Models::ResolutionAccepted}; with
      # `action: "refund"` it is the refund {Oblodai::Models::Payout} carrying `resolution`.
      #
      # @return [Oblodai::Models::ResolutionAccepted, Oblodai::Models::Payout]
      def resolve(**params)
        options = Base.take_options!(params)
        result = call("POST /v1/payment/resolve", params, **options)
        return Models::ResolutionAccepted.from(result) if result.is_a?(Hash) && result["resolution"] == "accepted"

        Models::Payout.from(result)
      end

      # `POST /v1/refund/batch` — up to 5000 refunds; track with `batches.info`.
      # @return [Oblodai::Models::BatchSubmitted]
      def batch(**params)
        options = Base.take_options!(params)
        call("POST /v1/refund/batch", params, model: Models::BatchSubmitted, **options)
      end
    end
  end
end
