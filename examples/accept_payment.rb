#!/usr/bin/env ruby
# frozen_string_literal: true

# Accept a payment: create an invoice, show the payer where to send the funds, then follow it.
# Run against the sandbox first:
#
#   OBLODAI_PUBLIC_ID=test_… OBLODAI_SECRET=… ruby -Ilib examples/accept_payment.rb

require "oblodai"

client = Oblodai::Client.new # credentials from OBLODAI_PUBLIC_ID / OBLODAI_SECRET

# Deliveries are signed with the endpoint's secret, so an invoice can only carry a `url_callback`
# once an endpoint exists. Register it once (at deploy time, not per invoice) and store the secret.
endpoint = client.webhooks.register(url: "https://shop.example/oblodai/webhook")
puts "webhook endpoint #{endpoint.endpoint_id}; store the secret if this is the first registration"

invoice = client.payments.create(
  amount: "25",           # a decimal String or a BigDecimal — never a Float
  currency: "USDT",       # price currency: a fiat (USD, EUR, …) or a coin
  network: "tron",        # omit to let the payer pick the network on the pay page
  order_id: "order-#{Time.now.to_i}",
  url_callback: "https://shop.example/oblodai/webhook",
  payer_email: "buyer@example.com"
)

puts "invoice #{invoice.uuid} (#{invoice.status})"
puts "pay page: #{invoice.url}"
puts "address:  #{invoice.address} — #{invoice.payer_amount} #{invoice.payer_currency}"
puts "expires:  #{invoice.expired_at}"

# Prefer webhooks for state changes; this is the fallback poll.
current = client.payments.get_info(order_id: invoice.order_id)
paid = Oblodai::Status.payment_paid?(current.status)
puts "status now: #{current.status} (paid: #{paid}, final: #{current.is_final})"
puts "paid #{current.amount_paid}, still due #{current.amount_remaining}"

# An underpayment waits for a decision: keep it, or send it back.
if Oblodai::Status.payment_underpaid?(current.status)
  resolution = client.payments.resolve(uuid: current.uuid, action: "accept")
  puts "resolved: #{resolution.inspect}"
end

# The last 10 invoices, newest first. `each` would walk every page.
client.payments.list_history(limit: 10).first_page.each do |payment|
  puts "#{payment.created_at}  #{payment.order_id.to_s.ljust(24)} " \
       "#{payment.amount.to_s("F")} #{payment.currency}  #{payment.status}"
end
