# frozen_string_literal: true

module TrackRelay
  # Catalog metadata for a single event.
  #
  # An EventDefinition is the immutable description of an event as
  # declared in `TrackRelay.catalog do ... end`. It holds the event name,
  # the schema of every declared param (a Hash of {ParamSchema} keyed by
  # param name), and any user_property declarations.
  #
  # EventDefinition is paired with {TrackRelay::EventPayload} at runtime:
  # the definition is the schema, the payload is the data, and
  # `payload.validate!` checks the data against the schema.
  #
  # Instances are deep-frozen at construction so the catalog cannot be
  # mutated after load. Re-defining an event requires {Catalog#clear!}.
  #
  # @example
  #   schema = TrackRelay::EventDefinition::ParamSchema.new(
  #     name: :article_id, type: :integer, required: true
  #   )
  #   definition = TrackRelay::EventDefinition.new(
  #     name: :article_viewed,
  #     params: {article_id: schema}
  #   )
  #   definition.params[:article_id].type  # => :integer
  class EventDefinition
    # The schema of a single param within an event definition.
    #
    # `name` is the param's Symbol key. `type` is one of `:integer`,
    # `:string`, `:float`, `:boolean`, `:datetime`. The remaining slots
    # are optional validator hooks consumed by {EventPayload#validate!}:
    #
    # - `required` (Boolean) — when true, missing values raise
    #   {ValidationError}.
    # - `max` (Integer) — for strings, max length; for numbers, max
    #   value. Overflows raise (no silent truncation).
    # - `in` (Array) — inclusion list; values not in the list raise.
    # - `format` (Regexp) — applied to coerced strings; mismatches raise.
    # - `sanitize` (Callable) — applied to the raw value BEFORE coercion
    #   and validation, so sanitization can preempt max/format checks.
    #
    # `Data.define` (Ruby 3.2+) gives us a frozen value object with a
    # keyword constructor, equality by value, and zero ceremony.
    ParamSchema = Data.define(
      :name,
      :type,
      :required,
      :max,
      :in,
      :format,
      :sanitize
    ) do
      # Override `initialize` to default the optional slots so callers
      # only need to pass `name:` and `type:`.
      def initialize(name:, type:, required: false, max: nil, in: nil, format: nil, sanitize: nil)
        super
      end
    end

    attr_reader :name, :params, :user_properties

    # @param name [Symbol] event name (e.g. `:article_viewed`)
    # @param params [Hash{Symbol => ParamSchema}] param schemas keyed by name
    # @param user_properties [Hash{Symbol => Symbol}] user-property names
    #   mapped to their type (e.g. `{plan: :string}`)
    def initialize(name:, params: {}, user_properties: {})
      @name = name
      @params = params.freeze
      @user_properties = user_properties.freeze
      freeze
    end
  end
end
