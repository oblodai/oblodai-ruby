#!/usr/bin/env ruby
# frozen_string_literal: true

# The sandbox: fake money from a faucet, a simulated deposit, the webhook it produced.
#
#   OBLODAI_PUBLIC_ID=test_oblodai_… OBLODAI_SECRET=oblodai_test_… ruby -Ilib examples/sandbox.rb

require "oblodai"

client = Oblodai::Client.new

topped = client.sandbox.faucet(asset: "USDT", amount: "1000", idempotency_key: "faucet-#{Time.now.to_i}")
puts "faucet: +#{topped.amount} #{topped.asset}"

invoice = client.payments.create(amount: "25", currency: "USDT", network: "tron",
                                 order_id: "sandbox-#{Time.now.to_i}")
# No amount pays exactly what is due; repeating a txid adds confirmations instead of paying twice.
deposit = client.sandbox.simulate_deposit(invoice_id: invoice.uuid)
puts "deposit #{deposit.txid}: #{deposit.amount}, #{deposit.confirmations} confirmations"

client.sandbox.list_webhooks(limit: 5).each do |delivery|
  puts "delivery #{delivery.id}: #{delivery.event_type} → #{delivery.status}"
end
