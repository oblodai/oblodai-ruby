# frozen_string_literal: true

require "bigdecimal"

# Spec §3 item 3: amounts are BigDecimal or decimal strings; a Float is an error before the network.
RSpec.describe "money on the wire" do
  it "refuses a Float amount before anything is sent" do
    http = FakeHTTP.new([])
    expect { client_with(http).payments.create(amount: 25.5, currency: "USDT") }
      .to raise_error(Oblodai::ConfigError) { |e|
            expect(e.code).to eq("sdk.float_amount")
            expect(e.field).to eq("amount")
          }
    expect { client_with(http).payouts.create_mass(payouts: [{ "amount" => 1.0, "currency" => "USDT" }]) }
      .to raise_error(Oblodai::ConfigError) { |e| expect(e.field).to eq("payouts[0].amount") }
    expect(http.calls).to be_empty
  end

  it "sends a BigDecimal as its decimal string and a String verbatim" do
    http = FakeHTTP.new([FakeHTTP.ok_for("createPayment")] * 2)
    client = client_with(http)
    client.payments.create(amount: BigDecimal("25.10"), currency: "USDT")
    client.payments.create(amount: "25.10", currency: "USDT")
    expect(http.calls[0].body).to include('"amount":"25.1"')
    expect(http.calls[1].body).to include('"amount":"25.10"')
  end

  it "accepts a number where the field is not money" do
    http = FakeHTTP.new([FakeHTTP.ok_for("createPayment")])
    client_with(http).payments.create(amount: "1", currency: "USDT", accuracy_payment_percent: 1.5)
    expect(http.calls[0].json).to include("accuracy_payment_percent" => 1.5)
  end

  it "keeps the list of non-money numbers equal to the contract's number fields" do
    spec = backend_spec
    skip "backend openapi.json not found (set OBLODAI_BACKEND)" if spec.nil?

    numbers = spec.dig("components", "schemas").flat_map do |_, schema|
      (schema["properties"] || {}).select { |_, prop| prop["type"] == "number" }.keys
    end
    expect(numbers.uniq.sort).to eq(Oblodai::RequestBuilder::NON_MONEY_NUMBERS.sort)
  end

  it "sends a request model as its wire form, amounts included" do
    http = FakeHTTP.new([FakeHTTP.ok_for("createPayment")])
    request = Oblodai::Models::PaymentRequest.new(amount: BigDecimal("3"), currency: "EUR", order_id: "o-1")
    client_with(http).payments.create(request, network: "tron")
    expect(http.calls[0].json).to eq("amount" => "3", "currency" => "EUR", "order_id" => "o-1",
                                     "network" => "tron")
  end

  it "refuses what JSON cannot carry" do
    http = FakeHTTP.new([])
    expect { client_with(http).payments.create(amount: BigDecimal("NaN"), currency: "USDT") }
      .to raise_error(Oblodai::ConfigError) { |e| expect(e.code).to eq("sdk.bad_body") }
    expect { client_with(http).payments.create(amount: Object.new, currency: "USDT") }
      .to raise_error(Oblodai::ConfigError) { |e| expect(e.code).to eq("sdk.bad_body") }
    expect(http.calls).to be_empty
  end

  it "parses amounts of the answer as BigDecimal" do
    http = FakeHTTP.new([FakeHTTP.ok_for("createPayment", "amount" => "25.10")])
    payment = client_with(http).payments.create(amount: "25.10", currency: "USDT")
    expect(payment.amount).to eq(BigDecimal("25.10"))
    expect(payment.amount).to be_a(BigDecimal)
  end
end

RSpec.describe Oblodai::Money do
  it "takes BigDecimal as well as strings, and refuses Float" do
    expect(described_class.add(BigDecimal("10.5"), "0.25")).to eq("10.75")
    expect(described_class.compare(BigDecimal("9"), "10")).to eq(-1)
    expect(described_class.equals?(BigDecimal("1.50"), "1.5")).to be(true)
    expect { described_class.add(1.5, "1") }
      .to raise_error(Oblodai::ConfigError) { |e| expect(e.code).to eq("sdk.float_amount") }
    expect { described_class.compare(BigDecimal("Infinity"), "1") }
      .to raise_error(Oblodai::ConfigError) { |e| expect(e.code).to eq("sdk.bad_amount") }
  end

  it "renders BigDecimal without an exponent" do
    expect(described_class.decimal_string(BigDecimal("1e-8"))).to eq("0.00000001")
    expect(described_class.decimal_string(BigDecimal("25"))).to eq("25")
    expect(described_class.decimal_string(BigDecimal("-0.5"))).to eq("-0.5")
  end
end
