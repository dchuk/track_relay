# frozen_string_literal: true

require "test_helper"

# Integration coverage for the untyped (no-catalog-match) path of
# {TrackRelay.track}.
#
# Untyped events exist for incremental adoption: a host application can
# drop the gem in and start firing events without a fully populated
# catalog. The path is gated by
# {TrackRelay::Configuration#untyped_events_allowed} (default true) so
# strict apps can opt out and surface unknown events as
# {TrackRelay::UnknownEventError}.
#
# These tests do NOT define a catalog in `setup` — that is the whole
# point. The shared `teardown` in `test/test_helper.rb` clears the
# catalog and resets config between tests.
class UntypedEventTest < ActiveSupport::TestCase
  test "untyped event instruments when untyped_events_allowed is true (default)" do
    events = []

    ActiveSupport::Notifications.subscribed(->(e) { events << e }, "track_relay.event") do
      TrackRelay.track(:not_in_catalog, foo: "bar", baz: 42)
    end

    assert_equal 1, events.size
    payload = events.first.payload[:event]
    assert_equal :not_in_catalog, payload.name
    assert_equal({foo: "bar", baz: 42}, payload.params)
    assert_nil payload.definition
    assert_predicate payload, :untyped?
  end

  test "untyped event raises UnknownEventError when disallowed" do
    TrackRelay.config.untyped_events_allowed = false

    assert_raises(TrackRelay::UnknownEventError) do
      TrackRelay.track(:not_in_catalog, foo: "bar")
    end
  end

  test "untyped event still partitions reserved keys into Current/context" do
    user = Object.new
    events = []

    ActiveSupport::Notifications.subscribed(->(e) { events << e }, "track_relay.event") do
      TrackRelay.track(:adhoc_event, foo: "bar", user: user, visitor_token: "vt")
    end

    payload = events.first.payload[:event]
    assert_equal({foo: "bar"}, payload.params)
    assert_same user, payload.context[:user]
    assert_equal "vt", payload.context[:visitor_token]
  end
end
