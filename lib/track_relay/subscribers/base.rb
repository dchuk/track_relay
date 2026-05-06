# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/class/attribute"

module TrackRelay
  module Subscribers
    # Base class for all track_relay subscribers.
    #
    # Each subscriber receives an {EventPayload} via {#handle}, which
    # routes to one of two paths:
    #
    #   - **sync** — `safe_deliver(payload)` is invoked inline on the
    #     calling thread. Used when the subclass calls {.synchronous!}
    #     or when {Configuration#force_synchronous} is `true`.
    #   - **async** — {DeliveryJob} is enqueued with the subscriber's
    #     class name and the payload's serialized form. The job calls
    #     `safe_deliver` on a fresh instance when it eventually runs.
    #
    # **Error contract (locked in 01-CONTEXT.md, 01-05-PLAN.md):**
    # `safe_deliver` returns `nil` on success or the StandardError on
    # failure — it NEVER re-raises inline. The {Dispatcher} collects
    # those returns during fan-out and re-raises the first one
    # afterwards, but only when {Configuration#swallow_subscriber_errors}
    # is `false`. This guarantees that one bad subscriber never blocks
    # peers, while still letting dev/test surface failures loudly once
    # everyone has had their chance.
    class Base
      class_attribute :synchronous, default: false

      # Mark this subclass as synchronous. Calls to {#handle} will run
      # `safe_deliver` inline rather than enqueueing a {DeliveryJob}.
      #
      # @return [Boolean] `true`
      def self.synchronous!
        self.synchronous = true
      end

      # Implement in subclasses to receive an {EventPayload}.
      #
      # @param payload [EventPayload]
      # @raise [NotImplementedError] when not overridden
      # @return [void]
      def deliver(payload)
        raise NotImplementedError, "#{self.class.name} must implement #deliver(payload)"
      end

      # Route `payload` to the sync or async path.
      #
      # **Returns:** `nil` on success, the StandardError on a sync
      # failure, or `nil` on the async path (the job runs later — its
      # eventual failure mode is handled inside {DeliveryJob#perform}).
      #
      # @param payload [EventPayload]
      # @return [nil, StandardError]
      def handle(payload)
        if self.class.synchronous || TrackRelay.config.force_synchronous
          safe_deliver(payload)
        else
          DeliveryJob.perform_later(self.class.name, payload.to_h)
          nil
        end
      end

      # Wrap {#deliver} with the per-subscriber rescue.
      #
      # Returns `nil` on success or the StandardError on failure. ALWAYS
      # logs the failure (via `Rails.logger.error`) when running under
      # Rails. NEVER re-raises — the Dispatcher (or {DeliveryJob}) makes
      # the loudness decision based on
      # {Configuration#swallow_subscriber_errors}.
      #
      # @param payload [EventPayload]
      # @return [nil, StandardError]
      def safe_deliver(payload)
        deliver(payload)
        nil
      rescue => e
        log_failure(e)
        e
      end

      private

      def log_failure(e)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.error(
          "[track_relay] subscriber=#{self.class.name} failed: #{e.class}: #{e.message}\n" \
          "#{Array(e.backtrace).first(5).join("\n")}"
        )
      end
    end
  end
end
