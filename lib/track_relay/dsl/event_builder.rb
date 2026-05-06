# frozen_string_literal: true

require "track_relay/event_definition"
require "track_relay/dsl/param_builder"
require "track_relay/validators/catalog_validator"

module TrackRelay
  module DSL
    # The DSL receiver for the body of `TrackRelay.catalog do ... end`.
    #
    # Provides two top-level methods:
    # - `event(name, &block)` — defines an event. The block is
    #   instance_exec'd against a {ParamBuilder} so type DSL methods
    #   (integer, string, float, boolean, datetime) work without any
    #   explicit receiver.
    # - `user_property(name, type)` — declares a catalog-wide user
    #   property (registered globally on {Catalog}, not attached to a
    #   single event).
    #
    # `event` is the layer where validation runs. After the block
    # populates a ParamBuilder, EventBuilder builds the
    # {EventDefinition}, calls {Validators::CatalogValidator.validate!}
    # to enforce GA4 + reserved-key rules, and registers the result.
    # That way the *first* time a definition exists, it is already
    # validated and immutable.
    class EventBuilder
      # Define a single event in the catalog.
      #
      # @param name [Symbol] event name
      # @yield no-args block evaluated in a {ParamBuilder} context
      # @raise [TrackRelay::Ga4ConstraintError] when the event or any
      #   param violates GA4 rules
      # @raise [TrackRelay::ReservedKeyError] when any param collides
      #   with a reserved context key
      # @raise [TrackRelay::CatalogError] when the event is already
      #   registered
      # @return [EventDefinition] the registered, frozen definition
      def event(name, &block)
        param_builder = ParamBuilder.new(name)
        param_builder.instance_exec(&block) if block

        definition = EventDefinition.new(
          name: name,
          params: param_builder.params,
          user_properties: param_builder.user_properties
        )

        Validators::CatalogValidator.validate!(definition)
        Catalog.register(definition)
        definition
      end

      # Register a catalog-wide user property (independent of any event).
      #
      # @param name [Symbol]
      # @param type [Symbol] one of `:string`, `:integer`, `:float`,
      #   `:boolean`, `:datetime`
      # @return [void]
      def user_property(name, type)
        Catalog.register_user_property(name, type)
      end
    end
  end
end
