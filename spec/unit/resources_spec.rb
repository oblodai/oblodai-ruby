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

  describe "lookups by uuid or order_id" do
    it "accepts the documented keyword form, the positional form and the model" do
      %i[info cancel qr resend].each do |method|
        http = FakeHTTP.new([FakeHTTP.ok("uuid" => "u1"), FakeHTTP.ok("uuid" => "u1"),
                             FakeHTTP.ok("uuid" => "u1"), FakeHTTP.ok("uuid" => "u1")])
        client = client_with(http)
        client.payments.public_send(method, "u1")
        client.payments.public_send(method, uuid: "u1")
        client.payments.public_send(method, order_id: "o-1")
        client.payments.public_send(method, Oblodai::Models::Payment.from("uuid" => "u1"))
        expect(http.calls.map(&:json)).to eq([{ "uuid" => "u1" }, { "uuid" => "u1" },
                                              { "order_id" => "o-1" }, { "uuid" => "u1" }])
      end
    end

    it "does the same for payouts" do
      http = FakeHTTP.new([FakeHTTP.ok("uuid" => "p1")] * 3)
      client = client_with(http)
      client.payouts.info("p1")
      client.payouts.info(uuid: "p1")
      client.payouts.get(order_id: "po-1")
      expect(http.calls.map(&:json)).to eq([{ "uuid" => "p1" }, { "uuid" => "p1" },
                                            { "order_id" => "po-1" }])
    end

    it "says so when neither is supplied, instead of paying a round trip to learn it" do
      http = FakeHTTP.new([])
      expect { client_with(http).payments.info }
        .to raise_error(Oblodai::ConfigError, /uuid: or order_id:/)
      expect { client_with(http).payouts.info }
        .to raise_error(Oblodai::ConfigError, /uuid: or order_id:/)
      expect(http.calls).to be_empty
    end
  end

  describe "ids may be the model the SDK returned" do
    it "reads the id out of it" do
      http = FakeHTTP.new([FakeHTTP.ok({})] * 5)
      client = client_with(http, payout_public_id: "wk", payout_secret: "s2")
      client.payout_links.info(Oblodai::Models::PayoutLink.from("link_id" => "pl-1"))
      client.payment_links.info(Oblodai::Models::PaymentLink.from("link_id" => "pml-1"))
      client.batches.info(Oblodai::Models::BatchSubmitted.from("batch_id" => "b-1"))
      client.splits.delete_rule(Oblodai::Models::SplitRule.from("rule_id" => "r-1"))
      client.wallets.qr(Oblodai::Models::Wallet.from("address" => "T-addr"))
      expect(http.calls.map(&:json)).to eq([{ "link_id" => "pl-1" }, { "link_id" => "pml-1" },
                                            { "batch_id" => "b-1" }, { "rule_id" => "r-1" },
                                            { "address" => "T-addr" }])
    end
  end

  describe "batches.info paging" do
    it "passes limit and offset so a batch bigger than one page can be walked" do
      http = FakeHTTP.new([FakeHTTP.ok("batch_id" => "b1", "kind" => "payout", "status" => "done")])
      client_with(http).batches.info("b1", limit: 100, offset: 200)
      expect(http.calls.first.json).to eq("batch_id" => "b1", "limit" => 100, "offset" => 200)
    end

    it "keeps them on the payout-key retry" do
      http = FakeHTTP.new([
                            FakeHTTP.api_error(403, { "code" => "merchant.wrong_key_kind",
                                                      "retryable" => false }),
                            FakeHTTP.ok("batch_id" => "b1")
                          ])
      client = client_with(http, payout_public_id: "wk", payout_secret: "s2")
      client.batches.info("b1", limit: 10)
      expect(http.calls.map(&:json)).to eq([{ "batch_id" => "b1", "limit" => 10 },
                                            { "batch_id" => "b1", "limit" => 10 }])
    end
  end

  describe "webhooks.test" do
    it "refuses a kind the gateway does not have a route for" do
      http = FakeHTTP.new([])
      ["invoice", "", "payment/../x", :unknown, nil].each do |kind|
        expect { client_with(http).webhooks.test(kind, url_callback: "https://x") }
          .to raise_error(Oblodai::ConfigError) { |e|
                expect(e.code).to eq("sdk.bad_config")
                expect(e.field).to eq("kind")
              }
      end
      expect(http.calls).to be_empty
    end

    it "accepts every kind the contract declares, as a string or a symbol" do
      Oblodai::Enums::WEBHOOK_KINDS.each do |kind|
        http = FakeHTTP.new([FakeHTTP.ok("ok" => true), FakeHTTP.ok("ok" => true)])
        client = client_with(http, payout_public_id: "wk", payout_secret: "s2")
        client.webhooks.test(kind, url_callback: "https://x")
        client.webhooks.test(kind.to_sym, url_callback: "https://x")
        expect(http.calls.map(&:path)).to eq(["/v1/test-webhook/#{kind}"] * 2)
      end
    end
  end

  describe "the generated route registry" do
    it "is frozen down to each route, so no caller can flip another's retry safety" do
      route = Oblodai::Contract::ROUTES.fetch("POST /v1/payout")
      expect(Oblodai::Contract::ROUTES).to be_frozen
      expect(route).to be_frozen
      expect { route.safe = true }.to raise_error(FrozenError)
      expect { route[:auth] = :public }.to raise_error(FrozenError)
    end
  end

  describe "models are value objects all the way down" do
    it "freezes the lists and hashes it decoded" do
      payment = Oblodai::Models::Payment.from(
        "uuid" => "u", "tx_list" => [{ "txid" => "t" }], "extra_thing" => { "a" => [1] }
      )
      expect(payment).to be_frozen
      expect(payment.tx_list).to be_frozen
      expect(payment.tx_list.first).to be_frozen
      expect(payment[:extra_thing]).to be_frozen
      expect { payment.tx_list << 1 }.to raise_error(FrozenError)
      expect { payment[:extra_thing]["b"] = 2 }.to raise_error(FrozenError)
    end
  end
end
