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
  # ## `_ga` cookie parsing
  #
  # GA's `_ga` cookie has the format `GA1.{version}.{client_id}` where
  # `client_id` is two dot-separated segments
  # (`{random_id}.{first_visit_timestamp}`). The full cookie therefore
  # has at least four dot-separated segments; this concern extracts the
  # last two as the GA4-shaped `client_id`. Malformed cookies (fewer
  # than four segments) yield `nil` so downstream code can rely on the
  # invariant "client_id is either nil or a valid GA4 client_id".
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
      TrackRelay::Current.client_id = _track_relay_client_id_from_cookie
    end

    def _track_relay_client_id_from_cookie
      ga_cookie = cookies["_ga"]
      return nil if ga_cookie.nil? || ga_cookie.empty?

      # _ga cookie format: "GA1.2.123456789.1234567890" — last two
      # segments form the GA4 client_id.
      parts = ga_cookie.split(".")
      return nil if parts.size < 4

      "#{parts[-2]}.#{parts[-1]}"
    end
  end
end
