# frozen_string_literal: true

require "pp"

# Bearer secrets never reach what the SDK shows people: hooks, error messages, inspect/pp, logs.
# The claim token of `/v1/claim/{token}` and `/v1/aml/{token}` and a signed document link's
# `sig`/`exp` travel in the URL; a caller's proxy credentials travel in headers; the CLI device
# flow's `device_code` travels in a model. Each one used to show up somewhere.
RSpec.describe "redaction" do
  token = "CLAIMTOKEN-ONE-TIME"

  def capture_hooks
    seen = []
    [Oblodai::Hooks.new(on_request: ->(info) { seen << info }, on_response: ->(info) { seen << info }), seen]
  end

  it "shows hooks the route with the claim token and proxy credentials masked" do
    hooks, seen = capture_hooks
    http = FakeHTTP.new([FakeHTTP.api_error(404, { "code" => "payout_link.not_found", "retryable" => false })])
    client = client_with(http, hooks: hooks,
                               headers: { "Authorization" => "Bearer PROXY-TOKEN", "x-api-key" => "PROXY-KEY",
                                          "X-Claim-Passcode" => "PASSCODE-1", "X-Trace" => "t-1" })
    error = begin
      client.payout_links.get_payout_claim(token)
    rescue Oblodai::Error => e
      e
    end
    request = seen.first
    expect(request.url).to end_with("/v1/claim/[redacted]")
    rendered = [request.inspect, request.headers.inspect, seen.last.inspect, error.inspect, error.message].join
    %W[#{token} PROXY-TOKEN PROXY-KEY PASSCODE-1].each { |secret| expect(rendered).not_to include(secret) }
    expect(request.headers["X-Trace"]).to eq("t-1")
    expect(http.calls.first.url).to include(token) # the wire keeps the real value
  end

  it "shows a signed document link without its sig or exp" do
    hooks, seen = capture_hooks
    http = FakeHTTP.new([{ status: 200, body: "%PDF", headers: { "content-type" => "application/pdf" } }])
    client_with(http, hooks: hooks).documents.get_signed("invoice", "i-1", exp: 1_900_000_000, sig: "SIGVALUE0123",
                                                                           lang: "en")
    url = seen.first.url
    expect(url).not_to include("SIGVALUE0123", "1900000000")
    expect(url).to include("sig=[redacted]", "exp=[redacted]", "lang=en")
    expect(http.calls.first.url).to include("sig=SIGVALUE0123")
  end

  it "keeps the claim token out of error messages" do
    too_big = FakeHTTP.new([{ status: 200, body: "x" * ((8 * 1024 * 1024) + 1) }])
    expect { client_with(too_big).payout_links.get_payout_claim(token) }
      .to raise_error(Oblodai::Error) { |e| expect([e.message.include?("exceeds"), e.message.include?(token)]).to eq([true, false]) }

    redirected = FakeHTTP.new([{ status: 200, body: "{}", url: "https://evil.test/v1/claim/#{token}" }])
    expect { client_with(redirected).payout_links.get_payout_claim(token) }
      .to raise_error(Oblodai::Error) { |e| expect([e.message.include?("evil.test"), e.message.include?(token)]).to eq([true, false]) }

    location = FakeHTTP.new([{ status: 302, body: "",
                               headers: { "location" => "https://evil.test/v1/claim/#{token}" } }])
    expect { client_with(location, retry_policy: { max_retries: 0 }).payout_links.get_payout_claim(token) }
      .to raise_error(Oblodai::Error) { |e| expect([e.message.include?("evil.test"), e.message.include?(token)]).to eq([true, false]) }
  end

  it "scrubs the URL out of a Net::HTTP error text" do
    adapter = Oblodai::HTTP::NetHTTPAdapter.new
    request = Oblodai::HTTP::Request.new(method: "GET", url: "https://api.test/v1/claim/#{token}", headers: {},
                                         display_url: "https://api.test/v1/claim/[redacted]")
    expect(adapter.send(:scrub, "cannot reach https://api.test/v1/claim/#{token} (/v1/claim/#{token})", request))
      .to eq("cannot reach https://api.test/v1/claim/[redacted] (/v1/claim/[redacted])")
  end

  it "renders neither the signature nor the token when a built request is inspected or pp'd" do
    credentials = Oblodai::RequestBuilder::Credentials.new(public_id: "p", secret: "SECRET-XYZ")
    claim = Oblodai::RequestBuilder.build(
      base_url: "https://api.test", route: Oblodai::Generated::ROUTES.fetch("getPayoutClaim"), body: "", ts: 1,
      user_agent: "ua", path_params: { token: token }
    )
    signed = Oblodai::RequestBuilder.build(
      base_url: "https://api.test", route: Oblodai::Generated::ROUTES.fetch("getBalance"), body: "", ts: 1,
      user_agent: "ua", credentials: credentials
    )
    signature = signed.headers.fetch(SIGNING::HEADER_SIGNATURE)
    expect(claim.url).to include(token)
    [claim, signed].each do |built|
      adapter_request = Oblodai::HTTP::Request.new(method: "GET", url: built.url, headers: built.headers,
                                                   display_url: built.display_url)
      [built.inspect, built.pretty_inspect, adapter_request.inspect, adapter_request.pretty_inspect].each do |shown|
        expect(shown).not_to include(token)
        expect(shown).not_to include(signature)
      end
    end
  end

  it "keeps the API secret out of pp and pretty_inspect of Credentials (IRB, Rails console)" do
    credentials = Oblodai::RequestBuilder::Credentials.new(public_id: "p", secret: "S3CRET-PP")
    out = StringIO.new
    PP.pp(credentials, out)
    [out.string, credentials.pretty_inspect, credentials.to_a.inspect, credentials.deconstruct_keys(nil).inspect]
      .each { |shown| expect(shown).not_to include("S3CRET-PP") }
    expect(credentials.secret).to eq("S3CRET-PP")
    client = Oblodai::Client.new(public_id: "p", secret: "S3CRET-PP", base_url: "https://api.test", env: {})
    [client, client.config, client.transport].each do |object|
      expect(object.pretty_inspect).not_to include("S3CRET-PP")
    end
  end

  it "redacts the CLI device code in models and log fields" do
    model = Oblodai::Models::CLIDeviceAuthorization.from_h(
      Samples.body("CLIDeviceAuthorization", "device_code" => "SECRET-DEVICE-CODE-123", "user_code" => "ABCD-EFGH")
    )
    expect(model.inspect).not_to include("SECRET-DEVICE-CODE-123")
    expect(model.pretty_inspect).not_to include("SECRET-DEVICE-CODE-123")
    expect(Oblodai::Logging.redact(model.to_h).inspect).not_to include("SECRET-DEVICE-CODE-123")
    expect(model.inspect).to include("ABCD-EFGH")
    expect(Oblodai::Logging.redact({ "X-Api-Key" => "k", "api_key" => { "secret" => "s" } }))
      .to eq({ "X-Api-Key" => "[redacted]", "api_key" => "[redacted]" })
  end
end
