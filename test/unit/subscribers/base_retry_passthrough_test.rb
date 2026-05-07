# frozen_string_literal: true

require "test_helper"

# Pin the Plan 02-04 carve-out on {TrackRelay::Subscribers::Base#safe_deliver}.
#
# REQ-23 (Phase 1) declares that `safe_deliver` rescues every
# `StandardError` and returns the exception object as a value when
# `config.swallow_subscriber_errors = true` (the production default).
# That blanket rescue is the *primary* contract — one bad subscriber
# never blocks peers in dev/test loud mode either, because the
# Dispatcher does its own collect-then-reraise *after* fan-out.
#
# Plan 02-04 needs a NARROW exception to that rule: ActiveJob's
# `retry_on` and `discard_on` macros only fire on **raised** exceptions
# (the Job's `#perform` must propagate them up). If the GA4 subscriber
# raises {DeliveryRetriableError} on a 5xx response and `safe_deliver`
# catches and returns it, the {DeliveryJob} sees a returned-value, not
# a raised exception, and the entire retry policy is silently broken
# in production — the only environment where `swallow_subscriber_errors`
# defaults to `true`.
#
# The fix is whitelist-style: rescue {DeliveryRetriableError} and
# {DeliveryDiscardableError} FIRST and re-raise. Then fall through to
# the existing `rescue => e ; log_failure ; e` branch for everything
# else.
#
# Three behaviors verified here:
#
#   1. `DeliveryRetriableError` re-raises through `safe_deliver` even
#      when `swallow_subscriber_errors = true`.
#   2. `DeliveryDiscardableError` re-raises identically.
#   3. Arbitrary `StandardError` is STILL swallowed (returned as a
#      value) in `swallow_subscriber_errors = true` — the carve-out
#      didn't accidentally widen REQ-23's contract.
class TrackRelay::Subscribers::BaseRetryPassthroughTest < ActiveSupport::TestCase
  # Tiny in-memory subscriber whose #deliver raises a configurable
  # exception. One subclass per test so synchronous! flag and any
  # other class_attribute settings cannot leak between tests.
  class RaisingBase < TrackRelay::Subscribers::Base
    synchronous!

    cattr_accessor :exception_to_raise

    def deliver(_payload)
      raise self.class.exception_to_raise
    end
  end

  setup do
    # Pin the production-default state: blanket-rescue swallow ON.
    TrackRelay.config.swallow_subscriber_errors = true
    @log_io = StringIO.new
    @prior_logger = Rails.logger
    Rails.logger = ::Logger.new(@log_io)
  end

  teardown do
    Rails.logger = @prior_logger
  end

  def build_payload
    TrackRelay::EventPayload.untyped(name: :anything, params: {}, context: {})
  end

  def make_subscriber(exception)
    klass = Class.new(RaisingBase)
    klass.exception_to_raise = exception
    klass.new
  end

  # ---- carve-out: DeliveryRetriableError re-raises ------------------

  test "DeliveryRetriableError escapes safe_deliver even with swallow_subscriber_errors=true" do
    sub = make_subscriber(TrackRelay::DeliveryRetriableError.new("503 from GA4"))

    err = assert_raises(TrackRelay::DeliveryRetriableError) do
      sub.safe_deliver(build_payload)
    end
    assert_equal "503 from GA4", err.message
  end

  test "DeliveryRetriableError carve-out does NOT log via log_failure" do
    # The retry path will eventually log on exhaustion; logging on
    # every transient retry would be noise.
    sub = make_subscriber(TrackRelay::DeliveryRetriableError.new("blip"))

    assert_raises(TrackRelay::DeliveryRetriableError) do
      sub.safe_deliver(build_payload)
    end

    refute_match(/\[track_relay\] subscriber=/, @log_io.string,
      "carve-out path must NOT call log_failure on retry/discard exceptions")
  end

  # ---- carve-out: DeliveryDiscardableError re-raises ----------------

  test "DeliveryDiscardableError escapes safe_deliver even with swallow_subscriber_errors=true" do
    sub = make_subscriber(TrackRelay::DeliveryDiscardableError.new("400 bad request"))

    err = assert_raises(TrackRelay::DeliveryDiscardableError) do
      sub.safe_deliver(build_payload)
    end
    assert_equal "400 bad request", err.message
  end

  # ---- arbitrary StandardError still swallowed ---------------------

  test "arbitrary StandardError IS still swallowed (REQ-23 contract preserved)" do
    sub = make_subscriber(RuntimeError.new("kaboom"))

    result = nil
    assert_nothing_raised do
      result = sub.safe_deliver(build_payload)
    end

    assert_kind_of RuntimeError, result, "REQ-23: arbitrary errors return as values"
    assert_equal "kaboom", result.message
    assert_match(/\[track_relay\] subscriber=/, @log_io.string,
      "non-carve-out path still logs via log_failure")
  end

  test "ArgumentError still swallowed even though it inherits from StandardError" do
    sub = make_subscriber(ArgumentError.new("bad arg"))

    result = sub.safe_deliver(build_payload)

    assert_kind_of ArgumentError, result
  end

  # ---- carve-out works regardless of swallow_subscriber_errors=false ----

  test "DeliveryRetriableError re-raises with swallow_subscriber_errors=false too" do
    # In dev/test loud mode the carve-out is redundant (all StandardErrors
    # eventually re-raise via the Dispatcher's collect-then-reraise),
    # but pinning the behavior anyway documents that the carve-out is
    # idempotent: it does not depend on the swallow flag.
    TrackRelay.config.swallow_subscriber_errors = false
    sub = make_subscriber(TrackRelay::DeliveryRetriableError.new("503"))

    assert_raises(TrackRelay::DeliveryRetriableError) do
      sub.safe_deliver(build_payload)
    end
  end

  # ---- subclasses of the carve-out classes also re-raise ------------

  test "subclasses of DeliveryRetriableError also re-raise (Class<= matching)" do
    custom_subclass = Class.new(TrackRelay::DeliveryRetriableError)
    sub = make_subscriber(custom_subclass.new("custom retry"))

    err = assert_raises(custom_subclass) do
      sub.safe_deliver(build_payload)
    end
    assert_equal "custom retry", err.message
  end
end
