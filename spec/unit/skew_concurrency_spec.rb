# frozen_string_literal: true

# One client is shared by every thread of a web process, and so is its learned clock offset. These
# are the cases where two calls correcting the same clock used to take each other's correction away.
# A gateway whose clock is an hour ahead: it refuses anything signed outside ±300 s and says so,
# with its own time in `Date`. Thread-safe, unlike the scripted fake.
class SkewedGateway
  SKEW = 3600

  attr_reader :calls, :rejected

  # `hold` makes the first `hold` requests wait for one another, so every thread has signed with
  # the stale offset before any of them can correct the shared clock — the race the old code lost.
  def initialize(hold: 0)
    @lock = Mutex.new
    @gate = ConditionVariable.new
    @hold = hold
    @arrived = 0
    @calls = 0
    @rejected = 0
  end

  def call(request, timeout:) # rubocop:disable Lint/UnusedMethodArgument
    await_siblings
    signed = request.headers[SIGNING::HEADER_TIMESTAMP].to_i
    server_now = Time.now.to_i + SKEW
    @lock.synchronize { @calls += 1 }
    if (server_now - signed).abs > Oblodai::Signing::SKEW_SECONDS
      @lock.synchronize { @rejected += 1 }
      return answer(401, { "error" => { "code" => "merchant.bad_signature", "message" => "skew",
                                        "retryable" => false } },
                    "date" => Time.at(server_now).httpdate)
    end

    answer(200, { "state" => 0, "result" => { "balance" => { "merchant" => [] } } })
  end

  private

  def await_siblings
    @lock.synchronize do
      next if @arrived >= @hold

      @arrived += 1
      @gate.broadcast if @arrived >= @hold
      @gate.wait(@lock, 5) while @arrived < @hold
    end
  end

  def answer(status, body, extra = {})
    Oblodai::HTTP::Response.new(status: status, body: JSON.generate(body),
                                headers: { "content-type" => "application/json" }.merge(extra))
  end
end

RSpec.describe "clock skew under concurrency" do
  it "lets every concurrent call through after a single correction" do
    gateway = SkewedGateway.new(hold: 10)
    client = client_with(gateway, retry_policy: { max_retries: 0 })

    results = 10.times.map { Thread.new { client.account.get_balance } }.map(&:value)

    expect(results.size).to eq(10)
    expect(results).to all(be_a(Oblodai::Models::BalanceResult))
    # All ten signed with the stale offset and were rejected together; each then re-signs its own
    # request, rather than concluding "a sibling already fixed the clock" and failing hard.
    expect(gateway.rejected).to eq(10)
    expect(gateway.calls).to eq(20)
    expect(client.transport.instance_variable_get(:@clock).offset)
      .to be_within(5).of(SkewedGateway::SKEW)
  end

  it "reverts its own correction only while nobody else has moved the clock" do
    clock = Oblodai::Clock.new
    clock.correct(120)
    # A sibling call corrected the clock in between: this call's revert must not undo it.
    expect(clock.revert_if_unchanged(60, 0)).to be(false)
    expect(clock.offset).to eq(120)
    # Its own correction, untouched: reverted.
    expect(clock.revert_if_unchanged(120, 0)).to be(true)
    expect(clock.offset).to eq(0)
  end

  it "gives up the correction when the re-signed attempt is rejected too" do
    bad_date = { "date" => Time.at(Time.now.to_i + 4000).httpdate }
    http = FakeHTTP.new([
                          FakeHTTP.api_error(401, { "code" => "merchant.bad_signature", "retryable" => false },
                                             bad_date),
                          FakeHTTP.api_error(401, { "code" => "merchant.bad_signature", "retryable" => false },
                                             bad_date)
                        ])
    client = client_with(http, retry_policy: { max_retries: 0 })
    expect { client.account.get_balance }.to raise_error(Oblodai::AuthenticationError)
    expect(http.calls.size).to eq(2) # one re-sign, no more
    expect(client.transport.instance_variable_get(:@clock).offset).to eq(0)
  end

  it "does not deadlock or tear the offset when threads read it while it moves" do
    clock = Oblodai::Clock.new
    readers = 4.times.map { Thread.new { 500.times.map { clock.offset } } }
    writer = Thread.new { 500.times { |i| clock.correct(i.even? ? 0 : 3600) } }
    seen = readers.flat_map(&:value)
    writer.join
    expect(seen.uniq.sort).to eq([0, 3600]).or eq([0]).or eq([3600])
  end
end
