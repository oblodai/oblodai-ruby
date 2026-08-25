# frozen_string_literal: true

require_relative "base"
require_relative "../models/payments"

module Oblodai
  module Resources
    # Invoices: create, look up, cancel, list, and the payer-facing checkout endpoints. Payment key.
    #
    # Every method takes the request fields as keyword arguments, plus the per-call options listed
    # in {Oblodai::Resources::Base::OPTION_KEYS}. Field names and their meaning are the core's own;
    # {Oblodai::Contract::REQUESTS} carries the generated documentation of each one.
    class Payments < Base
      # `POST /v1/payment` — create an invoice. Idempotent by `order_id` and by Idempotency-Key.
      #
      # @example
      #   client.payments.create(amount: "25", currency: "USDT", network: "tron", order_id: "o-1")
      # @param params [Hash] amount:, currency:, network:, order_id:, url_callback:, …
      # @return [Oblodai::Models::Payment]
      def create(**params)
        options = Base.take_options!(params)
        call("POST /v1/payment", params, model: Models::Payment, **options)
      end

      # `POST /v1/payment/info` — by `uuid` or by your `order_id`; includes `refunds`/`refund_status`.
      #
      # @param uuid [String, nil] positionally or by keyword
      # @param order_id [String, nil]
      # @return [Oblodai::Models::Payment]
      def info(uuid = nil, order_id: nil, **options)
        call("POST /v1/payment/info", lookup(uuid, order_id), model: Models::Payment, **options)
      end
      alias get info

      # `POST /v1/payment/cancel` — cancel an unpaid invoice (409 `invoice.not_payable` once a
      # deposit was seen).
      # @return [Oblodai::Models::Payment]
      def cancel(uuid = nil, order_id: nil, **options)
        call("POST /v1/payment/cancel", lookup(uuid, order_id), model: Models::Payment, **options)
      end

      # `POST /v1/payment/history` — newest first. Lazy: nothing is requested until the page is used.
      #
      # @example
      #   client.payments.history(limit: 50, status: "paid").each { |p| puts p.uuid }
      # @param params [Hash] limit:, offset:, status:, currency:, date_from:, …
      # @return [Oblodai::Page<Oblodai::Models::Payment>]
      def history(**params)
        options = Base.take_options!(params)
        page("POST /v1/payment/history", model: Models::Payment, params: params, **options)
      end
      alias list history

      # `POST /v1/payment/batch` — create up to 5000 invoices asynchronously; track with `batches.info`.
      # @return [Oblodai::Models::BatchSubmitted]
      def batch(**params)
        options = Base.take_options!(params)
        call("POST /v1/payment/batch", params, model: Models::BatchSubmitted, **options)
      end

      # `POST /v1/payment/qr` — QR image of the invoice's payment URI.
      # @return [Oblodai::Models::QrCode]
      def qr(uuid = nil, order_id: nil, **options)
        call("POST /v1/payment/qr", lookup(uuid, order_id), model: Models::QrCode, **options)
      end

      # `POST /v1/payment/services` — currencies/networks accepted for deposits, with limits and fees.
      # @return [Oblodai::Page<Oblodai::Models::ServiceMethod>]
      def services(**params)
        options = Base.take_options!(params)
        page("POST /v1/payment/services", model: Models::ServiceMethod, params: params, **options)
      end

      # `POST /v1/payment/send-email` — email the receipt (defaults to the invoice's `payer_email`).
      # @return [Oblodai::Models::EmailSent]
      def send_email(**params)
        options = Base.take_options!(params)
        call("POST /v1/payment/send-email", params, model: Models::EmailSent, **options)
      end

      # `POST /v1/payment/resend` — re-deliver the invoice's last webhook.
      # @return [Oblodai::Models::OkResult]
      def resend(uuid = nil, order_id: nil, **options)
        call("POST /v1/payment/resend", lookup(uuid, order_id), model: Models::OkResult, **options)
      end

      # --- payer-facing (public, unsigned) — for custom checkout pages ---

      # `GET /v1/pay/{id}` — the invoice as the payer sees it. No credentials needed.
      # @param uuid [String]
      # @return [Oblodai::Models::PublicPayment]
      def public_view(uuid, **options)
        call("GET /v1/pay/{id}", nil, model: Models::PublicPayment, path_params: { id: uuid }, **options)
      end

      # `POST /v1/pay/{id}/select` — pick the asset/network on a multi-currency invoice.
      # No credentials needed.
      # @return [Oblodai::Models::PublicPayment]
      def select(uuid, **params)
        options = Base.take_options!(params)
        call("POST /v1/pay/{id}/select", params, model: Models::PublicPayment,
                                                 path_params: { id: uuid }, **options)
      end

      # `GET /v1/pay/{id}/qr` — QR for the payer page. No credentials needed.
      # @return [Oblodai::Models::QrCode]
      def public_qr(uuid, **options)
        call("GET /v1/pay/{id}/qr", nil, model: Models::QrCode, path_params: { id: uuid }, **options)
      end

      private

      # A bare string is taken as the `uuid`; one of `uuid`/`order_id` is required by the core.
      def lookup(uuid, order_id)
        { uuid: uuid, order_id: order_id }.compact
      end
    end
  end
end
