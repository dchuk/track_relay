# frozen_string_literal: true

require "test_helper"
require "rspec/core"
require "rspec/expectations"

# `track_relay/testing` was already required by test_helper, but the
# matchers file is loaded lazily on first `defined?(RSpec)` check at
# require time. Since RSpec was loaded above (after test_helper),
# explicitly require the matchers here so they register.
require "track_relay/testing/rspec_matchers"

# Integration coverage for {TrackRelay::Testing}'s RSpec
# `have_tracked` matcher.
#
# The gem's own suite uses Minitest, so we exercise the RSpec matcher
# inline by mixing `RSpec::Matchers` into a Minitest test class. This
# keeps the dev-dep surface small (no `rspec` runtime, no `spec/`
# tree) while still proving the matcher works against real captures.
#
# Failures inside `expect(...).to ...` raise
# `RSpec::Expectations::ExpectationNotMetError`, which we catch with
# `assert_raises` to verify the negative paths.
#
# Contract under test:
#
# - `have_tracked(:event)` matches when at least one captured event has
#   that name;
# - `have_tracked(:event).with(**params)` further requires that at
#   least one captured event have params that include every key/value
#   pair in `params` (subset semantics);
# - the matcher fails with a helpful message when the event is missing
#   or when no captured event has the expected params;
# - the matcher raises a clear error if `TrackRelay.test_mode!` was
#   never called;
# - `have_identified` is registered as a Phase-01 placeholder that
#   never matches.
class RspecMatchersTest < ActiveSupport::TestCase
  include RSpec::Matchers

  setup do
    TrackRelay::Dispatcher.start!
    TrackRelay.catalog do
      event :foo do
        integer :n
      end
    end
    TrackRelay.test_mode!
  end

  teardown do
    TrackRelay.test_mode_off! if TrackRelay::Testing.active?
  end

  test "have_tracked matches a fired event" do
    TrackRelay.track(:foo, n: 1)
    expect(self).to have_tracked(:foo)
    pass # silence Minitest "missing assertions" — RSpec matchers raise on failure but don't bump @assertions
  end

  test "have_tracked.with(params) matches when subset is satisfied" do
    TrackRelay.track(:foo, n: 7)
    expect(self).to have_tracked(:foo).with(n: 7)
    pass # silence Minitest "missing assertions" — RSpec matchers raise on failure but don't bump @assertions
  end

  test "have_tracked fails when event missing" do
    error = assert_raises(RSpec::Expectations::ExpectationNotMetError) do
      expect(self).to have_tracked(:foo)
    end
    assert_match(/foo/, error.message)
  end

  test "have_tracked.with fails when params do not match" do
    TrackRelay.track(:foo, n: 1)
    error = assert_raises(RSpec::Expectations::ExpectationNotMetError) do
      expect(self).to have_tracked(:foo).with(n: 999)
    end
    assert_match(/n.*999/, error.message)
  end

  test "have_tracked failure message lists what was actually tracked" do
    TrackRelay.track(:foo, n: 1)
    error = assert_raises(RSpec::Expectations::ExpectationNotMetError) do
      expect(self).to have_tracked(:bar)
    end
    assert_match(/bar/, error.message)
  end

  test "have_identified is a Phase-01 placeholder that never matches" do
    user = Object.new
    error = assert_raises(RSpec::Expectations::ExpectationNotMetError) do
      expect(self).to have_identified(user)
    end
    assert_match(/Phase 01|not yet implemented/i, error.message)
  end
end

# Verify the matcher raises a clear error when test_mode! was never
# called (i.e. `TrackRelay.test_subscriber` is nil).
class RspecMatchersWithoutTestModeTest < ActiveSupport::TestCase
  include RSpec::Matchers

  test "have_tracked raises when test_mode! was not called" do
    refute TrackRelay::Testing.active?,
      "guard: this test must run with test_mode! NOT active"

    error = assert_raises(RuntimeError) do
      expect(self).to have_tracked(:foo)
    end
    assert_match(/test_mode!/, error.message)
  end
end
