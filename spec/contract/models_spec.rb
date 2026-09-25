# frozen_string_literal: true

# Generated models versus the golden bodies the core recorded (contract/fixtures). Every recorded
# 2xx answer goes through the SDK method of its route, end to end: it must parse, and no model on the
# way may be left with fields it does not know (`extra`) — a field the core started sending that the
# contract does not declare fails here. Webhook samples, statuses and error envelopes are checked
# against the generated enums and models the same way.
RSpec.describe "recorded answers" do
  by_key = Oblodai::Generated::ROUTES.to_h { |op, route| [route.key, op] }
  recorded = Fixtures.fixtures.select do |route, fx|
    (200..299).cover?(fx["status"]) && fx.dig("headers", "Content-Type").to_s.include?("json") && by_key.key?(route)
  end

  # Recordings older than a required field the core added since (fixtures: 2026-08-26). The answer
  # must fail on exactly that field; a refreshed recording drops its row here.
  added_since_recording = {
    "GET /v1/pay/{id}" => "fiat_purchase_available", # 2026-09-23
    "POST /v1/link/{id}/checkout" => "method_adjustment", # 2026-09-06
    "POST /v1/pay/{id}/select" => "method_adjustment",
    "POST /v1/payment" => "fee_percent", # 2026-09-10
    "POST /v1/payment/cancel" => "fee_percent",
    "POST /v1/payment/history" => "fee_percent",
    "POST /v1/payment/info" => "fee_percent",
    "POST /v1/sandbox/reset" => "payout_links_cancelled", # 2026-09-24
    "POST /v1/webhooks/deliveries" => "cancel_reason" # 2026-09-24
  }

  # Every `extra` field of every model inside `value`, with its path.
  def unknown_fields(value, where = "result")
    case value
    when Oblodai::Models::Base
      value.extra.keys.map { |name| "#{where}.#{name}" } +
        value.class::FIELDS.flat_map { |json| unknown_fields(reader(value, json), "#{where}.#{json}") }
    when Array then value.each_with_index.flat_map { |item, i| unknown_fields(item, "#{where}[#{i}]") }
    when Hash then value.flat_map { |key, item| unknown_fields(item, "#{where}.#{key}") }
    else []
    end
  end

  # The reader of a field by its JSON name (`end` is read as `end_`).
  def reader(model, json)
    name = json.gsub(/([a-z0-9])([A-Z])/, '\1_\2').downcase.gsub(/[^a-z0-9_]/, "_")
    [name, "#{name}_"].each { |n| return model.public_send(n) if model.respond_to?(n) }
    raise "#{model.class}: no reader for #{json}"
  end

  it "has recorded bodies to check" do
    expect(recorded.size).to be > 50
  end

  recorded.each do |route, fx|
    it "#{route} parses into its model with no unknown fields" do
      http = FakeHTTP.new([{ status: 200, body: fx["response"] }])
      client = Oblodai::Client.new(public_id: "pk", secret: "s", admin_token: "adm",
                                   base_url: "https://api.test", http: http, env: {})
      run = lambda do
        result = Coverage.call(client, by_key.fetch(route))
        result = result.first_page.items if result.is_a?(Oblodai::Page)
        result = result.result if result.is_a?(Oblodai::Job)
        result
      end
      added = added_since_recording[route]
      if added
        expect { run.call }.to raise_error(KeyError) { |e| expect(e.key).to eq(added) }
        next
      end
      result = run.call
      expect(result).not_to be_nil
      expect(unknown_fields(result)).to eq([]), "#{route}: the contract does not declare these fields"
    end
  end
end

RSpec.describe "vocabularies cover what the wire carries" do
  enums = Oblodai::Enums

  it "statuses in the golden bodies are in the enums" do
    Fixtures.result_of("POST /v1/payment/history")["items"].each do |payment|
      expect(enums::PaymentStatus::VALUES).to include(payment["status"])
    end
    Fixtures.result_of("POST /v1/payout/history")["items"].each do |payout|
      expect(enums::PayoutStatus::VALUES).to include(payout["status"])
    end
    Fixtures.result_of("POST /v1/payout/link/list")["items"].each do |link|
      expect(enums::PayoutLinkStatus::VALUES).to include(link["status"])
    end
    Fixtures.result_of("POST /v1/webhooks/deliveries")["items"].each do |delivery|
      expect(enums::WebhookDeliveryStatus::VALUES).to include(delivery["status"])
    end
  end

  it "webhook samples carry known event names and parse into their models with nothing unknown" do
    expect(Fixtures.webhook_samples).not_to be_empty
    Fixtures.webhook_samples.each do |sample|
      expect(enums::WebhookEventName::VALUES).to include(sample["headers"][SIGNING::HEADER_WEBHOOK_EVENT])
      body = sample["raw"] ? JSON.parse(sample["raw"]) : sample["body"]
      event = Oblodai::Webhooks::EVENT_MODELS.fetch(body["type"]).from_h(body)
      expect(event.extra).to eq({}), sample["headers"][SIGNING::HEADER_WEBHOOK_EVENT]
    end
  end

  it "flags the rehearsal deliveries among the samples and no others" do
    flagged = Fixtures.webhook_samples.select { |s| s["body"]["test"] == true }
    expect(flagged).not_to be_empty, "no rehearsal sample left to guard the test flag"
    Fixtures.webhook_samples.each do |sample|
      event = Oblodai::Webhooks.parse(sample["raw"] || JSON.generate(sample["body"]))
      expect(Oblodai::Webhooks.test_event?(event)).to be(sample["body"]["test"] == true)
    end
  end

  it "every recorded error code is a known code with the documented envelope" do
    Fixtures.error_samples.each do |code, fx|
      expect(enums::ErrorCode::VALUES).to include(code)
      error = fx.dig("response", "error")
      expect(error["code"]).to eq(code)
      expect([true, false]).to include(error["retryable"])
      expect(error["request_id"]).to be_a(String)
      expect(error["retry_after"]).to be > 0 if fx["status"] == 429
    end
  end

  it "turns every recorded error envelope into the right error class" do
    Fixtures.error_samples.each do |code, fx|
      error = Oblodai.api_error_from(fx["status"], fx.dig("response", "error"))
      expect(error.code).to eq(code)
      expect(error.http_status).to eq(fx["status"])
      expect(error.retryable?).to eq(fx.dig("response", "error", "retryable"))
      expect(error).to be_a(Oblodai::ApiError)
      expect(error).not_to be_synthetic
    end
  end

  it "every error code a method documents is in the catalogue" do
    source = File.read(File.expand_path("../../lib/oblodai/generated/resources.rb", __dir__))
    advertised = source.scan(/# Error codes: (.*?)\n\s*#\n/m).flat_map do |(block)|
      block.gsub(/\n\s*#\s*/, " ").split(",").map(&:strip)
    end
    expect(advertised.size).to be > 500
    expect(advertised.uniq - enums::ErrorCode::VALUES).to eq([])
  end
end

RSpec.describe "recorded requests" do
  by_key = Oblodai::Generated::ROUTES.to_h { |op, route| [route.key, op] }

  # The fixtures are real requests the core answered 2xx to: every field of each must be
  # expressible through the method's keywords and reach the wire unchanged.
  Fixtures.fixtures.each do |route, fx|
    next unless (200..299).cover?(fx["status"]) && fx["request"].is_a?(Hash) && !fx["request"].empty?
    next unless by_key.key?(route) && Oblodai::Generated::ROUTES.fetch(by_key[route]).method == "POST"

    it "#{route}: the recorded body goes out through keywords" do
      op = by_key.fetch(route)
      answer = Oblodai::Generated::ROUTES.fetch(op).bare ? { status: 200, body: "%PDF" } : FakeHTTP.ok_for(op)
      http = FakeHTTP.new([answer])
      client = Oblodai::Client.new(public_id: "pk", secret: "s", base_url: "https://api.test", http: http, env: {})
      namespace, name = Coverage.ledger.fetch(op)
      keywords = client.public_send(namespace).method(name).parameters.filter_map { |kind, arg| arg if kind == :key }
      args = fx["request"].to_h do |field, value|
        key = field.to_sym
        key = :"#{field}_" unless keywords.include?(key)
        expect(keywords).to include(key), "#{route}: no keyword for #{field}"
        [key, value]
      end
      args.delete(:idempotency_key) # a route's own idempotency_key field comes from the option
      result = Coverage.call(client, op, **args)
      result.first_page if result.is_a?(Oblodai::Page)
      sent = http.calls.first.json
      fx["request"].each do |field, value|
        next if field == "idempotency_key"

        expect(sent[field]).to eq(value), "#{route}: #{field}"
      end
    end
  end
end
