# frozen_string_literal: true

require "openssl"

module Oblodai
  # Request and webhook signing — the exact recipes the core verifies.
  #
  # Request (`crypto.SignRequest`):
  #
  #     canonical = ts "\n" METHOD "\n" requestURI "\n" idempotencyKey "\n" body
  #     signature = hex(HMAC-SHA256(secret, canonical))
  #
  # - `ts` is unix seconds; the core accepts ±300 s of skew.
  # - `requestURI` is path + raw query ("/v1/x?limit=1"), never the origin.
  # - The idempotency slot is the EMPTY STRING when no `Idempotency-Key` header is sent.
  # - `body` is the byte-exact request body; GETs sign an empty body.
  #
  # Pure: no clock, no I/O. The vectors in spec/unit/signing_spec.rb come from the core test suite.
  module Signing
    # Signed request headers as the core reads them.
    HEADER_PUBLIC_ID = "X-Public-Id"
    HEADER_SIGNATURE = "X-Signature"
    HEADER_TIMESTAMP = "X-Timestamp"
    HEADER_IDEMPOTENCY_KEY = "Idempotency-Key"
    # Accepted clock skew on the core side, in seconds.
    SKEW_SECONDS = 300

    module_function

    # The string the signature is computed over.
    #
    # @param ts [Integer] unix seconds, as sent in `X-Timestamp`
    # @param method [String] HTTP method (upper-cased here)
    # @param request_uri [String] path plus raw query, exactly as the request line carries it
    # @param body [String] request body bytes (already-serialized JSON, or "")
    # @param idempotency_key [String, nil] value of the `Idempotency-Key` header, or nil when absent
    # @return [String]
    def canonical_string(ts:, method:, request_uri:, body:, idempotency_key: nil)
      "#{ts}\n#{method.upcase}\n#{request_uri}\n#{idempotency_key}\n#{body}"
    end

    # @return [String] lowercase hex HMAC-SHA256 of the canonical string
    def sign_request(secret, ts:, method:, request_uri:, body:, idempotency_key: nil)
      canonical = canonical_string(ts: ts, method: method, request_uri: request_uri,
                                   body: body, idempotency_key: idempotency_key)
      OpenSSL::HMAC.hexdigest("SHA256", secret.to_s.b, canonical.b)
    end

    # Webhook signature — `webhook.Sign` on the core side:
    #
    #     signature = hex(HMAC-SHA256(secret, "<unix ts>." + payload))
    #
    # The payload is signed verbatim, so verifiers must use the raw request bytes, never a
    # re-encoded parse of them.
    #
    # @param secret [String]
    # @param ts [Integer]
    # @param payload [String]
    # @return [String]
    def sign_webhook(secret, ts, payload)
      OpenSSL::HMAC.hexdigest("SHA256", secret.to_s.b, "#{ts}.".b + payload.to_s.b)
    end
  end
end
