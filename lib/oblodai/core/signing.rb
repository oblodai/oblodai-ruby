# frozen_string_literal: true

require "openssl"
require_relative "../generated/signing"

module Oblodai
  # Request and webhook signing — the exact recipes the core verifies, as the contract declares them
  # in `x-oblodai-signing` ({Oblodai::Generated::SigningProtocol}, generated):
  #
  #     canonical = the parts of REQUEST_CANONICAL_ORDER joined by REQUEST_CANONICAL_SEPARATOR
  #     signature = hex(HMAC-SHA256(secret, canonical))
  #
  # - `ts` is unix seconds; the core accepts ±{SKEW_SECONDS} of skew.
  # - `request_uri` is path + raw query ("/v1/x?limit=1"), never the origin.
  # - The `idempotency_key` part is the EMPTY STRING when no idempotency key header is sent.
  # - `body` is the byte-exact request body; GETs sign an empty body.
  #
  # Pure: no clock, no I/O. The vectors in spec/unit/signing_spec.rb come from the core test suite.
  module Signing
    # Signed request headers as the core reads them — the contract's names.
    HEADER_PUBLIC_ID = Generated::SigningProtocol::HEADER_PUBLIC_ID
    HEADER_SIGNATURE = Generated::SigningProtocol::HEADER_SIGNATURE
    HEADER_TIMESTAMP = Generated::SigningProtocol::HEADER_TIMESTAMP
    HEADER_IDEMPOTENCY_KEY = Generated::SigningProtocol::HEADER_IDEMPOTENCY_KEY
    # Accepted clock skew on the core side, in seconds.
    SKEW_SECONDS = Generated::SigningProtocol::SKEW_SECONDS

    module_function

    # The string the signature is computed over.
    #
    # @param ts [Integer] unix seconds, as sent in the {HEADER_TIMESTAMP} header
    # @param method [String] HTTP method (upper-cased here)
    # @param request_uri [String] path plus raw query, exactly as the request line carries it
    # @param body [String] request body bytes (already-serialized JSON, or "")
    # @param idempotency_key [String, nil] value of the {HEADER_IDEMPOTENCY_KEY} header, or nil when absent
    # @return [String]
    def canonical_string(ts:, method:, request_uri:, body:, idempotency_key: nil)
      parts = request_parts(ts, method, request_uri, body, idempotency_key)
      Generated::SigningProtocol::REQUEST_CANONICAL_ORDER.map { |name| parts.fetch(name) }
                                                         .join(Generated::SigningProtocol::REQUEST_CANONICAL_SEPARATOR)
    end

    # @return [String] lowercase hex HMAC-SHA256 of the canonical string
    def sign_request(secret, ts:, method:, request_uri:, body:, idempotency_key: nil)
      mac(secret, Generated::SigningProtocol::REQUEST_CANONICAL_ORDER,
          request_parts(ts, method, request_uri, body, idempotency_key),
          Generated::SigningProtocol::REQUEST_CANONICAL_SEPARATOR)
    end

    # Webhook signature — `webhook.Sign` on the core side:
    #
    #     signature = hex(HMAC-SHA256(secret, WEBHOOK_CANONICAL_ORDER joined by WEBHOOK_CANONICAL_SEPARATOR))
    #
    # `ts` is the delivery's unix seconds. The payload is signed verbatim, so verifiers must use the
    # raw request bytes, never a re-encoded parse of them.
    #
    # @param secret [String]
    # @param ts [Integer]
    # @param payload [String]
    # @return [String]
    def sign_webhook(secret, ts, payload)
      mac(secret, Generated::SigningProtocol::WEBHOOK_CANONICAL_ORDER, { "ts" => ts.to_s, "payload" => payload.to_s },
          Generated::SigningProtocol::WEBHOOK_CANONICAL_SEPARATOR)
    end

    # Each part of the request canonical string, by the name the contract gives it.
    def request_parts(ts, method, request_uri, body, idempotency_key)
      { "ts" => ts.to_s, "METHOD" => method.to_s.upcase, "request_uri" => request_uri.to_s,
        "idempotency_key" => idempotency_key.to_s, "body" => body.to_s }
    end

    # The MAC over the parts in contract order, separated — every part as its bytes.
    def mac(secret, order, parts, separator)
      message = order.map { |name| parts.fetch(name).b }.join(separator.b)
      OpenSSL::HMAC.hexdigest("SHA256", secret.to_s.b, message)
    end
    private_class_method :request_parts, :mac
  end
end
