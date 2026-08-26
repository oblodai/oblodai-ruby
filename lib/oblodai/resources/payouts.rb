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
      # Codes worth branching on: `payout.insufficient_funds` (retryable — top up and repeat with the
      # SAME key), `payout.funds_maturing` (retryable — deposits not yet mature),
      # `payout.bad_address`, `payout.address_network_mismatch`, `payout.memo_required`,
      # `payout.amount_below_fee`, `payout.frozen`, `payout.order_id_required`,
      # `idempotency.key_reused`, `merchant.wrong_key_kind` (payment key on a payout route).
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
      #
      # @example Every accepted form
      #   client.payouts.info("6f1c…")           # positional uuid
      #   client.payouts.info(uuid: "6f1c…")     # keyword uuid
      #   client.payouts.info(order_id: "po-1")  # your own id
      #   client.payouts.info(payout)            # the model this SDK returned
      # @param ref [String, Oblodai::Models::Payout, nil] the payout, or its uuid
      # @return [Oblodai::Models::Payout]
      def info(ref = nil, uuid: nil, order_id: nil, **options)
        call("POST /v1/payout/info", lookup(ref, uuid, order_id), model: Models::Payout, **options)
      end
      alias get info

      # `POST /v1/payout/cancel` — cancel while not yet broadcast (pending/approved/awaiting_cosign);
      # 409 `payout.not_pending` after.
      # @param uuid [String, Oblodai::Models::Payout]
      # @return [Oblodai::Models::Payout]
      def cancel(uuid, **options)
        call("POST /v1/payout/cancel", { uuid: id_of(uuid, :uuid) }, model: Models::Payout, **options)
      end

      # `POST /v1/payout/approve` — approve a payout awaiting manual approval.
      # @param uuid [String, Oblodai::Models::Payout]
      # @return [Oblodai::Models::Payout]
      def approve(uuid, **options)
        call("POST /v1/payout/approve", { uuid: id_of(uuid, :uuid) }, model: Models::Payout, **options)
      end

      # `POST /v1/payout/history` — newest first. `kind: "refund"` lists refunds only.
      # @return [Oblodai::Page<Oblodai::Models::Payout>]
      def history(**params)
        options = Base.take_options!(params)
        page("POST /v1/payout/history", model: Models::Payout, params: params, **options)
      end
      alias list history

      # `POST /v1/payout/mass` — SYNCHRONOUS batch (at most 100): each element reports its own
      # outcome, so a call that returns 200 can still contain failures — check every element's `ok`.
      #
      # Call-level codes worth branching on: `payout.batch_too_large` (>100), `payout.empty_batch`,
      # `payout.insufficient_funds` (retryable), `payout.frozen`, `merchant.wrong_key_kind`.
      # Per-element failures arrive as `error_code` with the same vocabulary as {#create}.
      # @return [Array<Oblodai::Models::PayoutBatchElement>]
      def mass(**params)
        options = Base.take_options!(params)
        plain_list("POST /v1/payout/mass", params, model: Models::PayoutBatchElement, **options)
      end

      # `POST /v1/payout/batch` — ASYNCHRONOUS batch (at most 5000): returns a ticket; poll
      # `batches.info`. `order_id` is required on every item.
      #
      # Codes worth branching on: `payout.batch_too_large`, `payout.empty_batch`,
      # `payout.order_id_required`, `payout.reference_collision`, `payout.frozen`,
      # `merchant.wrong_key_kind`, `idempotency.key_reused`. Insufficient funds surface per element
      # while the batch runs, not on submission.
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

      private

      # A bare string (or a model) is taken as the `uuid`; the core requires one of `uuid`/`order_id`.
      def lookup(ref, uuid, order_id)
        found = id_of(ref, :uuid) || uuid
        if (found.nil? || found.empty?) && (order_id.nil? || order_id.to_s.empty?)
          raise ConfigError.new(
            "sdk.bad_config",
            "one of uuid: or order_id: is required (a bare string argument is taken as the uuid)",
            "uuid"
          )
        end

        { uuid: found, order_id: order_id }.compact
      end
    end

    # Refunds are payouts in the invoice's own asset; underpayments are resolved (accept or refund).
    class Refunds < Base
      # `POST /v1/payment/refund` — refund a paid invoice, fully or partially. Payout key.
      #
      # Codes worth branching on: `refund.nothing_to_refund`, `refund.exceeds_refundable`,
      # `refund.no_address` (the payer address is not refundable — ask for one),
      # `refund.dust` (below the network's minimum), `refund.reference_collision`,
      # `payout.insufficient_funds` (retryable), `merchant.wrong_key_kind`.
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
      # Codes worth branching on: `payment.not_found`, `payment.bad_status` (not `wrong_amount`),
      # `refund.nothing_to_refund`, `refund.no_address`, `refund.exceeds_excess`.
      #
      # @return [Oblodai::Models::ResolutionAccepted, Oblodai::Models::Payout]
      def resolve(**params)
        options = Base.take_options!(params)
        result = call("POST /v1/payment/resolve", params, **options)
        return Models::ResolutionAccepted.from(result) if result.is_a?(Hash) && result["resolution"] == "accepted"

        Models::Payout.from(result)
      end

      # `POST /v1/refund/batch` — up to 5000 refunds; track with `batches.info`. `reference` is
      # required on every item.
      #
      # Codes worth branching on: `payout.batch_too_large`, `payout.empty_batch`,
      # `refund.reference_collision`, `request.missing_field` (an item without `reference`),
      # `merchant.wrong_key_kind`, `idempotency.key_reused`.
      # @return [Oblodai::Models::BatchSubmitted]
      def batch(**params)
        options = Base.take_options!(params)
        call("POST /v1/refund/batch", params, model: Models::BatchSubmitted, **options)
      end
    end
  end
end
