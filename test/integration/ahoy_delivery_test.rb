# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# End-to-end integration coverage for {TrackRelay::Subscribers::Ahoy} —
# Plan 03-01.
#
# These tests pin the full pipeline:
#
#   TrackRelay.track(:purchase, ...) →
#   ActiveSupport::Notifications.instrument →
#   Dispatcher → Subscribers::Ahoy#handle (synchronous) →
#   controller.ahoy.track(name, params)
#
# AND the job-context skip path: when there is no controller in scope
# (background job, rake task, console), the subscriber must log a
# warning and return — no DeliveryJob enqueue, no Ahoy API call, no
# raised exception.
#
# Setup mirrors {Ga4SynchronousOptInTest}: register the subscriber via
# `TrackRelay.configure` and start the Dispatcher. A Minitest::Mock
# tracker stands in for `Ahoy::Tracker` so the test does not depend on
# Ahoy's request/visit/store machinery (`Ahoy::BaseStore#exclude?`
# behaves unpredictably in the harness without a real request — see
# 03-RESEARCH.md §"Open questions" #5).
class AhoyDeliveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    TrackRelay.configure do |c|
      c.subscribe(TrackRelay::Subscribers::Ahoy.new)
    end
    TrackRelay::Dispatcher.start!

    @log_io = StringIO.new
    @prior_logger = Rails.logger
    Rails.logger = ::Logger.new(@log_io)
  end

  teardown do
    Rails.logger = @prior_logger
    TrackRelay::Current.controller = nil
  end

  # Build a controller-like double whose `ahoy` method returns the
  # supplied tracker. `define_singleton_method` is sufficient for
  # `respond_to?(:ahoy, true)` to return true.
  def build_controller_with_tracker(tracker)
    controller = Object.new
    controller.define_singleton_method(:ahoy) { tracker }
    controller
  end

  # ---- Full pipeline: synchronous dispatch, no job enqueued ----------

  test "full pipeline dispatches inline via controller.ahoy.track and enqueues no DeliveryJob" do
    mock_tracker = Minitest::Mock.new
    mock_tracker.expect(:track, true, ["purchase", {value: 9.99, currency: "USD"}])
    TrackRelay::Current.controller = build_controller_with_tracker(mock_tracker)

    # `assert_no_enqueued_jobs only:` proves the synchronous path was
    # taken — the GA4-style async path would enqueue here.
    assert_no_enqueued_jobs(only: TrackRelay::DeliveryJob) do
      TrackRelay.track(:purchase, value: 9.99, currency: "USD")
    end

    # `mock.verify` raises MockExpectationError if `tracker.track` was
    # not called with the exact (String, Hash) tuple — this is the
    # full-pipeline assertion that the subscriber dispatched correctly.
    assert mock_tracker.verify
  end

  # ---- Job-context skip: no enqueue, no crash, warn logged -----------

  test "job context (no Current.controller) skips delivery without enqueueing or crashing" do
    # Leave Current.controller nil — simulates a DeliveryJob-style
    # context where the Rails Executor has cleared CurrentAttributes.
    assert_nil TrackRelay::Current.controller

    assert_nothing_raised do
      assert_no_enqueued_jobs(only: TrackRelay::DeliveryJob) do
        TrackRelay.track(:purchase, value: 1.0)
      end
    end

    assert_match(
      /\[track_relay\] Ahoy subscriber skipping delivery/,
      @log_io.string
    )
  end
end
