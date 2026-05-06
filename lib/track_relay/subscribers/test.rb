# frozen_string_literal: true

require "track_relay/subscribers/base"

module TrackRelay
  module Subscribers
    # In-memory capture subscriber for use in test suites.
    #
    # Plan 07 will wire this into `TrackRelay.test_mode!`, which swaps
    # the configured subscriber list for a single Test instance for the
    # duration of an example so consumer tests can assert against fired
    # events without sending them to real adapters.
    #
    # Per-instance state — no class-level globals — so multiple
    # instances do not crosstalk. {#clear!} resets the buffer; {#find}
    # filters by event name.
    #
    # @example
    #   sub = TrackRelay::Subscribers::Test.new
    #   sub.handle(payload)
    #   sub.events       # => [payload]
    #   sub.find(:foo)   # => [payload] if payload.name == :foo
    #   sub.clear!
    class Test < Base
      synchronous!

      # @return [Array<EventPayload>] captured payloads in insertion order
      attr_reader :events

      def initialize
        super
        @events = []
      end

      # Append the payload to {#events}. Called inline by {Base#handle}
      # because {.synchronous!} is set.
      #
      # @param payload [EventPayload]
      # @return [Array<EventPayload>] the events buffer (after append)
      def deliver(payload)
        @events << payload
      end

      # Clear the captured events buffer.
      #
      # @return [Array] the empty buffer
      def clear!
        @events.clear
      end

      # Return only the captured payloads whose `name` equals `name`.
      #
      # @param name [Symbol]
      # @return [Array<EventPayload>]
      def find(name)
        @events.select { |e| e.name == name }
      end
    end
  end
end
