# frozen_string_literal: true

# Spec §3 item 6: an error reads well in a log line — `[code] text (request_id=…)`.
RSpec.describe "error messages" do
  it "renders the code, the text and the request id" do
    error = Oblodai::ValidationError.new(code: "payment.bad_amount", message: "bad amount", request_id: "rq-7")
    expect(error.message).to eq("[payment.bad_amount] bad amount (request_id=rq-7)")
    expect(error.to_s).to eq(error.message)
    expect(error.text).to eq("bad amount")
  end

  it "leaves the suffix out when there is no request id" do
    error = Oblodai::ConfigError.new("sdk.bad_config", "nope")
    expect(error.message).to eq("[sdk.bad_config] nope")
  end

  it "carries the request id of an API answer" do
    http = FakeHTTP.new([FakeHTTP.api_error(404, { "code" => "payment.not_found", "message" => "no such payment",
                                                   "retryable" => false, "request_id" => "rq-1" })])
    expect { client_with(http).payments.get_info(uuid: "u") }
      .to raise_error(Oblodai::NotFoundError, "[payment.not_found] no such payment (request_id=rq-1)")
  end

  it "keeps the bare text in to_h and inspect" do
    error = Oblodai::ApiError.new(code: "x.y", message: "text", request_id: "r")
    expect(error.to_h[:message]).to eq("text")
    expect(error.inspect).to include('message="text"')
  end
end
