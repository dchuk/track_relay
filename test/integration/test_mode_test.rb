# frozen_string_literal: true

require "test_helper"
require "track_relay/testing"

# Integration coverage for {TrackRelay.test_mode!} / {TrackRelay.test_mode_off!}.
#
# `test_mode!` swaps the configured subscriber list for a single
# {TrackRelay::Subscribers::Test} instance for the duration of an
# example so consumer tests can assert against fired events without
# sending them to real adapters. `test_mode_off!` restores the
# previously captured list.
#
# Contract under test:
#
# - `test_mode!` replaces `config.subscribers` with exactly one
#   `Subscribers::Test`;
# - `test_mode_off!` restores the previously captured list;
# - `test_mode!` is idempotent — calling twice does not clobber the
#   originally-captured subscriber list and returns the same Test
#   instance;
# - after `test_mode_off!`, calling `test_mode!` again yields a fresh
#   Test subscriber (so per-test buffers are isolated);
# - events tracked while in test mode land in
#   `TrackRelay.test_subscriber.events`;
# - real subscribers do NOT receive events while in test mode.
class TestModeTest < ActiveSupport::TestCase
  setup do
    TrackRelay::Dispatcher.start!
    TrackRelay.catalog do
      event :foo do
        integer :n
      end
    end
  end

  teardown do
    # Defensive: ensure test_mode is off even if the test failed.
    TrackRelay.test_mode_off! if TrackRelay::Testing.active?
  end

  test "test_mode! replaces subscribers with a single Subscribers::Test" do
    real = TrackRelay::Subscribers::Test.new
    TrackRelay.config.subscribe(real)

    TrackRelay.test_mode!

    assert_equal 1, TrackRelay.config.subscribers.size
    assert_kind_of TrackRelay::Subscribers::Test, TrackRelay.config.subscribers.first
    refute_same real, TrackRelay.config.subscribers.first,
      "test_mode! must install a fresh Test subscriber, not the host's existing one"
  end

  test "test_mode! returns the new test subscriber so callers can hold a reference" do
    sub = TrackRelay.test_mode!

    assert_kind_of TrackRelay::Subscribers::Test, sub
    assert_same sub, TrackRelay.test_subscriber
    assert_same sub, TrackRelay.config.subscribers.first
  end

  test "test_mode_off! restores the previously captured subscriber list" do
    real_a = TrackRelay::Subscribers::Test.new
    real_b = TrackRelay::Subscribers::Test.new
    TrackRelay.config.subscribe(real_a)
    TrackRelay.config.subscribe(real_b)
    original = TrackRelay.config.subscribers.dup

    TrackRelay.test_mode!
    TrackRelay.test_mode_off!

    assert_equal original, TrackRelay.config.subscribers
    assert_nil TrackRelay.test_subscriber
    refute TrackRelay::Testing.active?
  end

  test "test_mode! is idempotent: second call returns the same Test instance" do
    first = TrackRelay.test_mode!
    second = TrackRelay.test_mode!

    assert_same first, second
    assert_equal 1, TrackRelay.config.subscribers.size
  end

  test "test_mode! twice does not clobber the originally-captured subscribers" do
    real = TrackRelay::Subscribers::Test.new
    TrackRelay.config.subscribe(real)
    original = TrackRelay.config.subscribers.dup

    TrackRelay.test_mode!
    TrackRelay.test_mode! # second call must NOT capture the test list as "previous"
    TrackRelay.test_mode_off!

    assert_equal original, TrackRelay.config.subscribers
  end

  test "after test_mode_off!, calling test_mode! again creates a fresh Test subscriber" do
    first = TrackRelay.test_mode!
    TrackRelay.test_mode_off!
    second = TrackRelay.test_mode!

    refute_same first, second
    assert_kind_of TrackRelay::Subscribers::Test, second
    assert_equal [], second.events
  end

  test "events tracked while in test mode land in TrackRelay.test_subscriber.events" do
    TrackRelay.test_mode!

    TrackRelay.track(:foo, n: 42)

    assert_equal 1, TrackRelay.test_subscriber.events.size
    captured = TrackRelay.test_subscriber.events.first
    assert_equal :foo, captured.name
    assert_equal 42, captured.params[:n]
  end

  test "real subscribers do NOT receive events while in test mode" do
    real = TrackRelay::Subscribers::Test.new
    TrackRelay.config.subscribe(real)

    TrackRelay.test_mode!
    TrackRelay.track(:foo, n: 1)

    assert_equal 0, real.events.size, "real subscriber must not see events while test_mode! is active"
    assert_equal 1, TrackRelay.test_subscriber.events.size
  end

  test "test_mode_off! is a no-op when not active" do
    refute TrackRelay::Testing.active?
    TrackRelay.test_mode_off! # should not raise
    refute TrackRelay::Testing.active?
  end
end
