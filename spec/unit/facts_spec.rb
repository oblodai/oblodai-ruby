# frozen_string_literal: true

# The runtime reads the API's facts from the generated code — no hand-kept copy to drift.
RSpec.describe "facts of the API" do
  it "recognizes every webhook kind the contract has, conversion included" do
    expect(Oblodai::Webhooks::EVENT_MODELS).to equal(Oblodai::Generated::WEBHOOK_MODELS)
    expect(Oblodai::Generated::WEBHOOK_KINDS).to include("payment", "payout", "wallet", "conversion")
    expect(Oblodai::Generated::WEBHOOK_EVENTS.fetch("conversion.completed")).to eq("conversion")
    Oblodai::Generated::WEBHOOK_KINDS.each do |kind|
      model = Oblodai::Generated::WEBHOOK_MODELS.fetch(kind)
      body = Samples.body(model.name.split("::").last, "type" => kind, "uuid" => "u-#{kind}")
      event = Oblodai::Webhooks.parse(JSON.generate(body))
      expect(event).to be_a(model)
      expect(Oblodai::Webhooks.known_event?(event)).to be(true), kind
    end
  end

  it "classifies statuses by the contract's classes" do
    expect(Oblodai::Status::FINAL_PAYMENT_STATUSES).to eq(%w[paid paid_over wrong_amount expired cancelled])
    expect(Oblodai::Status::FINAL_PAYOUT_STATUSES).to eq(%w[cancelled confirmed failed])
    expect(Oblodai::Status.payment_final?("wrong_amount")).to be(true)
    expect(Oblodai::Status.payment_final?("under_review")).to be(false)
    expect(Oblodai::Status.payment_paid?("paid_over")).to be(true)
    expect(Oblodai::Status.payment_paid?("wrong_amount")).to be(false)
    expect(Oblodai::Status.payment_underpaid?("wrong_amount")).to be(true)
    expect(Oblodai::Status.payout_final?("failed")).to be(true)
    expect(Oblodai::Status.payout_succeeded?("confirmed")).to be(true)
    expect(Oblodai::Status.payout_succeeded?("sent")).to be(false)
  end
end
