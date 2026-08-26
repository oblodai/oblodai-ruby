# frozen_string_literal: true

require "json"
require_relative "core/signing"
require_relative "core/util"
require_relative "errors"
require_relative "models/webhooks"

module Oblodai
  # Webhook verification — usable on its own (`require "oblodai/webhooks"`), no client and no API
  # key required. Deliveries are signed as:
  #
  #     X-Webhook-Timestamp: <unix seconds>
  #     X-Webhook-Signature: hex(HMAC-SHA256(secret, "<ts>." + rawBody))
  #     X-Webhook-Signature-Prev: same, with the previous secret — only during a rotation overlap
  #     X-Webhook-Event: invoice.<status> | payout.<status> | wallet.paid
  #     X-Webhook-Id: stable per delivery (identical across retries) — use it to deduplicate
  #     X-Webhook-Event-Time: unix seconds when the state change committed (order events by it)
  #     X-Webhook-Test: "true" on a rehearsal delivery (`webhooks.test`, sandbox) — see below
  #
  # Always verify over the RAW request bytes; a re-serialized parse will not match.
  #
  # Rehearsal deliveries are signed exactly like live ones and carry `test: true` in the body (and
  # `X-Webhook-Test: true`). A handler MUST check {Delivery#test?} / {test_event?} and never act on
  # a test event as if money moved.
  #
  #     event = Oblodai::Webhooks.verify(request.body.read, request.headers, secret: ENV["SECRET"])
  #     case event.type
  #     when "payment" then mark_order_paid(event.order_id) if event.status == "paid"
  #     end
  module Webhooks
    HEADER_TIMESTAMP = "X-Webhook-Timestamp"
    HEADER_SIGNATURE = "X-Webhook-Signature"
    HEADER_SIGNATURE_PREV = "X-Webhook-Signature-Prev"
    HEADER_EVENT = "X-Webhook-Event"
    HEADER_ID = "X-Webhook-Id"
    HEADER_EVENT_TIME = "X-Webhook-Event-Time"
    HEADER_TEST = "X-Webhook-Test"

    # Reject deliveries whose timestamp is further from now than this, seconds. 0 disables the check.
    DEFAULT_TOLERANCE = 300

    # A verified delivery: the event plus the advisory headers worth keeping.
    #
    # @!attribute [r] event
    #   @return [Oblodai::Models::PaymentEvent, Oblodai::Models::PayoutEvent, Oblodai::Models::WalletEvent]
    # @!attribute [r] id
    #   @return [String, nil] `X-Webhook-Id` — stable across retries; use it as your idempotency key
    # @!attribute [r] event_type
    #   @return [String, nil] `X-Webhook-Event`
    # @!attribute [r] event_time
    #   @return [Integer, nil] `X-Webhook-Event-Time` — when the state change committed
    # @!attribute [r] sent_at
    #   @return [Integer] `X-Webhook-Timestamp` — when this attempt was sent
    # @!attribute [r] test
    #   @return [Boolean] a rehearsal delivery — see {Delivery#test?}
    Delivery = Struct.new(:event, :id, :event_type, :event_time, :sent_at, :test, keyword_init: true) do
      # A rehearsal delivery (`X-Webhook-Test: true`, or `test: true` in the signed body): produced
      # by `webhooks.test` and by the sandbox, signed exactly like a live one, but NO money moved.
      # Never credit an order, release goods or pay anyone out on one.
      # @return [Boolean]
      def test?
        self[:test] == true
      end
    end

    # Event models by the `type` discriminator of the body.
    EVENT_MODELS = {
      "payment" => Models::PaymentEvent,
      "payout" => Models::PayoutEvent,
      "wallet" => Models::WalletEvent
    }.freeze

    module_function

    # Verify the signature and freshness, then parse. Never returns an unverified body.
    #
    # @param raw_body [String] the RAW request bytes
    # @param headers [Hash, #[]] the request headers, in any case or Rack spelling
    # @param secret [String] the endpoint secret from `webhooks.register` / `rotate_secret`
    # @param previous_secret [String, nil] during a rotation keep the outgoing secret here.
    #   Deliveries queued before the rotation stay signed with it for their whole retry life
    #   (~26 h), so keep it at least that long after rotating.
    # @param tolerance [Integer] seconds; 0 disables the freshness check
    # @param now [Integer, nil] injectable clock (unix seconds) for tests
    # @return [Oblodai::Models::PaymentEvent, Oblodai::Models::PayoutEvent, Oblodai::Models::WalletEvent]
    # @raise [Oblodai::SignatureError]
    def verify(raw_body, headers, secret:, previous_secret: nil, tolerance: DEFAULT_TOLERANCE, now: nil)
      verify_delivery(raw_body, headers, secret: secret, previous_secret: previous_secret,
                                         tolerance: tolerance, now: now).event
    end

    # Like {verify}, and also returns the delivery id, event type and times from the headers.
    # @return [Oblodai::Webhooks::Delivery]
    # @raise [Oblodai::SignatureError]
    def verify_delivery(raw_body, headers, secret:, previous_secret: nil,
                        tolerance: DEFAULT_TOLERANCE, now: nil)
      ts_raw = Util.header_value(headers, HEADER_TIMESTAMP)
      signature = Util.header_value(headers, HEADER_SIGNATURE)
      if ts_raw.nil? || ts_raw.empty? || signature.nil? || signature.empty?
        raise SignatureError.new("webhook.missing_header",
                                 "missing #{HEADER_TIMESTAMP} or #{HEADER_SIGNATURE}")
      end
      unless /\A-?\d+\z/.match?(ts_raw.to_s)
        raise SignatureError.new("webhook.bad_signature", "timestamp header is not an integer")
      end

      ts = ts_raw.to_i
      assert_fresh!(ts, tolerance, now)
      prev_signature = Util.header_value(headers, HEADER_SIGNATURE_PREV)
      assert_signed!(raw_body, ts, candidates(signature, prev_signature, secret, previous_secret))

      event_time = Util.header_value(headers, HEADER_EVENT_TIME)
      event = parse(raw_body)
      Delivery.new(
        event: event,
        id: Util.header_value(headers, HEADER_ID),
        event_type: Util.header_value(headers, HEADER_EVENT),
        event_time: /\A\d+\z/.match?(event_time.to_s) ? event_time.to_i : nil,
        sent_at: ts,
        test: Util.header_value(headers, HEADER_TEST) == "true" || test_event?(event)
      )
    end

    # @raise [Oblodai::SignatureError] when the delivery is outside the freshness window
    def assert_fresh!(ts, tolerance, now)
      return unless tolerance.positive?

      current = now || Time.now.to_i
      return unless (current - ts).abs > tolerance

      raise SignatureError.new(
        "webhook.stale_timestamp",
        "delivery timestamp #{ts} is outside the ±#{tolerance}s window"
      )
    end

    # A merchant who has not swapped the stored secret yet verifies the Prev header with it; one
    # who already swapped but kept the old copy verifies the main header with the new secret.
    # @return [Array<Array(String, String)>] signature/secret pairs worth checking
    def candidates(signature, prev_signature, secret, previous_secret)
      pairs = [[signature, secret]]
      pairs << [prev_signature, secret] if prev_signature
      if previous_secret
        pairs << [signature, previous_secret]
        pairs << [prev_signature, previous_secret] if prev_signature
      end
      pairs
    end

    # @raise [Oblodai::SignatureError] when no candidate signature matches the raw bytes
    def assert_signed!(raw_body, ts, pairs)
      ok = pairs.any? do |provided, key|
        Util.secure_compare(provided.to_s.downcase, Signing.sign_webhook(key, ts, raw_body))
      end
      return if ok

      raise SignatureError.new("webhook.bad_signature", "signature does not match the body")
    end

    # Parse a (previously verified) delivery body into the model for its `type`.
    # @param raw_body [String]
    # @return [Oblodai::Models::PaymentEvent, Oblodai::Models::PayoutEvent, Oblodai::Models::WalletEvent]
    # @raise [Oblodai::SignatureError]
    def parse(raw_body)
      body = begin
        JSON.parse(raw_body.to_s)
      rescue JSON::ParserError
        raise SignatureError.new("webhook.bad_signature", "body is not JSON")
      end
      unless body.is_a?(Hash) && body["type"].is_a?(String) && body["uuid"].is_a?(String)
        raise SignatureError.new("webhook.bad_signature",
                                 "body lacks the type/uuid fields every event carries")
      end
      model = EVENT_MODELS[body["type"]]
      raise SignatureError.new("webhook.bad_signature", "unknown event type #{body["type"].inspect}") if model.nil?

      model.from(body)
    end

    # A rehearsal delivery (`webhooks.test`, sandbox) carries `test: true` in the signed body. It is
    # a drill: no money moved, so never credit an order or release goods on one.
    #
    # @param event [#test, Hash]
    # @return [Boolean]
    def test_event?(event)
      value = event.respond_to?(:test) ? event.test : event[:test]
      value == true
    end

    # Deliveries can arrive out of order (a retried `paid` after a `refund`). Keep the last
    # `sequence` you processed per object and skip anything not newer.
    #
    # @param event [#sequence]
    # @param last_processed_sequence [Integer, nil]
    # @return [Boolean]
    def stale?(event, last_processed_sequence)
      return false if last_processed_sequence.nil?

      event.sequence <= last_processed_sequence
    end
  end
end
