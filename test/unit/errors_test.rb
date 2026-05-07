# frozen_string_literal: true

require "test_helper"

# Unit coverage for the typed exceptions in `lib/track_relay/errors.rb`.
#
# The two new classes added in Plan 02-04 — {TrackRelay::DeliveryRetriableError}
# and {TrackRelay::DeliveryDiscardableError} — are the load-bearing wire
# between `Subscribers::Ga4MeasurementProtocol#deliver` and the
# {DeliveryJob}'s `retry_on` / `discard_on` declarations. They must
# inherit from `StandardError` (NOT {TrackRelay::Error}) so:
#
#   1. ActiveJob's `retry_on`/`discard_on` will catch them (those macros
#      match StandardError subclasses).
#   2. Consumers who rescue `TrackRelay::Error` to log validation
#      failures do not accidentally swallow a retriable network blip.
#   3. The {Subscribers::Base#safe_deliver} carve-out can re-raise them
#      cleanly via `rescue ... ; raise`.
class TrackRelay::ErrorsTest < ActiveSupport::TestCase
  # ---- DeliveryRetriableError ---------------------------------------

  test "DeliveryRetriableError inherits from StandardError" do
    assert_kind_of StandardError, TrackRelay::DeliveryRetriableError.new
  end

  test "DeliveryRetriableError does NOT inherit from TrackRelay::Error" do
    refute_kind_of TrackRelay::Error, TrackRelay::DeliveryRetriableError.new,
      "Inheriting from TrackRelay::Error would let a `rescue TrackRelay::Error` " \
      "block silently swallow retriable network failures — see errors.rb rationale."
  end

  test "DeliveryRetriableError carries its message" do
    err = TrackRelay::DeliveryRetriableError.new("ga4 5xx")
    assert_equal "ga4 5xx", err.message
  end

  # ---- DeliveryDiscardableError -------------------------------------

  test "DeliveryDiscardableError inherits from StandardError" do
    assert_kind_of StandardError, TrackRelay::DeliveryDiscardableError.new
  end

  test "DeliveryDiscardableError does NOT inherit from TrackRelay::Error" do
    refute_kind_of TrackRelay::Error, TrackRelay::DeliveryDiscardableError.new
  end

  test "DeliveryDiscardableError carries its message" do
    err = TrackRelay::DeliveryDiscardableError.new("ga4 400 bad request")
    assert_equal "ga4 400 bad request", err.message
  end

  # ---- Ga4ConstraintError (existing — confirm contract preserved) ---

  test "Ga4ConstraintError still inherits from TrackRelay::Error (pre-existing contract)" do
    # Plan 02-04 reuses the existing class; this test pins the
    # inheritance so a future refactor doesn't accidentally re-parent it
    # to StandardError and break `rescue TrackRelay::Error` consumers.
    assert_kind_of TrackRelay::Error, TrackRelay::Ga4ConstraintError.new
  end
end
