# frozen_string_literal: true

# A secret reaches a log file through one of three doors: `p`/`inspect` (a REPL, an exception dump),
# `to_json` (a structured logger) or a logger the caller injected. All three are closed here.
RSpec.describe "secrets never print" do
  let(:client) do
    Oblodai::Client.new(public_id: "pk_test_1", secret: "super-secret-key",
                        admin_token: "adm-token", base_url: "https://api.test", http: FakeHTTP.new)
  end

  it "keeps the client, its config, its transport and its credentials unreadable" do
    [client.inspect, client.config.inspect, client.transport.inspect,
     client.config.credentials.inspect, client.config.credentials.to_s,
     client.config.credentials.to_json].each do |rendered|
      expect(rendered).not_to include("super-secret-key")
      expect(rendered).not_to include("adm-token")
    end
    expect(client.transport.inspect).to include("pk_test_1", "[redacted]")
    # …and the value is still readable when the caller means to read it.
    expect(client.config.credentials.secret).to eq("super-secret-key")
  end

  it "redacts secret-bearing models in inspect while keeping the accessor and the wire form" do
    cases = [
      [Oblodai::Models::RegisterWebhookResult.from_h(Samples.body("RegisterWebhookResult", "secret" => "whsec_live")),
       :secret, "whsec_live"],
      [Oblodai::Models::RotateWebhookSecretResult.from_h(
        Samples.body("RotateWebhookSecretResult", "secret" => "whsec_new")
      ), :secret, "whsec_new"],
      [Oblodai::Models::OnboardKey.from_h(Samples.body("OnboardKey", "secret" => "sk_live")), :secret, "sk_live"],
      [Oblodai::Models::PayoutLinkCreated.from_h(Samples.body("PayoutLinkCreated", "claim_token" => "tok_live")),
       :claim_token, "tok_live"],
      [Oblodai::Models::PayoutLinkCreated.from_h(
        Samples.body("PayoutLinkCreated", "claim_url" => "https://pay.example/claim/tok_live")
      ), :claim_url, "https://pay.example/claim/tok_live"],
      [Oblodai::Models::PayoutLinkCreated.from_h(Samples.body("PayoutLinkCreated", "passcode" => "1234")),
       :passcode, "1234"]
    ]
    cases.each do |model, field, value|
      expect(model.public_send(field)).to eq(value)
      expect(model.inspect).not_to include(value)
      expect(model.to_s).not_to include(value)
      expect(model.to_h[field.to_s]).to eq(value) # the wire form, for sending it back
    end
  end

  it "leaves an absent optional secret absent rather than inventing a placeholder" do
    endpoint = Oblodai::Models::RegisterWebhookResult.from_h("endpoint_id" => "e", "url" => "https://x")
    expect(endpoint.to_h).not_to have_key("secret")
    expect(endpoint.secret).to be_nil
    expect(endpoint.inspect).not_to include("secret")
  end

  it "compares models on their values, not on their redacted rendering" do
    one = Oblodai::Models::RegisterWebhookResult.from_h("endpoint_id" => "e", "url" => "u", "secret" => "a")
    two = Oblodai::Models::RegisterWebhookResult.from_h("endpoint_id" => "e", "url" => "u", "secret" => "b")
    same = Oblodai::Models::RegisterWebhookResult.from_h("endpoint_id" => "e", "url" => "u", "secret" => "a")
    expect(one).not_to eq(two)
    expect(one).to eq(same)
    expect(one.inspect).to eq(two.inspect)
  end

  it "redacts fields before a caller-injected logger sees them" do
    seen = []
    sink = Class.new do
      def initialize(seen) = @seen = seen
      def debug(message, fields = nil) = @seen << [message, fields]
      def info(message, fields = nil) = @seen << [message, fields]
      def warn(message, fields = nil) = @seen << [message, fields]
      def error(message, fields = nil) = @seen << [message, fields]
    end.new(seen)

    transport = Oblodai::Transport.new(base_url: "https://api.test", user_agent: "t", logger: sink)
    transport.instance_variable_get(:@logger)
             .debug("request", { secret: "sk_live", nested: { api_token: "t" }, route: "POST /v1/payment" })
    expect(seen.last[1]).to eq(secret: "[redacted]", nested: { api_token: "[redacted]" },
                               route: "POST /v1/payment")
  end

  it "keeps the raw response body off an error's own renderings" do
    error = Oblodai::ContractError.new("bad", 200, { "secret" => "leaked" })
    expect(error.inspect).not_to include("leaked")
    expect(error.to_json).not_to include("leaked")
    expect(error.to_h).not_to have_key(:raw)
    expect(error.raw_body).to eq("secret" => "leaked")
  end
end
