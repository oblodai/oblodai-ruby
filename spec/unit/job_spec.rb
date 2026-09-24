# frozen_string_literal: true

# Spec §3 item 8: batches and document jobs return a waiter.
RSpec.describe Oblodai::Job do
  def job_client(http)
    client_with(http)
  end

  it "wraps a batch create and polls getBatchInfo until the status is terminal" do
    http = FakeHTTP.new([
                          FakeHTTP.ok_for("createPayoutBatch", "batch_id" => "b-1"),
                          FakeHTTP.ok_for("getBatchInfo", "batch_id" => "b-1", "status" => "processing"),
                          FakeHTTP.ok_for("getBatchInfo", "batch_id" => "b-1", "status" => "completed")
                        ])
    job = job_client(http).batches.create_payout(payouts: [{ "amount" => "1", "currency" => "USDT" }])
    expect(job).to be_a(described_class)
    expect(job.id).to eq("b-1")
    expect(job.result).to be_a(Oblodai::Models::BatchSubmitResponse)
    allow(job).to receive(:pause)
    info = job.wait(timeout: 5, interval: 0.01)
    expect(info).to be_a(Oblodai::Models::BatchInfoResponse)
    expect(info.status).to eq("completed")
    expect(http.calls.map(&:path)).to eq(%w[/v1/payout/batch /v1/batch/info /v1/batch/info])
    expect(http.calls[1].json).to eq("batch_id" => "b-1")
    expect(http.calls[1].headers).not_to have_key("idempotency-key")
    expect(job).to have_received(:pause).once
  end

  it "gives up after the timeout" do
    http = FakeHTTP.new([FakeHTTP.ok_for("createPaymentBatch", "batch_id" => "b-2")] +
                        ([FakeHTTP.ok_for("getBatchInfo", "status" => "processing")] * 50))
    job = job_client(http).batches.create_payment(payments: [])
    expect { job.wait(timeout: 0.05, interval: 0.01) }
      .to raise_error(Oblodai::TransportError) { |e| expect(e.code).to eq("transport.deadline") }
  end

  it "downloads a finished document job" do
    http = FakeHTTP.new([
                          FakeHTTP.ok_for("createDocumentJob", "job_id" => "j-1"),
                          FakeHTTP.ok_for("getDocumentJob", "job_id" => "j-1", "status" => "done"),
                          { status: 200, body: "a,b\n", headers: { "content-type" => "text/csv" } }
                        ])
    job = job_client(http).documents.create_job(kind: "ledger")
    expect(job.wait.status).to eq("done")
    file = job.download
    expect(file.bytes).to eq("a,b\n")
    expect(http.calls[2].url).to eq("https://api.test/v1/documents/jobs/file?job_id=j-1")
  end

  it "refuses to download from a job that makes no file" do
    http = FakeHTTP.new([FakeHTTP.ok_for("createRefundBatch", "batch_id" => "b")])
    job = job_client(http).batches.create_refund(refunds: [])
    expect { job.download }.to raise_error(ArgumentError, /no file/)
  end

  it "is an error when the create answer carries no id" do
    http = FakeHTTP.new([FakeHTTP.ok_for("createPayoutBatch", "batch_id" => "")])
    expect { job_client(http).batches.create_payout(payouts: []) }.to raise_error(Oblodai::ContractError)
  end

  it "lists every long-running operation with a poll the contract has" do
    Oblodai::LRO::CREATES.each do |create, poll|
      expect(Oblodai::Generated::ROUTES).to have_key(create)
      expect(Oblodai::Generated::ROUTES).to have_key(poll)
      model = Oblodai::LRO::POLLS.fetch(poll).model
      expect(Oblodai::Models.const_defined?(model)).to be(true), model
    end
  end
end
