#!/usr/bin/env ruby
# frozen_string_literal: true

# A webhook receiver on Ruby's own HTTP server — no framework, no client, no API key. The two rules
# that matter: verify over the RAW bytes, and deduplicate on the delivery id.
#
# WEBrick left the standard library in Ruby 3.0 — `gem install webrick` (it is in this repository's
# development bundle) before running the example. Nothing in the gem itself needs it.
#
#   gem install webrick
#   OBLODAI_WEBHOOK_SECRET=... ruby examples/webhook_receiver.rb   # listens on :8096, PORT overrides

require "webrick"
require "oblodai/webhooks"

$stdout.sync = true

SECRET = ENV.fetch("OBLODAI_WEBHOOK_SECRET")
# During a rotation keep the outgoing secret here for ~26 h: deliveries queued before the rotation
# stay signed with it for their whole retry life.
PREVIOUS_SECRET = ENV.fetch("OBLODAI_WEBHOOK_SECRET_PREV", nil)

seen = {}          # delivery id → true, so a retried delivery is processed once
last_sequence = {} # object uuid → the last sequence processed, so an out-of-order retry is dropped

PORT = Integer(ENV.fetch("PORT", 8096))
server = WEBrick::HTTPServer.new(Port: PORT, AccessLog: [], Logger: WEBrick::Log.new(File::NULL))

server.mount_proc "/hook" do |request, response|
  raw = request.body.to_s # RAW bytes: a re-serialized parse would not match the signature

  begin
    delivery = Oblodai::Webhooks.verify_delivery(raw, request.header, secret: SECRET,
                                                                      previous_secret: PREVIOUS_SECRET)
  rescue Oblodai::SignatureError => e
    # Not authentic (or not fresh): refuse it, and the sender stops retrying.
    warn "rejected: #{e.code} #{e.message}"
    response.status = 401
    next
  rescue Oblodai::WebhookPayloadError => e
    # Authentic, but this release cannot read the body. Deliberately NOT a 401: the sender is the
    # gateway, and the delivery deserves investigation, not rejection as a forgery.
    warn "unreadable delivery: #{e.code} #{e.message}"
    response.status = 400
    next
  end

  event = delivery.event
  if delivery.test?
    # A rehearsal (webhooks.test / sandbox): signed exactly like a live delivery, but no money
    # moved — acknowledge it and settle nothing.
    puts "rehearsal delivery #{delivery.id} (#{delivery.event_type}), nothing to settle"
  elsif seen[delivery.id]
    puts "duplicate delivery #{delivery.id}, ignored"
  elsif Oblodai::Webhooks.stale?(event, last_sequence[event.uuid])
    puts "stale event #{event.sequence} for #{event.uuid}, ignored"
  else
    seen[delivery.id] = true
    last_sequence[event.uuid] = event.sequence

    # A newer gateway may send an event kind this release does not model; it arrives verbatim.
    unless Oblodai::Webhooks.known_event?(event)
      puts "unknown event type #{event.type}, ignored"
      response.status = 200
      response.body = "ok"
      next
    end

    case event.type
    when "payment"
      puts "invoice #{event.order_id}: #{event.status} — #{event.payment_amount} #{event.payer_currency}"
      # mark_order_paid(event.order_id) if event.status == "paid"
    when "payout"
      puts "payout #{event.uuid}: #{event.status}#{" (refund)" if event.is_refund}"
    when "wallet"
      puts "wallet #{event.address} received #{event.payment_amount} #{event.payer_currency}"
    end
  end

  # Answer 2xx quickly: the gateway retries anything else for about 26 hours.
  response.status = 200
  response.body = "ok"
end

trap("INT") { server.shutdown }
puts "listening on http://127.0.0.1:#{PORT}/hook"
server.start
