# frozen_string_literal: true

require "test_helper"

# Host-level fan-out gate (issue #1).
#
# `config.track_gate` is an optional callable evaluated once per
# {TrackRelay.track} call, before the `track_relay.event` notification
# fires — i.e. before ANY subscriber runs. Returning a falsy value
# drops the event for every subscriber; truthy allows it. `nil`
# (unset, the default) preserves current behavior.
#
# The callable receives `payload:` and `request:` keywords — the same
# keyword-style contract as the client_id resolver chain — so a host
# can implement e.g. "only track requests that prove a real browser":
#
#   config.track_gate = ->(payload:, request:) {
#     TrackRelay::ClientId::Ga.from_request(request)
#   }
class TrackGateTest < ActiveSupport::TestCase
  FakeRequest = Struct.new(:cookies, :original_url, :referer, :request_id, keyword_init: true)

  setup do
    @capture = TrackRelay::Subscribers::Test.new
    TrackRelay.configure do |c|
      c.subscribe(@capture)
    end
    TrackRelay::Dispatcher.start!
  end

  test "track_gate returning false drops the event for every subscriber" do
    TrackRelay.config.track_gate = ->(payload:, request:) { false }

    TrackRelay.track(:purchase, value: 1.0)

    assert_empty @capture.events
  end

  test "track_gate returning truthy lets the event through" do
    TrackRelay.config.track_gate = ->(payload:, request:) { true }

    TrackRelay.track(:purchase, value: 1.0)

    assert_equal 1, @capture.events.size
  end

  test "track_gate receives the built payload and the current request" do
    seen = nil
    TrackRelay.config.track_gate = ->(payload:, request:) {
      seen = {payload: payload, request: request}
      true
    }
    request = FakeRequest.new(cookies: {"_ga" => "GA1.1.1.2"}, original_url: "u", referer: nil, request_id: "r")

    TrackRelay.track(:purchase, value: 1.0, request: request)

    assert_kind_of TrackRelay::EventPayload, seen[:payload]
    assert_equal :purchase, seen[:payload].name
    assert_same request, seen[:request]
  end

  test "unset track_gate (default) tracks exactly as before" do
    assert_nil TrackRelay.config.track_gate

    TrackRelay.track(:purchase, value: 1.0)

    assert_equal 1, @capture.events.size
  end

  test "a browser-proof gate built on ClientId::Ga drops cookieless requests for all subscribers" do
    TrackRelay.config.track_gate = ->(payload:, request:) {
      TrackRelay::ClientId::Ga.from_request(request)
    }

    cookieless = FakeRequest.new(cookies: {}, original_url: "u", referer: nil, request_id: "r1")
    with_cookie = FakeRequest.new(
      cookies: {"_ga" => "GA1.1.860784081.1732738496"},
      original_url: "u", referer: nil, request_id: "r2"
    )

    TrackRelay.track(:purchase, value: 1.0, request: cookieless)
    TrackRelay.track(:purchase, value: 2.0, request: with_cookie)

    assert_equal 1, @capture.events.size
    assert_equal({value: 2.0}, @capture.events.first.params)
  end
end
