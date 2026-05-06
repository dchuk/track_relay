# frozen_string_literal: true

require "test_helper"
require "track_relay/configuration"

class TrackRelay::ConfigurationTest < ActiveSupport::TestCase
  setup { @config = TrackRelay::Configuration.new }

  # ---------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------

  test "new config starts with an empty subscribers array" do
    assert_equal [], @config.subscribers
  end

  test "untyped_events_allowed defaults to true" do
    assert_equal true, @config.untyped_events_allowed
  end

  test "untyped_log_path defaults to nil" do
    assert_nil @config.untyped_log_path
  end

  test "force_synchronous defaults to false" do
    assert_equal false, @config.force_synchronous
  end

  test "swallow_subscriber_errors is false in test env" do
    # Combustion sets RAILS_ENV=test before this file loads, so the
    # production-only default ("true") should not apply here.
    assert_equal false, @config.swallow_subscriber_errors
  end

  test "raise_on_validation_error defaults to true in test env" do
    # development_or_test? -> true under Combustion's test env
    assert_equal true, @config.raise_on_validation_error
  end

  # ---------------------------------------------------------------
  # subscribe
  # ---------------------------------------------------------------

  test "subscribe(obj) appends and returns obj" do
    sub = Object.new
    returned = @config.subscribe(sub)

    assert_same sub, returned
    assert_equal [sub], @config.subscribers
  end

  test "subscribe is chainable / multiple subscribers preserved in order" do
    a = Object.new
    b = Object.new
    @config.subscribe(a)
    @config.subscribe(b)

    assert_equal [a, b], @config.subscribers
  end

  # ---------------------------------------------------------------
  # replace_subscribers (Plan 07's test_mode! atomic-swap helper)
  # ---------------------------------------------------------------

  test "replace_subscribers swaps the list and returns the previous one" do
    original_a = Object.new
    original_b = Object.new
    @config.subscribe(original_a)
    @config.subscribe(original_b)

    new_a = Object.new
    previous = @config.replace_subscribers([new_a])

    assert_equal [original_a, original_b], previous
    assert_equal [new_a], @config.subscribers
  end

  test "replace_subscribers coerces nil to empty array" do
    @config.subscribe(Object.new)
    @config.replace_subscribers(nil)

    assert_equal [], @config.subscribers
  end

  # ---------------------------------------------------------------
  # reset!
  # ---------------------------------------------------------------

  test "reset! clears subscribers and restores defaults" do
    @config.subscribe(Object.new)
    @config.untyped_events_allowed = false
    @config.force_synchronous = true
    @config.untyped_log_path = "/tmp/foo.log"

    @config.reset!

    assert_equal [], @config.subscribers
    assert_equal true, @config.untyped_events_allowed
    assert_equal false, @config.force_synchronous
    assert_nil @config.untyped_log_path
  end
end
