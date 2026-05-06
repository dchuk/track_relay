# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# Integration coverage for {TrackRelay::Subscribers::Test}.
#
# The Test subscriber captures payloads in memory for assertion in
# tests. It is the building block of Plan 07's `TrackRelay.test_mode!`
# flow, which swaps the configured subscriber list for a single Test
# instance for the duration of an example.
#
# Contract under test:
#
# - opts into `synchronous!` so events are captured inline (no
#   DeliveryJob enqueue);
# - state is per-instance (no class-level globals — multiple instances
#   are independent);
# - exposes `events`, `clear!`, `find(name)` to consumers.
class SubscribersTestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def build_payload(name: :article_viewed, params: {})
    TrackRelay::EventPayload.untyped(name: name, params: params, context: {})
  end

  test "synchronous! is set so handle dispatches inline (no enqueue)" do
    assert TrackRelay::Subscribers::Test.synchronous,
      "Subscribers::Test must opt into synchronous!"
  end

  test "new instance has empty events" do
    sub = TrackRelay::Subscribers::Test.new
    assert_equal [], sub.events
  end

  test "handle appends payload to events synchronously, no job enqueued" do
    sub = TrackRelay::Subscribers::Test.new
    payload = build_payload

    assert_no_enqueued_jobs do
      sub.handle(payload)
    end

    assert_equal 1, sub.events.size
    assert_same payload, sub.events.first
  end

  test "clear! empties the captured events list" do
    sub = TrackRelay::Subscribers::Test.new
    sub.handle(build_payload(name: :a))
    sub.handle(build_payload(name: :b))
    assert_equal 2, sub.events.size

    sub.clear!
    assert_equal [], sub.events
  end

  test "find returns only events whose name matches" do
    sub = TrackRelay::Subscribers::Test.new
    sub.handle(build_payload(name: :article_viewed, params: {id: 1}))
    sub.handle(build_payload(name: :video_started))
    sub.handle(build_payload(name: :article_viewed, params: {id: 2}))

    matches = sub.find(:article_viewed)
    assert_equal 2, matches.size
    assert(matches.all? { |p| p.name == :article_viewed })
    assert_equal [1, 2], matches.map { |p| p.params[:id] }
  end

  test "find returns empty array when no events match" do
    sub = TrackRelay::Subscribers::Test.new
    sub.handle(build_payload(name: :foo))

    assert_equal [], sub.find(:bar)
  end

  test "two instances are independent (per-instance state, no class-level globals)" do
    a = TrackRelay::Subscribers::Test.new
    b = TrackRelay::Subscribers::Test.new

    a.handle(build_payload(name: :only_a))

    assert_equal 1, a.events.size
    assert_equal 0, b.events.size, "second instance must not see events captured by the first"
  end
end
