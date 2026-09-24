# frozen_string_literal: true

require "bigdecimal"
require "json"

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
          else raise "unknown check kind #{check["kind"]}"
          end
        end
      end
    end
  end

  describe "webhooks" do
    suite = Conformance.suite("webhook")
    signing, vectors = Conformance.source(suite)

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
          headers = { "X-Webhook-Timestamp" => ts.to_s, "X-Webhook-Signature" => signature }
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

  describe "calls" do
    # A value of the answer as the scenario spells it: amounts compare as numbers.
    def plain_equal?(got, want)
      return BigDecimal(want.to_s) == got if got.is_a?(BigDecimal)

      got == want
    end

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
          keys = script.requests.map { |r| r.headers["Idempotency-Key"] }
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
