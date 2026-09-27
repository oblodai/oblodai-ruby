#!/usr/bin/env ruby
# frozen_string_literal: true

# A webhook receiver on Ruby's own HTTP server — no framework, no client, no API key. The rules that
# matter:
#
# 1. Verify over the RAW bytes.
# 2. Decide on the SIGNED body only: the delivery id, event id, event and test headers are not
#    signed, so anyone who captured a delivery can resend it with other values in them.
# 3. ALWAYS ignore a rehearsal (`Delivery#test?`, the body's `test: true`).
# 4. Deduplicate on `Delivery#event_key` (type, object id and sequence from the signed body), and
#    drop out-of-order deliveries with `Oblodai::Webhooks.stale?`.
# 5. A resend of a state carries a new, higher sequence: make the action idempotent per object and
#    status (`@acted` below), so a second `paid` never settles twice.
#
# WEBrick left the standard library in Ruby 3.0 — `gem install webrick` (it is in this repository's
# development bundle) before running the example. Nothing in the gem itself needs it.
#
#   gem install webrick
#   OBLODAI_WEBHOOK_SECRET=... ruby -Ilib examples/webhook_receiver.rb   # listens on :8096, PORT overrides

require "oblodai/webhooks"

# The handler, apart from the server: raw body and headers in, [status, text] out.
class WebhookReceiver
  # @param secret [String] the endpoint secret
  # @param previous_secret [String, nil] during a rotation keep the outgoing secret for ~26 h:
  #   deliveries queued before the rotation stay signed with it for their whole retry life
  def initialize(secret:, previous_secret: nil, out: $stdout)
    @secret = secret
    @previous_secret = previous_secret
    @out = out
    @seen = {}          # event key → true, so a retried or replayed delivery is processed once
    @last_sequence = {} # [kind, object id] → the last sequence processed, so an out-of-order retry is dropped
    @acted = {}         # [kind, object id, status] → true, so a resent state is settled once
  end

  def call(raw, headers)
    delivery = Oblodai::Webhooks.verify_delivery(raw, headers, secret: @secret, previous_secret: @previous_secret)
    handle(delivery)
    # Answer 2xx quickly: the gateway retries anything else for about 26 hours.
    [200, "ok"]
  rescue Oblodai::SignatureError => e
    # Not authentic (or not fresh): refuse it.
    @out.puts "rejected: #{e.message}"
    [401, "bad signature"]
  rescue Oblodai::WebhookPayloadError => e
    # Authentic, but this release cannot read the body. Deliberately NOT a 401: the sender is the
    # gateway, and the delivery deserves investigation, not rejection as a forgery.
    @out.puts "unreadable delivery: #{e.message}"
    [400, "unreadable"]
  end

  private

  def handle(delivery)
    event = delivery.event
    if delivery.test?
      # A rehearsal (webhooks.send_test_* / sandbox): signed exactly like a live delivery, but no
      # money moved — acknowledge it and settle nothing.
      @out.puts "rehearsal delivery #{delivery.event_key}, nothing to settle"
    elsif !Oblodai::Webhooks.known_event?(event)
      # A newer gateway may send an event kind this release does not model; it arrives as a Hash.
      @out.puts "unknown event type #{event["type"]}, ignored"
    elsif delivery.event_key && @seen[delivery.event_key]
      # A retry, or a replay of a delivery already processed. The key comes from the signed body,
      # never from the (unsigned) event-id or delivery-id headers.
      @out.puts "duplicate event #{delivery.event_key}, ignored"
    elsif Oblodai::Webhooks.stale?(event, @last_sequence[object_key(event)])
      @out.puts "stale event #{event.sequence} for #{object_key(event).join(" ")}, ignored"
    else
      @seen[delivery.event_key] = true if delivery.event_key
      @last_sequence[object_key(event)] = event.sequence
      if @acted[object_key(event) + [event.status]]
        @out.puts "#{object_key(event).join(" ")} already #{event.status}, nothing to do"
      else
        @acted[object_key(event) + [event.status]] = true
        settle(event)
      end
    end
  end

  # Sequences are ordered per object; the object's id field depends on the kind (conversions: `id`).
  def object_key(event)
    [event.type, Oblodai::Webhooks.subject_id(event)]
  end

  def settle(event)
    case event
    when Oblodai::Models::PaymentWebhook
      @out.puts "invoice #{event.order_id}: #{event.status} — #{event.payment_amount} #{event.payer_currency}"
      # mark_order_paid(event.order_id) if event.status == Oblodai::Enums::PaymentStatus::PAID
    when Oblodai::Models::PayoutWebhook
      @out.puts "payout #{event.uuid}: #{event.status}"
    when Oblodai::Models::WalletWebhook
      @out.puts "wallet #{event.address} received #{event.payment_amount} #{event.payer_currency}"
    else
      @out.puts "#{event.type} #{Oblodai::Webhooks.subject_id(event)}: #{event.status}"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require "webrick"
  $stdout.sync = true

  receiver = WebhookReceiver.new(secret: ENV.fetch("OBLODAI_WEBHOOK_SECRET"),
                                 previous_secret: ENV.fetch("OBLODAI_WEBHOOK_SECRET_PREV", nil))
  port = Integer(ENV.fetch("PORT", 8096))
  server = WEBrick::HTTPServer.new(Port: port, AccessLog: [], Logger: WEBrick::Log.new(File::NULL))
  server.mount_proc "/hook" do |request, response|
    # RAW bytes: a re-serialized parse would not match the signature.
    response.status, response.body = receiver.call(request.body.to_s, request.header)
  end
  trap("INT") { server.shutdown }
  puts "listening on http://127.0.0.1:#{port}/hook"
  server.start
end
