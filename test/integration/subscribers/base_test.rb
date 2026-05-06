# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# Integration coverage for {TrackRelay::Subscribers::Base} — the
# sync-vs-async dispatch contract and the per-subscriber rescue.
#
# Contract under test (locked in 01-CONTEXT.md + 01-05-PLAN.md):
#
# - `safe_deliver` returns `nil` on success or the StandardError on
#   failure. It NEVER re-raises inline. The Dispatcher decides loudness
#   AFTER fan-out completes (see DispatcherTest).
# - `handle` returns `nil` on success or the StandardError on failure
#   (sync path), or `nil` (async path — DeliveryJob.perform_later
#   doesn't run inline under the :test adapter).
# - `synchronous!` flips a subclass into the sync path; otherwise the
#   default is async.
# - `force_synchronous = true` flips even async subscribers to sync.
class SubscribersBaseTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # ---- Test fixture subscribers -------------------------------------

  class FakeSync < TrackRelay::Subscribers::Base
    synchronous!

    class << self
      attr_accessor :captured
    end

    def deliver(payload)
      self.class.captured = payload
    end
  end

  class FakeAsync < TrackRelay::Subscribers::Base
    def deliver(payload)
      # Never invoked in async tests — DeliveryJob is enqueued, not run.
    end
  end

  class BoomSubscriber < TrackRelay::Subscribers::Base
    synchronous!

    def deliver(_payload)
      raise "boom"
    end
  end

  # ---- Helpers ------------------------------------------------------

  def build_payload(name: :article_viewed, params: {x: 1}, context: {})
    TrackRelay::EventPayload.untyped(name: name, params: params, context: context)
  end

  setup do
    FakeSync.captured = nil
    @log_io = StringIO.new
    @prior_logger = Rails.logger
    Rails.logger = ::Logger.new(@log_io)
  end

  teardown do
    Rails.logger = @prior_logger
  end

  # ---- Sync path ----------------------------------------------------

  test "synchronous subscriber: handle delivers inline and returns nil" do
    payload = build_payload
    sub = FakeSync.new

    assert_nil sub.handle(payload), "handle returns nil on successful sync delivery"
    assert_same payload, FakeSync.captured, "deliver was called inline"
  end

  # ---- Async path ---------------------------------------------------

  test "async subscriber: handle enqueues DeliveryJob with [class_name, to_h] and returns nil" do
    payload = build_payload
    sub = FakeAsync.new

    assert_enqueued_with(
      job: TrackRelay::DeliveryJob,
      args: ["SubscribersBaseTest::FakeAsync", payload.to_h]
    ) do
      assert_nil sub.handle(payload), "async handle returns nil"
    end
  end

  test "async subscriber: deliver is NOT called inline (job is only enqueued)" do
    payload = build_payload
    sub = FakeAsync.new

    sub.handle(payload)
    # FakeAsync#deliver is a no-op; we just confirm no job ran by asserting
    # the test adapter accumulated exactly one enqueued job.
    assert_equal 1, enqueued_jobs.size
    clear_enqueued_jobs
  end

  # ---- safe_deliver: never re-raises, always logs --------------------

  test "safe_deliver returns the StandardError on failure (NOT re-raised)" do
    payload = build_payload
    sub = BoomSubscriber.new

    result = sub.safe_deliver(payload)

    assert_kind_of StandardError, result, "safe_deliver returns the exception"
    assert_equal "boom", result.message
  end

  test "safe_deliver logs failure via Rails.logger.error including subscriber name + class + message" do
    payload = build_payload
    sub = BoomSubscriber.new

    sub.safe_deliver(payload)

    log_output = @log_io.string
    assert_match(/\[track_relay\] subscriber=SubscribersBaseTest::BoomSubscriber failed:/, log_output)
    assert_match(/RuntimeError: boom/, log_output)
  end

  test "safe_deliver does NOT re-raise even when swallow_subscriber_errors is false" do
    TrackRelay.config.swallow_subscriber_errors = false
    payload = build_payload
    sub = BoomSubscriber.new

    # Should NOT raise inline. The Dispatcher decides loudness after fan-out.
    result = nil
    assert_nothing_raised do
      result = sub.safe_deliver(payload)
    end
    assert_kind_of StandardError, result
  end

  test "safe_deliver returns nil on success" do
    payload = build_payload
    sub = FakeSync.new

    assert_nil sub.safe_deliver(payload)
  end

  # ---- handle returns the exception when sync delivery fails --------

  test "handle returns the StandardError when a synchronous subscriber raises" do
    payload = build_payload
    sub = BoomSubscriber.new

    result = sub.handle(payload)

    assert_kind_of StandardError, result, "handle propagates safe_deliver's return value"
    assert_equal "boom", result.message
  end

  # ---- force_synchronous: flips async subscribers to sync ----------

  test "force_synchronous=true flips async subscriber to sync path (no enqueue)" do
    TrackRelay.config.force_synchronous = true
    payload = build_payload
    sub = FakeAsync.new

    assert_no_enqueued_jobs do
      result = sub.handle(payload)
      # FakeAsync#deliver succeeds silently → handle returns nil
      assert_nil result
    end
  end

  test "force_synchronous=true: when sync delivery fails, handle returns the exception" do
    TrackRelay.config.force_synchronous = true
    payload = build_payload

    # An async-by-default subscriber that raises in #deliver
    klass = Class.new(TrackRelay::Subscribers::Base) do
      def deliver(_payload)
        raise "force-sync-boom"
      end
    end

    sub = klass.new
    result = sub.handle(payload)

    assert_kind_of StandardError, result
    assert_equal "force-sync-boom", result.message
  end

  # ---- deliver default: NotImplementedError -------------------------

  test "Base#deliver raises NotImplementedError so subclasses must override" do
    payload = build_payload
    sub = TrackRelay::Subscribers::Base.new

    err = assert_raises(NotImplementedError) { sub.deliver(payload) }
    assert_match(/must implement #deliver/, err.message)
  end
end
