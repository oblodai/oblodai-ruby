# frozen_string_literal: true

RSpec.describe Oblodai::Webhooks do
  # The samples were delivered by the core's real dispatcher to the recorder, signed with the
  # endpoint secret in force at that moment — the one returned by the rotate-secret call.
  let(:secret) { Fixtures.result_of("POST /v1/webhooks/rotate-secret")["secret"] }

  describe "against real deliveries" do
    Fixtures.webhook_samples.each do |sample|
      it "verifies #{sample["headers"]["X-Webhook-Event"]}" do
        raw = sample["raw"] || JSON.generate(sample["body"])
        ts = sample["headers"]["X-Webhook-Timestamp"].to_i
        delivery = described_class.verify_delivery(raw, sample["headers"], secret: secret, now: ts)

        expect(delivery.event.uuid).to eq(sample["body"]["uuid"])
        expect(delivery.event.type).to eq(sample["body"]["type"])
        expect(delivery.id).to eq(sample["headers"]["X-Webhook-Id"])
        expect(delivery.event_type).to eq(sample["headers"]["X-Webhook-Event"])
        expect(delivery.sent_at).to eq(ts)
        expect(delivery.event.sequence).to be_a(Integer)
        expect(sample["headers"]["X-Webhook-Event"]).to match(/\A(invoice|payout|wallet)\./)
        # Every field the core sent is one the generated model knows; nil optional fields stay absent.
        expect(delivery.event.extra).to eq({})
        expect(delivery.event.to_h.keys).to match_array(sample["body"].compact.keys)
        rehearsal = sample["body"]["test"] == true || sample["headers"]["X-Webhook-Test"] == "true"
        expect(delivery.test?).to be(rehearsal)
        expect(described_class.test_event?(delivery.event)).to be(sample["body"]["test"] == true)

        expect do
          described_class.verify(raw, sample["headers"], secret: "some-other-secret",
                                                         previous_secret: "another", now: ts)
        end.to raise_error(Oblodai::SignatureError, /does not match/)
      end
    end
  end

  describe "verification rules" do
    let(:body) do
      JSON.generate(Samples.body("PaymentWebhook", "type" => "payment", "uuid" => "u1", "order_id" => "o",
                                                   "status" => "paid", "is_final" => true, "sequence" => 7))
    end
    let(:ts) { 1_755_600_000 }

    def headers_for(raw, overrides = {})
      { "x-webhook-timestamp" => ts.to_s,
        "x-webhook-signature" => Oblodai::Signing.sign_webhook("whsec", ts, raw) }.merge(overrides)
    end

    def headers(overrides = {})
      headers_for(body, overrides)
    end

    it "accepts a valid signature with case-insensitive and Rack-spelled headers" do
      expect(described_class.verify(body, headers, secret: "whsec", now: ts).type).to eq("payment")
      rack = { "HTTP_X_WEBHOOK_TIMESTAMP" => ts.to_s,
               "HTTP_X_WEBHOOK_SIGNATURE" => Oblodai::Signing.sign_webhook("whsec", ts, body) }
      expect(described_class.verify(body, rack, secret: "whsec", now: ts).uuid).to eq("u1")
    end

    it "rejects a wrong secret, a tampered body and a missing header" do
      expect { described_class.verify(body, headers, secret: "other", now: ts) }
        .to raise_error(Oblodai::SignatureError)
      expect { described_class.verify(body.sub("paid", "paid_over"), headers, secret: "whsec", now: ts) }
        .to raise_error(/does not match/)
      expect { described_class.verify(body, { "x-webhook-signature" => "aa" }, secret: "whsec") }
        .to raise_error(/missing/)
    end

    it "rejects stale deliveries unless the tolerance is disabled" do
      expect { described_class.verify(body, headers, secret: "whsec", now: ts + 600) }
        .to raise_error(/outside/)
      expect(described_class.verify(body, headers, secret: "whsec", now: ts + 600, tolerance: 0).uuid)
        .to eq("u1")
    end

    it "verifies during a secret rotation via the Prev header or the previous_secret option" do
      rotated = headers("x-webhook-signature" => Oblodai::Signing.sign_webhook("new", ts, body),
                        "x-webhook-signature-prev" => Oblodai::Signing.sign_webhook("old", ts, body))
      expect(described_class.verify(body, rotated, secret: "old", now: ts).uuid).to eq("u1") # not swapped yet
      expect(described_class.verify(body, rotated, secret: "new", now: ts).uuid).to eq("u1") # swapped
      expect(described_class.verify(body, rotated, secret: "unrelated", previous_secret: "old",
                                                   now: ts).uuid).to eq("u1")
    end

    it "parses into the model for the event type and detects stale sequences" do
      event = described_class.parse(body)
      expect(event).to be_a(Oblodai::Models::PaymentWebhook)
      expect(described_class.stale?(event, 7)).to be(true)
      expect(described_class.stale?(event, 6)).to be(false)
      expect(described_class.stale?(event, nil)).to be(false)
      unknown = described_class.parse('{"type":"alien","uuid":"x","sequence":3}')
      expect(unknown).to eq("type" => "alien", "uuid" => "x", "sequence" => 3)
      expect(unknown).to be_frozen
      expect(described_class.known_event?(unknown)).to be(false)
      expect(described_class.known_event?(event)).to be(true)
      expect(described_class.stale?(unknown, 3)).to be(true)
      expect { described_class.parse("not json") }
        .to raise_error(Oblodai::WebhookPayloadError, /not JSON/)
      expect { described_class.parse('{"type":"payment"}') }
        .to raise_error(Oblodai::WebhookPayloadError, /uuid/)
      expect { described_class.parse('{"type":"payment","uuid":"u"}') }
        .to raise_error(Oblodai::WebhookPayloadError, /not usable/)
    end

    it "marks a rehearsal delivery from either the body flag or the header" do
      expect(described_class.verify_delivery(body, headers, secret: "whsec", now: ts).test?).to be(false)
      expect(described_class.test_event?(described_class.parse(body))).to be(false)

      from_header = described_class.verify_delivery(
        body, headers("x-webhook-test" => "true"), secret: "whsec", now: ts
      )
      expect(from_header.test?).to be(true)
      # The header alone does not make the parsed event a test event — only the signed body does.
      expect(described_class.test_event?(from_header.event)).to be(false)

      rehearsal = JSON.generate(Samples.body("PaymentWebhook", "type" => "payment", "uuid" => "u1",
                                                               "status" => "paid", "sequence" => 7, "test" => true))
      from_body = described_class.verify_delivery(rehearsal, headers_for(rehearsal), secret: "whsec", now: ts)
      expect(from_body.test?).to be(true)
      expect(from_body.event.test).to be(true)
      expect(described_class.test_event?(from_body.event)).to be(true)
    end

    it "returns the delivery headers worth keeping" do
      delivery = described_class.verify_delivery(
        body, headers("x-webhook-id" => "d-1", "x-webhook-event" => "invoice.paid",
                      "x-webhook-event-time" => "1755599999"),
        secret: "whsec", now: ts
      )
      expect(delivery.id).to eq("d-1")
      expect(delivery.event_type).to eq("invoice.paid")
      expect(delivery.event_time).to eq(1_755_599_999)
    end
  end
end
