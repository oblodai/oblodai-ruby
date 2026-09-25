# frozen_string_literal: true

# The rules a webhook receiver depends on and cannot verify itself: never hash with an empty key,
# check the MAC before the clock, answer an unreadable-but-authentic body with something other than
# a signature error, and never raise on an event kind a newer gateway invented.
RSpec.describe "#{Oblodai::Webhooks} hardening" do
  let(:ts) { 1_755_600_000 }
  let(:body) do
    JSON.generate(Samples.body("PaymentWebhook", "type" => "payment", "uuid" => "u1", "order_id" => "o",
                                                 "status" => "paid", "is_final" => true, "sequence" => 7))
  end

  def sign(raw, secret = "whsec", when_sent = ts)
    Oblodai::Signing.sign_webhook(secret, when_sent, raw)
  end

  def headers(raw = body, overrides = {})
    { SIGNING::HEADER_WEBHOOK_TIMESTAMP.downcase => ts.to_s,
      SIGNING::HEADER_WEBHOOK_SIGNATURE.downcase => sign(raw) }.merge(overrides)
  end

  describe "configuration is checked before any hashing" do
    it "refuses an empty or missing secret" do
      [nil, "", :whsec].each do |bad|
        expect { Oblodai::Webhooks.verify(body, headers, secret: bad, now: ts) }
          .to raise_error(Oblodai::ConfigError) { |e|
                expect(e.code).to eq("sdk.bad_config")
                expect(e.field).to eq("secret")
              }
      end
    end

    it "refuses an empty previous_secret instead of reading it as 'no previous secret'" do
      expect { Oblodai::Webhooks.verify(body, headers, secret: "whsec", previous_secret: "", now: ts) }
        .to raise_error(Oblodai::ConfigError) { |e| expect(e.field).to eq("previous_secret") }
      # Omitting it is the way to say there is none.
      expect(Oblodai::Webhooks.verify(body, headers, secret: "whsec", now: ts).uuid).to eq("u1")
    end

    it "cannot be talked into verifying with the empty key" do
      forged = headers(body, SIGNING::HEADER_WEBHOOK_SIGNATURE.downcase => Oblodai::Signing.sign_webhook("", ts, body))
      expect { Oblodai::Webhooks.verify(body, forged, secret: "", now: ts) }
        .to raise_error(Oblodai::ConfigError)
    end

    it "refuses a negative tolerance and disables the window on 0" do
      expect { Oblodai::Webhooks.verify(body, headers, secret: "whsec", tolerance: -1, now: ts) }
        .to raise_error(Oblodai::ConfigError) { |e| expect(e.field).to eq("tolerance") }
      expect { Oblodai::Webhooks.verify(body, headers, secret: "whsec", tolerance: 1.5, now: ts) }
        .to raise_error(Oblodai::ConfigError)
      # 0 disables freshness: a delivery from last year still verifies.
      expect(Oblodai::Webhooks.verify(body, headers, secret: "whsec", tolerance: 0,
                                                     now: ts + 31_536_000).uuid).to eq("u1")
    end
  end

  describe "order of checks" do
    it "answers a forged delivery with bad_signature whatever its timestamp says" do
      # If freshness were checked first, an unauthenticated caller could learn the receiver's clock
      # by watching which of the two errors comes back.
      stale = { SIGNING::HEADER_WEBHOOK_TIMESTAMP.downcase => (ts - 100_000).to_s,
                SIGNING::HEADER_WEBHOOK_SIGNATURE.downcase => "0" * 64 }
      expect { Oblodai::Webhooks.verify(body, stale, secret: "whsec", now: ts) }
        .to raise_error(Oblodai::SignatureError) { |e| expect(e.code).to eq("webhook.bad_signature") }
    end

    it "reports stale only for a delivery that is genuinely signed" do
      old = ts - 100_000
      signed = { SIGNING::HEADER_WEBHOOK_TIMESTAMP.downcase => old.to_s, SIGNING::HEADER_WEBHOOK_SIGNATURE.downcase => sign(body, "whsec", old) }
      expect { Oblodai::Webhooks.verify(body, signed, secret: "whsec", now: ts) }
        .to raise_error(Oblodai::SignatureError) { |e| expect(e.code).to eq("webhook.stale_timestamp") }
    end
  end

  describe "signature header shapes" do
    it "tolerates whitespace and upper-case hex, and refuses a 0x prefix or an empty value" do
      padded = headers(body, SIGNING::HEADER_WEBHOOK_SIGNATURE.downcase => "  #{sign(body).upcase}\n")
      expect(Oblodai::Webhooks.verify(body, padded, secret: "whsec", now: ts).uuid).to eq("u1")

      prefixed = headers(body, SIGNING::HEADER_WEBHOOK_SIGNATURE.downcase => "0x#{sign(body)}")
      expect { Oblodai::Webhooks.verify(body, prefixed, secret: "whsec", now: ts) }
        .to raise_error(Oblodai::SignatureError, /hexadecimal/)

      empty = headers(body, SIGNING::HEADER_WEBHOOK_SIGNATURE.downcase => "   ")
      expect { Oblodai::Webhooks.verify(body, empty, secret: "whsec", now: ts) }
        .to raise_error(Oblodai::SignatureError) { |e| expect(e.code).to eq("webhook.bad_signature") }
    end

    it "recognises the rehearsal header whatever its case" do
      flagged = headers(body, SIGNING::HEADER_WEBHOOK_TEST => "TRUE")
      expect(Oblodai::Webhooks.verify_delivery(body, flagged, secret: "whsec", now: ts).test?).to be(true)
    end
  end

  describe "an authentic delivery the receiver cannot read" do
    def verify_raw(raw)
      Oblodai::Webhooks.verify(raw, headers(raw), secret: "whsec", now: ts)
    end

    it "is webhook.bad_payload in the contract family, never a signature failure" do
      ["not json", "[]", '"text"', "{}", '{"type":""}', '{"type":"payment"}'].each do |raw|
        expect { verify_raw(raw) }.to raise_error(Oblodai::WebhookPayloadError) { |e|
          expect(e.code).to eq("webhook.bad_payload")
          expect(e).not_to be_a(Oblodai::SignatureError)
          expect(e).to be_a(Oblodai::ContractError)
        }
      end
    end
  end

  describe "an event kind this release does not model" do
    let(:raw) { JSON.generate(type: "settlement", uuid: "s1", sequence: 4, test: true, amount: "5") }

    it "comes back verbatim instead of raising" do
      delivery = Oblodai::Webhooks.verify_delivery(raw, headers(raw), secret: "whsec", now: ts)
      event = delivery.event
      expect(event).to be_a(Hash)
      expect(event["type"]).to eq("settlement")
      expect(Oblodai::Webhooks.known_event?(event)).to be(false)
      expect(event["amount"]).to eq("5") # unknown fields are kept, not dropped
      expect(event).to be_frozen
    end

    it "still works with the test and staleness helpers" do
      event = Oblodai::Webhooks.verify(raw, headers(raw), secret: "whsec", now: ts)
      expect(Oblodai::Webhooks.test_event?(event)).to be(true)
      expect(Oblodai::Webhooks.stale?(event, 4)).to be(true)
      expect(Oblodai::Webhooks.stale?(event, 3)).to be(false)
    end
  end

  describe "helpers never raise on a shape they did not expect" do
    it "treats a missing or non-integer sequence as not stale" do
      no_sequence = { "type" => "payment", "uuid" => "u" }
      expect(Oblodai::Webhooks.stale?(no_sequence, 5)).to be(false)
      expect(Oblodai::Webhooks.stale?({ "sequence" => "7" }, 5)).to be(false)
      expect(Oblodai::Webhooks.stale?({ "sequence" => 7 }, nil)).to be(false)
      expect(Oblodai::Webhooks.stale?({ "sequence" => 7 }, "5")).to be(false)
      expect(Oblodai::Webhooks.stale?({}, 5)).to be(false)
    end

    it "reads the test flag from a string-keyed body as well as a symbol-keyed one" do
      expect(Oblodai::Webhooks.test_event?("test" => true)).to be(true)
      expect(Oblodai::Webhooks.test_event?(test: true)).to be(true)
      expect(Oblodai::Webhooks.test_event?("test" => "true")).to be(false)
      expect(Oblodai::Webhooks.test_event?({})).to be(false)
      expect(Oblodai::Webhooks.test_event?(nil)).to be(false)
    end
  end
end
