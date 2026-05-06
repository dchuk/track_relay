# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# Integration coverage for {TrackRelay::DeliveryJob}.
#
# Contract under test:
#
# - The job is queued on `:track_relay`.
# - perform reconstructs the EventPayload from the serialized hash via
#   `EventPayload.from_h` and dispatches to the named subscriber.
# - Async loudness mirrors the sync Dispatcher contract: when
#   `safe_deliver` returns a StandardError AND
#   `swallow_subscriber_errors == false`, the job re-raises after
#   `safe_deliver` has already logged. When the config swallows, the
#   job returns normally — the error is logged-only.
class DeliveryJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # ---- Test fixture subscribers (referenced by class-name string) ----

  class CapturingSubscriber < TrackRelay::Subscribers::Base
    synchronous!

    class << self
      attr_accessor :captured
    end

    def deliver(payload)
      self.class.captured = payload
    end
  end

  class BoomSubscriber < TrackRelay::Subscribers::Base
    synchronous!

    def deliver(_payload)
      raise "boom"
    end
  end

  setup do
    CapturingSubscriber.captured = nil
    @log_io = StringIO.new
    @prior_logger = Rails.logger
    Rails.logger = ::Logger.new(@log_io)
  end

  teardown do
    Rails.logger = @prior_logger
  end

  # ---- queue_as ------------------------------------------------------

  test "DeliveryJob is queued on :track_relay" do
    assert_equal "track_relay", TrackRelay::DeliveryJob.new.queue_name
  end

  # ---- Round-trip: to_h → enqueue → from_h → subscriber -------------

  test "round-trip: payload.to_h serialized into job, reconstructed via EventPayload.from_h" do
    payload = TrackRelay::EventPayload.untyped(
      name: :article_viewed,
      params: {article_id: 42, slug: "hello"},
      context: {user: nil, controller: "ArticlesController", action: "show"}
    )

    TrackRelay::DeliveryJob.new.perform("DeliveryJobTest::CapturingSubscriber", payload.to_h)

    captured = CapturingSubscriber.captured
    assert_kind_of TrackRelay::EventPayload, captured
    assert_equal :article_viewed, captured.name
    assert_equal({article_id: 42, slug: "hello"}, captured.params)
    assert_equal "ArticlesController", captured.context[:controller]
    assert_equal "show", captured.context[:action]
    assert_nil captured.definition, "from_h reconstructs as untyped (definition: nil)"
  end

  test "round-trip survives ActiveJob string-key serialization" do
    payload = TrackRelay::EventPayload.untyped(
      name: :foo,
      params: {a: 1},
      context: {b: 2}
    )

    # Simulate ActiveJob argument round-trip (Symbol keys → String keys).
    serialized_then_deserialized = JSON.parse(JSON.generate(payload.to_h))

    TrackRelay::DeliveryJob.new.perform("DeliveryJobTest::CapturingSubscriber", serialized_then_deserialized)

    captured = CapturingSubscriber.captured
    assert_equal :foo, captured.name, "name string is coerced to Symbol"
    assert_equal 1, captured.params["a"] || captured.params[:a]
  end

  # ---- Async loud mode -----------------------------------------------

  test "loud mode: subscriber that raises causes perform to re-raise after logging" do
    TrackRelay.config.swallow_subscriber_errors = false

    payload = TrackRelay::EventPayload.untyped(name: :boom_event, params: {}, context: {})

    err = assert_raises(StandardError) do
      TrackRelay::DeliveryJob.new.perform("DeliveryJobTest::BoomSubscriber", payload.to_h)
    end
    assert_equal "boom", err.message

    log_output = @log_io.string
    assert_match(
      /\[track_relay\] subscriber=DeliveryJobTest::BoomSubscriber failed:/,
      log_output,
      "safe_deliver logs the failure BEFORE the job re-raises"
    )
  end

  # ---- Async quiet mode ----------------------------------------------

  test "quiet mode: subscriber that raises is logged but NOT re-raised" do
    TrackRelay.config.swallow_subscriber_errors = true

    payload = TrackRelay::EventPayload.untyped(name: :boom_event, params: {}, context: {})

    assert_nothing_raised do
      TrackRelay::DeliveryJob.new.perform("DeliveryJobTest::BoomSubscriber", payload.to_h)
    end

    log_output = @log_io.string
    assert_match(
      /\[track_relay\] subscriber=DeliveryJobTest::BoomSubscriber failed:/,
      log_output,
      "error is still logged in quiet mode"
    )
  end

  # ---- perform_later integration with :test adapter ------------------

  test "perform_later enqueues a TrackRelay::DeliveryJob with [class_name, payload_hash]" do
    payload = TrackRelay::EventPayload.untyped(name: :foo, params: {x: 1}, context: {})

    assert_enqueued_with(
      job: TrackRelay::DeliveryJob,
      args: ["DeliveryJobTest::CapturingSubscriber", payload.to_h]
    ) do
      TrackRelay::DeliveryJob.perform_later("DeliveryJobTest::CapturingSubscriber", payload.to_h)
    end
  end
end
