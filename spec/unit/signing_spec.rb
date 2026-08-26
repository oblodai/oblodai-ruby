# frozen_string_literal: true

RSpec.describe Oblodai::Signing do
  describe "request signing (vectors exported from the core test suite)" do
    Fixtures.contract["signing_vectors"].each do |vector|
      it vector["name"] do
        input = {
          ts: vector["ts"], method: vector["method"], request_uri: vector["request_uri"],
          idempotency_key: vector["idempotency_key"].to_s.empty? ? nil : vector["idempotency_key"],
          body: vector["body"]
        }
        expect(described_class.canonical_string(**input)).to eq(vector["canonical"])
        expect(described_class.sign_request(vector["secret"], **input)).to eq(vector["signature"])
      end
    end

    it "leaves the idempotency slot empty, not absent, when no key is sent" do
      with_slot = described_class.sign_request("s", ts: 1, method: "POST", request_uri: "/v1/x", body: "{}")
      explicit_nil = described_class.sign_request("s", ts: 1, method: "POST", request_uri: "/v1/x",
                                                       body: "{}", idempotency_key: nil)
      expect(with_slot).to eq(explicit_nil)
      expect(described_class.canonical_string(ts: 1, method: "POST", request_uri: "/v1/x", body: "{}"))
        .to eq("1\nPOST\n/v1/x\n\n{}")
    end

    it "signs the body bytes, so UTF-8 and its binary form agree" do
      body = '{"additional_data":"café 東京"}'
      a = described_class.sign_request("s", ts: 5, method: "POST", request_uri: "/v1/payment", body: body)
      b = described_class.sign_request("s", ts: 5, method: "POST", request_uri: "/v1/payment", body: body.b)
      expect(a).to eq(b)
    end

    it "upper-cases the method the way the core canonicalises it" do
      lower = described_class.sign_request("s", ts: 1, method: "post", request_uri: "/v1/x", body: "{}")
      upper = described_class.sign_request("s", ts: 1, method: "POST", request_uri: "/v1/x", body: "{}")
      expect(lower).to eq(upper)
    end
  end

  describe "webhook signing" do
    Fixtures.contract["webhook_vectors"].each_with_index do |vector, index|
      it "vector #{index}" do
        expect(described_class.sign_webhook(vector["secret"], vector["ts"], vector["payload"]))
          .to eq(vector["signature"])
      end
    end
  end
end
