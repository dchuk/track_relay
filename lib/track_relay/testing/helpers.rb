# frozen_string_literal: true

require "track_relay/testing"
require "track_relay/testing/minitest_assertions"

module TrackRelay
  module Testing
    # Minitest mix-in that combines {MinitestAssertions} with auto
    # setup/teardown for {TrackRelay.test_mode!}.
    #
    # Including this module into `ActiveSupport::TestCase` /
    # `Minitest::Test`:
    #   1. mixes in `assert_tracked` / `refute_tracked` /
    #      `track_relay_test`;
    #   2. registers `setup` / `teardown` blocks that auto-enable
    #      `TrackRelay.test_mode!` per test, so each example gets a fresh
    #      Test subscriber.
    #
    #   class MyTest < ActiveSupport::TestCase
    #     include TrackRelay::Testing::Helpers
    #
    #     test "fires :foo" do
    #       MyService.run!
    #       assert_tracked :foo, user_id: 1
    #     end
    #   end
    #
    # The `setup` / `teardown` blocks only register when the including
    # class supports them (i.e. when included into a Minitest test
    # class). Including the module elsewhere is a no-op for the hooks;
    # `MinitestAssertions` is still mixed in so consumers can wire
    # `test_mode!` themselves.
    module Helpers
      def self.included(base)
        base.include(MinitestAssertions)

        if base.respond_to?(:setup) && base.respond_to?(:teardown)
          base.setup { TrackRelay.test_mode! }
          base.teardown { TrackRelay.test_mode_off! }
        end
      end
    end
  end
end
