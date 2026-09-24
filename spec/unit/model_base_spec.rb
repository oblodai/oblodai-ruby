# frozen_string_literal: true

require "bigdecimal"

# Spec §3 item 4: answers are models; unknown fields are kept, an unknown enum value parses, the
# inspect is short and shows no secret.
RSpec.describe Oblodai::Models::Base do
  let(:payment) do
    Oblodai::Models::PaymentView.from_h(Samples.body("PaymentView", "uuid" => "u-1", "status" => "teleported",
                                                                    "amount" => "25.10", "brand_new" => { "x" => 1 }))
  end

  it "parses an unknown enum value as the string it is and keeps unknown fields in extra" do
    expect(payment.status).to eq("teleported")
    expect(payment.extra).to eq("brand_new" => { "x" => 1 })
    expect(payment["brand_new"]).to eq("x" => 1)
    expect(payment.to_h["brand_new"]).to eq("x" => 1)
  end

  it "is a frozen value object compared on its wire form" do
    expect(payment).to be_frozen
    same = Oblodai::Models::PaymentView.from_h(payment.to_h)
    expect(same).to eq(payment)
    expect(same.hash).to eq(payment.hash)
    expect(JSON.parse(payment.to_json)).to eq(payment.to_h)
  end

  it "fails loudly on a missing required field" do
    expect { Oblodai::Models::PaymentView.from_h("uuid" => "u") }.to raise_error(KeyError)
  end

  it "prints briefly and never prints a secret" do
    endpoint = Oblodai::Models::RegisterWebhookResult.from_h(
      Samples.body("RegisterWebhookResult", "secret" => "whsec_live_value")
    )
    expect(endpoint.secret).to eq("whsec_live_value")
    expect(endpoint.inspect).not_to include("whsec_live_value")
    expect(endpoint.inspect).to include("[redacted]")
    expect(payment.inspect).to start_with("#<Oblodai::Models::PaymentView ")
    expect(payment.inspect.length).to be <= Oblodai::Models::Base::INSPECT_LIMIT
  end

  it "parses a nested unknown field without failing" do
    balance = Oblodai::Models::BalanceResult.from_h("balance" => { "merchant" => [], "brand_new_bucket" => [] },
                                                    "brand_new_total" => "0")
    expect(balance.extra).to eq("brand_new_total" => "0")
    expect(balance.balance.extra).to eq("brand_new_bucket" => [])
  end
end
