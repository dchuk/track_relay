# frozen_string_literal: true

require "track_relay/current"
require "track_relay/subscribers/base"

module TrackRelay
  module Subscribers
    # Server-side Ahoy subscriber (REQ-09).
    #
    # Routes catalog events through Ahoy's only public tracking surface
    # — `controller.ahoy.track(name, properties)` — by reading
    # {TrackRelay::Current.controller} on the synchronous request
    # thread. When no controller is in scope (background job, rake
    # task, console), or the host application does not include
    # `Ahoy::Controller` in its `ApplicationController`, the subscriber
    # logs a warning and skips delivery — it does NOT raise, does NOT
    # enqueue a {DeliveryJob}, and does NOT touch any internal Ahoy
    # API.
    #
    # ## Why synchronous (not async like GA4)
    #
    # `Ahoy::Tracker` is bound to the live request — it wraps the
    # controller's cookie jar and visit lifecycle. By the time a
    # {DeliveryJob} runs, `Rails.application.executor.wrap` has
    # already cleared {ActiveSupport::CurrentAttributes}, so
    # `Current.controller` is nil and the live tracker instance is
    # unreachable. {.synchronous!} therefore opts the subscriber into
    # inline delivery on the request thread — `#handle` calls
    # `safe_deliver(payload)` directly instead of enqueueing a job.
    #
    # `tracker.track` is an in-process database write (it calls
    # `@store.track_event(data)` which does `event_model.create!` or
    # equivalent), not a network call, so synchronous delivery adds
    # negligible request overhead and matches how Ahoy itself works
    # (Ahoy::Trackable wires `track` as an inline before_action helper).
    #
    # ## Why no `require "ahoy"`
    #
    # The subscriber must load cleanly in non-Ahoy host applications
    # (the gem ships with the file in `lib/track_relay.rb`'s require
    # manifest unconditionally). Duck-typing via
    # `controller.respond_to?(:ahoy, true)` handles the absent-Ahoy
    # case without a top-level require — the same pattern used by
    # {ClientId::AhoyVisitor}.
    #
    # ## Why no `Ahoy::Event.create!` / `Ahoy::Tracker.new`
    #
    # `Ahoy::Tracker` is the sole public tracking surface. Internal
    # APIs (`Ahoy::Event.create!`, `Ahoy::Visit#track` — which does NOT
    # exist on the visit model) are off-limits because they bypass
    # Ahoy's bot-exclusion store, user-method config, and visit
    # association logic. The subscriber dispatches via
    # `controller.ahoy.track(name, properties)` only.
    #
    # ## Skip conditions
    #
    # All three skip paths log a `Rails.logger.warn` line of the form
    # `[track_relay] Ahoy subscriber skipping delivery — <reason>` and
    # `return` from {#deliver}. They MUST NOT raise — host applications
    # that boot without Ahoy or call `TrackRelay.track` from a job
    # must not crash.
    #
    # 1. `Current.controller` is nil — job, rake, or console context.
    # 2. The controller does not `respond_to?(:ahoy, true)` —
    #    `Ahoy::Controller` was never `include`d.
    # 3. `controller.ahoy` returns nil — defensive coverage for a
    #    controller that has the helper but no live tracker yet.
    class Ahoy < Base
      synchronous!

      # Dispatch `payload` to `controller.ahoy.track` when a live
      # controller with an Ahoy tracker is in scope. Skip-and-warn
      # otherwise.
      #
      # @param payload [TrackRelay::EventPayload]
      # @return [void]
      def deliver(payload)
        controller = TrackRelay::Current.controller

        unless controller&.respond_to?(:ahoy, true)
          log_skip("no controller or ahoy tracker in context")
          return
        end

        tracker = controller.ahoy

        unless tracker
          log_skip("controller.ahoy returned nil")
          return
        end

        tracker.track(payload.name.to_s, payload.params)
      end

      private

      # Mirror of {Subscribers::Ga4MeasurementProtocol#warn_missing_credentials}
      # — guarded `Rails.logger.warn` so the subscriber stays callable
      # in non-Rails contexts (e.g. plain `require "track_relay"` from
      # a script).
      #
      # @param reason [String]
      # @return [void]
      def log_skip(reason)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn("[track_relay] Ahoy subscriber skipping delivery — #{reason}")
      end
    end
  end
end
