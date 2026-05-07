# frozen_string_literal: true

require "active_support/concern"
require "track_relay/current"

module TrackRelay
  # Controller-side tracking helper.
  #
  # Host applications include this concern in `ApplicationController` (or
  # any controller) to get:
  #
  #   - A `before_action` that populates {Current.controller},
  #     {Current.request}, and {Current.client_id} (the latter derived
  #     from the `_ga` cookie if present) before any action runs. This
  #     means {TrackRelay.track} called inside an action automatically
  #     captures the originating controller / request in
  #     `payload.context`.
  #
  #   - An instance method `track(name, **params)` that delegates to
  #     {TrackRelay.track}. The delegate is sugar — host code can also
  #     call `TrackRelay.track(...)` directly.
  #
  # The concern is NOT auto-included. Host apps include it explicitly,
  # which keeps the gem opt-in and avoids surprising behavior in
  # controllers that don't want tracking. The Phase 4 install generator
  # will wire the include into ApplicationController.
  #
  # ## `client_id` resolver chain
  #
  # The before_action runs the ordered chain at
  # {TrackRelay::Configuration#client_id_resolvers} (default
  # `[ClientId::Ga, ClientId::AhoyVisitor, ClientId::Session]`). The
  # FIRST resolver to return a non-nil value wins; later resolvers are
  # not invoked. Each resolver call is wrapped in `rescue StandardError`
  # so a single misbehaving resolver cannot block client_id resolution
  # — the chain skips it and continues.
  #
  # The default first resolver ({ClientId::Ga}) reproduces Phase 1's
  # `_ga`-cookie parser bit-for-bit, so existing behavior is preserved.
  # Hosts can prepend custom resolvers (e.g. a request-header reader
  # for native-app traffic) via `TrackRelay.config.client_id_resolvers.unshift(...)`.
  module ControllerTracking
    extend ActiveSupport::Concern

    included do
      before_action :_track_relay_set_current
    end

    # Delegate to {TrackRelay.track}. Sugar for in-controller call sites
    # so the host doesn't have to spell `TrackRelay.track` explicitly.
    #
    # @param name [Symbol]
    # @param params [Hash]
    # @return [void]
    def track(name, **params)
      TrackRelay.track(name, **params)
    end

    private

    def _track_relay_set_current
      TrackRelay::Current.controller = self
      TrackRelay::Current.request = request
      TrackRelay::Current.client_id = _resolve_client_id
    end

    # Run the resolver chain in order; return the first non-nil result.
    # Each resolver's `#call` is wrapped in `rescue StandardError` so a
    # broken resolver cannot poison the chain — it simply yields nil and
    # the iteration continues to the next resolver.
    #
    # @return [String, nil]
    def _resolve_client_id
      TrackRelay.config.client_id_resolvers.each do |resolver|
        result = begin
          resolver.call(controller: self)
        rescue => e
          Rails.logger&.warn(
            "[track_relay] client_id resolver #{resolver.class} raised " \
            "#{e.class}: #{e.message} — skipping"
          )
          nil
        end

        return result unless result.nil?
      end
      nil
    end
  end
end
