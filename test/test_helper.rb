# frozen_string_literal: true

require "bundler/setup"
require "combustion"

Combustion.path = "test/internal"
Combustion.initialize!(:action_controller, :active_job) do
  config.active_job.queue_adapter = :test
  config.logger = ActiveSupport::Logger.new(IO::NULL)
end

require "track_relay"
require "minitest/autorun"
require "active_support/current_attributes/test_helper"

class ActiveSupport::TestCase
  include ActiveSupport::CurrentAttributes::TestHelper
end
