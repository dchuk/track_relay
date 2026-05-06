# frozen_string_literal: true

require "test_helper"

class TrackRelay::CurrentTest < ActiveSupport::TestCase
  test "Current is a subclass of ActiveSupport::CurrentAttributes" do
    assert_operator TrackRelay::Current, :<, ActiveSupport::CurrentAttributes
  end

  test "Current.user persists within a single test" do
    TrackRelay::Current.user = "alice"
    assert_equal "alice", TrackRelay::Current.user
  end

  test "Current.user is nil at the start of this test (auto-reset between tests)" do
    # If the prior test's `Current.user = "alice"` leaked into this test,
    # this assertion fails — proving the TestHelper-based reset works.
    assert_nil TrackRelay::Current.user
  end

  test "Current.set yields a block and restores prior values afterward" do
    TrackRelay::Current.user = "outer-user"
    TrackRelay::Current.request = "outer-request"

    TrackRelay::Current.set(user: "inner-user", request: "inner-request") do
      assert_equal "inner-user", TrackRelay::Current.user
      assert_equal "inner-request", TrackRelay::Current.request
    end

    assert_equal "outer-user", TrackRelay::Current.user
    assert_equal "outer-request", TrackRelay::Current.request
  end

  test "all five attributes are independently settable" do
    TrackRelay::Current.user = :u
    TrackRelay::Current.request = :r
    TrackRelay::Current.visit = :v
    TrackRelay::Current.controller = :c
    TrackRelay::Current.client_id = :cid

    assert_equal :u, TrackRelay::Current.user
    assert_equal :r, TrackRelay::Current.request
    assert_equal :v, TrackRelay::Current.visit
    assert_equal :c, TrackRelay::Current.controller
    assert_equal :cid, TrackRelay::Current.client_id
  end

  test "Current responds to :set and :reset (provided by AS::CurrentAttributes)" do
    assert_respond_to TrackRelay::Current, :set
    assert_respond_to TrackRelay::Current, :reset
  end
end
