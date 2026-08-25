#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates lib/oblodai/contract/{routes,enums,requests}.rb from contract/contract.json (exported by
# the core's TestSDKContract_Export) and contract/descriptions.en.json (English field docs).
# Nothing in the generated files is edited by hand. Run: rake codegen. CI gate: rake drift.

require "digest"
require "json"
require "pathname"

ROOT = Pathname.new(__dir__).parent
OUT_DIR = ROOT.join("lib", "oblodai", "contract")

raw = ROOT.join("contract", "contract.json").binread
contract = JSON.parse(raw)
descriptions = JSON.parse(ROOT.join("contract", "descriptions.en.json").read)
CONTRACT_HASH = Digest::SHA256.hexdigest(raw)

HEADER = <<~RUBY.freeze
  # frozen_string_literal: true

  # GENERATED FILE — do not edit. Source: contract/contract.json (core #{contract["core_commit"][0, 12]}).
  # Regenerate with: rake codegen
RUBY

# Routes the SDK never calls: they are not part of the merchant surface.
INTERNAL = %r{^/(healthz|readyz|docs|openapi\.json|internal)}
# Read-only routes: a transport failure may be retried without risking a duplicate side effect.
SAFE_SUFFIX = %r{/(info|history|list|calculate|validate|services|get|balance|qr|deliveries)$}
# Paths that look read-only but whose body can mutate state.
NOT_SAFE = ["POST /v1/vrcs"].freeze

def safe?(route)
  return false if NOT_SAFE.include?("#{route["method"]} #{route["path"]}")

  route["method"] == "GET" || SAFE_SUFFIX.match?(route["path"])
end

routes = contract["routes"]
         .reject { |r| INTERNAL.match?(r["path"]) }
         .sort_by { |r| [r["path"], r["method"]] }

# --- routes.rb ---------------------------------------------------------------------------------

def route_literal(route)
  fields = [
    %(method: "#{route["method"]}"),
    %(path: "#{route["path"]}"),
    %(auth: :#{route["auth"]}),
    "idempotent: #{route["idempotent"]}",
    "safe: #{safe?(route)}",
    "bare: #{route["bare"]}",
    "list: #{route["list"] ? ":#{route["list"]}" : "nil"}"
  ]
  %(Route.new(#{fields.join(", ")}))
end

routes_rb = HEADER.dup
routes_rb << <<~RUBY

  require_relative "route"

  module Oblodai
    module Contract
      # Commit of the core the contract snapshot was exported from.
      CORE_COMMIT = "#{contract["core_commit"]}"
      # When the snapshot was exported (RFC 3339).
      EXPORTED_AT = "#{contract["exported_at"]}"
      # SHA-256 of contract/contract.json — sent in the User-Agent so support can pin the vocabulary.
      CONTRACT_HASH = "#{CONTRACT_HASH}"

      # Every merchant-facing route the core declares, keyed exactly as its conformance table keys
      # them ("METHOD /path"). Path templates keep their `{name}` segments.
      #
      # @return [Hash{String => Oblodai::Contract::Route}] frozen registry of #{routes.size} routes
      ROUTES = {
RUBY
routes.each do |route|
  routes_rb << %(      "#{route["method"]} #{route["path"]}" => #{route_literal(route)},\n)
end
routes_rb << <<~RUBY
      }.freeze
    end
  end
RUBY
OUT_DIR.join("routes.rb").write(routes_rb)

# --- enums.rb ----------------------------------------------------------------------------------

ENUMS = {
  "payment_status" => ["PAYMENT_STATUSES", "Invoice lifecycle: select → created → confirm_check → " \
                                           "paid | paid_over | wrong_amount | expired | cancelled."],
  "payout_status" => ["PAYOUT_STATUSES", "Payout lifecycle: pending → approved → awaiting_cosign → " \
                                         "broadcasting → sent → confirmed | failed | cancelled."],
  "payout_link_status" => ["PAYOUT_LINK_STATUSES", "Payout link (cheque) lifecycle."],
  "delivery_status" => ["DELIVERY_STATUSES", "Webhook delivery states; `dead` means the core gave up retrying."],
  "network" => ["NETWORKS", "Settlement networks the core can price and move funds on."],
  "fee_bearer" => ["FEE_BEARERS", "Who is asked to bear the network fee when a request states it."],
  "fee_bearer_result" => ["FEE_BEARER_RESULTS", "Who actually bore the fee on a priced result."],
  "batch_on_error" => ["BATCH_ON_ERRORS", "What an asynchronous batch does when an element fails."],
  "webhook_kind" => ["WEBHOOK_KINDS", "Event families a test delivery can rehearse."],
  "error_kind" => ["ERROR_KINDS", "Coarse classification the core attaches to an error envelope."]
}.freeze

# Vocabularies the core does not export as enums yet; pinned here from its handlers.
LOCAL_ENUMS = {
  "AMOUNT_MODES" => [%w[fixed open range], "How a payment link prices its invoices."]
}.freeze

def word_array(values, indent)
  pad = " " * indent
  lines = []
  values.each_slice(4) { |slice| lines << "#{pad}  #{slice.map(&:inspect).join(", ")}" }
  "[\n#{lines.join(",\n")}\n#{pad}].freeze"
end

enums_rb = HEADER.dup
enums_rb << <<~RUBY

  module Oblodai
    # Vocabularies exactly as the core declares them. Values are plain frozen strings: a value newer
    # than this snapshot still flows through the SDK untouched, it simply is not listed here.
    module Enums
RUBY
ENUMS.each do |key, (const, doc)|
  values = contract["enums"][key] or raise "enum #{key} missing from contract.json"
  enums_rb << "      # #{doc}\n      # @return [Array<String>]\n"
  enums_rb << "      #{const} = #{word_array(values, 6)}\n\n"
end
LOCAL_ENUMS.each do |const, (values, doc)|
  enums_rb << "      # #{doc}\n      # @return [Array<String>]\n"
  enums_rb << "      #{const} = #{word_array(values, 6)}\n\n"
end
enums_rb << "      # Webhook event types: `invoice.<status>`, `payout.<status>`, `wallet.paid`.\n"
enums_rb << "      # @return [Array<String>]\n"
enums_rb << "      EVENT_TYPES = #{word_array(contract["event_types"], 6)}\n\n"
enums_rb << "      # Every error code the core source can emit (`family.reason`).\n"
enums_rb << "      # @return [Array<String>]\n"
enums_rb << "      ERROR_CODES = #{word_array(contract["error_codes"], 6)}\n"
enums_rb << <<~RUBY
    end
  end
RUBY
OUT_DIR.join("enums.rb").write(enums_rb)

# --- requests.rb -------------------------------------------------------------------------------

# Request fields drawn from a generated enum: the vocabulary is attached to the field so an editor,
# an agent or a validation layer can offer it without re-deriving it from the route.
FIELD_ENUMS = {
  "network" => "NETWORKS",
  "pinned_network" => "NETWORKS",
  "on_error" => "BATCH_ON_ERRORS",
  "fee_bearer" => "FEE_BEARERS",
  "amount_mode" => "AMOUNT_MODES"
}.freeze
ROUTE_FIELD_ENUMS = {
  "POST /v1/payment/history#status" => "PAYMENT_STATUSES",
  "POST /v1/payout/history#status" => "PAYOUT_STATUSES",
  "POST /v1/test-webhook/payment#status" => "PAYMENT_STATUSES",
  "POST /v1/test-webhook/payout#status" => "PAYOUT_STATUSES",
  "POST /v1/payment/testing-webhook#status" => "PAYMENT_STATUSES"
}.freeze
ROUTE_FIELD_VALUES = {
  "POST /v1/payout/history#kind" => %w[payout refund],
  "POST /v1/payment/resolve#action" => %w[accept refund],
  "POST /v1/test-webhook/wallet#status" => %w[paid]
}.freeze
MONEY_FIELD = /(^|_)(amount|min_amount|max_amount|amount_fixed)$/
# Fields the handler requires although the shared DTO marks them optional (batch items reuse the
# single-create DTO, where the core backfills the key from the Idempotency-Key header).
REQUIRED_OVERRIDES = {
  "POST /v1/payment/batch" => ["payments.order_id"],
  "POST /v1/payout/batch" => ["payouts.order_id"],
  "POST /v1/refund/batch" => ["refunds.reference"],
  "POST /v1/transfer/batch" => ["transfers.order_id", "transfers.amount", "transfers.currency"],
  "POST /v1/payout/link/batch" => ["items.reference"],
  "POST /v1/transfer/to-user" => %w[amount currency],
  "POST /v1/claim/{token}" => %w[address]
}.freeze
# Request schemas for routes whose core DTO is not declared in docsapi (kept to one place so a
# future undocumented route has somewhere to go; remove an entry once the core documents it).
REQUEST_OVERRIDES = {
  "POST /v1/merchants" => {
    "type" => "object",
    "required" => ["email"],
    "properties" => {
      "email" => { "type" => "string", "example" => "owner@shop.example" },
      "name" => { "type" => "string", "example" => "Acme" }
    }
  }
}.freeze

# Collected while walking the schemas and reported at the end; a constant so the top-level helper
# methods below can reach it.
MISSING_DESCRIPTIONS = [] # rubocop:disable Style/MutableConstant

def ruby_type(schema)
  case schema["type"]
  when "string" then :string
  when "integer" then :integer
  when "number" then :number
  when "boolean" then :boolean
  when "array" then :array
  when "object" then :object
  else :unknown
  end
end

# The vocabulary a field draws its values from, when the core declares one.
def field_values(route, key, name)
  if (enum = ROUTE_FIELD_ENUMS["#{route}##{key}"] || FIELD_ENUMS[name])
    "enum: Enums::#{enum}"
  elsif (values = ROUTE_FIELD_VALUES["#{route}##{key}"])
    "values: %w[#{values.join(" ")}].freeze"
  end
end

def field_entry(route, prefix, name, schema, required, descriptions, indent)
  pad = " " * indent
  key = "#{prefix}#{name}"
  desc = descriptions.dig("request", route, key)
  MISSING_DESCRIPTIONS << "#{route}##{key}" if desc.nil? && schema["description"]
  parts = ["type: :#{ruby_type(schema)}"]
  parts << "required: true" if required
  parts << "money: true" if MONEY_FIELD.match?(name)
  parts << field_values(route, key, name)
  parts << "example: #{schema["example"].inspect}" if schema.key?("example")
  parts << "doc: #{desc.inspect}" if desc
  parts.compact!

  out = "#{pad}#{name}: { #{parts.join(", ")}"
  nested = schema["type"] == "array" ? schema["items"] : schema
  if nested.is_a?(Hash) && nested["properties"]
    out << ", fields: {\n"
    out << object_fields(route, "#{key}.", nested, descriptions, indent + 2)
    out << "#{pad}} "
  else
    out << " "
  end
  "#{out}}.freeze"
end

def object_fields(route, prefix, schema, descriptions, indent)
  required = Array(schema["required"]).dup
  REQUIRED_OVERRIDES.fetch(route, []).each do |path|
    required << path.delete_prefix(prefix) if path.start_with?(prefix) && !path.delete_prefix(prefix).include?(".")
  end
  fields = schema["properties"].keys.sort.map do |name|
    field_entry(route, prefix, name, schema["properties"][name], required.include?(name), descriptions, indent)
  end
  "#{fields.join(",\n")}\n"
end

requests_rb = HEADER.dup
requests_rb << <<~RUBY

  require_relative "enums"

  module Oblodai
    module Contract
      # Request bodies by route, generated from the core's documented DTOs: field names, required
      # flags, value vocabularies, examples and the English description of every field.
      #
      # Every entry is `{ field_name => { type:, required:, money:, enum:, values:, example:, doc:,
      # fields: } }`; `fields:` recurses into object and array-of-object members. Amounts marked
      # `money: true` are decimal strings — never floats.
      #
      # @example What the core accepts on an invoice
      #   Oblodai::Contract::REQUESTS["POST /v1/payment"][:amount][:doc]
      #   # => "Amount to pay, in currency."
      #
      # @return [Hash{String => Hash{Symbol => Hash}}]
      REQUESTS = {
RUBY
routes.each do |route|
  key = "#{route["method"]} #{route["path"]}"
  schema = route["request_schema"] || REQUEST_OVERRIDES[key]
  next unless schema.is_a?(Hash) && schema["properties"]

  requests_rb << %(      "#{key}" => {\n)
  requests_rb << object_fields(key, "", schema, descriptions, 8)
  requests_rb << "      }.freeze,\n"
end
requests_rb << <<~RUBY
      }.freeze
    end
  end
RUBY
OUT_DIR.join("requests.rb").write(requests_rb)

unless MISSING_DESCRIPTIONS.empty?
  warn "codegen: #{MISSING_DESCRIPTIONS.size} request fields lack an English description " \
       "in contract/descriptions.en.json:\n  #{MISSING_DESCRIPTIONS.join("\n  ")}"
end
puts "codegen: #{routes.size} routes, #{contract["error_codes"].size} error codes, " \
     "contract #{CONTRACT_HASH[0, 12]}"
