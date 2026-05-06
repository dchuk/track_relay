# frozen_string_literal: true

require "bundler/setup"
require "combustion"

# Require track_relay BEFORE Combustion.initialize! so that the
# Railtie is registered with Rails::Railtie.subclasses before the
# application boots. Otherwise the Railtie's initializers would never
# run because the host app finished booting before the gem was loaded.
require "track_relay"

Combustion.path = "test/internal"
Combustion.initialize!(:action_controller, :active_job) do
  config.active_job.queue_adapter = :test
  config.logger = ActiveSupport::Logger.new(IO::NULL)
end

require "minitest/autorun"
require "active_support/current_attributes/test_helper"

class ActiveSupport::TestCase
  include ActiveSupport::CurrentAttributes::TestHelper

  teardown do
    # Stop the global Dispatcher subscription so a test that starts it
    # does not leak its subscription block into subsequent tests. Safe
    # to call when the Dispatcher was never started.
    TrackRelay::Dispatcher.stop! if defined?(TrackRelay::Dispatcher)
    TrackRelay::Catalog.clear! if defined?(TrackRelay::Catalog)
    TrackRelay.reset_config!
  end
end
