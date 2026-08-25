#!/usr/bin/env ruby
# frozen_string_literal: true

# Send money out: price it, dry-run it, then create it — with an idempotency key you control, so a
# lost response can never turn into a second payout.
#
#   OBLODAI_PAYOUT_PUBLIC_ID=… OBLODAI_PAYOUT_SECRET=… ruby examples/payout.rb

require "oblodai"

client = Oblodai::Client.new
address = "TQrY8bkbpXKPt2LZbU8jqfnpFbUSF15sbx"

balance = client.account.balance
puts "USDT available: #{balance.available("USDT") || "0"}"

quote = client.payouts.calculate(amount: "10", currency: "USDT", network: "tron")
puts "fee #{quote.commission} (#{quote.fee_bearer} pays), debited #{quote.payer_amount}"

order_id = "payout-#{Time.now.to_i}"

payout =
  begin
    # The dry run runs every check `create` runs, and reserves nothing.
    check = client.payouts.validate(amount: "10", currency: "USDT", network: "tron", address: address)
    abort "the gateway would refuse this payout" unless check.valid
    puts "maturity note: #{check.maturity_note}" unless check.maturity_note.to_s.empty?

    client.payouts.create(
      amount: "10", currency: "USDT", network: "tron", address: address, order_id: order_id,
      # Your own key makes the retry safe across a process restart, not just inside one call.
      idempotency_key: "payout-#{order_id}"
    )
  rescue Oblodai::Error => e
    case e.code
    when "payout.insufficient_funds", "payout.funds_maturing"
      # Retryable: the SDK already retried inside the call; wait longer and try again later.
      # In the sandbox, top the balance up first: client.sandbox.faucet(asset: "USDT", amount: "100")
      abort "not enough funds yet (retry after #{e.retry_after || 60}s, request #{e.request_id})"
    else
      raise
    end
  end

puts "payout #{payout.uuid}: #{payout.status}, txid #{payout.txid.empty? ? "(not broadcast yet)" : payout.txid}"
puts "final: #{payout.final?}, confirmed: #{payout.succeeded?}"

# Many at once: up to 100 synchronously (mass), up to 5000 asynchronously (batch).
elements = client.payouts.mass(payouts: [
                                 { amount: "1", currency: "USDT", network: "tron", address: address,
                                   order_id: "#{order_id}-a" }
                               ])
elements.each { |element| puts "##{element.idx} ok=#{element.ok} #{element.message}" }
