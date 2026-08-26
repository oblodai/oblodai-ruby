# frozen_string_literal: true

RSpec.describe Oblodai::Config do
  it "reads credentials and the base URL from the environment" do
    config = described_class.new(env: { "OBLODAI_PUBLIC_ID" => "pk", "OBLODAI_SECRET" => "s",
                                        "OBLODAI_BASE_URL" => "https://x.test/" })
    expect(config.credentials.public_id).to eq("pk")
    expect(config.credentials.secret).to eq("s")
    expect(config.base_url).to eq("https://x.test")
  end

  it "refuses plain http except for loopback or when explicitly allowed" do
    expect { described_class.new(base_url: "http://api.oblodai.com", env: {}) }
      .to raise_error(Oblodai::ConfigError, /https/)
    expect(described_class.new(base_url: "http://localhost:8095", env: {}).base_url)
      .to eq("http://localhost:8095")
    expect(described_class.new(base_url: "http://127.0.0.1:8095", env: {}).base_url)
      .to eq("http://127.0.0.1:8095")
    expect(described_class.new(base_url: "http://10.0.0.1", allow_insecure_base_url: true, env: {}).base_url)
      .to eq("http://10.0.0.1")
    expect(described_class.new(base_url: "http://10.0.0.1",
                               env: { "OBLODAI_ALLOW_INSECURE" => "1" }).base_url).to eq("http://10.0.0.1")
  end

  it "refuses half a key pair" do
    expect { described_class.new(public_id: "pk", env: {}) }.to raise_error(Oblodai::ConfigError, /together/)
    expect { described_class.new(secret: "s", env: {}) }.to raise_error(Oblodai::ConfigError, /together/)
  end

  it "has no payout credential pair to configure: one API key signs every signed route" do
    expect { described_class.new(payout_public_id: "wk", payout_secret: "s", env: {}) }
      .to raise_error(ArgumentError, /unknown keyword/)
    expect(described_class.instance_method(:initialize).parameters.map(&:last))
      .not_to include(:payout_public_id, :payout_secret)
  end

  it "treats an empty environment variable as unset, not as a credential" do
    # `export OBLODAI_SECRET=` in a shell profile arrives as "": signing with it would produce a 401
    # nobody can explain, so it counts as absent — and half a pair is still refused.
    config = described_class.new(env: { "OBLODAI_PUBLIC_ID" => "", "OBLODAI_SECRET" => "  ",
                                        "OBLODAI_BASE_URL" => "" })
    expect(config.credentials).to be_nil
    expect(config.base_url).to eq(Oblodai::DEFAULT_BASE_URL) # a blank URL falls through to the default
    expect { described_class.new(env: { "OBLODAI_PUBLIC_ID" => "pk", "OBLODAI_SECRET" => "" }) }
      .to raise_error(Oblodai::ConfigError, /together/)
  end

  it "refuses a base URL without a scheme or a host" do
    ["api.oblodai.com", "/v1", "https://", "not a url at all"].each do |bad|
      expect { described_class.new(base_url: bad, env: {}) }
        .to raise_error(Oblodai::ConfigError) { |e|
              expect(e.code).to eq("sdk.bad_config")
              expect(e.field).to eq("base_url")
            }
    end
  end

  it "turns OBLODAI_LOG into a logger and redacts secrets" do
    config = described_class.new(env: { "OBLODAI_LOG" => "debug" })
    expect(config.logger).to be_a(Oblodai::IOLogger)
    expect(Oblodai::Logging.redact(secret: "abc", nested: { signature: "s", route: "r" }))
      .to eq(secret: "[redacted]", nested: { signature: "[redacted]", route: "r" })
  end

  it "accepts retry overrides" do
    config = described_class.new(retry_policy: { max_retries: 0 }, env: {})
    expect(config.retry_policy.max_retries).to eq(0)
    expect(config.retry_policy.base_delay_ms).to eq(250)
  end
end

RSpec.describe Oblodai::Money do
  it "works at arbitrary precision and keeps the widest scale" do
    expect(described_class.add("0.1", "0.2")).to eq("0.3")
    expect(described_class.add("10.000000", "0.5")).to eq("10.500000")
    expect(described_class.subtract("1", "1.000001")).to eq("-0.000001")
    expect(described_class.compare("25", "25.000000")).to eq(0)
    expect(described_class.compare("0.000000000000000001", "0")).to eq(1)
    expect(described_class).to be_zero("0.000000")
    expect(described_class).to be_negative("-0.1")
    expect(described_class.equals?("1.50", "1.5")).to be(true)
    # Every rejection is the SDK's own error, never a native TypeError from inside a helper.
    ["1,5", ".5", "5.", "1e3", "+1", "1_000", "", "9" * 65].each do |bad|
      expect { described_class.add(bad, "1") }
        .to raise_error(Oblodai::ConfigError) { |e| expect(e.code).to eq("sdk.bad_amount") }
      expect(described_class.valid?(bad)).to be(false)
    end
    expect { described_class.compare(25, "25") }.to raise_error(Oblodai::ConfigError, /expected a string/)
  end
end

RSpec.describe Oblodai::Status do
  it "follows the core vocabulary" do
    expect(described_class).to be_payment_paid("paid_over")
    expect(described_class).not_to be_payment_paid("wrong_amount")
    expect(described_class).to be_payment_underpaid("wrong_amount")
    expect(described_class).not_to be_payment_final("confirm_check")
    expect(described_class).not_to be_payout_final("sent")
    expect(described_class).to be_payout_final("confirmed")
    expect(described_class).to be_payout_succeeded("confirmed")
  end
end

RSpec.describe Oblodai::Models::Model do
  let(:payment) do
    Oblodai::Models::Payment.from("uuid" => "u", "status" => "paid", "amount" => "25",
                                  "tx_list" => [{ "txid" => "t", "amount" => "25" }],
                                  "brand_new_field" => 7)
  end

  it "exposes wire names as attributes and keeps unknown fields" do
    expect(payment.uuid).to eq("u")
    expect(payment.tx_list.first).to be_a(Oblodai::Models::PaymentTx)
    expect(payment.tx_list.first.txid).to eq("t")
    expect(payment[:brand_new_field]).to eq(7)
    expect(payment.extra).to eq(brand_new_field: 7)
  end

  it "round-trips to the wire shape and is frozen" do
    expect(payment.to_h).to eq(uuid: "u", status: "paid", amount: "25",
                               tx_list: [{ txid: "t", amount: "25" }], brand_new_field: 7)
    expect(payment).to be_frozen
    expect(payment).to eq(Oblodai::Models::Payment.from(JSON.parse(payment.to_json)))
  end
end
