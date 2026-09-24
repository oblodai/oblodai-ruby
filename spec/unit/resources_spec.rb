# frozen_string_literal: true

require "tmpdir"

# The resource layer: what a caller is allowed to pass, what reaches the wire, and what the SDK
# refuses before it gets there.
RSpec.describe "resource surface" do
  describe Oblodai::FileResult do
    it "writes the server-suggested name as a bare basename, never as a path" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          [
            ["../../../tmp/escaped.pdf", "escaped.pdf"],
            ["/etc/cron.d/payload", "payload"],
            ['..\\..\\windows.pdf', "windows.pdf"],
            ["statement.pdf", "statement.pdf"]
          ].each do |suggested, expected|
            file = described_class.new(bytes: "%PDF", content_type: "application/pdf",
                                       filename: suggested)
            expect(file.safe_filename).to eq(expected)
            expect(file.save).to eq(expected)
            expect(File.exist?(File.join(dir, expected))).to be(true)
          end
          expect(Dir.children(dir).sort).to eq(%w[escaped.pdf payload statement.pdf windows.pdf])
        end
      end
    end

    it "refuses to guess when nothing usable is left of the name" do
      ["..", ".", "/", "", "../..", nil].each do |suggested|
        file = described_class.new(bytes: "%PDF", content_type: "application/pdf", filename: suggested)
        expect(file.safe_filename).to be_nil
        expect { file.save }.to raise_error(ArgumentError, /pass one to #save/)
      end
    end

    it "writes wherever the caller says" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "sub.pdf")
        file = described_class.new(bytes: "%PDF", content_type: "application/pdf", filename: "../x")
        expect(file.save(target)).to eq(target)
        expect(File.binread(target)).to eq("%PDF")
      end
    end
  end

  describe "request parameters (spec §3 item 1)" do
    it "takes keywords, a Hash with wire names, or a request model" do
      http = FakeHTTP.new([FakeHTTP.ok_for("getPaymentInfo")] * 4)
      client = client_with(http)
      client.payments.get_info(uuid: "u1")
      client.payments.get_info({ "order_id" => "o-1" })
      client.payments.get_info({ uuid: "u2" })
      client.payments.get_info(Oblodai::Models::LookupRequest.new(uuid: "u3"))
      expect(http.calls.map(&:json)).to eq([{ "uuid" => "u1" }, { "order_id" => "o-1" }, { "uuid" => "u2" },
                                            { "uuid" => "u3" }])
    end

    it "adds keywords to a Hash, and refuses a field given both ways" do
      http = FakeHTTP.new([FakeHTTP.ok_for("createPayment")])
      client = client_with(http)
      client.payments.create({ "amount" => "1" }, currency: "USDT")
      expect(http.calls[0].json).to eq("amount" => "1", "currency" => "USDT")
      expect { client.payments.create({ "amount" => "1" }, amount: "2") }
        .to raise_error(ArgumentError, /amount given twice/)
    end

    it "refuses a misspelled keyword before anything is sent" do
      http = FakeHTTP.new([])
      expect { client_with(http).payments.create(amout: "1") }.to raise_error(ArgumentError, /amout/)
      expect(http.calls).to be_empty
    end

    it "fills path parameters positionally and query parameters by keyword" do
      http = FakeHTTP.new([FakeHTTP.ok_for("getCheckout"),
                           { status: 200, body: "%PDF", headers: { "content-type" => "application/pdf" } }])
      client = client_with(http)
      client.checkout.get("inv-1")
      client.documents.get_signed("statement", "d-1", exp: "123", sig: "abc")
      expect(http.calls[0].path).to eq("/v1/pay/inv-1")
      expect(http.calls[1].path).to eq("/v1/documents/statement/d-1")
      expect(http.calls[1].query).to eq("exp" => "123", "sig" => "abc")
    end
  end

  describe "the client" do
    it "has one namespace per resource of the contract" do
      client = client_with(FakeHTTP.new([]))
      names = Oblodai::Client::RESOURCES.keys
      expect(names.size).to eq(16)
      names.each { |name| expect(client.public_send(name)).to be_a(Oblodai::Resources::Base) }
      locked = File.readlines(File.expand_path("../../names.lock", __dir__), chomp: true).map { |l| l.split(".").first }
      expect(locked.uniq.sort).to eq(names.map(&:to_s).sort)
    end

    it "serves every locked name" do
      client = client_with(FakeHTTP.new([]))
      File.readlines(File.expand_path("../../names.lock", __dir__), chomp: true).each do |line|
        resource, method = line.split(".")
        expect(client.public_send(resource)).to respond_to(method), line
      end
    end
  end

  describe "the generated route registry" do
    it "is frozen down to each route, so no caller can flip another's retry safety" do
      route = Oblodai::Generated::ROUTES.fetch("createPayout")
      expect(Oblodai::Generated::ROUTES).to be_frozen
      expect(route).to be_frozen
      expect { route.safe = true }.to raise_error(FrozenError)
      expect { route[:auth] = :public }.to raise_error(FrozenError)
    end
  end
end
