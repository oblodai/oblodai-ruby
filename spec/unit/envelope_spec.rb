# frozen_string_literal: true

# The envelope decoder is the SDK's border with a peer it does not control. Everything here is a
# body that has the documented shape and the wrong contents: the SDK must answer with its own error
# family, never with a Ruby exception from inside a helper, and never let a wrong-typed field steer
# a retry decision.
RSpec.describe Oblodai::Envelope do
  describe "success envelope" do
    it "raises ContractError, not NoMethodError, when a 2xx body has no usable state" do
      [
        '{"result":{}}',                # no state at all
        '{"state":"0","result":{}}',    # state as a string
        '{"state":null,"result":{}}',
        '{"state":0}',                  # state without result
        "{}",
        "[]"
      ].each do |body|
        expect { described_class.decode(200, body) }
          .to raise_error(Oblodai::ContractError) { |e| expect(e.code).to eq("sdk.bad_envelope") }
      end
    end

    it "accepts the documented envelope" do
      decoded = described_class.decode(200, '{"state":0,"result":{"uuid":"u"}}')
      expect(decoded).to be_ok
      expect(decoded.result).to eq("uuid" => "u")
    end

    it "surfaces a 2xx body that is not JSON as a ContractError" do
      expect { described_class.decode(200, "<html>hi</html>") }
        .to raise_error(Oblodai::ContractError, /expected a JSON envelope/)
    end
  end

  describe "error envelope decoded field by field" do
    it "demotes a body whose code is not a usable string, keeping request_id" do
      body = '{"error":{"code":123,"message":"nope","request_id":"rq-9","retryable":true}}'
      error = described_class.decode(500, body).error
      expect(error).to be_synthetic          # no usable envelope: the core may not have answered
      expect(error.code).to eq("internal")
      expect(error.request_id).to eq("rq-9")
      expect(error).to be_retryable          # from the status alone, not from the body's flag
    end

    it "ignores a non-boolean retryable and falls back to the status" do
      %w[yes 1 null].each do |value|
        error = described_class.decode(400,
                                       %({"error":{"code":"payment.bad_amount","retryable":#{value.inspect}}})).error
        expect(error).not_to be_retryable
      end
      error = described_class.decode(503, '{"error":{"code":"db.down","retryable":"yes"}}').error
      expect(error).to be_retryable # 503 is retryable on its own
      expect(error).not_to be_synthetic
    end

    it "falls back to HTTP <status> when the message is not a string" do
      error = described_class.decode(400, '{"error":{"code":"payment.bad_amount","message":{"a":1}}}').error
      expect(error.message).to eq("HTTP 400 (payment.bad_amount)")
      expect(error.field).to be_nil
    end

    it "drops a non-string field and request_id instead of carrying them" do
      error = described_class.decode(400, '{"error":{"code":"x.y","field":7,"request_id":[1]}}').error
      expect(error.field).to be_nil
      expect(error.request_id).to be_nil
    end
  end

  describe "retry_after" do
    def retry_after_of(value)
      described_class.decode(429, %({"error":{"code":"request.rate_limited","retry_after":#{value}}})).error.retry_after
    end

    it "accepts integers, floats and numeric strings" do
      expect(retry_after_of("12")).to eq(12)
      expect(retry_after_of("1.5")).to eq(2) # rounded up: never wait less than told
      expect(retry_after_of('"30"')).to eq(30)
    end

    it "clamps out-of-range and refuses non-numbers" do
      expect(retry_after_of("-5")).to eq(0)
      expect(retry_after_of("999999999")).to eq(Oblodai::MAX_RETRY_AFTER_SECONDS)
      expect(retry_after_of("9" * 400)).to eq(Oblodai::MAX_RETRY_AFTER_SECONDS)
      expect(retry_after_of("true")).to be_nil
      expect(retry_after_of('"soon"')).to be_nil
      expect(retry_after_of("null")).to be_nil
      expect(retry_after_of('{"a":1}')).to be_nil
    end

    it "parses the Retry-After header as delta-seconds or an HTTP-date, always clamped" do
      now = Time.now
      expect(described_class.parse_retry_after("7", now)).to eq(7)
      expect(described_class.parse_retry_after("  ", now)).to be_nil
      expect(described_class.parse_retry_after("later", now)).to be_nil
      expect(described_class.parse_retry_after((now - 600).httpdate, now)).to eq(0)
      expect(described_class.parse_retry_after("Fri, 31 Dec 9999 23:59:59 GMT", now))
        .to eq(Oblodai::MAX_RETRY_AFTER_SECONDS)
      expect(described_class.parse_retry_after("9" * 30, now)).to eq(Oblodai::MAX_RETRY_AFTER_SECONDS)
    end

    it "waits at most the policy cap even when the peer asks for a day" do
      policy = Oblodai::RetryPolicy.new
      error = described_class.decode(429, '{"error":{"code":"request.rate_limited","retry_after":86400}}').error
      expect(error.retry_after).to eq(86_400) # reported verbatim (clamped to the plausibility bound)
      expect(policy.delay_ms(error, attempt: 0)).to eq(30_000) # but slept for at most max_retry_after_ms
    end
  end

  describe "redirects and bodies without an envelope" do
    it "reports a 3xx as a configuration error, never as a hop to follow" do
      error = described_class.decode(302, "", location: "https://elsewhere.example/v1").error
      expect(error).to be_synthetic
      expect(error.message).to include("unexpected redirect", "elsewhere.example")
    end

    it "keeps the evidence of a proxy answer" do
      error = described_class.decode(502, "<html>bad gateway</html>", retry_after: "1").error
      expect(error).to be_synthetic
      expect(error).to be_retryable
      expect(error.retry_after).to eq(1)
      expect(error.message).to include("without an Oblodai error envelope")
    end
  end
end
