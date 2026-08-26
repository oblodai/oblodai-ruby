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
  # The checks run in one deliberate order: headers, then the MAC, then freshness, then the body.
  # The MAC comes before the timestamp so an unauthenticated caller cannot use the freshness window
  # as an oracle, and the body is parsed only after it is known to be authentic.
  #
  # Rehearsal deliveries are signed exactly like live ones and carry `test: true` in the body (and
  # `X-Webhook-Test: true`). A handler MUST check {Delivery#test?} / {test_event?} and never act on
  # a test event as if money moved.
  #
  #     event = Oblodai::Webhooks.verify(request.body.read, request.headers, secret: ENV["SECRET"])
  #     next unless Oblodai::Webhooks.known_event?(event)  # a newer core may send a new type
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
    #   @return [Oblodai::Models::PaymentEvent, Oblodai::Models::PayoutEvent,
    #     Oblodai::Models::WalletEvent, Oblodai::Models::UnknownEvent]
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
      def initialize(*)
        super
        freeze
      end

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

    # A hex signature: no `0x`, either case, whitespace around it tolerated.
    HEX = /\A[0-9a-fA-F]+\z/

    module_function

    # Verify the signature and freshness, then parse. Never returns an unverified body.
    #
    # @param raw_body [String] the RAW request bytes
    # @param headers [Hash, #[]] the request headers, in any case or Rack spelling
    # @param secret [String] the endpoint secret from `webhooks.register` / `rotate_secret`.
    #   Must be non-empty: verifying with an empty key would accept whatever an attacker sends.
    # @param previous_secret [String, nil] during a rotation keep the outgoing secret here.
    #   Deliveries queued before the rotation stay signed with it for their whole retry life
    #   (~26 h), so keep it at least that long. Supplying an empty string is a configuration error,
    #   not "no previous secret" — omit it instead.
    # @param tolerance [Integer] seconds; 0 disables the freshness check, negative is a ConfigError
    # @param now [Integer, nil] injectable clock (unix seconds) for tests
    # @return [Oblodai::Models::PaymentEvent, Oblodai::Models::PayoutEvent,
    #   Oblodai::Models::WalletEvent, Oblodai::Models::UnknownEvent]
    # @raise [Oblodai::ConfigError] the secret or the tolerance is unusable
    # @raise [Oblodai::SignatureError] the delivery is not authentic or not fresh
    # @raise [Oblodai::WebhookPayloadError] the delivery is authentic but its body is not an event
    def verify(raw_body, headers, secret:, previous_secret: nil, tolerance: DEFAULT_TOLERANCE, now: nil)
      verify_delivery(raw_body, headers, secret: secret, previous_secret: previous_secret,
                                         tolerance: tolerance, now: now).event
    end

    # Like {verify}, and also returns the delivery id, event type and times from the headers.
    # @return [Oblodai::Webhooks::Delivery]
    def verify_delivery(raw_body, headers, secret:, previous_secret: nil,
                        tolerance: DEFAULT_TOLERANCE, now: nil)
      # Configuration first, before a single byte is hashed: verifying with an empty key would
      # "verify" whatever an attacker sends, since they can compute HMAC("", body) as easily as we.
      secret = require_secret!(secret, "secret")
      previous_secret = require_secret!(previous_secret, "previous_secret") unless previous_secret.nil?
      tolerance = require_tolerance!(tolerance)

      ts, signature, prev_signature = read_headers(headers)
      assert_signed!(raw_body, ts, candidates(signature, prev_signature, secret, previous_secret))
      assert_fresh!(ts, tolerance, now)

      event_time = Util.header_value(headers, HEADER_EVENT_TIME)
      event = parse(raw_body)
      Delivery.new(
        event: event,
        id: Util.header_value(headers, HEADER_ID),
        event_type: Util.header_value(headers, HEADER_EVENT),
        event_time: /\A\d+\z/.match?(event_time.to_s.strip) ? event_time.to_s.strip.to_i : nil,
        sent_at: ts,
        test: true_header?(Util.header_value(headers, HEADER_TEST)) || test_event?(event)
      )
    end

    # The signed timestamp and the one or two signatures the sender attached.
    # @return [Array(Integer, String, String, nil)]
    # @raise [Oblodai::SignatureError]
    def read_headers(headers)
      ts_raw = Util.header_value(headers, HEADER_TIMESTAMP)
      signature = Util.header_value(headers, HEADER_SIGNATURE)
      if ts_raw.nil? || ts_raw.strip.empty? || signature.nil?
        raise SignatureError.new("webhook.missing_header",
                                 "missing #{HEADER_TIMESTAMP} or #{HEADER_SIGNATURE}")
      end
      unless /\A-?\d+\z/.match?(ts_raw.strip)
        raise SignatureError.new("webhook.bad_signature", "timestamp header is not an integer")
      end

      prev_raw = Util.header_value(headers, HEADER_SIGNATURE_PREV)
      [ts_raw.strip.to_i, normalize_signature(signature, HEADER_SIGNATURE),
       prev_raw.nil? ? nil : normalize_signature(prev_raw, HEADER_SIGNATURE_PREV)]
    end

    # Signature headers survive proxies that add whitespace and senders that upper-case hex, but a
    # `0x`-prefixed value is not what the core signs — accepting it would mean accepting a value
    # that never matches, framed as a mismatch the integrator cannot explain.
    # @return [String] lowercase hex
    def normalize_signature(raw, header)
      value = raw.to_s.strip
      raise SignatureError.new("webhook.bad_signature", "#{header} is empty") if value.empty?
      unless HEX.match?(value)
        raise SignatureError.new(
          "webhook.bad_signature",
          "#{header} is not hexadecimal (a \"0x\" prefix is not part of the signature)"
        )
      end

      value.downcase
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
        Util.secure_compare(provided, Signing.sign_webhook(key, ts, raw_body))
      end
      return if ok

      raise SignatureError.new("webhook.bad_signature", "signature does not match the body")
    end

    # Parse a (previously verified) delivery body into the model for its `type`. A body that is not
    # usable JSON, or lacks the fields every event carries, raises `webhook.bad_payload` —
    # deliberately NOT a signature error, so a receiver that answers 401 to forged deliveries does
    # not answer 401 to an authentic one it simply could not read.
    #
    # An event kind from a newer core is handed back verbatim as {Oblodai::Models::UnknownEvent}
    # rather than rejected: a receiver that throws on a type it has not heard of turns a new gateway
    # feature into an outage.
    #
    # @param raw_body [String]
    # @return [Oblodai::Models::Model]
    # @raise [Oblodai::WebhookPayloadError]
    def parse(raw_body)
      body = begin
        JSON.parse(raw_body.to_s)
      rescue JSON::ParserError
        raise WebhookPayloadError.new("delivery body is not JSON", raw_body.to_s)
      end
      raise WebhookPayloadError.new("delivery body is not a JSON object", body) unless body.is_a?(Hash)
      unless body["type"].is_a?(String) && !body["type"].empty?
        raise WebhookPayloadError.new("delivery body has no `type` string", body)
      end

      model = EVENT_MODELS[body["type"]]
      return Models::UnknownEvent.from(body) if model.nil?
      unless body["uuid"].is_a?(String)
        raise WebhookPayloadError.new("#{body["type"]} event has no `uuid` string", body)
      end

      model.from(body)
    end

    # Whether this release models the event field by field. Narrow with it before switching on
    # `type`; an unknown kind is an {Oblodai::Models::UnknownEvent} whose raw fields are still
    # readable with `event[:name]`.
    # @return [Boolean]
    def known_event?(event)
      EVENT_MODELS.key?(event.respond_to?(:type) ? event.type : event_field(event, :type))
    end

    # A rehearsal delivery (`webhooks.test`, sandbox) carries `test: true` in the signed body. It is
    # a drill: no money moved, so never credit an order or release goods on one.
    #
    # @param event [#test, Hash] an event model or a decoded body, string- or symbol-keyed
    # @return [Boolean]
    def test_event?(event)
      value = event.respond_to?(:test) ? event.test : event_field(event, :test)
      value == true
    end

    # Deliveries can arrive out of order (a retried `paid` after a `refund`). Keep the last
    # `sequence` you processed per object and skip anything not newer. Never raises: an event
    # without a usable `sequence` is not stale, because nothing about it can be compared.
    #
    # @param event [#sequence, Hash]
    # @param last_processed_sequence [Integer, nil]
    # @return [Boolean]
    def stale?(event, last_processed_sequence)
      return false unless last_processed_sequence.is_a?(Integer)

      sequence = event.respond_to?(:sequence) ? event.sequence : event_field(event, :sequence)
      return false unless sequence.is_a?(Integer)

      sequence <= last_processed_sequence
    end

    # Read a field from a decoded body whichever way its keys are spelled.
    def event_field(event, name)
      return nil unless event.respond_to?(:[])

      value = event[name]
      value.nil? && !name.is_a?(String) ? event[name.to_s] : value
    end

    # @raise [Oblodai::ConfigError]
    # @return [String]
    def require_secret!(value, field)
      return value if value.is_a?(String) && !value.empty?

      raise ConfigError.new(
        "sdk.bad_config",
        "#{field} must be a non-empty string; verifying with an empty key would accept any body",
        field
      )
    end

    # @raise [Oblodai::ConfigError]
    # @return [Integer]
    def require_tolerance!(value)
      return value if value.is_a?(Integer) && !value.negative?

      raise ConfigError.new(
        "sdk.bad_config",
        "tolerance must be a non-negative number of seconds (0 disables the freshness check)",
        "tolerance"
      )
    end

    def true_header?(value)
      value.to_s.strip.downcase == "true"
    end
  end
end
