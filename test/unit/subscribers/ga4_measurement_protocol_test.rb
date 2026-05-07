# frozen_string_literal: true

require "test_helper"
require "json"

# Webmock-stubbed unit coverage for {TrackRelay::Subscribers::Ga4MeasurementProtocol}.
#
# This file pins the GA4 Measurement Protocol wire contract (Scout §2):
#
#   POST https://www.google-analytics.com/mp/collect
#     ?measurement_id=G-XXXXXXXXXX
#     &api_secret=<secret>
#   Content-Type: application/json
#   Body: {
#     "client_id": "<from payload.context[:client_id]>",
#     "user_id":   "<optional>",
#     "timestamp_micros": <int>,
#     "events": [{ "name": "<event_name>", "params": { ... } }]
#   }
#
# The subscriber is invoked synchronously here (no DeliveryJob) so the
# tests exercise the HTTP layer in isolation. Async / retry semantics
# live in `test/integration/ga4_delivery_retry_test.rb`.
#
# Note on stub URLs: webmock matches the full URI including query
# string, so each `stub_request` for GA4 specifies the query
# explicitly via `with(query: ...)` (or uses `hash_including({})` to
# match any). Bare `stub_request(:post, GA4_URL)` would NOT match the
# subscriber's request because it includes `?measurement_id=...&api_secret=...`.
class TrackRelay::Subscribers::Ga4MeasurementProtocolTest < ActiveSupport::TestCase
  GA4_URL = TrackRelay::Subscribers::Ga4MeasurementProtocol::ENDPOINT_URL
  GA4_URL_EU = TrackRelay::Subscribers::Ga4MeasurementProtocol::ENDPOINT_URL_EU

  setup do
    @subscriber = TrackRelay::Subscribers::Ga4MeasurementProtocol.new
    TrackRelay.configure do |c|
      c.ga4_measurement_id = "G-TEST123"
      c.ga4_api_secret = "secret-abc"
    end
    @log_io = StringIO.new
    @prior_logger = Rails.logger
    Rails.logger = ::Logger.new(@log_io)
  end

  teardown do
    Rails.logger = @prior_logger
  end

  def build_payload(name, params, context: {})
    TrackRelay::EventPayload.untyped(
      name: name,
      params: params,
      context: {client_id: "860784081.1732738496"}.merge(context),
      timestamp: Time.utc(2026, 5, 6, 12, 0, 0)
    )
  end

  # Default stub for any `with(query: ...)` matcher — used when the test
  # doesn't care about query string assertions.
  def stub_ga4(url: GA4_URL, status: 200, body: "")
    stub_request(:post, url)
      .with(query: hash_including({}))
      .to_return(status: status, body: body)
  end

  # ---- Happy path: URL + query string + JSON body --------------------

  test "POSTs to mp/collect with measurement_id and api_secret in query string" do
    stub = stub_request(:post, GA4_URL)
      .with(query: {measurement_id: "G-TEST123", api_secret: "secret-abc"})
      .to_return(status: 200, body: "")

    @subscriber.deliver(build_payload(:purchase, {value: 9.99, currency: "USD"}))

    assert_requested(stub)
  end

  test "request body has client_id from payload.context, timestamp_micros, and events array" do
    stub_ga4

    @subscriber.deliver(build_payload(:purchase, {value: 9.99, currency: "USD"}))

    assert_requested(:post, GA4_URL, query: hash_including({})) do |req|
      body = JSON.parse(req.body)
      assert_equal "860784081.1732738496", body["client_id"]
      assert_kind_of Integer, body["timestamp_micros"]
      assert_equal 1, body["events"].size
      assert_equal "purchase", body["events"][0]["name"]
      assert_equal({"value" => 9.99, "currency" => "USD"}, body["events"][0]["params"])
      true
    end
  end

  test "Content-Type header is application/json" do
    stub_ga4

    @subscriber.deliver(build_payload(:purchase, {}))

    assert_requested(:post, GA4_URL,
      query: hash_including({}),
      headers: {"Content-Type" => "application/json"})
  end

  test "user_id from payload.context is forwarded as top-level user_id" do
    stub_ga4

    payload = build_payload(:sign_up, {method: "email"}, context: {user_id: "user_42"})
    @subscriber.deliver(payload)

    assert_requested(:post, GA4_URL, query: hash_including({})) do |req|
      body = JSON.parse(req.body)
      assert_equal "user_42", body["user_id"]
      true
    end
  end

  test "timestamp_micros derives from payload.timestamp" do
    stub_ga4

    expected_micros = (Time.utc(2026, 5, 6, 12, 0, 0).to_f * 1_000_000).to_i
    @subscriber.deliver(build_payload(:purchase, {}))

    assert_requested(:post, GA4_URL, query: hash_including({})) do |req|
      body = JSON.parse(req.body)
      assert_equal expected_micros, body["timestamp_micros"]
      true
    end
  end

  test "Symbol param keys are stringified in the JSON body" do
    stub_ga4

    @subscriber.deliver(build_payload(:purchase, {value: 9.99, item_id: "sku-1"}))

    assert_requested(:post, GA4_URL, query: hash_including({})) do |req|
      body = JSON.parse(req.body)
      keys = body["events"][0]["params"].keys
      assert_includes keys, "value"
      assert_includes keys, "item_id"
      true
    end
  end

  # ---- EU-region toggle ---------------------------------------------

  test "ga4_use_eu_endpoint = true posts to region1.google-analytics.com" do
    TrackRelay.config.ga4_use_eu_endpoint = true
    stub = stub_request(:post, GA4_URL_EU)
      .with(query: {measurement_id: "G-TEST123", api_secret: "secret-abc"})
      .to_return(status: 200, body: "")

    @subscriber.deliver(build_payload(:purchase, {value: 1.0}))

    assert_requested(stub)
  end

  test "ga4_use_eu_endpoint = false (default) posts to www.google-analytics.com" do
    stub_ga4

    @subscriber.deliver(build_payload(:purchase, {value: 1.0}))

    assert_requested(:post, GA4_URL, query: hash_including({}))
  end

  # ---- Missing credentials --------------------------------------

  test "missing ga4_measurement_id logs warn and skips POST" do
    TrackRelay.config.ga4_measurement_id = nil

    @subscriber.deliver(build_payload(:purchase, {}))

    # No request was made — webmock would have raised on unstubbed call.
    assert_match(/missing config: ga4_measurement_id/, @log_io.string)
  end

  test "missing ga4_api_secret logs warn and skips POST" do
    TrackRelay.config.ga4_api_secret = nil

    @subscriber.deliver(build_payload(:purchase, {}))

    assert_match(/missing config: ga4_api_secret/, @log_io.string)
  end

  test "both credentials missing — single warn line names both" do
    TrackRelay.config.ga4_measurement_id = nil
    TrackRelay.config.ga4_api_secret = nil

    @subscriber.deliver(build_payload(:purchase, {}))

    assert_match(/missing config: ga4_measurement_id, ga4_api_secret/, @log_io.string)
  end

  # ---- Async-by-default contract ------------------------------------

  test "Ga4MeasurementProtocol is async by default (no synchronous! call)" do
    refute TrackRelay::Subscribers::Ga4MeasurementProtocol.synchronous,
      "GA4 subscriber must be async by default per REQ-11; opt in via .synchronous!"
  end

  # ---- Error mapping (5xx / 4xx / network) --------------------------

  test "5xx response raises DeliveryRetriableError" do
    stub_ga4(status: 503, body: "Service Unavailable")

    err = assert_raises(TrackRelay::DeliveryRetriableError) do
      @subscriber.deliver(build_payload(:purchase, {}))
    end
    assert_match(/HTTP 503/, err.message)
  end

  test "500 response raises DeliveryRetriableError" do
    stub_ga4(status: 500)

    assert_raises(TrackRelay::DeliveryRetriableError) do
      @subscriber.deliver(build_payload(:purchase, {}))
    end
  end

  test "4xx response raises DeliveryDiscardableError" do
    stub_ga4(status: 400, body: "Bad Request")

    err = assert_raises(TrackRelay::DeliveryDiscardableError) do
      @subscriber.deliver(build_payload(:purchase, {}))
    end
    assert_match(/HTTP 400/, err.message)
  end

  test "401 response raises DeliveryDiscardableError (defensive — GA4 returns 2xx in practice)" do
    stub_ga4(status: 401)

    assert_raises(TrackRelay::DeliveryDiscardableError) do
      @subscriber.deliver(build_payload(:purchase, {}))
    end
  end

  test "Errno::ECONNREFUSED raises DeliveryRetriableError" do
    stub_request(:post, GA4_URL)
      .with(query: hash_including({}))
      .to_raise(Errno::ECONNREFUSED)

    err = assert_raises(TrackRelay::DeliveryRetriableError) do
      @subscriber.deliver(build_payload(:purchase, {}))
    end
    assert_match(/Errno::ECONNREFUSED/, err.message)
  end

  test "SocketError raises DeliveryRetriableError" do
    stub_request(:post, GA4_URL)
      .with(query: hash_including({}))
      .to_raise(SocketError.new("getaddrinfo failed"))

    assert_raises(TrackRelay::DeliveryRetriableError) do
      @subscriber.deliver(build_payload(:purchase, {}))
    end
  end

  test "Net::OpenTimeout raises DeliveryRetriableError" do
    stub_request(:post, GA4_URL)
      .with(query: hash_including({}))
      .to_raise(Net::OpenTimeout)

    assert_raises(TrackRelay::DeliveryRetriableError) do
      @subscriber.deliver(build_payload(:purchase, {}))
    end
  end

  # ---- Fallback client_id ---------------------------------------

  test "missing payload context client_id falls back to a synthesized rand.timestamp value" do
    stub_ga4

    payload = TrackRelay::EventPayload.untyped(
      name: :purchase,
      params: {},
      context: {},
      timestamp: Time.utc(2026, 5, 6, 12, 0, 0)
    )
    @subscriber.deliver(payload)

    assert_requested(:post, GA4_URL, query: hash_including({})) do |req|
      body = JSON.parse(req.body)
      # Synthesized as "<rand>.<unix_ts>" — must look like client_id
      assert_match(/\A\d+\.\d+\z/, body["client_id"])
      true
    end
  end
end
