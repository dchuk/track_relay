# frozen_string_literal: true

module TrackRelay
  # Process-wide configuration for track_relay.
  #
  # Holds every Phase-01 knob: the subscriber list, defaults for
  # untyped-event handling, and the test-mode synchronous override.
  # The host application configures it via {TrackRelay.configure}; the
  # rest of the gem reads it via {TrackRelay.config}.
  #
  # @example Host-app initializer
  #   TrackRelay.configure do |c|
  #     c.subscribe(MyAnalyticsSubscriber.new)
  #     c.untyped_events_allowed = false
  #     c.untyped_log_path = Rails.root.join("log/untyped_events.log")
  #   end
  class Configuration
    # @!attribute [rw] swallow_subscriber_errors
    #   Whether subscriber exceptions are caught and logged instead of
    #   re-raised. Defaults to `true` in production, `false` elsewhere.
    # @!attribute [rw] untyped_log_path
    #   Optional path for logging untyped (non-catalog) events.
    #   `nil` disables the untyped log.
    # @!attribute [rw] untyped_events_allowed
    #   Whether {TrackRelay.track} accepts events not in the catalog.
    # @!attribute [rw] force_synchronous
    #   When `true`, subscribers run inline regardless of their async
    #   preference. Used by `test_mode!` (Plan 07) and integration tests.
    # @!attribute [rw] raise_on_validation_error
    #   Whether catalog/payload validation errors raise (dev/test) or
    #   are merely logged (prod). Defaults to true in dev/test.
    # @!attribute [rw] client_id_resolvers
    #   Ordered chain of `#call(controller:, **)`-callables consulted
    #   by {ControllerTracking#_resolve_client_id} to populate
    #   {Current.client_id}. First non-nil result wins. Defaults to
    #   `[ClientId::Ga.new, ClientId::AhoyVisitor.new,
    #   ClientId::Session.new]` (Plan 02-02 / REQ-26).
    attr_accessor :swallow_subscriber_errors,
      :untyped_log_path,
      :untyped_events_allowed,
      :force_synchronous,
      :raise_on_validation_error,
      :client_id_resolvers

    # @return [Array] registered subscriber instances, in insertion order
    attr_reader :subscribers

    def initialize
      reset!
    end

    # Restore every setting to its environment-aware default and clear
    # the subscriber list. Used by tests and by {TrackRelay.reset_config!}.
    #
    # @return [void]
    def reset!
      @subscribers = []
      @swallow_subscriber_errors = production_env?
      @untyped_log_path = nil
      @untyped_events_allowed = true
      @force_synchronous = false
      @raise_on_validation_error = development_or_test_env?
      @client_id_resolvers = default_client_id_resolvers
    end

    # Append a subscriber to the registry.
    #
    # @param subscriber [#call, Object] any object conforming to the
    #   subscriber protocol (Plan 05 defines the contract).
    # @return [Object] the subscriber, so the call is chainable / usable
    #   as `sub = config.subscribe(MySubscriber.new)`.
    def subscribe(subscriber)
      @subscribers << subscriber
      subscriber
    end

    # Atomically replace the subscriber list and return the previous
    # one. Plan 07's `TrackRelay.test_mode!` uses this to swap in a
    # capturing subscriber for the duration of a test block and then
    # restore the original list.
    #
    # @param list [Array, nil] new subscribers (`nil` is coerced to `[]`)
    # @return [Array] the previous subscriber list (caller's snapshot)
    def replace_subscribers(list)
      previous = @subscribers
      @subscribers = Array(list)
      previous
    end

    private

    # Build a fresh default resolver chain. Each call returns a new
    # array with new resolver instances so a mutated chain in one test
    # cannot leak into another (the {Session} resolver is otherwise
    # stateless, but the array container itself must be per-config).
    def default_client_id_resolvers
      [
        ClientId::Ga.new,
        ClientId::AhoyVisitor.new,
        ClientId::Session.new
      ]
    end

    def production_env?
      current_env == "production"
    end

    def development_or_test_env?
      %w[development test].include?(current_env)
    end

    def current_env
      if defined?(Rails) && Rails.respond_to?(:env)
        Rails.env.to_s
      else
        ENV.fetch("RACK_ENV", "development")
      end
    end
  end
end
