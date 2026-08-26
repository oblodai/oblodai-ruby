# frozen_string_literal: true

require_relative "../errors"

module Oblodai
  # Amounts are decimal strings; never `to_f` them (USDT has 6 decimals, BTC 8, ETH 18). These
  # helpers compare and add at arbitrary precision, and keep the scale of the widest operand, so
  # `add("10.000000", "0.5")` is `"10.500000"` — the shape the core would have rendered.
  #
  # An amount is a plain `String`, which means `a < b` and `amounts.sort` compile and are WRONG:
  # `"9" < "10"` is true lexicographically and false numerically. Order amounts with {compare}
  # (or {equals?}), never with `<`, `>`, `sort` or `max`.
  module Money
    # Longest amount accepted. Far beyond any asset's precision, and short enough to bound the work
    # a hostile input can ask for.
    MAX_LENGTH = 64

    # Optional `-`, then digits, then at most one `.` followed by at least one digit. `.5`, `5.`,
    # `1e3`, `+1`, `1_000`, `Infinity` and `NaN` are all refused: every one of them is a place where
    # a caller thought they had a number and the wire would have carried something else.
    DECIMAL = /\A-?\d+(\.\d+)?\z/

    module_function

    # @param amount [String]
    # @return [Boolean] whether the string is a decimal amount the core would accept
    def valid?(amount)
      amount.is_a?(String) && !amount.empty? && amount.length <= MAX_LENGTH && DECIMAL.match?(amount)
    end

    # @param a [String]
    # @param b [String]
    # @return [Integer] -1, 0 or 1 — the only correct way to order two amounts
    # @raise [Oblodai::ConfigError] `sdk.bad_amount` when either side is not a decimal amount
    def compare(a, b)
      scale = scale_of(a, b)
      scaled(a, scale) <=> scaled(b, scale)
    end

    # Numeric equality of two amounts ("1.50" equals "1.5"). Deliberately NOT named `equal?`, which
    # is Ruby's one-argument object-identity predicate on every object.
    # @return [Boolean]
    def equals?(a, b)
      compare(a, b).zero?
    end

    # @return [String]
    def add(a, b)
      scale = scale_of(a, b)
      unscale(scaled(a, scale) + scaled(b, scale), scale)
    end

    # @return [String]
    def subtract(a, b)
      scale = scale_of(a, b)
      unscale(scaled(a, scale) - scaled(b, scale), scale)
    end

    # @return [Boolean]
    def zero?(amount)
      scaled(amount, scale_of(amount)).zero?
    end

    # @return [Boolean]
    def negative?(amount)
      scaled(amount, scale_of(amount)).negative?
    end

    # @param amount [String]
    # @param scale [Integer]
    # @return [Integer] the amount as an integer number of its smallest units
    def scaled(amount, scale)
      neg, int, frac = parts(amount)
      value = "#{int}#{frac.ljust(scale, "0")}".to_i
      neg ? -value : value
    end

    # Every rejection is one SDK error — never a native TypeError from deep inside a helper.
    # @raise [Oblodai::ConfigError]
    def parts(amount)
      bad_amount!(amount, "expected a string") unless amount.is_a?(String)
      bad_amount!(amount, "empty") if amount.empty?
      bad_amount!(amount, "longer than #{MAX_LENGTH} characters") if amount.length > MAX_LENGTH
      bad_amount!(amount, "expected digits with at most one dot") unless DECIMAL.match?(amount)

      neg = amount.start_with?("-")
      int, frac = (neg ? amount[1..] : amount).split(".")
      [neg, int || "0", frac || ""]
    end

    def bad_amount!(value, why)
      shown = value.is_a?(String) ? value[0, 80].inspect : value.class.name
      raise ConfigError.new("sdk.bad_amount", "not a decimal amount (#{why}): #{shown}", "amount")
    end

    def scale_of(*amounts)
      amounts.map { |a| parts(a)[2].length }.max
    end

    def unscale(value, scale)
      neg = value.negative?
      digits = value.abs.to_s.rjust(scale + 1, "0")
      int = digits[0...(digits.length - scale)]
      frac = digits[(digits.length - scale)..]
      "#{"-" if neg}#{int}#{".#{frac}" unless scale.zero?}"
    end
  end
end
