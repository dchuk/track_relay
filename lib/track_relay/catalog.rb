# frozen_string_literal: true

require "track_relay/errors"

module TrackRelay
  # Process-wide registry of event definitions and user properties.
  #
  # The {DSL::EventBuilder} pushes definitions in via {register}; the
  # rest of the gem (and host applications) read them out via {lookup},
  # {defined?}, and {all}.
  #
  # State is module-level by design — the gem assumes one catalog per
  # Ruby process, populated during boot. Tests that need isolation call
  # {clear!} in `setup` / `teardown` to reset between cases.
  #
  # @example Registering and looking up an event
  #   TrackRelay.catalog do
  #     event :article_viewed do
  #       integer :article_id, required: true
  #     end
  #   end
  #
  #   TrackRelay::Catalog.lookup(:article_viewed)
  #   # => #<TrackRelay::EventDefinition name=:article_viewed ...>
  module Catalog
    @definitions = {}
    @user_properties = {}

    class << self
      # @return [Hash{Symbol => Symbol}] catalog-wide user properties
      attr_reader :user_properties

      # Register a new {EventDefinition} in the catalog.
      #
      # @param definition [EventDefinition]
      # @raise [TrackRelay::CatalogError] when an event with the same
      #   name is already registered (defensive guard against catalog
      #   bugs that could silently shadow events)
      # @return [EventDefinition]
      def register(definition)
        if @definitions.key?(definition.name)
          raise CatalogError,
            "Event #{definition.name.inspect} is already registered. Call TrackRelay::Catalog.clear! before re-registering (e.g. in tests)."
        end
        @definitions[definition.name] = definition
      end

      # Register a catalog-wide user property.
      #
      # @param name [Symbol]
      # @param type [Symbol]
      # @return [Symbol] the type, for chaining
      def register_user_property(name, type)
        @user_properties[name] = type
      end

      # @param name [Symbol]
      # @return [EventDefinition, nil]
      def lookup(name)
        @definitions[name]
      end

      # @param name [Symbol]
      # @return [Boolean] whether an event with the given name is
      #   registered
      def defined?(name)
        @definitions.key?(name)
      end

      # @return [Array<EventDefinition>] frozen array of all registered
      #   definitions
      def all
        @definitions.values.freeze
      end

      # Reset the registry. Intended for test isolation; do not call in
      # production code.
      #
      # @return [void]
      def clear!
        @definitions = {}
        @user_properties = {}
      end
    end
  end
end
