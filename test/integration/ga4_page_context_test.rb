# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"
require "json"

# Notification-time page/session enrichment for GA4 MP events (issue #1).
#
# GA4 files server-side events under a blank page path unless the event
# params carry `page_location` (and friends). When
# `config.ga4_enrich_page_context = true`, the GA4 subscriber captures
# them from the current request INSIDE `#handle` — the request is gone
# by the time the async DeliveryJob performs — and rides them through
# the serialized payload:
#
#   - `page_location`  — always (request.original_url)
#   - `page_referrer`  — only when a referer exists
#   - `session_id` + `engagement_time_msec` — only when the gtag
#     session cookie `_ga_<stream>` is present and parseable
class Ga4PageContextTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  GA4_URL = TrackRelay::Subscribers::Ga4MeasurementProtocol::ENDPOINT_URL

  FakeRequest = Struct.new(:cookies, :original_url, :referer, :request_id, keyword_init: true)

  setup do
    TrackRelay.configure do |c|
      c.ga4_measurement_id = "G-TEST123"
      c.ga4_api_secret = "secret-abc"
      c.ga4_enrich_page_context = true
      c.subscribe(TrackRelay::Subscribers::Ga4MeasurementProtocol.new)
    end

    TrackRelay::Dispatcher.start!

    stub_request(:post, GA4_URL)
      .with(query: hash_including({}))
      .to_return(status: 200, body: "")
  end

  def fake_request(cookies: {}, original_url: "https://example.test/articles/42", referer: nil)
    FakeRequest.new(
      cookies: cookies,
      original_url: original_url,
      referer: referer,
      request_id: "req-1"
    )
  end

  def delivered_body
    perform_enqueued_jobs(only: TrackRelay::DeliveryJob)
    body = nil
    assert_requested(:post, GA4_URL, query: hash_including({}), times: 1) do |req|
      body = JSON.parse(req.body)
      true
    end
    body
  end

  test "delivered params include page_location from the request URL" do
    TrackRelay.track(:purchase, value: 9.99, request: fake_request)

    params = delivered_body["events"][0]["params"]
    assert_equal "https://example.test/articles/42", params["page_location"]
  end

  test "page_referrer is included only when the request has a referer" do
    TrackRelay.track(:purchase, value: 1.0, request: fake_request(referer: "https://news.ycombinator.com/"))

    params = delivered_body["events"][0]["params"]
    assert_equal "https://news.ycombinator.com/", params["page_referrer"]
  end

  test "page_referrer is omitted when the request has no referer" do
    TrackRelay.track(:purchase, value: 1.0, request: fake_request(referer: nil))

    params = delivered_body["events"][0]["params"]
    refute_includes params.keys, "page_referrer"
  end

  test "gtag session cookie yields session_id and a nominal engagement_time_msec" do
    request = fake_request(cookies: {"_ga_TEST123" => "GS1.1.1700000456.3.1.1700000789.60.0.0"})
    TrackRelay.track(:purchase, value: 1.0, request: request)

    params = delivered_body["events"][0]["params"]
    assert_equal "1700000456", params["session_id"]
    assert_equal 100, params["engagement_time_msec"]
  end

  test "malformed gtag session cookie omits session params but still delivers page_location" do
    request = fake_request(cookies: {"_ga_TEST123" => "GS1.1"})
    TrackRelay.track(:purchase, value: 1.0, request: request)

    params = delivered_body["events"][0]["params"]
    assert_equal "https://example.test/articles/42", params["page_location"]
    refute_includes params.keys, "session_id"
    refute_includes params.keys, "engagement_time_msec"
  end

  test "enrichment enabled but no request in scope delivers the original params untouched" do
    TrackRelay.track(:purchase, value: 1.0, client_id: "860784081.1732738496")

    params = delivered_body["events"][0]["params"]
    assert_equal({"value" => 1.0}, params)
  end

  test "peer subscribers receive the original payload — never the GA4-enriched copy" do
    TrackRelay.config.ga4_require_browser_client_id = true
    peer = TrackRelay.config.subscribe(TrackRelay::Subscribers::Test.new)

    request = fake_request(
      cookies: {"_ga" => "GA1.1.860784081.1732738496", "_ga_TEST123" => "GS1.1.1700000456.3.1.1700000789.60.0.0"},
      referer: "https://news.ycombinator.com/"
    )
    TrackRelay.track(:purchase, value: 1.0, request: request)

    assert_equal 1, peer.events.size
    peer_payload = peer.events.first
    assert_equal({value: 1.0}, peer_payload.params)
    refute_includes peer_payload.params.keys, :page_location
    assert_nil peer_payload.context[:client_id]
  end
end
