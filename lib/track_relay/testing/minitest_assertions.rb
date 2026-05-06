# frozen_string_literal: true

module TrackRelay
  module Testing
    # Minitest assertions for use against the active
    # {TrackRelay::Subscribers::Test} (the one installed by
    # {TrackRelay.test_mode!}).
    #
    # Designed to be mixed into `ActiveSupport::TestCase` /
    # `Minitest::Test` either directly or via {Helpers}, which also
    # registers per-test setup/teardown to enable test mode automatically.
    #
    # Used directly:
    #
    #   class MyTest < ActiveSupport::TestCase
    #     include TrackRelay::Testing::MinitestAssertions
    #
    #     setup    { TrackRelay.test_mode! }
    #     teardown { TrackRelay.test_mode_off! }
    #
    #     test "fires :foo" do
    #       MyService.run!
    #       assert_tracked :foo, user_id: 1
    #     end
    #   end
    #
    # Or via {Helpers}, which wires the setup/teardown for you.
    module MinitestAssertions
      # Return the active Test subscriber, or raise a helpful message
      # if {TrackRelay.test_mode!} has not been called yet.
      #
      # @raise [RuntimeError]
      # @return [TrackRelay::Subscribers::Test]
      def track_relay_test
        TrackRelay.test_subscriber ||
          raise("Call TrackRelay.test_mode! before using assert_tracked / refute_tracked")
      end

      # Assert at least one event named `name` was captured. When
      # `expected_params` is supplied, also assert at least one matching
      # event has params that include every key/value pair in
      # `expected_params` (subset semantics).
      #
      # @param name [Symbol]
      # @param expected_params [Hash{Symbol => Object}]
      # @raise [Minitest::Assertion] when the assertion fails
      # @return [void]
      def assert_tracked(name, **expected_params)
        events = track_relay_test.find(name)
        assert events.any?,
          "Expected an event :#{name} to be tracked, but found #{track_relay_test.events.map(&:name).inspect}"
        return if expected_params.empty?

        match = events.find { |e| expected_params.all? { |k, v| e.params[k] == v } }
        assert match,
          "Expected :#{name} with params >= #{expected_params.inspect}, got #{events.map(&:params).inspect}"
      end

      # Assert no event named `name` was captured.
      #
      # @param name [Symbol]
      # @raise [Minitest::Assertion] when an event named `name` was tracked
      # @return [void]
      def refute_tracked(name)
        events = track_relay_test.find(name)
        refute events.any?,
          "Expected no event :#{name} to be tracked, but got #{events.map(&:params).inspect}"
      end
    end
  end
end
