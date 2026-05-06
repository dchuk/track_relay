# frozen_string_literal: true

require "test_helper"
require "track_relay/testing/helpers"

# Integration coverage for {TrackRelay::Testing::MinitestAssertions} via
# the {TrackRelay::Testing::Helpers} mix-in.
#
# Including `Helpers` into a Minitest test class:
#   1. mixes in `assert_tracked` / `refute_tracked` / `track_relay_test`;
#   2. registers `setup` / `teardown` blocks that auto-enable
#      `TrackRelay.test_mode!` per test, giving each example a fresh
#      Test subscriber.
#
# Contract under test:
#
# - `assert_tracked(:event)` passes when at least one captured event
#   matches `:event` and fails with a helpful message otherwise;
# - `assert_tracked(:event, **params)` matches subset semantics — the
#   captured params must include every key/value in `params`, but may
#   carry extras;
# - `refute_tracked(:event)` is the inverse;
# - `track_relay_test` returns the active Test subscriber and raises a
#   helpful message when test_mode! has not been called;
# - the `Helpers` include auto-enables test_mode per test, and
#   per-test isolation works (events from one test do not bleed into
#   the next).
class MinitestAssertionsTest < ActiveSupport::TestCase
  include TrackRelay::Testing::Helpers

  setup do
    TrackRelay::Dispatcher.start!
    TrackRelay.catalog do
      event :foo do
        integer :n
      end
    end
  end

  test "assert_tracked passes when event was tracked" do
    TrackRelay.track(:foo, n: 1)
    assert_tracked :foo
  end

  test "assert_tracked with params matches subset" do
    TrackRelay.track(:foo, n: 7)
    assert_tracked :foo, n: 7
  end

  test "assert_tracked with params fails when value differs" do
    TrackRelay.track(:foo, n: 1)
    error = assert_raises(Minitest::Assertion) do
      assert_tracked :foo, n: 999
    end
    assert_match(/Expected :foo with params/, error.message)
  end

  test "assert_tracked fails with helpful message when not tracked" do
    error = assert_raises(Minitest::Assertion) do
      assert_tracked :foo
    end
    assert_match(/Expected an event :foo/, error.message)
  end

  test "refute_tracked passes when event was not tracked" do
    refute_tracked :foo
  end

  test "refute_tracked fails when event was tracked" do
    TrackRelay.track(:foo, n: 1)
    assert_raises(Minitest::Assertion) do
      refute_tracked :foo
    end
  end

  test "track_relay_test returns the active Test subscriber" do
    assert_kind_of TrackRelay::Subscribers::Test, track_relay_test
    assert_same TrackRelay.test_subscriber, track_relay_test
  end

  test "test_mode! is auto-enabled by Helpers include" do
    assert TrackRelay::Testing.active?,
      "Helpers#setup must call TrackRelay.test_mode! automatically"
  end

  test "events isolate between tests" do
    # If isolation is broken, a previous test's :foo events would still
    # be visible here (the file is loaded once and tests share the same
    # process). The Helpers teardown calls test_mode_off! and the next
    # setup calls test_mode! → fresh Test subscriber.
    refute_tracked :foo
  end
end

# Separate test class to verify the helpful error path of
# `track_relay_test` when test_mode! has NOT been called. This class
# does NOT include Helpers, so test_mode! never runs.
class MinitestAssertionsWithoutTestModeTest < ActiveSupport::TestCase
  include TrackRelay::Testing::MinitestAssertions

  test "track_relay_test raises a helpful message when test_mode! was not called" do
    error = assert_raises(RuntimeError) do
      track_relay_test
    end
    assert_match(/test_mode!/, error.message)
  end
end
