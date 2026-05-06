# frozen_string_literal: true

require "track_relay"
require "track_relay/subscribers/test"

module TrackRelay
  # Opt-in testing entry point for {TrackRelay}.
  #
  # `lib/track_relay.rb` does NOT require this file — consumers add
  # `require "track_relay/testing"` themselves in their `test_helper.rb`
  # / `rails_helper.rb`. This keeps the auto setup/teardown helpers and
  # the RSpec matcher hooks out of production runtime. The gem's own
  # `test/test_helper.rb` performs that require explicitly because the
  # gem's tests are themselves consumers of the testing surface.
  #
  # `test_mode!` swaps the configured subscriber list for a single
  # {TrackRelay::Subscribers::Test} for the duration of an example so
  # consumer tests can assert against fired events without sending them
  # to real adapters. `test_mode_off!` restores the previously captured
  # list.
  #
  # `test_mode!` is idempotent: calling twice without restoring returns
  # the same Test instance and does NOT clobber the originally-captured
  # subscriber list. After `test_mode_off!`, calling `test_mode!` again
  # creates a fresh Test subscriber so per-test buffers stay isolated.
  module Testing
    module_function

    # Replace `TrackRelay.config.subscribers` with a single
    # {Subscribers::Test} and snapshot the previous list. Idempotent.
    #
    # @return [Subscribers::Test] the active test subscriber
    def test_mode!
      return @test_subscriber if active?
      test_subscriber = Subscribers::Test.new
      @previous_subscribers = TrackRelay.config.replace_subscribers([test_subscriber])
      @test_subscriber = test_subscriber
    end

    # Restore the subscriber list captured by {.test_mode!}. No-op when
    # not active.
    #
    # @return [void]
    def test_mode_off!
      return unless active?
      TrackRelay.config.replace_subscribers(@previous_subscribers)
      @previous_subscribers = nil
      @test_subscriber = nil
    end

    # @return [Boolean] whether {.test_mode!} is currently active
    def active?
      !@test_subscriber.nil?
    end

    # @return [Subscribers::Test, nil] the active test subscriber, or nil
    def test_subscriber
      @test_subscriber
    end
  end

  class << self
    # Convenience delegate to {Testing.test_mode!}.
    #
    # @return [Subscribers::Test]
    def test_mode!
      Testing.test_mode!
    end

    # Convenience delegate to {Testing.test_mode_off!}.
    #
    # @return [void]
    def test_mode_off!
      Testing.test_mode_off!
    end

    # Convenience delegate to {Testing.test_subscriber}.
    #
    # @return [Subscribers::Test, nil]
    def test_subscriber
      Testing.test_subscriber
    end
  end
end
