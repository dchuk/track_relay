# frozen_string_literal: true

require "active_support/notifications"
require "track_relay/catalog"
require "track_relay/current"
require "track_relay/errors"
require "track_relay/event_payload"

module TrackRelay
  # Central orchestrator for {TrackRelay.track} and {TrackRelay.identify}.
  #
  # `track` is the integration point of:
  #
  #   - {RESERVED_KEYS} extraction (split-routed: some keys land on
  #     {Current}, `:visitor_token` lands directly in `payload.context`)
  #   - {Catalog} lookup (typed vs untyped path)
  #   - {EventPayload} construction + {EventPayload#validate!}
  #   - context snapshot (read at `track` time so async delivery in
  #     Plan 05 has the data after `Current` is reset)
  #   - `ActiveSupport::Notifications.instrument("track_relay.event", ...)`
  #
  # All four steps happen on the calling thread before any subscriber
  # runs, so reserved-key partitioning and validation are deterministic
  # from the host application's perspective.
  #
  # Reserved-key split rationale (per Plan 01-04 must_have):
  #
  #   - `:user`, `:request`, `:client_id` are {Current} attributes —
  #     bound via `Current.set(...) { ... }` for the duration of the
  #     instrumentation block.
  #   - `:visitor_token` is intentionally NOT a {Current} attribute.
  #     {Current} carries `:visit` (an Ahoy-style record), not a raw
  #     opaque token. The token is merged directly into
  #     `payload.context[:visitor_token]` so subscribers (and the
  #     downstream DeliveryJob in Plan 05) can read it without
  #     touching {Current}.
  #
  # `identify` is a thin pass-through in Phase 01: it instruments
  # `track_relay.identify` with `{user:, properties:}` and performs
  # no catalog validation against `user_property` declarations.
  # Adapter-specific user-property handling is deferred to Phase 02.
  module Instrumenter
    # AS::Notifications event name for typed/untyped event tracking.
    NOTIFICATION = "track_relay.event"

    # AS::Notifications event name for identify calls.
    IDENTIFY_NOTIFICATION = "track_relay.identify"

    # Reserved keys that must be partitioned onto {Current} (block-scoped
    # via `Current.set`). See {DIRECT_CONTEXT_KEYS} for keys that bypass
    # {Current} and land directly on `payload.context`.
    CURRENT_ATTR_KEYS = %i[user request client_id].freeze

    # Reserved keys that bypass {Current} entirely and are merged
    # directly into `payload.context` at build time.
    DIRECT_CONTEXT_KEYS = %i[visitor_token].freeze

    module_function

    # Track a typed (catalog-defined) or untyped event.
    #
    # Reserved keys are extracted from `params` BEFORE catalog lookup so
    # they never appear in `payload.params`. Validation gating respects
    # {Configuration#raise_on_validation_error} (`true` re-raises, `false`
    # logs and swallows without instrumenting).
    #
    # @param name [Symbol] event name; looked up in {Catalog}
    # @param params [Hash{Symbol => Object}] event params + reserved keys
    # @return [void]
    # @raise [UnknownEventError] when the event is not in the catalog
    #   AND {Configuration#untyped_events_allowed} is false
    # @raise [ValidationError] when a typed event fails validation AND
    #   {Configuration#raise_on_validation_error} is true
    def track(name, **params)
      current_attrs, direct_context, event_params = partition_reserved(params)
      with_current_attrs(current_attrs) do
        definition = Catalog.lookup(name)
        payload = build_payload(
          name: name,
          definition: definition,
          params: event_params,
          extra_context: direct_context
        )
        return unless validate(payload)
        return unless track_gate_allows?(payload)
        ActiveSupport::Notifications.instrument(NOTIFICATION, event: payload)
      end
    end

    # Identify a user — Phase 01 pass-through.
    #
    # Instruments `track_relay.identify` with `{user:, properties:}`.
    # No catalog validation happens here; adapter-specific user_property
    # validation is deferred to Phase 02 where each subscriber decides
    # how to handle properties (GA4 user_properties, Ahoy User update,
    # etc.).
    #
    # TODO(phase-02): wire `Catalog.user_properties` validation here so
    # consumers can declare user_property schemas and have them enforced
    # at identify time.
    #
    # @param user [Object] user-like object (or id) to identify
    # @param user_properties [Hash] arbitrary properties to attach
    # @return [void]
    def identify(user, **user_properties)
      ActiveSupport::Notifications.instrument(
        IDENTIFY_NOTIFICATION,
        user: user,
        properties: user_properties
      )
    end

    # Bind `current_attrs` on {Current} for the duration of `block`.
    #
    # When the hash is empty, `Current.set(**{})` would raise
    # `ArgumentError: wrong number of arguments (given 0, expected 1)`
    # under ActiveSupport 8.x. Skipping the wrapper in that case
    # preserves the no-reserved-keys path (most calls).
    #
    # @param current_attrs [Hash]
    # @yield with `Current` bound
    # @return [Object] the block's return value
    def with_current_attrs(current_attrs, &block)
      if current_attrs.empty?
        block.call
      else
        Current.set(**current_attrs, &block)
      end
    end

    # Split params into three buckets:
    #
    #   - `current_attrs` — keys that {Current.set} accepts
    #     (`:user`, `:request`, `:client_id`)
    #   - `direct_context` — keys that bypass {Current} and land
    #     directly on `payload.context` (`:visitor_token`)
    #   - `event_params` — everything else (validated against catalog)
    #
    # @param params [Hash]
    # @return [Array(Hash, Hash, Hash)] three-tuple of partitioned hashes
    def partition_reserved(params)
      current_attrs = {}
      direct_context = {}
      event_params = {}

      params.each do |key, value|
        if CURRENT_ATTR_KEYS.include?(key)
          current_attrs[key] = value
        elsif DIRECT_CONTEXT_KEYS.include?(key)
          direct_context[key] = value
        else
          event_params[key] = value
        end
      end

      [current_attrs, direct_context, event_params]
    end

    # Build either a typed or untyped {EventPayload}, merging
    # `extra_context` (e.g. `:visitor_token`) into the snapshot of
    # {Current} taken at instrument time.
    #
    # Untyped path is gated by
    # {Configuration#untyped_events_allowed} — when disallowed,
    # {UnknownEventError} is raised.
    #
    # @param name [Symbol]
    # @param definition [EventDefinition, nil]
    # @param params [Hash]
    # @param extra_context [Hash] reserved keys that go straight to
    #   context (currently just `:visitor_token`)
    # @return [EventPayload]
    # @raise [UnknownEventError]
    def build_payload(name:, definition:, params:, extra_context: {})
      context = current_context.merge(extra_context)

      if definition
        EventPayload.new(definition: definition, params: params, context: context)
      elsif TrackRelay.config.untyped_events_allowed
        EventPayload.untyped(name: name, params: params, context: context)
      else
        raise UnknownEventError,
          "Unknown event #{name.inspect}; declare it in your catalog or set config.untyped_events_allowed = true"
      end
    end

    # Snapshot {Current} at instrument time. Plan 05's DeliveryJob
    # depends on this contract: by the time the job runs, the Rails
    # Executor has already cleared {Current}, so async subscribers
    # must read from `payload.context`, not from `Current` directly.
    #
    # Keys snapshot:
    #
    #   - `:user`        — Current.user (any object)
    #   - `:controller`  — Current.controller&.class&.name (String)
    #   - `:action`      — Current.controller&.action_name (String)
    #   - `:client_id`   — Current.client_id (String)
    #   - `:visit`       — Current.visit (Ahoy-style record or nil)
    #   - `:request_id`  — Current.request&.request_id (String)
    #
    # `:controller` and `:action` are required by Plan 05's Logger
    # JSONL shape.
    #
    # @return [Hash]
    def current_context
      controller = Current.controller
      action = controller.respond_to?(:action_name) ? controller.action_name : nil

      {
        user: Current.user,
        controller: controller&.class&.name,
        action: action,
        client_id: Current.client_id,
        visit: Current.visit,
        request_id: Current.request&.request_id
      }
    end

    # Evaluate {Configuration#track_gate} once per track call, inside
    # the `Current.set` scope so the gate sees the same request the
    # subscribers would. Runs AFTER validation and BEFORE the
    # notification fans out — a falsy return means no subscriber ever
    # sees the event. Unset gate (`nil`) always allows.
    #
    # @param payload [EventPayload]
    # @return [Boolean]
    def track_gate_allows?(payload)
      gate = TrackRelay.config.track_gate
      return true if gate.nil?

      !!gate.call(payload: payload, request: Current.request)
    end

    # Run {EventPayload#validate!} and apply the
    # {Configuration#raise_on_validation_error} gate.
    #
    # Returns truthy when the caller should proceed to instrument and
    # `nil` when validation failed and was swallowed (no instrument).
    #
    # @param payload [EventPayload]
    # @return [Object, nil] truthy on success, `nil` on swallowed failure
    # @raise [ValidationError] when validation fails AND
    #   {Configuration#raise_on_validation_error} is true
    def validate(payload)
      payload.validate!
      payload
    rescue ValidationError => e
      raise if TrackRelay.config.raise_on_validation_error

      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.error("[track_relay] validation failed for #{payload.name.inspect}: #{e.message}")
      end

      nil
    end
  end
end
