# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# Browser-proof delivery gate for the GA4 subscriber (issue #1).
#
# When `config.ga4_require_browser_client_id = true`, the GA4
# Measurement Protocol subscriber delivers ONLY when the current
# request carries a genuine `_ga` cookie — the cookie is set by gtag
# JS, which bots and scrapers don't execute, so its presence is proof
# of a real browser. No cookie (or a malformed one) means no
# DeliveryJob is enqueued at all — never the random client_id
# fallback.
#
# Everything here goes through the public `TrackRelay.track` path with
# the Dispatcher running, passing the request via the `request:`
# reserved key exactly as ControllerTracking does.
class Ga4BrowserGateTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  GA4_URL = TrackRelay::Subscribers::Ga4MeasurementProtocol::ENDPOINT_URL

  FakeRequest = Struct.new(:cookies, :original_url, :referer, :request_id, keyword_init: true)

  setup do
    TrackRelay.configure do |c|
      c.ga4_measurement_id = "G-TEST123"
      c.ga4_api_secret = "secret-abc"
      c.ga4_require_browser_client_id = true
      c.subscribe(TrackRelay::Subscribers::Ga4MeasurementProtocol.new)
    end

    TrackRelay::Dispatcher.start!
  end

  def fake_request(cookies: {}, original_url: "https://example.test/articles/42", referer: nil)
    FakeRequest.new(
      cookies: cookies,
      original_url: original_url,
      referer: referer,
      request_id: "req-1"
    )
  end

  test "gate enabled: request without a _ga cookie enqueues no GA4 delivery" do
    assert_no_enqueued_jobs(only: TrackRelay::DeliveryJob) do
      TrackRelay.track(:purchase, value: 9.99, request: fake_request(cookies: {}))
    end
  end

  test "gate enabled: valid _ga cookie delivers exactly once with the cookie-derived client_id" do
    stub_request(:post, GA4_URL)
      .with(query: hash_including({}))
      .to_return(status: 200, body: "")

    assert_enqueued_jobs(1, only: TrackRelay::DeliveryJob) do
      TrackRelay.track(
        :purchase,
        value: 9.99,
        request: fake_request(cookies: {"_ga" => "GA1.1.860784081.1732738496"})
      )
    end

    perform_enqueued_jobs(only: TrackRelay::DeliveryJob)

    assert_requested(:post, GA4_URL, query: hash_including({}), times: 1) do |req|
      body = JSON.parse(req.body)
      assert_equal "860784081.1732738496", body["client_id"]
      true
    end
  end

  test "gate enabled: malformed _ga cookie (fewer than 4 segments) enqueues no delivery" do
    assert_no_enqueued_jobs(only: TrackRelay::DeliveryJob) do
      TrackRelay.track(:purchase, value: 1.0, request: fake_request(cookies: {"_ga" => "GA1.1"}))
    end
  end

  test "gate enabled: track outside a request (no request in scope) enqueues no delivery" do
    assert_no_enqueued_jobs(only: TrackRelay::DeliveryJob) do
      TrackRelay.track(:purchase, value: 1.0, client_id: "860784081.1732738496")
    end
  end

  test "gate disabled (default): cookieless track still delivers with the fallback client_id" do
    TrackRelay.config.ga4_require_browser_client_id = false

    assert_enqueued_jobs(1, only: TrackRelay::DeliveryJob) do
      TrackRelay.track(:purchase, value: 1.0, request: fake_request(cookies: {}))
    end
  end
end
