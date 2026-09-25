# frozen_string_literal: true

# The runtime signs and verifies by the generated protocol (`Oblodai::Generated::SigningProtocol`,
# from the contract's `x-oblodai-signing`), not by literals of its own: a header the core renames, a
# reordered canonical string or a new skew reaches the SDK by regeneration alone.
RSpec.describe "signing protocol from the contract" do
  protocol = Oblodai::Generated::SigningProtocol

  it "is the backend spec's x-oblodai-signing" do
    skip "backend openapi.json not found (set OBLODAI_BACKEND)" if backend_spec.nil?
    signing = backend_spec.fetch("x-oblodai-signing")
    expect([protocol::HEADER_PUBLIC_ID, protocol::HEADER_SIGNATURE, protocol::HEADER_TIMESTAMP,
            protocol::HEADER_IDEMPOTENCY_KEY]).to eq(signing.fetch("headers"))
    expect([protocol::HEADER_WEBHOOK_TIMESTAMP, protocol::HEADER_WEBHOOK_SIGNATURE,
            protocol::HEADER_WEBHOOK_SIGNATURE_PREV, protocol::HEADER_WEBHOOK_EVENT, protocol::HEADER_WEBHOOK_ID,
            protocol::HEADER_WEBHOOK_EVENT_ID, protocol::HEADER_WEBHOOK_EVENT_TIME])
      .to eq(signing.dig("webhook", "headers"))
    expect(protocol::HEADER_WEBHOOK_TEST).to eq(signing.dig("webhook", "test_header"))
    expect(protocol::SIGNATURE_ALGORITHM).to eq(signing.fetch("algorithm"))
    expect(protocol::SKEW_SECONDS).to eq(signing.fetch("skew_seconds"))
    expect(protocol::MAX_BODY).to eq(signing.fetch("max_body"))
    expect(protocol::MAX_IDEMPOTENCY_KEY_LENGTH).to eq(signing.fetch("max_idempotency_key_length"))
  end

  it "keeps the public names of 1.x as the generated values" do
    expect(Oblodai::Signing::HEADER_PUBLIC_ID).to equal(protocol::HEADER_PUBLIC_ID)
    expect(Oblodai::Signing::HEADER_SIGNATURE).to equal(protocol::HEADER_SIGNATURE)
    expect(Oblodai::Signing::HEADER_TIMESTAMP).to equal(protocol::HEADER_TIMESTAMP)
    expect(Oblodai::Signing::HEADER_IDEMPOTENCY_KEY).to equal(protocol::HEADER_IDEMPOTENCY_KEY)
    expect(Oblodai::Signing::SKEW_SECONDS).to equal(protocol::SKEW_SECONDS)
    expect(Oblodai::Idempotency::MAX_KEY_LENGTH).to equal(protocol::MAX_IDEMPOTENCY_KEY_LENGTH)
    expect(Oblodai::Webhooks::HEADER_TIMESTAMP).to equal(protocol::HEADER_WEBHOOK_TIMESTAMP)
    expect(Oblodai::Webhooks::HEADER_SIGNATURE).to equal(protocol::HEADER_WEBHOOK_SIGNATURE)
    expect(Oblodai::Webhooks::HEADER_SIGNATURE_PREV).to equal(protocol::HEADER_WEBHOOK_SIGNATURE_PREV)
    expect(Oblodai::Webhooks::HEADER_EVENT).to equal(protocol::HEADER_WEBHOOK_EVENT)
    expect(Oblodai::Webhooks::HEADER_ID).to equal(protocol::HEADER_WEBHOOK_ID)
    expect(Oblodai::Webhooks::HEADER_EVENT_ID).to equal(protocol::HEADER_WEBHOOK_EVENT_ID)
    expect(Oblodai::Webhooks::HEADER_EVENT_TIME).to equal(protocol::HEADER_WEBHOOK_EVENT_TIME)
    expect(Oblodai::Webhooks::HEADER_TEST).to equal(protocol::HEADER_WEBHOOK_TEST)
    expect(Oblodai::Webhooks::DEFAULT_TOLERANCE).to equal(protocol::SKEW_SECONDS)
  end

  it "spells no signing or webhook header outside lib/oblodai/generated" do
    skip "backend openapi.json not found (set OBLODAI_BACKEND)" if backend_spec.nil?
    signing = backend_spec.fetch("x-oblodai-signing")
    names = [*signing.fetch("headers"), *signing.dig("webhook", "headers"), signing.dig("webhook", "test_header")]
            .map(&:downcase)
    lib = File.expand_path("../../lib", __dir__)
    offenders = Dir.glob(File.join(lib, "**", "*.rb")).reject { |p| p.include?("/generated/") }.flat_map do |path|
      text = File.read(path).downcase
      names.select { |n| text.include?(n) }.map { |n| "#{path.delete_prefix("#{lib}/")}: #{n}" }
    end
    expect(offenders).to eq([])
  end

  # The body and idempotency-key limits as source literals: decimal, and `1 << n` for a power of two
  # (digit separators — 1_048_576 — do not hide one). The skew is not scanned for: its value is also an
  # HTTP status class (`< 300`); the alias expectations above hold it.
  it "spells no literal of the body or idempotency-key limit outside lib/oblodai/generated" do
    pats = [protocol::MAX_BODY, protocol::MAX_IDEMPOTENCY_KEY_LENGTH].map { |l| /(?<![\w.])#{l}(?![\w.])/ }
    pats << /\b1\s*<<\s*#{protocol::MAX_BODY.bit_length - 1}\b/ if protocol::MAX_BODY.nobits?(protocol::MAX_BODY - 1)
    # Lines that carry the same number for another limit: the `request_id:` option (X-Request-ID) is
    # not part of x-oblodai-signing.
    other_limit = { "oblodai/core/options.rb" => /request_id/ }
    lib = File.expand_path("../../lib", __dir__)
    offenders = Dir.glob(File.join(lib, "**", "*.rb")).reject { |p| p.include?("/generated/") }.flat_map do |path|
      rel = path.delete_prefix("#{lib}/")
      File.readlines(path).each_with_index.flat_map do |line, i|
        next [] if other_limit[rel]&.match?(line)

        text = line.gsub(/(?<=\d)_(?=\d)/, "")
        pats.filter_map { |re| "#{rel}:#{i + 1}: #{re.source}" if re.match?(text) }
      end
    end
    expect(offenders).to eq([])
  end

  it "builds the request canonical string in the generated order with the generated separator" do
    stub_const("Oblodai::Generated::SigningProtocol::REQUEST_CANONICAL_ORDER",
               %w[METHOD body ts idempotency_key request_uri].freeze)
    stub_const("Oblodai::Generated::SigningProtocol::REQUEST_CANONICAL_SEPARATOR", "|")
    canonical = Oblodai::Signing.canonical_string(ts: 7, method: "post", request_uri: "/v1/x", body: "{}",
                                                  idempotency_key: "k")
    expect(canonical).to eq("POST|{}|7|k|/v1/x")
    expect(Oblodai::Signing.sign_request("s", ts: 7, method: "post", request_uri: "/v1/x", body: "{}",
                                              idempotency_key: "k"))
      .to eq(OpenSSL::HMAC.hexdigest("SHA256", "s", canonical))
  end

  it "signs a webhook in the generated order with the generated separator" do
    stub_const("Oblodai::Generated::SigningProtocol::WEBHOOK_CANONICAL_ORDER", %w[payload ts].freeze)
    stub_const("Oblodai::Generated::SigningProtocol::WEBHOOK_CANONICAL_SEPARATOR", "~")
    expect(Oblodai::Signing.sign_webhook("s", 9, "{}")).to eq(OpenSSL::HMAC.hexdigest("SHA256", "s", "{}~9"))
  end

  it "refuses an idempotency key longer than the contract allows" do
    stub_const("Oblodai::Generated::SigningProtocol::MAX_IDEMPOTENCY_KEY_LENGTH", 4)
    expect { Oblodai::Idempotency.assert_key!("abcde") }.to raise_error(Oblodai::ConfigError, /max 4/)
    expect { Oblodai::Idempotency.assert_key!("abcd") }.not_to raise_error
  end

  it "re-signs for skew by the contract's window" do
    stub_const("Oblodai::Generated::SigningProtocol::SKEW_SECONDS", 10)
    # 60 s of drift: far inside half of 300 s, but past half of the stubbed 10 s window.
    server_now = Time.now.to_i + 60
    http = FakeHTTP.new([
                          FakeHTTP.api_error(401, { "code" => "merchant.bad_signature", "retryable" => false },
                                             "date" => Time.at(server_now).httpdate),
                          FakeHTTP.ok_for("getBalance")
                        ])
    client_with(http, retry_policy: { max_retries: 0 }).account.get_balance
    expect(http.calls.size).to eq(2)
    stamp = http.calls[1].headers[protocol::HEADER_TIMESTAMP.downcase].to_i
    expect(stamp).to be_within(5).of(server_now)
  end
end
