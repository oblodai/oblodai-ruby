# frozen_string_literal: true

require_relative "base"
require_relative "../contract/enums"
require_relative "../models/webhooks"

module Oblodai
  module Resources
    # Webhook endpoint management and delivery inspection. Signature verification lives in
    # {Oblodai::Webhooks} and needs no client and no API key.
    class Webhooks < Base
      # `POST /v1/webhooks` — register (or replace) the merchant's endpoint; returns the signing
      # secret once. The secret is readable as `endpoint.secret` and redacted in `to_h`, `to_json`
      # and `inspect`.
      # @param url [String]
      # @return [Oblodai::Models::WebhookEndpoint]
      def register(url, **options)
        call("POST /v1/webhooks", { url: url }, model: Models::WebhookEndpoint, **options)
      end

      # `POST /v1/webhooks/rotate-secret` — new secret; the old one keeps verifying until
      # `previous_secret_valid_until`. Payout key.
      # @return [Oblodai::Models::WebhookSecretRotated]
      def rotate_secret(**options)
        call("POST /v1/webhooks/rotate-secret", nil, model: Models::WebhookSecretRotated, **options)
      end

      # `POST /v1/webhooks/deliveries` — delivery log, newest first.
      # @return [Oblodai::Page<Oblodai::Models::WebhookDelivery>]
      def deliveries(**params)
        options = Base.take_options!(params)
        page("POST /v1/webhooks/deliveries", model: Models::WebhookDelivery, params: params, **options)
      end

      # `POST /v1/test-webhook/{payment|payout|wallet}` — deliver a sample event of that kind to
      # `url_callback`, signed like a real one. The delivery carries `test: true`, so a receiver
      # must not treat it as money moved.
      #
      # @param kind [String, Symbol] one of {Oblodai::Enums::WEBHOOK_KINDS}
      # @raise [Oblodai::ConfigError] when `kind` is not one of them (an unknown kind would
      #   otherwise be a KeyError from inside the route registry)
      # @return [Oblodai::Models::WebhookTestResult]
      def test(kind, **params)
        options = Base.take_options!(params)
        name = kind.to_s
        unless Enums::WEBHOOK_KINDS.include?(name)
          raise ConfigError.new(
            "sdk.bad_config",
            "unknown webhook kind #{kind.inspect}; expected one of " \
            "#{Enums::WEBHOOK_KINDS.join(", ")}",
            "kind"
          )
        end

        call("POST /v1/test-webhook/#{name}", params, model: Models::WebhookTestResult, **options)
      end

      # `POST /v1/payment/testing-webhook` — the older rehearsal door (payment events only).
      # @deprecated use `test("payment", …)`
      # @return [Oblodai::Models::WebhookTestResult]
      def test_legacy(**params)
        options = Base.take_options!(params)
        call("POST /v1/payment/testing-webhook", params, model: Models::WebhookTestResult, **options)
      end
    end
  end
end
