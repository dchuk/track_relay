# frozen_string_literal: true

# RSpec matchers for {TrackRelay}.
#
# Loaded conditionally — guarded by `defined?(RSpec)` so requiring
# `track_relay/testing` is safe even when RSpec is not on the load
# path. Consumers who use RSpec require this file from their
# `rails_helper.rb` (or rely on the auto-load below from
# `track_relay/testing.rb`).
#
# Provided matchers:
#
#   - `have_tracked(name)` — passes when at least one event named
#     `name` was captured by the active Test subscriber. Supports
#     `.with(**params)` to require subset-matching params on at least
#     one captured event.
#   - `have_identified(user)` — Phase-01 placeholder that never
#     matches; identify capture in the Test subscriber is deferred to
#     Phase 02.
#
# Usage:
#
#   require "track_relay/testing"
#
#   RSpec.describe "checkout" do
#     before { TrackRelay.test_mode! }
#     after  { TrackRelay.test_mode_off! }
#
#     it "fires :purchase" do
#       Checkout.run!
#       expect(track_relay).to have_tracked(:purchase).with(amount_cents: 1999)
#     end
#   end
#
# The `track_relay` example-group helper (registered below) returns
# the active Test subscriber so `expect(track_relay).to ...` reads
# naturally. The matcher itself reads the global
# `TrackRelay.test_subscriber`, so the receiver is mostly stylistic.
if defined?(RSpec)
  RSpec::Matchers.define :have_tracked do |name|
    match do |_actual|
      raise "Call TrackRelay.test_mode! before have_tracked" unless TrackRelay::Testing.active?
      events = TrackRelay.test_subscriber.find(name)
      next false if events.empty?
      next true if @expected_params.nil?
      events.any? { |e| @expected_params.all? { |k, v| e.params[k] == v } }
    end

    chain :with do |params|
      @expected_params = params
    end

    failure_message do |_actual|
      seen = TrackRelay.test_subscriber.events.map { |e| {name: e.name, params: e.params} }
      msg = "expected an event :#{name} to be tracked"
      msg += " with params >= #{@expected_params.inspect}" if @expected_params
      "#{msg}, but got #{seen.inspect}"
    end
  end

  RSpec::Matchers.define :have_identified do |_user|
    # Phase 01 placeholder: identify capture is not yet wired into the
    # Test subscriber. Documented as TODO for Phase 02.
    match { |_actual| false }
    failure_message { "have_identified is not yet implemented in Phase 01" }
  end

  if defined?(RSpec.configure)
    RSpec.configure do |config|
      config.include(Module.new do
        # Returns the active Test subscriber so RSpec example groups
        # can write `expect(track_relay).to have_tracked(...)`.
        def track_relay
          TrackRelay.test_subscriber || raise("Call TrackRelay.test_mode! first")
        end
      end)
    end
  end
end
