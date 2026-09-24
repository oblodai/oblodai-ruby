# frozen_string_literal: true

require "stringio"
require "tmpdir"

# The examples run: each examples/*.rb executes against the same scripted gateway as the README. The
# scripts are what a merchant copies first, so a renamed method, a changed result shape or a method
# that now returns a Job must break a spec, not the merchant.
RSpec.describe "examples" do
  dir = File.expand_path("../../examples", __dir__)

  around do |example|
    saved = ENV.to_h.slice("OBLODAI_PUBLIC_ID", "OBLODAI_SECRET")
    ENV["OBLODAI_PUBLIC_ID"] = "example"
    ENV["OBLODAI_SECRET"] = "s" * 32
    example.run
  ensure
    %w[OBLODAI_PUBLIC_ID OBLODAI_SECRET].each { |k| saved.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
  end

  def run_script(path)
    gateway = Gateway.new
    allow(Oblodai::HTTP::NetHTTPAdapter).to receive(:new).and_return(gateway)
    out = StringIO.new
    $stdout = out
    Dir.mktmpdir { |tmp| Dir.chdir(tmp) { load path } }
    [gateway, out.string]
  rescue SystemExit => e
    raise "#{File.basename(path)} exited early (#{e.status}): #{out.string}"
  ensure
    $stdout = STDOUT
  end

  %w[accept_payment.rb payout.rb sandbox.rb].each do |name|
    it "#{name} walks its main path" do
      gateway, out = run_script(File.join(dir, name))
      expect(gateway.calls).not_to be_empty
      expect(out).not_to be_empty
    end
  end

  it "payout.rb sends its own idempotency key and waits for the batch" do
    gateway, out = run_script(File.join(dir, "payout.rb"))
    create = gateway.calls.find { |r| r.url.end_with?("/v1/payout") }
    expect(create.headers["Idempotency-Key"]).to start_with("payout-")
    expect(out).to include("batch ", "completed")
  end

  describe "webhook_receiver.rb" do
    before(:all) { load File.join(File.expand_path("../../examples", __dir__), "webhook_receiver.rb") }

    let(:out) { StringIO.new }
    let(:receiver) { WebhookReceiver.new(secret: "whsec-example", out: out) }
    let(:ts) { Time.now.to_i }

    def delivery(body, id: "d-1", secret: "whsec-example")
      raw = JSON.generate(body)
      [raw, { "X-Webhook-Timestamp" => ts.to_s, "X-Webhook-Id" => id,
              "X-Webhook-Signature" => Oblodai::Signing.sign_webhook(secret, ts, raw) }]
    end

    it "settles an authentic delivery once and refuses a forgery" do
      body = Samples.body("PaymentWebhook", "type" => "payment", "uuid" => "u", "status" => "paid",
                                            "sequence" => 3)
      raw, headers = delivery(body)
      expect(receiver.call(raw, headers)).to eq([200, "ok"])
      expect(receiver.call(raw, headers)).to eq([200, "ok"])
      expect(out.string).to include("invoice", "duplicate delivery d-1")
      expect(receiver.call("#{raw} ", headers).first).to eq(401)
    end

    it "acknowledges a rehearsal, an unknown kind and an unreadable body without a 401" do
      rehearsal = Samples.body("PayoutWebhook", "type" => "payout", "uuid" => "p", "test" => true)
      expect(receiver.call(*delivery(rehearsal, id: "d-2")).first).to eq(200)
      expect(receiver.call(*delivery({ "type" => "settlement", "uuid" => "s" }, id: "d-3")).first).to eq(200)
      expect(receiver.call(*delivery({ "type" => "payment", "uuid" => "u" }, id: "d-4")).first).to eq(400)
      expect(out.string).to include("rehearsal", "unknown event type settlement", "unreadable")
    end
  end
end
