# frozen_string_literal: true

require "test_helper"
require "json"

# REQ-27 split-enforcement coverage (call-time half) for
# {TrackRelay::Subscribers::Ga4MeasurementProtocol}.
#
# **The split** (Scout §8):
#
#   - **Boot-time** name-shape + reserved-name validation already
#     ships in {TrackRelay::Validators::Ga4Constraints} (catalog DSL
#     load path). Plan 02-04 does NOT replan that.
#   - **Call-time** payload checks live in
#     {Ga4MeasurementProtocol#validate_ga4_payload!}, invoked from
#     `#deliver` BEFORE the HTTP call. This file pins those checks.
#
# **Two checks** (call-time):
#
#   1. `payload.params.size > 25` — guards against dynamic runtime
#      overruns that the catalog's static ≤25 check cannot catch
#      (e.g. an untyped event built from user input).
#   2. Param keys whose name starts with `firebase_`, `ga_`, or
#      `google_` — GA4 reserves these prefixes; the existing
#      `NAME_PATTERN` regex does not block them.
#
# **Behavior gate** (REQ-05): both checks honor
# `config.raise_on_validation_error`:
#
#   - `true` (dev/test default) → raise {Ga4ConstraintError},
#     skip the POST.
#   - `false` (prod default)    → `Rails.logger.warn`, skip the
#     POST, return without raising.
class TrackRelay::Subscribers::Ga4PayloadValidationTest < ActiveSupport::TestCase
  GA4_URL = TrackRelay::Subscribers::Ga4MeasurementProtocol::ENDPOINT_URL

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

  def build_payload(name, params)
    TrackRelay::EventPayload.untyped(
      name: name,
      params: params,
      context: {client_id: "860784081.1732738496"},
      timestamp: Time.utc(2026, 5, 6, 12, 0, 0)
    )
  end

  def stub_ga4(status: 200)
    stub_request(:post, GA4_URL)
      .with(query: hash_including({}))
      .to_return(status: status, body: "")
  end

  # ---- > 25 params (dev/test: raise) -------------------------------

  test "26 params with raise_on_validation_error=true raises Ga4ConstraintError" do
    TrackRelay.config.raise_on_validation_error = true
    too_many = (1..26).each_with_object({}) { |i, h| h[:"k#{i}"] = i }

    err = assert_raises(TrackRelay::Ga4ConstraintError) do
      @subscriber.deliver(build_payload(:purchase, too_many))
    end
    assert_match(/26 params/, err.message)
    assert_match(/GA4 max is 25/, err.message)
  end

  test "26 params with raise_on_validation_error=true does NOT POST" do
    TrackRelay.config.raise_on_validation_error = true
    too_many = (1..26).each_with_object({}) { |i, h| h[:"k#{i}"] = i }

    # Register a stub that would explode if a request sneaks through.
    stub_ga4(status: 200)

    assert_raises(TrackRelay::Ga4ConstraintError) do
      @subscriber.deliver(build_payload(:purchase, too_many))
    end
    assert_not_requested(:post, GA4_URL, query: hash_including({}))
  end

  # ---- > 25 params (prod: log + skip) -------------------------------

  test "26 params with raise_on_validation_error=false logs warn and skips POST" do
    TrackRelay.config.raise_on_validation_error = false
    too_many = (1..26).each_with_object({}) { |i, h| h[:"k#{i}"] = i }

    stub_ga4(status: 200)
    @subscriber.deliver(build_payload(:purchase, too_many))

    assert_match(/26 params/, @log_io.string)
    assert_match(/GA4 max is 25/, @log_io.string)
    assert_not_requested(:post, GA4_URL, query: hash_including({}))
  end

  # ---- exactly 25 params is fine ------------------------------------

  test "exactly 25 params posts successfully" do
    stub_ga4(status: 200)
    twenty_five = (1..25).each_with_object({}) { |i, h| h[:"k#{i}"] = i }

    @subscriber.deliver(build_payload(:purchase, twenty_five))

    assert_requested(:post, GA4_URL, query: hash_including({}))
  end

  # ---- reserved-prefix: firebase_ -----------------------------------

  test "param key starting with firebase_ raises in dev/test" do
    TrackRelay.config.raise_on_validation_error = true

    err = assert_raises(TrackRelay::Ga4ConstraintError) do
      @subscriber.deliver(build_payload(:purchase, {firebase_x: 1}))
    end
    assert_match(/firebase_/, err.message)
    assert_match(/reserved prefix/, err.message)
  end

  test "param key starting with firebase_ logs and skips POST in prod" do
    TrackRelay.config.raise_on_validation_error = false
    stub_ga4

    @subscriber.deliver(build_payload(:purchase, {firebase_x: 1}))

    assert_match(/firebase_/, @log_io.string)
    assert_not_requested(:post, GA4_URL, query: hash_including({}))
  end

  # ---- reserved-prefix: ga_ -----------------------------------------

  test "param key starting with ga_ raises in dev/test" do
    TrackRelay.config.raise_on_validation_error = true

    err = assert_raises(TrackRelay::Ga4ConstraintError) do
      @subscriber.deliver(build_payload(:purchase, {ga_session: "x"}))
    end
    assert_match(/ga_session/, err.message)
  end

  # ---- reserved-prefix: google_ -------------------------------------

  test "param key starting with google_ raises in dev/test" do
    TrackRelay.config.raise_on_validation_error = true

    err = assert_raises(TrackRelay::Ga4ConstraintError) do
      @subscriber.deliver(build_payload(:purchase, {google_id: "y"}))
    end
    assert_match(/google_id/, err.message)
  end

  # ---- string param keys also covered (not just symbols) ------------

  test "string param key starting with firebase_ also raises" do
    TrackRelay.config.raise_on_validation_error = true

    assert_raises(TrackRelay::Ga4ConstraintError) do
      @subscriber.deliver(build_payload(:purchase, {"firebase_str" => 1}))
    end
  end

  # ---- clean payload: no warning, POST proceeds ---------------------

  test "clean payload (no constraint violation) POSTs without warnings" do
    stub_ga4

    @subscriber.deliver(build_payload(:purchase, {value: 9.99, currency: "USD"}))

    assert_requested(:post, GA4_URL, query: hash_including({}))
    refute_match(/GA4 payload/, @log_io.string)
    refute_match(/reserved prefix/, @log_io.string)
  end

  # ---- name-shape NOT re-validated at call time ---------------------

  test "non-snake_case event name does NOT raise at call time (boot-time validates names)" do
    # Plan 02-04 explicitly does NOT re-run event-name validation at
    # call time — that's covered by Validators::Ga4Constraints during
    # catalog load. An untyped event with a malformed name still flows
    # through the subscriber; GA4 will silently drop it (per Scout §2
    # line 211) but track_relay does not block it.
    stub_ga4

    assert_nothing_raised do
      @subscriber.deliver(build_payload(:BadName, {value: 1}))
    end
    assert_requested(:post, GA4_URL, query: hash_including({}))
  end
end
