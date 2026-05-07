# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "track_relay/errors"
require "track_relay/subscribers/base"
require "track_relay/validators/ga4_constraints"

module TrackRelay
  module Subscribers
    # GA4 Measurement Protocol server-side subscriber (REQ-08, REQ-11).
    #
    # POSTs each event to Google Analytics 4 via the Measurement Protocol
    # endpoint:
    #
    #   POST https://www.google-analytics.com/mp/collect
    #     ?measurement_id=G-XXXXXXXXXX
    #     &api_secret=<secret>
    #   Content-Type: application/json
    #   Body: { client_id:, user_id:, timestamp_micros:, events: [{name:, params:}] }
    #
    # Async by default — `#deliver` runs inside a {DeliveryJob} (loadbalanced
    # via ActiveJob). Hosts that need inline delivery (e.g. unit-test
    # determinism, low-traffic ingestion) can call {.synchronous!} per
    # REQ-11.
    #
    # ## Configuration
    #
    # Read from {TrackRelay::Configuration} at *delivery time* (NOT at
    # class-body load time) so credentials lambdas / late-bound configs
    # work:
    #
    #   - `config.ga4_measurement_id` — `G-XXXXXXXXXX`
    #   - `config.ga4_api_secret`     — per-stream MP secret
    #   - `config.ga4_use_eu_endpoint` — when `true`, post to
    #     `https://region1.google-analytics.com/mp/collect`
    #
    # When `ga4_measurement_id` or `ga4_api_secret` is `nil`, `#deliver`
    # emits a single `Rails.logger.warn` and returns without raising —
    # gem-loaded-but-not-configured apps must not crash.
    #
    # ## Error contract
    #
    # `#deliver` raises:
    #
    #   - {TrackRelay::DeliveryRetriableError} on transient failures
    #     (HTTP 5xx, `Net::OpenTimeout`, `Net::ReadTimeout`,
    #     `Errno::ECONNREFUSED`, `SocketError`). Mapped to
    #     `retry_on` in {DeliveryJob}.
    #   - {TrackRelay::DeliveryDiscardableError} on permanent failures
    #     (HTTP 4xx — defensive: GA4 returns 2xx in practice even on
    #     malformed payloads). Mapped to `discard_on` in {DeliveryJob}.
    #   - {TrackRelay::Ga4ConstraintError} when call-time payload
    #     validation fails AND `config.raise_on_validation_error` is
    #     `true` (dev/test). In production (`raise_on_validation_error
    #     = false`) the violation is logged via `Rails.logger.warn` and
    #     the POST is skipped.
    #
    # ## Why typed retriable/discardable exceptions?
    #
    # ActiveJob's `retry_on`/`discard_on` macros only fire on raised
    # exceptions, not returned values. {Subscribers::Base#safe_deliver}
    # normally rescues any `StandardError` and returns it (the REQ-23
    # blanket-rescue contract), so a 5xx retry would never reach the
    # job's retry policy. {Subscribers::Base} therefore carves these two
    # exception classes out of the rescue: it re-raises them so
    # {DeliveryJob} can map them to `retry_on`/`discard_on`. See
    # `test/unit/subscribers/base_retry_passthrough_test.rb`.
    class Ga4MeasurementProtocol < Base
      # GA4 production endpoint (US/global region).
      ENDPOINT_URL = "https://www.google-analytics.com/mp/collect"

      # GA4 EU-region endpoint, selected via `config.ga4_use_eu_endpoint = true`.
      ENDPOINT_URL_EU = "https://region1.google-analytics.com/mp/collect"

      # Net::HTTP open timeout (TCP connect).
      OPEN_TIMEOUT_SECONDS = 5

      # Net::HTTP read timeout (response wait).
      READ_TIMEOUT_SECONDS = 10

      # GA4-reserved param-name prefixes. Per Scout §2 / REQ-27, params
      # starting with these prefixes must not be sent — GA4 silently
      # drops them.
      RESERVED_PARAM_PREFIXES = %w[firebase_ ga_ google_].freeze

      # POST `payload` to the GA4 Measurement Protocol endpoint.
      #
      # See class docs for the full configuration / error contract.
      #
      # @param payload [TrackRelay::EventPayload]
      # @raise [TrackRelay::DeliveryRetriableError] on 5xx or network blip
      # @raise [TrackRelay::DeliveryDiscardableError] on 4xx
      # @raise [TrackRelay::Ga4ConstraintError] on call-time payload
      #   violation when `raise_on_validation_error` is true
      # @return [void]
      def deliver(payload)
        config = TrackRelay.config
        measurement_id = config.ga4_measurement_id
        api_secret = config.ga4_api_secret

        if measurement_id.nil? || api_secret.nil?
          warn_missing_credentials(measurement_id, api_secret)
          return
        end

        return unless validate_ga4_payload!(payload)

        post_to_ga4(payload, measurement_id, api_secret, config.ga4_use_eu_endpoint)
      end

      private

      # Run call-time payload constraint checks (REQ-27 split). Returns
      # `true` when delivery should proceed, `false` when a constraint
      # was violated AND `raise_on_validation_error` is `false` (the
      # subscriber logs and skips the POST). Raises
      # {Ga4ConstraintError} when `raise_on_validation_error` is `true`.
      def validate_ga4_payload!(payload)
        if payload.params.size > Validators::Ga4Constraints::MAX_PARAMS_PER_EVENT
          msg = "GA4 payload for #{payload.name.inspect} has #{payload.params.size} params; GA4 max is #{Validators::Ga4Constraints::MAX_PARAMS_PER_EVENT}"
          return handle_constraint_violation(msg)
        end

        payload.params.each_key do |key|
          as_str = key.to_s
          next unless RESERVED_PARAM_PREFIXES.any? { |prefix| as_str.start_with?(prefix) }

          msg = "Param #{key.inspect} on event #{payload.name.inspect} uses a GA4-reserved prefix (one of #{RESERVED_PARAM_PREFIXES.inspect})"
          return false unless handle_constraint_violation(msg)
        end

        true
      end

      # Honor the {Configuration#raise_on_validation_error} gate.
      # Returns `false` (skip the POST) when the violation is logged;
      # raises {Ga4ConstraintError} otherwise. Mirrors the pattern in
      # {Instrumenter#validate}.
      def handle_constraint_violation(msg)
        if TrackRelay.config.raise_on_validation_error
          raise Ga4ConstraintError, msg
        end

        Rails.logger&.warn("[track_relay] #{msg}")
        false
      end

      def post_to_ga4(payload, measurement_id, api_secret, use_eu)
        uri = build_endpoint_uri(measurement_id, api_secret, use_eu)
        body = build_request_body(payload)
        response = http_post(uri, body)
        map_response_to_exception!(response)
      end

      def build_endpoint_uri(measurement_id, api_secret, use_eu)
        base = use_eu ? ENDPOINT_URL_EU : ENDPOINT_URL
        uri = URI(base)
        uri.query = URI.encode_www_form(
          measurement_id: measurement_id,
          api_secret: api_secret
        )
        uri
      end

      def build_request_body(payload)
        body = {
          client_id: client_id_for(payload),
          timestamp_micros: timestamp_micros(payload),
          events: [{
            name: payload.name.to_s,
            params: stringify_params(payload.params)
          }]
        }

        user_id = payload.context[:user_id] || payload.context["user_id"]
        body[:user_id] = user_id.to_s if user_id

        JSON.generate(body)
      end

      # GA4 requires a `client_id` even when `payload.context[:client_id]`
      # is nil (e.g. server-side events with no `_ga` cookie). Generate a
      # deterministic-shaped fallback (`<rand>.<unix_ts>`) so the POST
      # still goes through — the `client_id` is the cohort identifier in
      # GA4, not a true per-user key.
      def client_id_for(payload)
        explicit = payload.context[:client_id] || payload.context["client_id"]
        return explicit if explicit && !explicit.to_s.empty?

        "#{SecureRandom.random_number(2_147_483_647)}.#{Time.now.to_i}"
      end

      def timestamp_micros(payload)
        ts = payload.timestamp || Time.now
        (ts.to_f * 1_000_000).to_i
      end

      def stringify_params(params)
        out = {}
        params.each { |k, v| out[k.to_s] = v }
        out
      end

      def http_post(uri, body)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = OPEN_TIMEOUT_SECONDS
        http.read_timeout = READ_TIMEOUT_SECONDS

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request.body = body

        http.request(request)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError => e
        raise DeliveryRetriableError, "GA4 network error: #{e.class}: #{e.message}"
      end

      # Map the response code to retry/discard semantics. GA4 returns 2xx
      # in practice for both successful and malformed payloads (Scout §2
      # line 211), so 4xx is defensive coverage in case Google ever
      # changes the contract.
      def map_response_to_exception!(response)
        code = response.code.to_i
        return if code.between?(200, 299)

        message = "GA4 returned HTTP #{code}: #{response.body.to_s[0, 200]}"

        if code.between?(500, 599)
          raise DeliveryRetriableError, message
        else
          raise DeliveryDiscardableError, message
        end
      end

      def warn_missing_credentials(measurement_id, api_secret)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

        missing = []
        missing << "ga4_measurement_id" if measurement_id.nil?
        missing << "ga4_api_secret" if api_secret.nil?
        Rails.logger.warn(
          "[track_relay] Ga4MeasurementProtocol skipping delivery — missing config: #{missing.join(", ")}"
        )
      end
    end
  end
end
