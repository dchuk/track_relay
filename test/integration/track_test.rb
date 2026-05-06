# frozen_string_literal: true

require "test_helper"

# Integration coverage for the typed-event path of {TrackRelay.track}.
#
# Each test wires a tiny catalog in `setup`, fires an event, and uses
# `ActiveSupport::Notifications.subscribed { }` to capture the resulting
# `track_relay.event` notification. The payload of that notification
# is the {TrackRelay::EventPayload} the {TrackRelay::Instrumenter}
# built — which is the contract Plan 05's DeliveryJob will rely on.
#
# Catalog state and config mutations are reset by the `teardown` block
# in `test/test_helper.rb`, so no per-test cleanup is needed here.
class TrackTest < ActiveSupport::TestCase
  setup do
    TrackRelay.catalog do
      event :article_viewed do
        integer :article_id, required: true
        string :slug, required: true
        string :category
      end
    end
  end

  test "track instruments track_relay.event with EventPayload" do
    events = []
    ActiveSupport::Notifications.subscribed(->(e) { events << e }, "track_relay.event") do
      TrackRelay.track(:article_viewed, article_id: 1, slug: "hello", category: "news")
    end

    assert_equal 1, events.size
    payload = events.first.payload[:event]
    assert_kind_of TrackRelay::EventPayload, payload
    assert_equal :article_viewed, payload.name
    assert_equal({article_id: 1, slug: "hello", category: "news"}, payload.params)
  end

  test "track coerces params via EventPayload#validate!" do
    events = []
    ActiveSupport::Notifications.subscribed(->(e) { events << e }, "track_relay.event") do
      TrackRelay.track(:article_viewed, article_id: "42", slug: "x")
    end

    assert_equal 42, events.first.payload[:event].params[:article_id]
  end

  test "track raises ValidationError when raise_on_validation_error is true" do
    TrackRelay.config.raise_on_validation_error = true

    assert_raises(TrackRelay::ValidationError) do
      TrackRelay.track(:article_viewed, slug: "x")
    end
  end

  test "track does not instrument when validation fails AND swallow is enabled" do
    TrackRelay.config.raise_on_validation_error = false
    events = []

    ActiveSupport::Notifications.subscribed(->(e) { events << e }, "track_relay.event") do
      TrackRelay.track(:article_viewed, slug: "x")
    end

    assert_empty events
  end

  test "reserved :user goes to Current/context, never params" do
    user = Object.new
    events = []

    ActiveSupport::Notifications.subscribed(->(e) { events << e }, "track_relay.event") do
      TrackRelay.track(:article_viewed, article_id: 1, slug: "x", user: user)
    end

    payload = events.first.payload[:event]
    refute_includes payload.params.keys, :user
    assert_same user, payload.context[:user]
  end

  test ":visitor_token goes to context, never params, never Current" do
    events = []

    ActiveSupport::Notifications.subscribed(->(e) { events << e }, "track_relay.event") do
      TrackRelay.track(:article_viewed, article_id: 1, slug: "x", visitor_token: "vt-123")
    end

    payload = events.first.payload[:event]
    refute_includes payload.params.keys, :visitor_token
    assert_equal "vt-123", payload.context[:visitor_token]
    refute_respond_to TrackRelay::Current, :visitor_token,
      "Current should not expose :visitor_token; it lives only on payload.context"
  end
end
