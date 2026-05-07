# frozen_string_literal: true

require "test_helper"

# Integration coverage for {TrackRelay::ControllerTracking}.
#
# The concern is intentionally thin:
#
#   - `included` adds `before_action :_track_relay_set_current` so every
#     request to a controller including the concern populates
#     {Current.controller}, {Current.request}, and {Current.client_id}
#     (derived from the `_ga` cookie when present).
#   - Instance method `track(name, **params)` is a thin delegate to
#     {TrackRelay.track}, exposing the call site's controller (`self`)
#     to the {Instrumenter} via {Current}.
#
# These tests exercise the full request → before_action → track →
# Notifications.instrument → captured payload pipeline through the
# Combustion-booted internal app's `ArticlesController`.
class ControllerTrackingTest < ActionDispatch::IntegrationTest
  setup do
    TrackRelay.catalog do
      event :article_viewed do
        integer :article_id, required: true
        string :slug, required: true
      end
    end
    @captured = []
    @subscription = ActiveSupport::Notifications.subscribe("track_relay.event") do |*, payload|
      @captured << payload[:event]
    end
  end

  teardown do
    ActiveSupport::Notifications.unsubscribe(@subscription) if @subscription
  end

  test "track helper inside a controller fires an event" do
    get article_path(42)
    assert_response :ok
    assert_equal 1, @captured.size
    assert_equal :article_viewed, @captured.first.name
    assert_equal({article_id: 42, slug: "test-slug"}, @captured.first.params)
  end

  test "before_action sets Current.controller and Current.request at instrument time" do
    snapshot = nil
    snap_sub = ActiveSupport::Notifications.subscribe("track_relay.event") do |*, _|
      snapshot = {
        controller: TrackRelay::Current.controller&.class&.name,
        request: TrackRelay::Current.request&.class&.name
      }
    end

    get article_path(1)
    assert_equal "ArticlesController", snapshot[:controller]
    assert_equal "ActionDispatch::Request", snapshot[:request]
  ensure
    ActiveSupport::Notifications.unsubscribe(snap_sub) if snap_sub
  end

  test "_ga cookie populates Current.client_id" do
    snapshot = nil
    sub = ActiveSupport::Notifications.subscribe("track_relay.event") do |*, _|
      snapshot = TrackRelay::Current.client_id
    end

    cookies["_ga"] = "GA1.2.123456789.1700000000"
    get article_path(1)
    assert_equal "123456789.1700000000", snapshot
  ensure
    ActiveSupport::Notifications.unsubscribe(sub) if sub
  end

  test "missing _ga cookie falls through to Session UUID (Phase 02 chain)" do
    # Phase 02: when the _ga cookie is absent and Ahoy isn't in play,
    # the default chain falls through to {ClientId::Session}, which
    # mints a SecureRandom UUID into session[:track_relay_client_id].
    # Phase 01 returned nil here; Phase 02 returns a stable UUID.
    snapshot = :sentinel
    sub = ActiveSupport::Notifications.subscribe("track_relay.event") do |*, _|
      snapshot = TrackRelay::Current.client_id
    end

    get article_path(1)
    refute_nil snapshot, "Session resolver should mint a UUID when no _ga cookie is present"
    assert_match(/\A[0-9a-f-]{36}\z/, snapshot)
  ensure
    ActiveSupport::Notifications.unsubscribe(sub) if sub
  end

  test "malformed _ga cookie falls through to Session UUID (Phase 02 chain)" do
    # Same fall-through logic when the cookie has fewer than four
    # segments — the Ga resolver returns nil, then Session takes over.
    snapshot = :sentinel
    sub = ActiveSupport::Notifications.subscribe("track_relay.event") do |*, _|
      snapshot = TrackRelay::Current.client_id
    end

    cookies["_ga"] = "GA1.2"
    get article_path(1)
    refute_nil snapshot
    assert_match(/\A[0-9a-f-]{36}\z/, snapshot)
  ensure
    ActiveSupport::Notifications.unsubscribe(sub) if sub
  end
end
