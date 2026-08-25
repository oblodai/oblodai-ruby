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
        expect(delivery.event.to_h.keys.map(&:to_s)).to match_array(sample["body"].keys)

        expect do
          described_class.verify(raw, sample["headers"], secret: "some-other-secret",
                                                         previous_secret: "another", now: ts)
        end.to raise_error(Oblodai::SignatureError, /does not match/)
      end
    end
  end

  describe "verification rules" do
    let(:body) do
      JSON.generate(type: "payment", uuid: "u1", order_id: "o", status: "paid", is_final: true,
                    sequence: 7, event_at: "2026-01-01T00:00:00Z")
    end
    let(:ts) { 1_755_600_000 }

    def headers(overrides = {})
      { "x-webhook-timestamp" => ts.to_s,
        "x-webhook-signature" => Oblodai::Signing.sign_webhook("whsec", ts, body) }.merge(overrides)
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
      expect(event).to be_a(Oblodai::Models::PaymentEvent)
      expect(described_class.stale?(event, 7)).to be(true)
      expect(described_class.stale?(event, 6)).to be(false)
      expect(described_class.stale?(event, nil)).to be(false)
      expect { described_class.parse('{"type":"alien","uuid":"x"}') }.to raise_error(/unknown event type/)
      expect { described_class.parse("not json") }.to raise_error(/not JSON/)
      expect { described_class.parse('{"type":"payment"}') }.to raise_error(%r{type/uuid})
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
