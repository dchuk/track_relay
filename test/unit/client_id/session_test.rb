# frozen_string_literal: true

require "test_helper"

# Unit coverage for {TrackRelay::ClientId::Session} — Plan 02-02 Task 2.
#
# Contract:
#
# - `#call(controller:, **)` reads `controller.session`.
# - On first call when `session[:track_relay_client_id]` is unset,
#   generates a `SecureRandom.uuid` and stores it under that key (so
#   subsequent requests in the same session get the SAME id).
# - On subsequent calls returns the previously stored UUID unchanged.
# - Returns `nil` when no session is available (controller is nil OR
#   `controller.session` is nil) — e.g. API-only controllers without
#   session middleware.
class TrackRelay::ClientId::SessionTest < ActiveSupport::TestCase
  StubController = Struct.new(:session)

  setup { @resolver = TrackRelay::ClientId::Session.new }

  test "first call generates a UUID and stores it under :track_relay_client_id" do
    session = {}
    controller = StubController.new(session)

    result = @resolver.call(controller: controller)

    refute_nil result
    assert_match(/\A[0-9a-f-]{36}\z/, result, "expected SecureRandom.uuid format")
    assert_equal result, session[:track_relay_client_id]
  end

  test "subsequent calls return the same stored UUID (session-stable)" do
    session = {}
    controller = StubController.new(session)

    first = @resolver.call(controller: controller)
    second = @resolver.call(controller: controller)
    third = @resolver.call(controller: controller)

    assert_equal first, second
    assert_equal first, third
  end

  test "returns the existing UUID when one was pre-seeded by a prior request" do
    session = {track_relay_client_id: "preexisting-uuid-from-last-request"}
    controller = StubController.new(session)

    assert_equal "preexisting-uuid-from-last-request",
      @resolver.call(controller: controller)
  end

  test "returns nil when controller is nil" do
    assert_nil @resolver.call(controller: nil)
  end

  test "returns nil when controller has no session" do
    controller = StubController.new(nil)

    assert_nil @resolver.call(controller: controller)
  end

  test "ignores unknown keyword arguments (forward-compatible)" do
    session = {}
    controller = StubController.new(session)

    result = @resolver.call(controller: controller, request: :ignored)
    refute_nil result
  end
end
