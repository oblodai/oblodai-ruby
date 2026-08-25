# frozen_string_literal: true

require_relative "oblodai/version"
require_relative "oblodai/errors"
require_relative "oblodai/config"
require_relative "oblodai/client"
require_relative "oblodai/webhooks"
require_relative "oblodai/contract/routes"
require_relative "oblodai/contract/enums"
require_relative "oblodai/contract/requests"
require_relative "oblodai/helpers/money"
require_relative "oblodai/helpers/status"
require_relative "oblodai/models/account"
require_relative "oblodai/models/catalog"
require_relative "oblodai/models/links"
require_relative "oblodai/models/merchants"
require_relative "oblodai/models/payments"
require_relative "oblodai/models/payouts"
require_relative "oblodai/models/sandbox"
require_relative "oblodai/models/webhooks"

# Official Ruby client for the Oblodai crypto payment gateway.
#
#     client = Oblodai::Client.new(public_id: ENV["OBLODAI_PUBLIC_ID"], secret: ENV["OBLODAI_SECRET"])
#     invoice = client.payments.create(amount: "25", currency: "USDT", network: "tron",
#                                      order_id: "order-1001",
#                                      url_callback: "https://shop.example/oblodai/webhook")
#     puts invoice.url
#
# - Amounts are decimal STRINGS ({Oblodai::Money} adds and compares them exactly).
# - Every failure is an {Oblodai::Error} carrying the API's own `code` and `retryable` flag.
# - Lists are lazy {Oblodai::Page}s: `each` walks every page, `first_page` fetches one.
# - Webhook verification lives in {Oblodai::Webhooks} and needs no client.
module Oblodai
  # Path of the contract snapshot shipped with the gem (routes, schemas, golden bodies, vectors).
  # @return [String]
  def self.contract_path
    File.expand_path("../contract", __dir__)
  end
end
