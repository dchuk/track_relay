# frozen_string_literal: true

require "test_helper"

# Integration coverage for {TrackRelay::Dispatcher}.
#
# The Dispatcher is the single AS::Notifications subscription that
# fans events out to {Configuration#subscribers}. Its job is to
# implement the **collect-then-reraise** error contract locked in
# 01-CONTEXT.md and 01-05-PLAN.md:
#
# 1. Iterate every configured subscriber, calling `handle(payload)`.
# 2. Collect any exception each subscriber returns (Subscribers::Base
#    returns the StandardError from safe_deliver; never re-raises).
# 3. AFTER fan-out completes, if `swallow_subscriber_errors == false`
#    AND any exception was collected, re-raise the **first** one.
#
# This guarantees one bad subscriber never blocks peers from
# receiving the event, while still surfacing failures loudly in
# dev/test where loudness is on.
#
# `start!`/`stop!` must be idempotent so the Plan 06 Railtie can call
# `start!` once at boot without worrying about double-subscription.
class DispatcherTest < ActiveSupport::TestCase
  setup do
    @log_io = StringIO.new
    @prior_logger = Rails.logger
    Rails.logger = ::Logger.new(@log_io)
    # Pristine subscription state at the start of each test.
    TrackRelay::Dispatcher.stop!
  end

  teardown do
    TrackRelay::Dispatcher.stop!
    Rails.logger = @prior_logger
  end

  # ---- Test fixture subscribers ------------------------------------

  class BoomSub < TrackRelay::Subscribers::Base
    synchronous!

    def initialize(message: "boom")
      super()
      @message = message
    end

    def deliver(_payload)
      raise @message
    end
  end

  # ---- Helpers ------------------------------------------------------

  def fresh_test_subscriber
    TrackRelay::Subscribers::Test.new
  end

  # ---- Basic lifecycle ----------------------------------------------

  test "start! then track: every configured subscriber receives the payload" do
    a = fresh_test_subscriber
    b = fresh_test_subscriber
    TrackRelay.config.replace_subscribers([a, b])

    TrackRelay::Dispatcher.start!
    TrackRelay.track(:foo, x: 1)

    assert_equal 1, a.events.size
    assert_equal 1, b.events.size
    assert_equal :foo, a.events.first.name
    assert_equal({x: 1}, a.events.first.params)
  end

  test "stop! removes the subscription: subsequent track does not reach subscribers" do
    sub = fresh_test_subscriber
    TrackRelay.config.replace_subscribers([sub])

    TrackRelay::Dispatcher.start!
    TrackRelay.track(:foo, x: 1)
    assert_equal 1, sub.events.size

    TrackRelay::Dispatcher.stop!
    TrackRelay.track(:foo, x: 2)
    assert_equal 1, sub.events.size, "no new event should be delivered after stop!"
  end

  test "start! is idempotent: calling twice does not duplicate delivery" do
    sub = fresh_test_subscriber
    TrackRelay.config.replace_subscribers([sub])

    TrackRelay::Dispatcher.start!
    TrackRelay::Dispatcher.start! # should be a no-op
    TrackRelay.track(:foo, x: 1)

    assert_equal 1, sub.events.size,
      "double start! must register exactly one subscription"
  end

  test "stop! is idempotent: calling twice (or with no prior start!) does not raise" do
    assert_nothing_raised { TrackRelay::Dispatcher.stop! }
    TrackRelay::Dispatcher.start!
    TrackRelay::Dispatcher.stop!
    assert_nothing_raised { TrackRelay::Dispatcher.stop! }
  end

  test "started? reflects subscription state" do
    refute TrackRelay::Dispatcher.started?
    TrackRelay::Dispatcher.start!
    assert TrackRelay::Dispatcher.started?
    TrackRelay::Dispatcher.stop!
    refute TrackRelay::Dispatcher.started?
  end

  # ---- Collect-then-reraise (loud mode) ----------------------------

  test "loud mode, BOOM-BEFORE-TEST: track raises AND test subscriber STILL captured the event" do
    TrackRelay.config.swallow_subscriber_errors = false
    boom = BoomSub.new
    test_sub = fresh_test_subscriber
    TrackRelay.config.replace_subscribers([boom, test_sub])

    TrackRelay::Dispatcher.start!

    err = assert_raises(RuntimeError) do
      TrackRelay.track(:foo, x: 1)
    end
    assert_equal "boom", err.message

    assert_equal 1, test_sub.events.size,
      "peer subscriber must STILL receive the event even when a peer raised — collect-then-reraise"
  end

  test "loud mode, BOOM-AFTER-TEST: track raises AND test subscriber STILL captured the event" do
    TrackRelay.config.swallow_subscriber_errors = false
    test_sub = fresh_test_subscriber
    boom = BoomSub.new
    TrackRelay.config.replace_subscribers([test_sub, boom])

    TrackRelay::Dispatcher.start!

    assert_raises(RuntimeError) do
      TrackRelay.track(:foo, x: 1)
    end

    assert_equal 1, test_sub.events.size
  end

  # ---- Collect-then-swallow (quiet mode) ---------------------------

  test "quiet mode, BOOM-BEFORE-TEST: track does NOT raise; test subscriber STILL captured" do
    TrackRelay.config.swallow_subscriber_errors = true
    boom = BoomSub.new
    test_sub = fresh_test_subscriber
    TrackRelay.config.replace_subscribers([boom, test_sub])

    TrackRelay::Dispatcher.start!

    assert_nothing_raised do
      TrackRelay.track(:foo, x: 1)
    end

    assert_equal 1, test_sub.events.size
  end

  test "quiet mode, BOOM-AFTER-TEST: track does NOT raise; test subscriber STILL captured" do
    TrackRelay.config.swallow_subscriber_errors = true
    test_sub = fresh_test_subscriber
    boom = BoomSub.new
    TrackRelay.config.replace_subscribers([test_sub, boom])

    TrackRelay::Dispatcher.start!

    assert_nothing_raised do
      TrackRelay.track(:foo, x: 1)
    end

    assert_equal 1, test_sub.events.size
  end

  # ---- First-error-wins ordering -----------------------------------

  test "loud mode with multiple boom subscribers: only the FIRST collected exception is re-raised" do
    TrackRelay.config.swallow_subscriber_errors = false
    first = BoomSub.new(message: "first-boom")
    second = BoomSub.new(message: "second-boom")
    TrackRelay.config.replace_subscribers([first, second])

    TrackRelay::Dispatcher.start!

    err = assert_raises(RuntimeError) do
      TrackRelay.track(:foo, x: 1)
    end

    assert_equal "first-boom", err.message,
      "Dispatcher must re-raise the FIRST collected exception"
  end

  # ---- Defensive rescue for non-Base subscribers -------------------

  test "non-Base subscriber that raises inline: peers still run; loudness honored" do
    TrackRelay.config.swallow_subscriber_errors = false

    # A POROish subscriber that ignores the safe_deliver contract.
    rogue = Class.new do
      def handle(_payload)
        raise "rogue-boom"
      end
    end.new

    test_sub = fresh_test_subscriber
    TrackRelay.config.replace_subscribers([rogue, test_sub])

    TrackRelay::Dispatcher.start!

    err = assert_raises(RuntimeError) do
      TrackRelay.track(:foo, x: 1)
    end
    assert_equal "rogue-boom", err.message

    assert_equal 1, test_sub.events.size,
      "peer subscriber must still see the event when a non-Base peer raised inline"
  end
end
