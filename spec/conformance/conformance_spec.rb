# frozen_string_literal: true

require "bigdecimal"
require "json"
require "uri"

# The shared conformance suite every Oblodai SDK runs (backend `tools/sdkgen/conformance`).
#
# Scenarios are read from `$SDKGEN_CONFORMANCE`, else from `tools/sdkgen/conformance` of the backend
# checkout the drift check uses (`$OBLODAI_BACKEND`, else `../oblodai-backend`). Signing vectors are
# not in the scenario files: each suite names the backend `openapi.json` and a pointer into its
# `x-oblodai-signing`, and the vectors are read from there. Every call scenario runs through the
# generated method of its operation on a scripted HTTP adapter; retry pauses are recorded instead of
# slept.
module Conformance
  module_function

  def dir
    explicit = ENV.fetch("SDKGEN_CONFORMANCE", nil)
    return explicit if explicit

    backend = ENV.fetch("OBLODAI_BACKEND") { File.expand_path("../../../oblodai-backend", __dir__) }
    File.join(backend, "tools", "sdkgen", "conformance")
  end

  def available?
    return true if File.directory?(dir)
    raise "conformance suite not found at #{dir}" if ENV["SDKGEN_CONFORMANCE"] || ENV["OBLODAI_BACKEND"]

    false
  end

  def suite(name)
    JSON.parse(File.read(File.join(dir, "#{name}.json")))
  end

  def pointer(doc, path)
    path.delete_prefix("/").split("/").reduce(doc) { |cur, part| cur.fetch(part.gsub("~1", "/").gsub("~0", "~")) }
  end

  # The spec's `x-oblodai-signing` and the vectors the suite points at.
  def source(suite)
    src = suite.fetch("source")
    spec = JSON.parse(File.read(File.expand_path(src.fetch("spec"), dir)))
    [spec.fetch("x-oblodai-signing"), pointer(spec, src.fetch("pointer"))]
  end

  # Header names by role (`header_names`), read from the spec and never from the SDK's own constants:
  # a header the core renamed that did not reach the SDK fails here.
  def header_names(suite)
    names = suite.fetch("header_names")
    spec = JSON.parse(File.read(File.expand_path(suite.dig("source", "spec"), dir)))
    list = pointer(spec, names.fetch("pointer"))
    roles = names.fetch("roles")
    raise "header_names: #{list.size} names for #{roles.size} roles" unless list.size == roles.size

    roles.zip(list).to_h
  end

  # The rehearsal header name the spec gives (`header_names.test_pointer`) — again the spec's name,
  # not the SDK's constant.
  def test_header(suite)
    spec = JSON.parse(File.read(File.expand_path(suite.dig("source", "spec"), dir)))
    name = pointer(spec, suite.fetch("header_names").fetch("test_pointer"))
    raise "header_names.test_pointer: empty name" if name.to_s.empty?

    name
  end

  # Send a request vector through the signing transport the client's methods use — keys `public_id`
  # + the vector's secret, clock at the vector's `ts` — and return the one request that reached the
  # HTTP adapter. That request is the vector's own — method, path + raw query and body bytes — so a
  # matching signature proves the SDK signed what it sent.
  def send_vector(vector, public_id)
    script = Script.new([{ "status" => 200, "json" => { "state" => 0, "result" => {} } }])
    path, raw_query = vector.fetch("request_uri").split("?", 2)
    key = vector.fetch("idempotency_key")
    route = Oblodai::RouteSpec.new(operation_id: "conformanceRequestHeaders", method: vector.fetch("method"),
                                   path: path, auth: :key, idempotent: !key.empty?, safe: false, bare: false,
                                   list_kind: nil)
    transport = Oblodai::Transport.new(
      base_url: "https://api.test", user_agent: "conformance", http: script,
      credentials: Oblodai::RequestBuilder::Credentials.new(public_id: public_id, secret: vector.fetch("secret")),
      clock: Oblodai::Clock.new(-> { vector.fetch("ts") })
    )
    body = vector.fetch("method") == "GET" ? nil : JSON.parse(vector.fetch("body"))
    transport.call(route, Oblodai::Transport::CallOptions.new(
                            body: body, query: URI.decode_www_form(raw_query.to_s).to_h,
                            idempotency_key: key.empty? ? nil : key
                          ))
    raise "sent #{script.requests.size} requests, want 1" unless script.requests.size == 1

    request = script.requests.first
    raise "method #{request.method}, want #{vector["method"]}" unless request.method.to_s == vector.fetch("method")

    uri = URI(request.url)
    sent_uri = uri.query ? "#{uri.path}?#{uri.query}" : uri.path
    raise "request_uri #{sent_uri}, want #{vector["request_uri"]}" unless sent_uri == vector.fetch("request_uri")
    unless request.body.to_s == vector.fetch("body")
      raise "body #{request.body.inspect}, want #{vector["body"].inspect}"
    end

    request
  end

  # Replays the scenario's responses and records what the SDK sent.
  class Script
    attr_reader :requests

    def initialize(responses)
      @queue = responses.dup
      @requests = []
    end

    def call(request, timeout:) # rubocop:disable Lint/UnusedMethodArgument
      @requests << request
      step = @queue.shift
      raise "unscripted request #{request.method} #{request.url}" if step.nil?
      raise Oblodai::TransportError.new("transport.timeout", "scripted timeout") if step["transport_error"] == "timeout"

      headers = step.fetch("headers", {}).to_h { |k, v| [k.downcase, v] }
      if step.key?("json")
        body = JSON.generate(step["json"])
        headers["content-type"] ||= "application/json"
      else
        body = "<html>proxy</html>"
        headers["content-type"] ||= "text/html"
      end
      Oblodai::HTTP::Response.new(status: step.fetch("status"), headers: headers, body: body, url: request.url)
    end
  end
end

RSpec.describe "conformance" do
  unless Conformance.available?
    it "runs the shared suite" do
      skip "conformance suite not found at #{Conformance.dir}; set OBLODAI_BACKEND or SDKGEN_CONFORMANCE"
    end
    next
  end

  describe "request signing" do
    suite = Conformance.suite("signing")
    _, vectors = Conformance.source(suite)
    names = Conformance.header_names(suite)

    it "has vectors" do
      expect(vectors).not_to be_empty
    end

    suite.fetch("checks").each do |check|
      vectors.each_with_index do |vector, i|
        it "#{check["name"]} ##{i}" do
          key = vector["idempotency_key"].to_s
          args = { ts: vector["ts"], method: vector["method"], request_uri: vector["request_uri"],
                   body: vector["body"], idempotency_key: key.empty? ? nil : key }
          case check["kind"]
          when "request_canonical"
            expect(Oblodai::Signing.canonical_string(**args)).to eq(vector["canonical"])
          when "request_signature"
            expect(Oblodai::Signing.sign_request(vector["secret"], **args)).to eq(vector["signature"])
          when "request_headers"
            sent = Conformance.send_vector(vector, check.fetch("public_id")).headers.to_h { |k, v| [k.downcase, v] }
            header = ->(role) { sent[names.fetch(role).downcase] }
            expect(header.call("public_id")).to eq(check["public_id"]), names["public_id"]
            expect(header.call("signature")).to eq(vector["signature"]), names["signature"]
            expect(header.call("timestamp")).to eq(vector["ts"].to_s), names["timestamp"]
            expect(header.call("idempotency_key")).to eq(key.empty? ? nil : key), names["idempotency_key"]
          else raise "unknown check kind #{check["kind"]}"
          end
        end
      end
    end
  end

  describe "webhooks" do
    suite = Conformance.suite("webhook")
    signing, vectors = Conformance.source(suite)
    names = Conformance.header_names(suite)

    suite.fetch("checks").each do |check|
      vectors.each_with_index do |vector, i|
        it "#{check["name"]} ##{i}" do
          secret = vector["secret"]
          ts = vector["ts"]
          payload = vector["payload"]
          if check["kind"] == "webhook_signature"
            expect(Oblodai::Signing.sign_webhook(secret, ts, payload)).to eq(vector["signature"])
            next
          end
          expect(check["kind"]).to eq("webhook_verify")

          skew = Integer(signing.fetch("skew_seconds"))
          offset = { "skew" => skew, "skew+1" => skew + 1 }.fetch(check["now_from_ts"], check["now_from_ts"])
          signature = vector["signature"]
          case check["mutate"]
          when "payload" then payload += " "
          when "signature" then signature = (signature[0] == "0" ? "1" : "0") + signature[1..]
          end
          headers = { names.fetch("timestamp") => ts.to_s, names.fetch("signature") => signature }
          verify = -> { Oblodai::Webhooks.verify(payload, headers, secret: secret, tolerance: skew, now: ts + Integer(offset)) }
          if check["expect"] == "ok"
            # The vectors sign bare payloads, not whole events: verify gets past the MAC and the
            # freshness window and only then may refuse to parse — that refusal still is a pass.
            begin
              verify.call
            rescue Oblodai::WebhookPayloadError
              nil
            end
          else
            expect { verify.call }.to raise_error(Oblodai::SignatureError) { |e|
              expect(e.code).to eq("webhook.#{check["expect"]}")
            }
          end
        end
      end
    end
  end

  describe "webhook deliveries" do
    suite = Conformance.suite("webhook_delivery")
    _, deliveries = Conformance.source(suite)
    names = Conformance.header_names(suite)
    test_header = Conformance.test_header(suite)

    it "has a delivery of every event this release knows" do
      expect(deliveries.map { |d| d["event"] }).to match_array(Oblodai::Generated::WEBHOOK_EVENTS.keys)
    end

    suite.fetch("checks").each do |check|
      raise "unknown check kind #{check["kind"]}" unless check["kind"] == "webhook_delivery"

      deliveries.each do |vector|
        it "#{check["name"]} — #{vector["event"]} (#{check["key"]})" do
          secret = vector.fetch({ "current" => "secret", "previous" => "previous_secret" }.fetch(check["key"]))
          headers = vector["headers"].dup
          headers[test_header] = "true" if check["test"]
          delivery = Oblodai::Webhooks.verify_delivery(vector["payload"], headers, secret: secret, now: vector["ts"])
          expect(delivery.test?).to be(check.fetch("test", false)), "test? (rehearsal header #{test_header})"
          expect(delivery.event).to be_a(Oblodai::Generated::WEBHOOK_MODELS.fetch(vector["kind"]))
          expect(Oblodai::Webhooks.known_event?(delivery.event)).to be(true)
          suite.fetch("fields").each do |role, field|
            next if field.empty?

            header = names.fetch(role)
            value = delivery.public_send(field)
            want = vector.dig("headers", header)
            expect(value).to eq(value.is_a?(Integer) ? Integer(want) : want), "#{field} ≠ #{header}"
          end
        end
      end
    end
  end

  # forward_compat webhooks: the body parses, keeps its raw type, and is known exactly as said.
  describe "webhook bodies" do
    bodies = Conformance.suite("forward_compat").fetch("webhooks")

    it("has webhook bodies") { expect(bodies).not_to be_empty }

    bodies.each do |body|
      it body["name"] do
        event = Oblodai::Webhooks.parse(JSON.generate(body.fetch("body")))
        type = event.is_a?(Oblodai::Models::Base) ? event.type : event["type"]
        expect(type).to eq(body.dig("expect", "type"))
        expect(Oblodai::Webhooks.known_event?(event)).to be(body.dig("expect", "known"))
      end
    end
  end

  describe "calls" do
    # A value of the answer as the scenario spells it: amounts compare as numbers.
    def plain_equal?(got, want)
      return BigDecimal(want.to_s) == got if got.is_a?(BigDecimal)

      got == want
    end

    # The idempotency key header as the spec names it.
    idempotency_header = Conformance.header_names(Conformance.suite("signing")).fetch("idempotency_key")

    %w[retry money forward_compat].each do |name|
      Conformance.suite(name).fetch("scenarios").each do |scenario|
        it "#{name}/#{scenario["name"]}" do
          script = Conformance::Script.new(scenario.fetch("responses"))
          client = Oblodai::Client.new(public_id: "pk_conformance", secret: "secret-conformance",
                                       base_url: "https://api.test", http: script, env: {})
          delays = []
          allow(client.transport).to receive(:snooze) { |seconds| delays << (seconds * 1000.0) }

          args = scenario.dig("call", "args").to_h { |k, v| [k.to_sym, v] }
          result = nil
          error = nil
          begin
            result = Coverage.call(client, scenario.dig("call", "operation"), **args)
          rescue Oblodai::Error => e
            error = e
          end

          expect_ = scenario.fetch("expect")
          expect(script.requests.size).to eq(expect_.fetch("requests")), script.requests.map(&:url).inspect
          keys = script.requests.map { |r| r.headers.find { |k, _| k.casecmp?(idempotency_header) }&.last }
          case expect_["idempotency_key"]
          when "absent" then expect(keys).to all(be_nil)
          when "present" then expect(keys).to all(be_a(String))
          end
          expect(keys.uniq.size).to eq(1) if expect_["same_idempotency_key"]
          expect(keys.first).not_to be_nil if expect_["same_idempotency_key"]
          expect(delays.map(&:round)).to eq(expect_["delays_ms"]) if expect_.key?("delays_ms")
          (expect_["request_body_field"] || {}).each do |field, want|
            expect(JSON.parse(script.requests.last.body)[field]).to eq(want)
          end
          if expect_.key?("error_code")
            expect(error).to be_a(Oblodai::Error)
            expect(error.code).to eq(expect_["error_code"])
            next
          end
          raise error if error

          (expect_["result_field"] || {}).each do |field, want|
            got = result.public_send(field)
            expect(plain_equal?(got, want)).to be(true), "#{field}: #{got.inspect} != #{want.inspect}"
          end
        end
      end
    end
  end
end
