# frozen_string_literal: true

require_relative "oblodai/version"
require_relative "oblodai/errors"
require_relative "oblodai/config"
require_relative "oblodai/client"
require_relative "oblodai/webhooks"
require_relative "oblodai/helpers/money"
require_relative "oblodai/helpers/status"

# Official Ruby client for the Oblodai crypto payment gateway.
#
#     client = Oblodai::Client.new(public_id: ENV["OBLODAI_PUBLIC_ID"], secret: ENV["OBLODAI_SECRET"])
#     invoice = client.payments.create(amount: "25", currency: "USDT", network: "tron",
#                                      order_id: "order-1001")
#     puts invoice.url
#
# - Methods are `client.<resource>.<method>`, generated from the gateway's OpenAPI contract
#   (`Oblodai::Generated::ROUTES` lists every operation by its `operationId`).
# - Request fields are keyword arguments; amounts are `BigDecimal` or decimal strings, never Float.
# - Responses are frozen models (`Oblodai::Models::*`) with `BigDecimal` amounts.
# - Every failure is an {Oblodai::Error}: `e.message` is `[code] text (request_id=…)`.
# - Lists are lazy {Oblodai::Page}s: `each` walks every item, `each_page` every page.
# - Batches and document jobs return an {Oblodai::Job}: `job.wait`.
# - Webhook verification lives in {Oblodai::Webhooks} and needs no client.
module Oblodai
end
