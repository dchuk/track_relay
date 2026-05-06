# frozen_string_literal: true

require "test_helper"

# Integration coverage for {TrackRelay.identify}.
#
# Phase 01 ships identify as a thin AS::Notifications pass-through —
# adapter-specific user_property handling (GA4 user_properties, Ahoy
# User update, etc.) is deferred to Phase 02. The Instrumenter does NOT
# validate `user_properties` against `Catalog.user_properties` here.
#
# Both notifications (`track_relay.event` and `track_relay.identify`)
# share the same Notifier; these tests confirm they coexist without
# crosstalk by subscribing only to the identify name.
class IdentifyTest < ActiveSupport::TestCase
  test "identify instruments track_relay.identify with user + properties" do
    user = Object.new
    events = []

    ActiveSupport::Notifications.subscribed(->(e) { events << e }, "track_relay.identify") do
      TrackRelay.identify(user, plan: "pro", cohort: "2026-05")
    end

    assert_equal 1, events.size
    assert_equal "track_relay.identify", events.first.name
    assert_same user, events.first.payload[:user]
    assert_equal({plan: "pro", cohort: "2026-05"}, events.first.payload[:properties])
  end

  test "identify with no properties still fires" do
    user = Object.new
    events = []

    ActiveSupport::Notifications.subscribed(->(e) { events << e }, "track_relay.identify") do
      TrackRelay.identify(user)
    end

    assert_equal 1, events.size
    assert_same user, events.first.payload[:user]
    assert_equal({}, events.first.payload[:properties])
  end

  test "identify does not fire on the track_relay.event channel" do
    track_events = []
    identify_events = []

    ActiveSupport::Notifications.subscribed(->(e) { track_events << e }, "track_relay.event") do
      ActiveSupport::Notifications.subscribed(->(e) { identify_events << e }, "track_relay.identify") do
        TrackRelay.identify(Object.new, plan: "pro")
      end
    end

    assert_empty track_events, "identify must not leak onto the track_relay.event channel"
    assert_equal 1, identify_events.size
  end
end
