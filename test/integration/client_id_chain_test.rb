# frozen_string_literal: true

require "test_helper"

# End-to-end coverage for the configurable client_id resolver chain in
# {TrackRelay::ControllerTracking} — Plan 02-02 Task 4.
#
# Drives the Combustion dummy app's `ArticlesController` (which
# includes `TrackRelay::ControllerTracking`) through realistic
# controller flow. After each `get`, the test inspects
# `TrackRelay::Current.client_id` snapshot to confirm the chain
# resolved as expected:
#
#   - Phase-1 parity: `_ga` cookie present → `ClientId::Ga` value
#   - First-non-nil semantics: chain stops at first resolver that
#     returns a non-nil value
#   - Custom resolvers inserted at position 0 win over defaults
#   - A resolver raising StandardError is skipped silently — the chain
#     continues and returns the next resolver's value
#   - The Session resolver yields a session-stable UUID across two
#     requests (i.e. before_action invocations) on the same session
class ClientIdChainTest < ActionDispatch::IntegrationTest
  setup do
    TrackRelay.catalog do
      event :article_viewed do
        integer :article_id, required: true
        string :slug, required: true
      end
    end
    @snapshots = []
    @subscription = ActiveSupport::Notifications.subscribe("track_relay.event") do |*, _|
      @snapshots << TrackRelay::Current.client_id
    end
  end

  teardown do
    ActiveSupport::Notifications.unsubscribe(@subscription) if @subscription
  end

  # Test-only resolver: returns a constant value so we can assert chain
  # ordering without touching cookies/Ahoy/session state.
  class ConstantResolver
    def initialize(value)
      @value = value
    end

    def call(controller:, **)
      @value
    end
  end

  # Test-only resolver that always raises. Used to prove the chain
  # rescues StandardError and continues.
  class RaisingResolver
    def call(controller:, **)
      raise StandardError, "boom"
    end
  end

  # ---- Phase-1 parity ----------------------------------------------------

  test "_ga cookie present yields the same client_id as Phase 1's parser" do
    cookies["_ga"] = "GA1.2.123456789.1700000000"
    get article_path(1)

    assert_equal "123456789.1700000000", @snapshots.last
  end

  # ---- First-non-nil semantics ------------------------------------------

  test "first non-nil resolver wins; later resolvers are not invoked" do
    invoked = []
    early = Class.new do
      define_method(:call) do |**|
        invoked << :early
        "from-early"
      end
    end.new
    late = Class.new do
      define_method(:call) do |**|
        invoked << :late
        "from-late"
      end
    end.new

    TrackRelay.config.client_id_resolvers = [early, late]
    get article_path(1)

    assert_equal "from-early", @snapshots.last
    assert_equal [:early], invoked,
      "the chain must short-circuit on first non-nil result"
  end

  # ---- Custom resolver at position 0 ------------------------------------

  test "custom resolver inserted at position 0 wins over defaults" do
    TrackRelay.config.client_id_resolvers.unshift(ConstantResolver.new("custom-id"))
    cookies["_ga"] = "GA1.2.999.999"
    get article_path(1)

    assert_equal "custom-id", @snapshots.last,
      "custom resolver at position 0 must beat the default Ga resolver"
  end

  # ---- Exception isolation ----------------------------------------------

  test "a resolver raising StandardError does NOT abort the chain" do
    TrackRelay.config.client_id_resolvers = [
      RaisingResolver.new,
      ConstantResolver.new("after-raise")
    ]
    get article_path(1)

    assert_equal "after-raise", @snapshots.last,
      "the chain must rescue per-resolver errors and continue"
  end

  test "exception inside a resolver is rescued without re-raising" do
    TrackRelay.config.client_id_resolvers = [RaisingResolver.new]

    assert_nothing_raised do
      get article_path(1)
    end

    assert_nil @snapshots.last,
      "all resolvers raised → client_id is nil; no exception propagates"
  end

  # ---- AhoyVisitor placeholder integration ------------------------------

  test "no _ga cookie + AhoyVisitor returning a token yields that token" do
    ahoy_resolver = Class.new do
      def call(controller:, **)
        "tok-from-ahoy"
      end
    end.new

    TrackRelay.config.client_id_resolvers = [
      TrackRelay::ClientId::Ga.new,
      ahoy_resolver,
      TrackRelay::ClientId::Session.new
    ]
    get article_path(1)

    assert_equal "tok-from-ahoy", @snapshots.last
  end

  # ---- Session UUID is session-stable across requests -------------------

  test "Session-fallback UUID is stable across two before_action invocations" do
    # No _ga cookie → Ga returns nil. Default AhoyVisitor returns nil
    # (controller doesn't include Ahoy::Trackable). Session resolver
    # mints a UUID and stashes it in session[:track_relay_client_id]
    # so the next request sees the same value.
    get article_path(1)
    first = @snapshots.last
    refute_nil first, "Session resolver should mint a UUID on first request"
    assert_match(/\A[0-9a-f-]{36}\z/, first)

    get article_path(2)
    second = @snapshots.last
    assert_equal first, second,
      "client_id must persist across requests on the same session"
  end
end
