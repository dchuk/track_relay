# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

# End-to-end integration coverage for the Plan 02-04 retry / discard
# wiring. Three layers must cooperate:
#
#   1. {Subscribers::Ga4MeasurementProtocol#deliver} maps HTTP responses
#      to {DeliveryRetriableError} / {DeliveryDiscardableError}.
#   2. {Subscribers::Base#safe_deliver}'s carve-out re-raises those two
#      classes (the REQ-23 narrow exception).
#   3. {DeliveryJob} declares
#      `retry_on TrackRelay::DeliveryRetriableError` and
#      `discard_on TrackRelay::DeliveryDiscardableError`.
#
# If ANY of those three is mis-wired, the retry policy is silently
# broken in production. This file is the canary.
class Ga4DeliveryRetryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  GA4_URL = TrackRelay::Subscribers::Ga4MeasurementProtocol::ENDPOINT_URL

  setup do
    TrackRelay.configure do |c|
      c.ga4_measurement_id = "G-TEST123"
      c.ga4_api_secret = "secret-abc"
    end
  end

  def build_payload_hash
    TrackRelay::EventPayload.untyped(
      name: :purchase,
      params: {value: 9.99, currency: "USD"},
      context: {client_id: "860784081.1732738496"},
      timestamp: Time.utc(2026, 5, 6, 12, 0, 0)
    ).to_h
  end

  def stub_ga4(status:, body: "")
    stub_request(:post, GA4_URL)
      .with(query: hash_including({}))
      .to_return(status: status, body: body)
  end

  # ---- retry_on / discard_on declared on the class ------------------

  test "DeliveryJob declares retry_on TrackRelay::DeliveryRetriableError" do
    handlers = TrackRelay::DeliveryJob.send(:rescue_handlers)
    classes = handlers.flat_map { |h| Array(h[0]) }
    assert_includes classes, "TrackRelay::DeliveryRetriableError",
      "retry_on must register TrackRelay::DeliveryRetriableError"
  end

  test "DeliveryJob declares discard_on TrackRelay::DeliveryDiscardableError" do
    handlers = TrackRelay::DeliveryJob.send(:rescue_handlers)
    classes = handlers.flat_map { |h| Array(h[0]) }
    assert_includes classes, "TrackRelay::DeliveryDiscardableError",
      "discard_on must register TrackRelay::DeliveryDiscardableError"
  end

  test "DEFAULT_GA4_DELIVERY_ATTEMPTS is the class-local constant 5" do
    assert_equal 5, TrackRelay::DeliveryJob::DEFAULT_GA4_DELIVERY_ATTEMPTS
  end

  test "config does not expose ga4_delivery_attempts (deferred to Phase 4)" do
    refute_respond_to TrackRelay.config, :ga4_delivery_attempts
  end

  # ---- 5xx → DeliveryRetriableError → re-enqueue --------------------

  test "5xx response triggers retry_on (job is re-enqueued)" do
    TrackRelay.config.swallow_subscriber_errors = false
    stub_ga4(status: 503, body: "Service Unavailable")

    # `retry_on` schedules a re-enqueue when the exception is raised.
    # Under the :test adapter, perform_now executes the rescue handler,
    # which calls `retry_job` => assert_enqueued_with sees the new job.
    assert_enqueued_with(job: TrackRelay::DeliveryJob) do
      TrackRelay::DeliveryJob.perform_now(
        "TrackRelay::Subscribers::Ga4MeasurementProtocol",
        build_payload_hash
      )
    end
  end

  # ---- 4xx → DeliveryDiscardableError → silent drop -----------------

  test "4xx response triggers discard_on (no re-enqueue, no exception bubbles)" do
    TrackRelay.config.swallow_subscriber_errors = false
    stub_ga4(status: 400, body: "Bad Request")

    # discard_on swallows the exception entirely — the job appears to
    # have completed successfully from the queue's perspective.
    assert_no_enqueued_jobs(only: TrackRelay::DeliveryJob) do
      assert_nothing_raised do
        TrackRelay::DeliveryJob.perform_now(
          "TrackRelay::Subscribers::Ga4MeasurementProtocol",
          build_payload_hash
        )
      end
    end
  end

  # ---- network errors → DeliveryRetriableError → re-enqueue ---------

  test "Errno::ECONNREFUSED triggers retry_on" do
    TrackRelay.config.swallow_subscriber_errors = false
    stub_request(:post, GA4_URL)
      .with(query: hash_including({}))
      .to_raise(Errno::ECONNREFUSED)

    assert_enqueued_with(job: TrackRelay::DeliveryJob) do
      TrackRelay::DeliveryJob.perform_now(
        "TrackRelay::Subscribers::Ga4MeasurementProtocol",
        build_payload_hash
      )
    end
  end

  test "Net::OpenTimeout triggers retry_on" do
    TrackRelay.config.swallow_subscriber_errors = false
    stub_request(:post, GA4_URL)
      .with(query: hash_including({}))
      .to_raise(Net::OpenTimeout)

    assert_enqueued_with(job: TrackRelay::DeliveryJob) do
      TrackRelay::DeliveryJob.perform_now(
        "TrackRelay::Subscribers::Ga4MeasurementProtocol",
        build_payload_hash
      )
    end
  end

  # ---- carve-out works END-TO-END with swallow_subscriber_errors=true ----

  test "carve-out: swallow_subscriber_errors=true STILL retries on 5xx" do
    # The load-bearing production scenario: REQ-23's blanket-rescue
    # would normally catch DeliveryRetriableError inside safe_deliver
    # and return it as a value, hiding it from ActiveJob. The Plan
    # 02-04 carve-out re-raises those typed exceptions so retry_on
    # fires. Without the carve-out this test would NOT enqueue a retry.
    TrackRelay.config.swallow_subscriber_errors = true
    stub_ga4(status: 503)

    assert_enqueued_with(job: TrackRelay::DeliveryJob) do
      TrackRelay::DeliveryJob.perform_now(
        "TrackRelay::Subscribers::Ga4MeasurementProtocol",
        build_payload_hash
      )
    end
  end

  test "carve-out: swallow_subscriber_errors=true STILL discards on 4xx" do
    TrackRelay.config.swallow_subscriber_errors = true
    stub_ga4(status: 400)

    assert_no_enqueued_jobs(only: TrackRelay::DeliveryJob) do
      assert_nothing_raised do
        TrackRelay::DeliveryJob.perform_now(
          "TrackRelay::Subscribers::Ga4MeasurementProtocol",
          build_payload_hash
        )
      end
    end
  end

  # ---- arbitrary StandardError: unchanged REQ-23 swallow path ------

  test "non-carve-out StandardError still follows REQ-23 swallow path under swallow=true" do
    # An unrelated bug in #deliver (e.g. NoMethodError) should NOT
    # trigger retry_on (it's not a DeliveryRetriableError) and should
    # NOT bubble up under swallow=true. Confirms the carve-out didn't
    # widen REQ-23.
    TrackRelay.config.swallow_subscriber_errors = true

    # Force a non-typed error by stubbing the GA4 endpoint with a
    # non-mappable response — a 200 OK still allows the subscriber's
    # internal logic to run, so we instead inject a buggy subscriber
    # whose #deliver raises RuntimeError.
    klass = Class.new(TrackRelay::Subscribers::Base) do
      def deliver(_payload) = raise "boom"
    end
    Object.const_set(:GenericBoomSubscriber, klass)

    begin
      assert_no_enqueued_jobs(only: TrackRelay::DeliveryJob) do
        assert_nothing_raised do
          TrackRelay::DeliveryJob.perform_now("GenericBoomSubscriber", build_payload_hash)
        end
      end
    ensure
      Object.send(:remove_const, :GenericBoomSubscriber)
    end
  end
end
