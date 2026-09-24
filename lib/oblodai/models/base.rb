# frozen_string_literal: true

require "json"
require_relative "../core/logger"

module Oblodai
  module Models
    # Base of every generated model (`Oblodai::Models::*`): a frozen value object with one reader per
    # field of the API. Parsing is tolerant by design — a field this release does not know lands in
    # `extra`, and an enum value it does not know stays a plain String — so a new server release
    # never breaks an old SDK. Amounts are `BigDecimal`.
    #
    # Subclasses (generated) define `from_h`, `to_h` and the readers; this base adds equality, JSON
    # and a short `inspect` that never shows a secret.
    class Base
      # The longest `inspect` a model produces; anything longer is cut and ends with "...>".
      INSPECT_LIMIT = 1024

      # Read a field by its JSON name, known or not.
      # @param name [String, Symbol]
      # @return [Object, nil]
      def [](name)
        to_h[name.to_s]
      end

      # Compared on the wire form: same class, same fields, same unknown fields.
      def ==(other)
        other.class == self.class && other.to_h == to_h
      end
      alias eql? ==

      def hash
        [self.class, to_h].hash
      end

      # @return [String] the wire form as JSON
      def to_json(*)
        to_h.to_json(*)
      end

      # Short, and never the value of a field whose name looks secret (`secret`, `token`,
      # `signature`, `passcode`, ...); fields that are nil are left out.
      def inspect
        shown = Logging.redact(to_h).compact
        text = "#<#{self.class.name} #{shown.map { |key, value| "#{key}=#{value.inspect}" }.join(" ")}>"
        text.length > INSPECT_LIMIT ? "#{text[0, INSPECT_LIMIT - 4]}...>" : text
      end
      alias to_s inspect
    end
  end
end
