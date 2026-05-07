# frozen_string_literal: true

require "test_helper"

# Unit coverage for {TrackRelay::ClientId::Ga} — Plan 02-02 Task 1.
#
# Contract:
#
# - `#call(controller:, **)` reads `controller.request.cookies["_ga"]`.
# - The `_ga` cookie format is `GA1.<version>.<random_int>.<unix_ts>`;
#   the GA4-shaped client_id is the last two dot-separated segments
#   joined with `.` (e.g. `"GA1.2.123.456"` → `"123.456"`).
# - Returns `nil` when the cookie is missing, empty, or malformed
#   (fewer than four dot-separated segments).
# - Behavior is bit-for-bit identical to Phase 1's
#   `_track_relay_client_id_from_cookie` parser at
#   `lib/track_relay/controller_tracking.rb:62-71`.
class TrackRelay::ClientId::GaTest < ActiveSupport::TestCase
  # Tiny stub controller exposing only what the resolver inspects:
  # `controller.request.cookies["_ga"]`. We avoid pulling in a real
  # ActionController to keep the unit test fast and focused.
  StubRequest = Struct.new(:cookies)
  StubController = Struct.new(:request)

  def stub_controller(ga_cookie)
    cookies = ga_cookie.nil? ? {} : {"_ga" => ga_cookie}
    StubController.new(StubRequest.new(cookies))
  end

  setup { @resolver = TrackRelay::ClientId::Ga.new }

  test "returns last two segments of a standard GA1 cookie" do
    controller = stub_controller("GA1.2.860784081.1732738496")
    assert_equal "860784081.1732738496", @resolver.call(controller: controller)
  end

  test "returns last two segments even when cookie has extra prefix segments" do
    # Robustness: parser always takes parts[-2..-1], not parts[2..3].
    controller = stub_controller("GA1.2.x.y.860784081.1732738496")
    assert_equal "860784081.1732738496", @resolver.call(controller: controller)
  end

  test "returns nil when the cookie is missing" do
    controller = stub_controller(nil)
    assert_nil @resolver.call(controller: controller)
  end

  test "returns nil when the cookie is empty" do
    controller = stub_controller("")
    assert_nil @resolver.call(controller: controller)
  end

  test "returns nil when the cookie has fewer than 4 segments" do
    controller = stub_controller("GA1.2")
    assert_nil @resolver.call(controller: controller)
  end

  test "returns nil when the cookie has exactly 3 segments" do
    controller = stub_controller("GA1.2.123")
    assert_nil @resolver.call(controller: controller)
  end

  test "returns nil when controller is nil" do
    assert_nil @resolver.call(controller: nil)
  end

  test "returns nil when controller has no request" do
    controller = StubController.new(nil)
    assert_nil @resolver.call(controller: controller)
  end

  test "ignores unknown keyword arguments (forward-compatible)" do
    controller = stub_controller("GA1.2.123.456")
    assert_equal "123.456", @resolver.call(controller: controller, request: :ignored)
  end
end
