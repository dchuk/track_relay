# frozen_string_literal: true

require "active_job"

module TrackRelay
  # ActiveJob-backed async delivery for non-synchronous subscribers.
  #
  # The job receives `[subscriber_class_name, payload_hash]` (because
  # ActiveJob arguments must be GlobalID-serializable, not raw
  # subscriber instances or {EventPayload} objects). On `perform` it
  # reconstructs the {EventPayload} via {EventPayload.from_h} and
  # dispatches to a fresh subscriber instance.
  #
  # **Async loudness mirrors the sync {Dispatcher} contract:** when
  # `safe_deliver` returns a StandardError AND
  # {Configuration#swallow_subscriber_errors} is `false`, the job
  # re-raises after `safe_deliver` has already logged. This lets
  # ActiveJob's normal error path (retry / discard / failed-job queue)
  # surface the failure. Under the `:test` adapter this propagates
  # synchronously through `perform_now`/`perform_later`.
  #
  # The job receives a serialized hash, **not** {Current} state —
  # ActiveJob's Executor clears CurrentAttributes before `perform`, so
  # any context the subscriber needs must already be on
  # `payload.context` (snapshotted at track time by the Instrumenter).
  #
  # ## GA4 retry / discard policy (Plan 02-04)
  #
  # `retry_on TrackRelay::DeliveryRetriableError` covers transient GA4
  # failures (HTTP 5xx, network timeouts, ECONNREFUSED, SocketError).
  # The wait algorithm `:polynomially_longer` produces ~3s, ~18s, ~83s,
  # ~258s with 15% default jitter — appropriate for GA4 since the
  # Measurement Protocol has no strict ordering requirement, sends are
  # idempotent enough for analytics, and GA4's 72-hour event-backdating
  # window means late retries still arrive correctly.
  #
  # `discard_on TrackRelay::DeliveryDiscardableError` covers HTTP 4xx
  # (defensive — Scout §2 confirms GA4 returns 2xx in practice even on
  # malformed payloads, but mapping 4xx to discard is correct in case
  # Google ever changes that contract).
  #
  # ### Why `DEFAULT_GA4_DELIVERY_ATTEMPTS` is a class-local constant
  #
  # `retry_on` runs at class-body load time, **before** any
  # `TrackRelay.configure` block in a host's initializer has had a
  # chance to mutate {TrackRelay.config}. Reading `TrackRelay.config.
  # ga4_delivery_attempts` here would either crash (singleton not yet
  # built) or capture a stale default that the host's initializer is
  # about to overwrite. Pinning the value to a class-local constant
  # sidesteps the load-order hazard entirely. A future minor (Phase 4)
  # can introduce runtime configurability via `self.inherited` /
  # `after_initialize` machinery without breaking this contract.
  class DeliveryJob < ActiveJob::Base
    queue_as :track_relay

    # GA4 retry attempt cap (Plan 02-04). Class-local constant — see
    # the rationale in the class docstring above. Future Phase 4 work
    # may introduce `config.ga4_delivery_attempts` once a safe
    # late-binding path exists; until then, `5` is the contract.
    DEFAULT_GA4_DELIVERY_ATTEMPTS = 5

    retry_on TrackRelay::DeliveryRetriableError,
      wait: :polynomially_longer,
      attempts: DEFAULT_GA4_DELIVERY_ATTEMPTS

    discard_on TrackRelay::DeliveryDiscardableError

    # @param subscriber_class_name [String] fully-qualified subscriber
    #   class name (e.g. `"TrackRelay::Subscribers::Logger"`)
    # @param payload_hash [Hash] result of {EventPayload#to_h}, possibly
    #   round-tripped through JSON (string keys)
    # @return [void]
    def perform(subscriber_class_name, payload_hash)
      subscriber = subscriber_class_name.constantize.new
      payload = EventPayload.from_h(payload_hash)
      result = subscriber.safe_deliver(payload)

      # `safe_deliver` already logged via Rails.logger.error. If the
      # host opts out of swallowing, re-raise so ActiveJob's normal
      # error path surfaces the failure.
      raise result if result.is_a?(StandardError) && !TrackRelay.config.swallow_subscriber_errors
    end
  end
end
