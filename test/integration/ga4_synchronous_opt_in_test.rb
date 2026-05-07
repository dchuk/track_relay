# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# Pin REQ-11's `synchronous!` opt-in path for the GA4 subscriber.
#
# The default contract (Plan 02-04 Task 2) ships
# {Subscribers::Ga4MeasurementProtocol} as **async** — `#handle`
# enqueues a {DeliveryJob}. Hosts that need inline delivery (test
# determinism, low-traffic ingestion, debugging) can call
# `.synchronous!` on the class. This test verifies that the inline
# path takes effect: the HTTP POST happens INSIDE the `track`
# call, and NO `DeliveryJob` is enqueued.
#
# The `synchronous!` machinery itself is Phase-1 Subscribers::Base
# scaffolding (see `test/unit/subscribers/base_filter_test.rb`-style
# coverage). This integration test only verifies that the GA4
# subscriber participates correctly.
#
# **Important:** `synchronous!` mutates a class-level
# `class_attribute`, which means the change leaks across tests
# unless we reset it. We capture-and-restore in setup/teardown.
class Ga4SynchronousOptInTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  GA4_URL = TrackRelay::Subscribers::Ga4MeasurementProtocol::ENDPOINT_URL

  setup do
    @prior_synchronous = TrackRelay::Subscribers::Ga4MeasurementProtocol.synchronous

    TrackRelay.configure do |c|
      c.ga4_measurement_id = "G-TEST123"
      c.ga4_api_secret = "secret-abc"
      c.subscribe(TrackRelay::Subscribers::Ga4MeasurementProtocol.new)
    end

    TrackRelay::Dispatcher.start!
  end

  teardown do
    TrackRelay::Subscribers::Ga4MeasurementProtocol.synchronous = @prior_synchronous
  end

  def stub_ga4(status: 200)
    stub_request(:post, GA4_URL)
      .with(query: hash_including({}))
      .to_return(status: status, body: "")
  end

  test "synchronous! opt-in dispatches inline (POST happens inside track call, no job enqueued)" do
    TrackRelay::Subscribers::Ga4MeasurementProtocol.synchronous!
    stub_ga4

    # Use payload-context client_id since there's no controller wiring
    # in this integration test.
    assert_no_enqueued_jobs(only: TrackRelay::DeliveryJob) do
      TrackRelay.track(:purchase, value: 9.99, currency: "USD", client_id: "860784081.1732738496")
    end

    assert_requested(:post, GA4_URL, query: hash_including({}))
  end

  test "default (no synchronous!) enqueues a DeliveryJob and does NOT post inline" do
    # Sanity-check the inverse: WITHOUT synchronous!, track returns
    # before the POST happens — the DeliveryJob is enqueued instead.
    refute TrackRelay::Subscribers::Ga4MeasurementProtocol.synchronous,
      "Default state must be async — earlier test's synchronous! flag leaked"

    # Stub anyway so a misbehaving inline path would still be caught
    # by webmock's allow-list rather than crashing on a real connect.
    stub_ga4

    assert_enqueued_with(job: TrackRelay::DeliveryJob) do
      TrackRelay.track(:purchase, value: 1.0, client_id: "860784081.1732738496")
    end

    # The job is enqueued but not yet executed under :test adapter;
    # verify no HTTP went out before the job runs.
    assert_not_requested(:post, GA4_URL, query: hash_including({}))
  end
end
