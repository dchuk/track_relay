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
    # @!attribute [rw] ga4_measurement_id
    #   GA4 Measurement Protocol `measurement_id` query parameter
    #   (`G-XXXXXXXXXX`). Read at delivery time so credentials
    #   lambdas / late-bound configs work. Defaults to `nil`; when
    #   `nil` at delivery time the GA4 subscriber emits a
    #   `Rails.logger.warn` and skips the POST without raising.
    # @!attribute [rw] ga4_api_secret
    #   GA4 Measurement Protocol `api_secret` query parameter, scoped
    #   per data stream. Read at delivery time. Defaults to `nil`;
    #   same warn-and-skip behavior as {#ga4_measurement_id} when
    #   missing. Treat as a credential — never commit to source.
    # @!attribute [rw] ga4_use_eu_endpoint
    #   When `true`, the GA4 subscriber posts to
    #   `https://region1.google-analytics.com/mp/collect` instead of
    #   the global endpoint. Defaults to `false`.
    # @!attribute [rw] ga4_require_browser_client_id
    #   When `true`, the GA4 subscriber delivers ONLY when the current
    #   request carries a genuine `_ga` cookie (set by gtag JS, which
    #   bots don't execute). No cookie — or a malformed one — means no
    #   DeliveryJob is enqueued at all; the random client_id fallback
    #   never fires. The cookie-derived client_id is merged into the
    #   delivered payload's context. Defaults to `false` (deliver
    #   everything, as before).
    # @!attribute [rw] ga4_enrich_page_context
    #   When `true`, the GA4 subscriber captures page context from the
    #   current request at notification time and merges it into the
    #   delivered event's params: `page_location` (request URL),
    #   `page_referrer` (when a referer exists), and — when the gtag
    #   session cookie `_ga_<stream>` is parseable — `session_id` plus
    #   a nominal `engagement_time_msec`. Without these GA4 files
    #   server-side events under a blank page path. Defaults to
    #   `false`.
    # @!attribute [rw] track_gate
    #   Optional callable evaluated once per {TrackRelay.track} call,
    #   BEFORE the event notification fans out to any subscriber.
    #   Receives `payload:` (the built {EventPayload}) and `request:`
    #   ({Current.request}, possibly `nil`) keywords; a falsy return
    #   drops the event for every subscriber. `nil` (the default)
    #   disables the gate entirely — current behavior.
    attr_accessor :swallow_subscriber_errors,
      :untyped_log_path,
      :untyped_events_allowed,
      :force_synchronous,
      :raise_on_validation_error,
      :client_id_resolvers,
      :ga4_measurement_id,
      :ga4_api_secret,
      :ga4_use_eu_endpoint,
      :ga4_require_browser_client_id,
      :ga4_enrich_page_context,
      :track_gate

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
      @ga4_measurement_id = nil
      @ga4_api_secret = nil
      @ga4_use_eu_endpoint = false
      @ga4_require_browser_client_id = false
      @ga4_enrich_page_context = false
      @track_gate = nil
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
