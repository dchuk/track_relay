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

      # Subscriber-side event-name filters (Plan 02-01). Both default to
      # `nil`, which means "no filter — receive every event" (Phase 1
      # behavior). When set, they are stored as `Set<Symbol>` by the
      # {.filter} class DSL and consulted by {#filtered?} at the top of
      # {#handle}, BEFORE the sync/async branch.
      #
      # The class-level value is the default for instances of this
      # subscriber; {TrackRelay.subscribe} (Plan 02-01) overrides per
      # instance via the singleton-class accessors so two instances of
      # the same subscriber can carry different filters without
      # cross-talk.
      class_attribute :only_events, default: nil
      class_attribute :except_events, default: nil

      # Mark this subclass as synchronous. Calls to {#handle} will run
      # `safe_deliver` inline rather than enqueueing a {DeliveryJob}.
      #
      # @return [Boolean] `true`
      def self.synchronous!
        self.synchronous = true
      end

      # Class-level DSL for declaring an event-name filter.
      #
      #   class MySubscriber < TrackRelay::Subscribers::Base
      #     filter only: %i[purchase sign_up]
      #   end
      #
      # `only:` and `except:` are mutually exclusive in spirit but not
      # enforced as such — if both are set, `only:` wins (an event must
      # be in the allow-list AND not in the deny-list to pass). Pass
      # `nil` to clear a previously set filter.
      #
      # @param only [Array<Symbol, String>, nil] allow-list; if non-nil,
      #   only events whose name is in this set are delivered.
      # @param except [Array<Symbol, String>, nil] deny-list; events in
      #   this set are dropped.
      # @return [void]
      def self.filter(only: nil, except: nil)
        self.only_events = coerce_event_set(only)
        self.except_events = coerce_event_set(except)
      end

      # Coerce a filter input (Array<Symbol|String>, Set, single Symbol,
      # or nil) into a `Set<Symbol>` or `nil`. Internal helper shared by
      # the class-level {.filter} DSL and the per-instance override path
      # ({Base#set_filter_overrides!}, used by {TrackRelay.subscribe}).
      #
      # @param value [Array, Set, Symbol, String, nil]
      # @return [Set<Symbol>, nil]
      def self.coerce_event_set(value)
        return nil if value.nil?
        Set.new(Array(value).map(&:to_sym))
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
      # **Filter gate (Plan 02-01):** if `only_events` / `except_events`
      # exclude `payload.name`, return `nil` immediately — BEFORE the
      # sync/async branch and BEFORE `safe_deliver`'s rescue boundary.
      # A filtered event with a buggy `#deliver` therefore neither runs
      # nor logs.
      #
      # @param payload [EventPayload]
      # @return [nil, StandardError]
      def handle(payload)
        return nil if filtered?(payload.name.to_sym)

        payload = prepare(payload)
        return nil if payload.nil?

        if self.class.synchronous || TrackRelay.config.force_synchronous
          safe_deliver(payload)
        else
          DeliveryJob.perform_later(self.class.name, payload.to_h)
          nil
        end
      end

      # Notification-time hook, called by {#handle} after the event-name
      # filter and BEFORE the sync/async branch — i.e. while the request
      # ({Current.request}) is still in scope, which is gone by the time
      # an async {DeliveryJob} runs.
      #
      # Subclasses override this to gate delivery (return `nil` to drop
      # the event silently — no job, no `deliver`) or to swap in an
      # enriched **copy** of the payload. The same payload object fans
      # out to every subscriber, so implementations must never mutate
      # `payload` — build a new {EventPayload} instead.
      #
      # @param payload [EventPayload]
      # @return [EventPayload, nil] the payload to deliver, or `nil` to drop
      def prepare(payload)
        payload
      end

      # Wrap {#deliver} with the per-subscriber rescue.
      #
      # Returns `nil` on success or the StandardError on failure. ALWAYS
      # logs the failure (via `Rails.logger.error`) when running under
      # Rails. NEVER re-raises arbitrary `StandardError`s — the
      # Dispatcher (or {DeliveryJob}) makes the loudness decision based
      # on {Configuration#swallow_subscriber_errors}.
      #
      # **REQ-23 carve-out (Plan 02-04):**
      # {TrackRelay::DeliveryRetriableError} and
      # {TrackRelay::DeliveryDiscardableError} are RE-RAISED unconditionally
      # — even when `swallow_subscriber_errors = true` (the production
      # default). ActiveJob's `retry_on` / `discard_on` macros only fire
      # on raised exceptions; without this carve-out the GA4 retry/discard
      # policy in {DeliveryJob} would be silently broken in production
      # because `safe_deliver` would catch the exception, return it as a
      # value, and the job would think delivery succeeded.
      #
      # The carve-out is INTENTIONALLY NARROW: arbitrary `StandardError`s
      # still flow through the existing log-and-return path — REQ-23's
      # blanket-rescue contract is preserved for everything outside of
      # the typed retry/discard exception classes.
      #
      # @param payload [EventPayload]
      # @return [nil, StandardError]
      def safe_deliver(payload)
        deliver(payload)
        nil
      rescue TrackRelay::DeliveryRetriableError, TrackRelay::DeliveryDiscardableError
        # Carve-out: ActiveJob retry_on/discard_on must see these.
        # Do NOT log here — the DeliveryJob's retry path will log on
        # eventual exhaustion, and the discard path is an intentional
        # drop. Logging on every retry attempt would spam the log with
        # transient blips that resolve on retry.
        raise
      rescue => e
        log_failure(e)
        e
      end

      # Set per-instance `only:` / `except:` filter overrides on this
      # subscriber. Used by {TrackRelay.subscribe} so a single subscriber
      # class can be registered multiple times with different filters.
      #
      # Each non-nil argument is coerced via {Base.coerce_event_set} and
      # stored on the instance's singleton class so it does not bleed
      # across instances or mutate the class-level defaults declared via
      # {.filter}. Passing `nil` for either argument leaves that override
      # untouched (the instance falls through to the class default).
      #
      # @param only [Array<Symbol, String>, Set, nil]
      # @param except [Array<Symbol, String>, Set, nil]
      # @return [self]
      def set_filter_overrides!(only: nil, except: nil)
        unless only.nil?
          singleton_class.instance_variable_set(:@only_events_override, self.class.coerce_event_set(only))
        end
        unless except.nil?
          singleton_class.instance_variable_set(:@except_events_override, self.class.coerce_event_set(except))
        end
        self
      end

      # Read the effective `only:` filter for this instance — the
      # singleton override (set by {TrackRelay.subscribe}) when present,
      # otherwise the class-level default declared via {.filter}.
      #
      # @return [Set<Symbol>, nil]
      def only_events
        if singleton_class.instance_variable_defined?(:@only_events_override)
          singleton_class.instance_variable_get(:@only_events_override)
        else
          self.class.only_events
        end
      end

      # Read the effective `except:` filter for this instance — the
      # singleton override (set by {TrackRelay.subscribe}) when present,
      # otherwise the class-level default declared via {.filter}.
      #
      # @return [Set<Symbol>, nil]
      def except_events
        if singleton_class.instance_variable_defined?(:@except_events_override)
          singleton_class.instance_variable_get(:@except_events_override)
        else
          self.class.except_events
        end
      end

      private

      # @param event_name [Symbol] coerced from `payload.name`
      # @return [Boolean] true ⇒ drop this event before delivery
      def filtered?(event_name)
        only = only_events
        except = except_events
        return false if only.nil? && except.nil?
        return true if only && !only.include?(event_name)
        return true if except&.include?(event_name)
        false
      end

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
