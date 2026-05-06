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
  class DeliveryJob < ActiveJob::Base
    queue_as :track_relay

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
