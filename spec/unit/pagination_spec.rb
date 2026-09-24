# frozen_string_literal: true

RSpec.describe Oblodai::Page do
  def payment(uuid)
    Samples.body("PaymentView", "uuid" => uuid, "status" => "paid", "amount" => "25")
  end

  it "first_page gives one page; each walks every item lazily" do
    http = FakeHTTP.new([
                          FakeHTTP.page([payment("1"), payment("2")], 0, 5, 2),
                          FakeHTTP.page([payment("3"), payment("4")], 2, 5, 2),
                          FakeHTTP.page([payment("5")], 4, 5, 2)
                        ])
    page = client_with(http).payments.list_history(limit: 2)

    first = page.first_page
    expect(first.items.map(&:uuid)).to eq(%w[1 2])
    expect(first).to have_pages
    expect(first.total).to eq(5)
    expect(page.paginate["total"]).to eq(5)
    expect(http.calls.size).to eq(1)

    expect(page.map(&:uuid)).to eq(%w[1 2 3 4 5]) # reuses the first page it already fetched
    expect(http.calls.size).to eq(3)
    expect(http.calls[1].json).to eq("limit" => 2, "offset" => 2)
  end

  it "each_page walks the pages themselves, one request each" do
    http = FakeHTTP.new([
                          FakeHTTP.page([payment("1"), payment("2")], 0, 3, 2),
                          FakeHTTP.page([payment("3")], 2, 3, 2)
                        ])
    page = client_with(http).payments.list_history(limit: 2)
    sizes = page.each_page.map(&:size)
    expect(sizes).to eq([2, 1])
    expect(page.by_page.first.items.map(&:uuid)).to eq(%w[1 2]) # the first page is not re-fetched
    expect(http.calls.size).to eq(2)
  end

  it "stops on a short page even when the core keeps saying has_pages" do
    http = FakeHTTP.new([{ status: 200,
                           body: { "state" => 0,
                                   "result" => { "items" => [],
                                                 "paginate" => { "total" => 99, "per_page" => 2,
                                                                 "offset" => 0, "has_pages" => true } } } }])
    expect(client_with(http).payouts.list_history(limit: 2).to_a).to eq([])
    expect(http.calls.size).to eq(1)
  end

  it "all(max) collects with a cap and Enumerable#first stops early" do
    http = FakeHTTP.new([
                          FakeHTTP.page([payment("1"), payment("2")], 0, 3, 2),
                          FakeHTTP.page([payment("3")], 2, 3, 2)
                        ])
    expect(client_with(http).payments.list_history(limit: 2).all.map(&:uuid)).to eq(%w[1 2 3])

    http2 = FakeHTTP.new([FakeHTTP.page([payment("1"), payment("2")], 0, 9, 2)])
    expect(client_with(http2).payments.list_history(limit: 2).first(2).map(&:uuid)).to eq(%w[1 2])
    expect(client_with(http2).payments.list_history(limit: 2).all(0)).to eq([])
    expect(http2.calls.size).to eq(1)
  end

  it "sends list parameters in the body on POST lists and in the query on GET lists" do
    http = FakeHTTP.new([FakeHTTP.page([], 0, 0, 5), FakeHTTP.page([], 0, 0, 5)])
    client = client_with(http)
    client.payments.list_history(limit: 5, status: "paid").first_page
    client.sandbox.list_webhooks(limit: 5).first_page
    expect(http.calls[0].json).to eq("status" => "paid", "limit" => 5, "offset" => 0)
    expect(http.calls[1].query).to eq("limit" => "5", "offset" => "0")
  end

  it "applies the default page size when the caller gives none" do
    http = FakeHTTP.new([FakeHTTP.page([], 0, 0, 50)])
    client_with(http).payments.list_history.first_page
    expect(http.calls[0].json).to eq("limit" => Oblodai::Page::DEFAULT_LIMIT, "offset" => 0)
  end

  it "decodes items into models" do
    http = FakeHTTP.new([FakeHTTP.page([payment("u")], 0, 1, 5)])
    item = client_with(http).payments.list_history(limit: 5).first_page.items.first
    expect(item).to be_a(Oblodai::Models::PaymentView)
    expect(Oblodai::Status.payment_paid?(item.status)).to be(true)
    expect(item.amount).to eq(BigDecimal("25"))
  end
end
