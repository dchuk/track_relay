# frozen_string_literal: true

require "test_helper"

# Unit coverage for {TrackRelay::Subscribers::Ahoy} — Plan 03-01.
#
# Contract under test (per `must_haves` in 03-01-PLAN.md):
#
# - **Synchronous dispatch:** `synchronous!` flag opts the subscriber
#   into inline delivery — `handle` calls `safe_deliver` on the request
#   thread instead of enqueueing a {DeliveryJob}. Reason:
#   `Current.controller` is a live controller instance and is gone by
#   the time a job runs (Rails Executor clears `CurrentAttributes`
#   before job run).
#
# - **Duck-typed Ahoy integration:** the subscriber does NOT
#   `require "ahoy"`. It probes `controller.respond_to?(:ahoy, true)`
#   and dispatches via `controller.ahoy.track(name, params)` — Ahoy's
#   ONLY public tracking surface. Internal Ahoy APIs
#   (`Ahoy::Event.create!`, `Ahoy::Tracker.new`) are forbidden.
#
# - **Skip-not-raise:** when `Current.controller` is nil OR controller
#   does not `respond_to?(:ahoy, true)` OR `controller.ahoy` returns
#   nil, the subscriber MUST log a warning via `Rails.logger.warn` and
#   `return` — no raise, no enqueue, no Ahoy API call.
#
# - **Event-name coercion:** catalog Symbols (e.g. `:purchase`) are
#   coerced to Strings before reaching `tracker.track`.
#
# - **Filter gate runs BEFORE deliver:** {Subscribers::Base#handle}
#   short-circuits via `filtered?` at the top, so a filtered event
#   never reaches `tracker.track`. The filter test must therefore call
#   `subscriber.handle(payload)`, not `safe_deliver` directly (which
#   would bypass the filter).
#
# Tests use a stubbed tracker (Minitest::Mock or
# `define_singleton_method(:ahoy)` on a plain Object) — they do NOT
# instantiate a real `Ahoy::Tracker`. Reason:
# `Ahoy::BaseStore#exclude?` checks for bots and `Rails::HealthController`
# and behaves unpredictably in the test harness without a real request.
# Stubbing isolates the subscriber contract.
class TrackRelay::Subscribers::AhoyTest < ActiveSupport::TestCase
  setup do
    # Swap Rails.logger BEFORE instantiating the subscriber so a missing
    # `TrackRelay::Subscribers::Ahoy` constant during RED phase does not
    # leave `@prior_logger` unset and let teardown nil out Rails.logger
    # for all downstream tests in the run.
    @log_io = StringIO.new
    @prior_logger = Rails.logger
    Rails.logger = ::Logger.new(@log_io)
    @subscriber = TrackRelay::Subscribers::Ahoy.new
  end

  teardown do
    Rails.logger = @prior_logger
    TrackRelay::Current.controller = nil
  end

  def build_payload(name, params = {})
    TrackRelay::EventPayload.untyped(name: name, params: params, context: {})
  end

  # Build a controller-like double whose `ahoy` method returns the
  # supplied tracker. Uses `define_singleton_method` so
  # `respond_to?(:ahoy, true)` returns true (the duck-typing precedent
  # from `lib/track_relay/client_id/ahoy_visitor.rb`).
  def build_controller_with_tracker(tracker)
    controller = Object.new
    controller.define_singleton_method(:ahoy) { tracker }
    controller
  end

  # ---- Happy path: controller.ahoy.track is called -------------------

  test "dispatches via controller.ahoy.track when controller is present" do
    mock_tracker = Minitest::Mock.new
    mock_tracker.expect(:track, true, ["purchase", {value: 9.99}])
    TrackRelay::Current.controller = build_controller_with_tracker(mock_tracker)

    result = @subscriber.safe_deliver(build_payload(:purchase, {value: 9.99}))

    assert_nil result, "safe_deliver returns nil on success"
    assert mock_tracker.verify
  end

  # ---- Skip path: controller does not respond to :ahoy ---------------

  test "skips and warns when controller does not respond_to?(:ahoy)" do
    # Plain Object — no ahoy method. respond_to?(:ahoy, true) is false.
    TrackRelay::Current.controller = Object.new

    result = @subscriber.safe_deliver(build_payload(:purchase))

    assert_nil result
    assert_match(
      /Ahoy subscriber skipping delivery — no controller or ahoy tracker in context/,
      @log_io.string
    )
  end

  # ---- Skip path: no Current.controller (job/console context) --------

  test "skips and warns when Current.controller is nil (job context)" do
    # Leave Current.controller unset — simulates background job, rake,
    # or console where Rails Executor has cleared CurrentAttributes.
    assert_nil TrackRelay::Current.controller

    result = @subscriber.safe_deliver(build_payload(:purchase))

    assert_nil result
    assert_match(
      /Ahoy subscriber skipping delivery — no controller or ahoy tracker in context/,
      @log_io.string
    )
  end

  # ---- Skip path: controller.ahoy returns nil ------------------------

  test "skips and warns when controller.ahoy returns nil" do
    # respond_to?(:ahoy) is true but the method returns nil — e.g. a
    # controller that has Ahoy::Controller included but where the
    # tracker hasn't been built yet (defensive coverage).
    TrackRelay::Current.controller = build_controller_with_tracker(nil)

    result = @subscriber.safe_deliver(build_payload(:purchase))

    assert_nil result
    assert_match(
      /Ahoy subscriber skipping delivery — controller\.ahoy returned nil/,
      @log_io.string
    )
  end

  # ---- Event-name coercion: Symbol → String --------------------------

  test "coerces event name from Symbol to String at the tracker boundary" do
    mock_tracker = Minitest::Mock.new
    # Mock asserts the EXACT String "purchase" — if the subscriber
    # accidentally passed the Symbol :purchase, the mock would raise
    # MockExpectationError on verify.
    mock_tracker.expect(:track, true, ["purchase", {}])
    TrackRelay::Current.controller = build_controller_with_tracker(mock_tracker)

    @subscriber.safe_deliver(build_payload(:purchase))

    assert mock_tracker.verify
  end

  # ---- Filter gate runs BEFORE deliver -------------------------------

  test "class-level filter only: blocks non-matching events before tracker.track" do
    # Build a subclass with `filter only: [:purchase]` — must be a
    # subclass so the class_attribute mutation does not leak to the
    # canonical TrackRelay::Subscribers::Ahoy class (other tests rely
    # on the unfiltered default).
    filtered_class = Class.new(TrackRelay::Subscribers::Ahoy) do
      filter only: [:purchase]
    end
    sub = filtered_class.new

    # Tracker has NO expectations — if subscriber bypassed the filter
    # and called tracker.track, the mock would raise on the unexpected
    # call. After handle, verify confirms zero invocations occurred.
    mock_tracker = Minitest::Mock.new
    TrackRelay::Current.controller = build_controller_with_tracker(mock_tracker)

    # IMPORTANT: call `handle` (not `safe_deliver`) because the filter
    # gate lives in Subscribers::Base#handle, not in #safe_deliver.
    # safe_deliver would bypass the filter and the test would falsely
    # pass on a regression where filter logic was removed.
    result = sub.handle(build_payload(:page_view))

    assert_nil result, "filtered event returns nil from #handle"
    assert mock_tracker.verify, "tracker.track must not be called for filtered events"
  end

  # ---- Synchronous flag is set ---------------------------------------

  test "synchronous flag is set on the class" do
    assert TrackRelay::Subscribers::Ahoy.synchronous,
      "Ahoy subscriber must be synchronous — Current.controller is gone " \
      "by the time a DeliveryJob runs (Rails Executor clears " \
      "CurrentAttributes before job execution)."
  end
end
