# frozen_string_literal: true

require "track_relay/event_definition"

module TrackRelay
  module DSL
    # The DSL receiver for the body of `event :name do ... end`.
    #
    # Each type method (`integer`, `string`, `float`, `boolean`,
    # `datetime`) records a {EventDefinition::ParamSchema} keyed by param
    # name. `user_property` accumulates user-property declarations
    # separately so they can be passed through to the resulting
    # EventDefinition without polluting `params`.
    #
    # ParamBuilder does NOT validate or register anything itself — that
    # is {EventBuilder}'s job. Keeping the builder side-effect-free makes
    # it trivial to test and lets EventBuilder run validation against the
    # complete definition (so e.g. param-count overflow is reported with
    # the full param set).
    class ParamBuilder
      attr_reader :params, :user_properties

      # @param event_name [Symbol] the name of the surrounding event;
      #   stored for diagnostic context only
      def initialize(event_name)
        @event_name = event_name
        @params = {}
        @user_properties = {}
      end

      # @param name [Symbol] param name
      # @param opts [Hash] optional ParamSchema slots (required, max, in,
      #   format, sanitize)
      # @return [EventDefinition::ParamSchema]
      def integer(name, **opts)
        record_param(name, :integer, opts)
      end

      def string(name, **opts)
        record_param(name, :string, opts)
      end

      def float(name, **opts)
        record_param(name, :float, opts)
      end

      def boolean(name, **opts)
        record_param(name, :boolean, opts)
      end

      def datetime(name, **opts)
        record_param(name, :datetime, opts)
      end

      # Declare a user property on the surrounding event. Accumulated
      # separately from regular params so EventDefinition can keep them
      # in `user_properties`.
      #
      # @param name [Symbol]
      # @param type [Symbol] one of the type symbols (`:string`,
      #   `:integer`, etc.)
      def user_property(name, type)
        @user_properties[name] = type
      end

      private

      def record_param(name, type, opts)
        schema = EventDefinition::ParamSchema.new(name: name, type: type, **opts)
        @params[name] = schema
      end
    end
  end
end
