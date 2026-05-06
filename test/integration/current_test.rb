# frozen_string_literal: true

require "test_helper"

# Integration-level coverage for {TrackRelay::Current} under Combustion.
#
# Why this lives in test/integration/ instead of test/unit/:
#   {ActiveSupport::CurrentAttributes} hooks the Rails Executor for its
#   reset semantics. We want at least one assertion that exercises the
#   subclass under a fully booted Rails app (Combustion) — not just the
#   in-process AS pieces — so regressions in our wiring or in upstream
#   Rails surface here, not silently in production.
class CurrentIntegrationTest < ActiveSupport::TestCase
  test "Current.user persists within a single test" do
    TrackRelay::Current.user = "alice"
    assert_equal "alice", TrackRelay::Current.user
  end

  test "Current.user is nil at start of next test (auto-reset)" do
    # If "alice" leaked from the prior test, this fails — proving the
    # ActiveSupport::CurrentAttributes::TestHelper hook in
    # test/test_helper.rb is wired.
    assert_nil TrackRelay::Current.user
  end

  test "Current.set restores previous values when the block returns" do
    TrackRelay::Current.user = "bob"

    TrackRelay::Current.set(user: "carol") do
      assert_equal "carol", TrackRelay::Current.user
    end

    assert_equal "bob", TrackRelay::Current.user
  end

  test "all five attributes are independent" do
    TrackRelay::Current.user = "u"
    TrackRelay::Current.request = "r"
    TrackRelay::Current.visit = "v"
    TrackRelay::Current.controller = "c"
    TrackRelay::Current.client_id = "cid"

    assert_equal "u", TrackRelay::Current.user
    assert_equal "r", TrackRelay::Current.request
    assert_equal "v", TrackRelay::Current.visit
    assert_equal "c", TrackRelay::Current.controller
    assert_equal "cid", TrackRelay::Current.client_id
  end
end
