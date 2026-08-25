# frozen_string_literal: true

module Oblodai
  # Minimal structured-logger contract: anything responding to debug/info/warn/error(message,
  # fields) fits (a Ruby ::Logger wrapper, a Rails logger, semantic_logger). Field values that
  # carry secrets are redacted before they reach the logger, so a debug log never leaks a key,
  # a signature or a cheque passcode.
  module Logging
    SENSITIVE = /secret|signature|passcode|token|authorization|password/i

    module_function

    # Replace values of sensitive-looking keys, recursively, without touching the original object.
    # @param value [Object]
    # @return [Object]
    def redact(value)
      case value
      when Array then value.map { |v| redact(v) }
      when Hash
        value.each_with_object({}) do |(k, v), out|
          out[k] = SENSITIVE.match?(k.to_s) ? "[redacted]" : redact(v)
        end
      else value
      end
    end
  end

  # Discards everything. The default when no logger is configured.
  class NullLogger
    def debug(_message, _fields = nil); end
    def info(_message, _fields = nil); end
    def warn(_message, _fields = nil); end
    def error(_message, _fields = nil); end
  end

  # Writes one line per event to an IO, gated by level. `OBLODAI_LOG=debug|info|warn|error`
  # selects it from the environment when no logger is passed.
  class IOLogger
    LEVELS = { debug: 0, info: 1, warn: 2, error: 3 }.freeze

    # @param level [Symbol]
    # @param io [IO]
    def initialize(level = :warn, io = $stderr)
      @min = LEVELS.fetch(level.to_sym, 2)
      @io = io
    end

    LEVELS.each_key do |level|
      define_method(level) do |message, fields = nil|
        emit(level, message, fields)
      end
    end

    private

    def emit(level, message, fields)
      return if LEVELS[level] < @min

      line = "[oblodai] #{level.to_s.upcase} #{message}"
      line += " #{Logging.redact(fields).inspect}" if fields && !fields.empty?
      @io.puts(line)
    end
  end
end
