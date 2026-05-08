# frozen_string_literal: true

require "test_helper"

# Unit coverage for {TrackRelay::ClientId::AhoyVisitor} — Plan 02-02 Task 2.
#
# Contract:
#
# - `#call(controller:, **)` returns `controller.ahoy.visitor_token`
#   when the controller exposes the Ahoy gem's `ahoy` helper.
# - Returns `nil` when the controller does NOT respond to `:ahoy`. Must
#   NOT raise NameError, must NOT require ahoy. Duck-typed via
#   `respond_to?(:ahoy, true)`.
# - Returns `nil` when `ahoy.visitor_token` is `nil`.
# - Returns `nil` when controller is nil.
class TrackRelay::ClientId::AhoyVisitorTest < ActiveSupport::TestCase
  AhoyDouble = Struct.new(:visitor_token)

  # Controller WITH ahoy helper (e.g. an Ahoy::Trackable-included
  # ApplicationController in a host app).
  class ControllerWithAhoy
    def initialize(token)
      @ahoy = AhoyDouble.new(token)
    end

    attr_reader :ahoy
  end

  # Controller WITHOUT ahoy — bare Object stand-in. `respond_to?(:ahoy, true)`
  # returns false; the resolver must short-circuit to nil without
  # touching the constant.
  ControllerWithoutAhoy = Class.new

  setup { @resolver = TrackRelay::ClientId::AhoyVisitor.new }

  test "returns visitor_token when ahoy is present" do
    controller = ControllerWithAhoy.new("tok-abc-123")

    assert_equal "tok-abc-123", @resolver.call(controller: controller)
  end

  test "returns nil when ahoy.visitor_token is nil" do
    controller = ControllerWithAhoy.new(nil)

    assert_nil @resolver.call(controller: controller)
  end

  test "returns nil when controller does not respond to :ahoy (no NameError)" do
    controller = ControllerWithoutAhoy.new

    assert_nil @resolver.call(controller: controller)
  end

  test "returns nil when controller is nil" do
    assert_nil @resolver.call(controller: nil)
  end

  test "ignores unknown keyword arguments (forward-compatible)" do
    controller = ControllerWithAhoy.new("tok-xyz")

    assert_equal "tok-xyz", @resolver.call(controller: controller, request: :ignored)
  end

  test "does not require ahoy gem" do
    # Sanity check: the resolver source MUST NOT contain a top-level
    # `require "ahoy"` (or `require "ahoy/..."`). If a future commit
    # adds one, this test fails loudly. We strip comments before
    # matching so doc strings that mention `require "ahoy"` are OK.
    source = File.read(File.expand_path("../../../lib/track_relay/client_id/ahoy_visitor.rb", __dir__))
    code = source.lines.reject { |l| l.lstrip.start_with?("#") }.join
    refute_match(/^\s*require\s+["']ahoy/, code,
      "AhoyVisitor must be duck-typed; never require the ahoy gem")
  end
end
