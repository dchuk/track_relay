# frozen_string_literal: true

module TrackRelay
  module ClientId
    # Resolver that extracts the GA4-shaped `client_id` from the host
    # app's `_ga` cookie.
    #
    # Default position-0 entry in {Configuration#client_id_resolvers}.
    # Reproduces Phase 01's `_track_relay_client_id_from_cookie` parser
    # bit-for-bit so existing behavior is preserved when the resolver
    # chain is enabled.
    #
    # ## `_ga` cookie format
    #
    # The `_ga` cookie ships with format
    # `GA1.<version>.<random_int>.<unix_ts>` (four dot-separated
    # segments). The GA4 Measurement Protocol expects the client_id to
    # be the last two segments joined with a dot — e.g. cookie
    # `"GA1.2.860784081.1732738496"` yields client_id
    # `"860784081.1732738496"`.
    #
    # The parser always takes the last two segments (`parts[-2..]`)
    # rather than the 3rd/4th, so it is robust against:
    #   - Custom server-side cookie writers that prepend extra segments
    #   - Future Google rollouts that change the prefix segment count
    #
    # Cookies with fewer than four segments are treated as malformed
    # and yield `nil` (callers should fall through to the next resolver
    # in the chain).
    class Ga
      # Parse a raw `_ga` cookie value into a GA4 client_id.
      #
      # This is THE canonical `_ga` parse rule — the resolver chain
      # ({#call}) and the browser-proof delivery gate
      # ({Subscribers::Ga4MeasurementProtocol#prepare}) both delegate
      # here so the "fewer than four segments = malformed = nil"
      # posture is defined exactly once.
      #
      # @param cookie_value [String, nil] raw `_ga` cookie value
      # @return [String, nil] the parsed GA4 client_id, or `nil` when
      #   the value is missing/empty/malformed.
      def self.parse(cookie_value)
        return nil if cookie_value.nil? || cookie_value.empty?

        parts = cookie_value.split(".")
        return nil if parts.size < 4

        "#{parts[-2]}.#{parts[-1]}"
      end

      # Extract and parse the `_ga` cookie from a request-like object.
      #
      # @param request [#cookies, nil] any object exposing
      #   `request.cookies["_ga"]` (e.g. an `ActionDispatch::Request`).
      # @return [String, nil]
      def self.from_request(request)
        parse(request&.cookies&.[]("_ga"))
      end

      # @param controller [#request] any object exposing
      #   `controller.request.cookies["_ga"]`. Typically an
      #   `ActionController::Base` instance from
      #   {ControllerTracking#_resolve_client_id}.
      # @return [String, nil] the parsed GA4 client_id, or `nil` when the
      #   cookie is missing/empty/malformed.
      def call(controller:, **)
        self.class.from_request(controller&.request)
      end
    end
  end
end
