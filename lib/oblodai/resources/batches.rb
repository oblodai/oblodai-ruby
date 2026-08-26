# frozen_string_literal: true

require_relative "base"
require_relative "../models/payments"
require_relative "../models/payouts"

module Oblodai
  module Resources
    # Progress of asynchronous batches (payment, refund, payout, transfer, payout-link).
    class Batches < Base
      # `POST /v1/batch/info` — status, counters and per-row outcomes.
      #
      # Accepts either key kind; the core requires the kind that created the batch, so a payout
      # batch is retried once with the payout key when one is configured.
      #
      # The per-row `items` are paged by the core: pass `limit:`/`offset:` to walk a batch bigger
      # than one page instead of seeing only its first rows.
      #
      # @param batch_id [String, Oblodai::Models::BatchSubmitted] the batch, or its `batch_id`
      # @param limit [Integer, nil] page size of `items`
      # @param offset [Integer, nil] where that page starts
      # @return [Oblodai::Models::BatchInfo]
      def info(batch_id, limit: nil, offset: nil, **options)
        body = { batch_id: id_of(batch_id, :batch_id), limit: limit, offset: offset }.compact
        call("POST /v1/batch/info", body, model: Models::BatchInfo, **options)
      rescue PermissionError => e
        raise e unless e.code == "merchant.wrong_key_kind" && !options[:prefer_payout_key]

        call("POST /v1/batch/info", body, model: Models::BatchInfo,
                                          **options.merge(prefer_payout_key: true))
      end
      alias get info
    end

    # Internal, instant, fee-free moves between platform balances. Payout key.
    class Transfers < Base
      # `POST /v1/transfer/to-personal` — business balance → the owner's personal wallet
      # (needs an owner link).
      #
      # Codes worth branching on: `transfer.bad_amount`, `merchant.no_owner`,
      # `merchant.no_personal_wallet`, `payout.insufficient_funds` (retryable),
      # `payout.funds_maturing` (retryable), `merchant.wrong_key_kind`.
      # @return [Oblodai::Models::TransferToPersonal]
      def to_personal(**params)
        options = Base.take_options!(params)
        call("POST /v1/transfer/to-personal", params, model: Models::TransferToPersonal, **options)
      end

      # `POST /v1/transfer/to-user` — business balance → another platform user's personal wallet.
      # `amount` and `currency` are required.
      #
      # Codes worth branching on: `transfer.bad_amount`, `transfer.no_recipient`,
      # `transfer.recipient_not_found`, `transfer.bad_recipient` (the recipient is yourself),
      # `payout.insufficient_funds` (retryable), `merchant.wrong_key_kind`.
      # @return [Oblodai::Models::TransferToUser]
      def to_user(**params)
        options = Base.take_options!(params)
        call("POST /v1/transfer/to-user", params, model: Models::TransferToUser, **options)
      end

      # `POST /v1/transfer/batch` — ASYNCHRONOUS batch of {#to_user} transfers; poll `batches.info`.
      # `order_id` is required on every item.
      #
      # Codes worth branching on: `payout.batch_too_large`, `payout.empty_batch`,
      # `request.missing_field` (an item without `order_id`/`amount`/`currency`),
      # `transfer.recipient_not_found`, `merchant.wrong_key_kind`, `idempotency.key_reused`.
      # @return [Oblodai::Models::BatchSubmitted]
      def batch(**params)
        options = Base.take_options!(params)
        call("POST /v1/transfer/batch", params, model: Models::BatchSubmitted, **options)
      end
    end
  end
end
