# frozen_string_literal: true

require "time"
require "track_relay/errors"

module TrackRelay
  # Runtime data for a single event in flight.
  #
  # An EventPayload pairs a {EventDefinition} (the schema) with the raw
  # values supplied at the call site (`TrackRelay.track(:foo, ...)`),
  # plus the request-derived context (user, visitor_token, client_id,
  # etc.) and a timestamp. It is the value passed through the
  # `track_relay.event` ActiveSupport::Notifications instrumentation.
  #
  # Two constructors:
  # - `EventPayload.new(definition:, params:, ...)` — typed payload;
  #   {validate!} coerces and enforces the definition's schema.
  # - `EventPayload.untyped(name:, params:, ...)` — untyped payload (no
  #   matching definition); {validate!} is a no-op so consumers can
  #   still ship the raw event for the untyped-events linter (see
  #   Plan 04).
  #
  # `validate!` is destructive: it replaces `@params` with the coerced
  # hash so subscribers see post-coercion values. Errors raise
  # {ValidationError} naming the offending key.
  class EventPayload
    # Sentinel values that the strict boolean coercion accepts. Anything
    # else raises {ValidationError}.
    BOOLEAN_TRUE_VALUES = [true, "true", 1].freeze
    BOOLEAN_FALSE_VALUES = [false, "false", 0].freeze

    attr_reader :definition, :params, :context, :timestamp

    # @param definition [EventDefinition] schema for typed events
    # @param params [Hash{Symbol => Object}] raw param values
    # @param context [Hash] request-derived metadata (user, visitor,
    #   request, etc.)
    # @param timestamp [Time] event timestamp; defaults to now
    def initialize(definition:, params:, context: {}, timestamp: Time.now)
      @definition = definition
      @params = params
      @context = context
      @timestamp = timestamp
      @untyped_name = nil
    end

    # Build an untyped payload — no definition, no schema enforcement.
    # Used when a host application calls `TrackRelay.track(:unknown, ...)`
    # while `untyped_events_allowed = true`.
    #
    # @param name [Symbol] event name (stored separately because there
    #   is no definition to read it from)
    # @param params [Hash]
    # @param context [Hash]
    # @param timestamp [Time]
    # @return [EventPayload]
    def self.untyped(name:, params:, context: {}, timestamp: Time.now)
      payload = new(definition: nil, params: params, context: context, timestamp: timestamp)
      payload.instance_variable_set(:@untyped_name, name)
      payload
    end

    # @return [Symbol] event name (from definition or untyped store)
    def name
      @definition ? @definition.name : @untyped_name
    end

    # @return [Boolean] whether this payload was built without a
    #   matching catalog definition
    def untyped?
      @definition.nil?
    end

    # Coerce and validate `@params` against `@definition.params`.
    # Mutates `@params` to the coerced hash.
    #
    # For each schema entry the order of operations is:
    # 1. Apply `sanitize` callable if present (raw -> sanitized).
    # 2. Check `required` against post-sanitize value.
    # 3. Coerce to `type`.
    # 4. Apply `max` (length for strings, value for numbers).
    # 5. Apply `in` inclusion list.
    # 6. Apply `format` regex (strings only).
    #
    # After per-key processing, any incoming param not declared in the
    # schema raises {ValidationError}.
    #
    # No-op for untyped payloads.
    #
    # @raise [ValidationError]
    # @return [Hash{Symbol => Object}] coerced params
    def validate!
      return @params if untyped?

      coerced = {}

      @definition.params.each do |key, schema|
        raw_value = @params[key]
        raw_value = schema.sanitize.call(raw_value) if schema.sanitize&.respond_to?(:call) && @params.key?(key)

        if raw_value.nil?
          if schema.required
            raise ValidationError, "Param #{key.inspect} is required but was not provided"
          end
          next
        end

        coerced_value = coerce(key, schema.type, raw_value)
        check_max!(key, schema.max, coerced_value) if schema.max
        check_in!(key, schema.in, coerced_value) if schema.in
        check_format!(key, schema.format, coerced_value) if schema.format

        coerced[key] = coerced_value
      end

      extras = @params.keys - @definition.params.keys
      unless extras.empty?
        raise ValidationError,
          "Unexpected param(s) #{extras.map(&:inspect).join(", ")} not declared on event #{@definition.name.inspect}"
      end

      @params = coerced
    end

    # Serialize to a Hash suitable for ActiveJob arguments / JSON
    # encoding. Used by the DeliveryJob in Plan 05.
    #
    # @return [Hash]
    def to_h
      {
        name: name,
        params: @params,
        context: @context,
        timestamp: @timestamp.respond_to?(:iso8601) ? @timestamp.iso8601 : @timestamp.to_s
      }
    end

    private

    def coerce(key, type, value)
      case type
      when :integer then coerce_integer(key, value)
      when :string then coerce_string(value)
      when :float then coerce_float(key, value)
      when :boolean then coerce_boolean(key, value)
      when :datetime then coerce_datetime(key, value)
      else
        raise ValidationError, "Param #{key.inspect} has unsupported type #{type.inspect}"
      end
    end

    def coerce_integer(key, value)
      Integer(value)
    rescue ArgumentError, TypeError
      raise ValidationError, "Param #{key.inspect} cannot be coerced to Integer (got #{value.inspect})"
    end

    def coerce_string(value)
      String(value)
    end

    def coerce_float(key, value)
      Float(value)
    rescue ArgumentError, TypeError
      raise ValidationError, "Param #{key.inspect} cannot be coerced to Float (got #{value.inspect})"
    end

    def coerce_boolean(key, value)
      return true if BOOLEAN_TRUE_VALUES.include?(value)
      return false if BOOLEAN_FALSE_VALUES.include?(value)

      raise ValidationError,
        "Param #{key.inspect} cannot be coerced to Boolean — accepted values are true/false/'true'/'false'/1/0 (got #{value.inspect})"
    end

    def coerce_datetime(key, value)
      case value
      when Time, DateTime
        value
      when String
        begin
          Time.iso8601(value)
        rescue ArgumentError
          raise ValidationError, "Param #{key.inspect} is not a valid ISO8601 datetime (got #{value.inspect})"
        end
      else
        raise ValidationError,
          "Param #{key.inspect} cannot be coerced to datetime — expected Time, DateTime, or ISO8601 String (got #{value.class})"
      end
    end

    def check_max!(key, max, value)
      length_or_value = value.is_a?(String) ? value.length : value

      if length_or_value > max
        unit = value.is_a?(String) ? "length" : "value"
        raise ValidationError,
          "Param #{key.inspect} #{unit} #{length_or_value} exceeds max #{max}"
      end
    end

    def check_in!(key, allowed, value)
      unless allowed.include?(value)
        raise ValidationError,
          "Param #{key.inspect} value #{value.inspect} is not in inclusion list #{allowed.inspect}"
      end
    end

    def check_format!(key, format, value)
      unless value.is_a?(String) && value.match?(format)
        raise ValidationError,
          "Param #{key.inspect} value #{value.inspect} does not match format #{format.inspect}"
      end
    end
  end
end
