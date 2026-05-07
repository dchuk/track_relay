# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/track_relay/install/install_generator"

module TrackRelay
  module Generators
    class InstallGeneratorTest < Rails::Generators::TestCase
      tests TrackRelay::Generators::InstallGenerator
      destination File.expand_path("../../../tmp/generator_test", __dir__)
      setup :prepare_destination

      test "creates richly commented initializer" do
        run_generator
        assert_file "config/initializers/track_relay.rb" do |content|
          assert_match(/TrackRelay\.configure do \|config\|/, content)
          assert_match(/Subscribers::Logger\.new/, content)
          assert_match(/# config\.subscribe TrackRelay::Subscribers::Ahoy/, content)
          assert_match(/Requires the .ahoy_matey. gem/, content)
        end
      end

      test "creates sample catalog with hello_world event" do
        run_generator
        assert_file "config/track_relay/sample.rb" do |content|
          assert_match(/TrackRelay\.catalog do/, content)
          assert_match(/event :hello_world do/, content)
          assert_match(/string :message, required: true/, content)
        end
      end

      test "creates ApplicationSubscriber base class" do
        run_generator
        assert_file "app/track_relay/subscribers/application_subscriber.rb" do |content|
          assert_match(/class ApplicationSubscriber < TrackRelay::Subscribers::Base/, content)
          assert_match(/def deliver\(payload\)/, content)
          assert_match(/raise NotImplementedError/, content)
        end
      end

      test "injects ControllerTracking into ApplicationController when not yet included" do
        # prepare_destination yields an empty tree — create the stub first.
        FileUtils.mkdir_p(File.join(destination_root, "app/controllers"))
        File.write(
          File.join(destination_root, "app/controllers/application_controller.rb"),
          "class ApplicationController < ActionController::Base\nend\n"
        )
        run_generator
        assert_file "app/controllers/application_controller.rb" do |content|
          assert_match(/include TrackRelay::ControllerTracking/, content)
        end
      end

      test "skips ControllerTracking inject when already included (idempotent)" do
        FileUtils.mkdir_p(File.join(destination_root, "app/controllers"))
        original = "class ApplicationController < ActionController::Base\n  include TrackRelay::ControllerTracking\nend\n"
        File.write(File.join(destination_root, "app/controllers/application_controller.rb"), original)
        run_generator
        assert_file "app/controllers/application_controller.rb" do |content|
          # Single include only — no duplicate.
          assert_equal 1, content.scan(/include TrackRelay::ControllerTracking/).size
        end
      end

      test "skips inject and prints message when ApplicationController is missing" do
        # prepare_destination already wiped the tree; no ApplicationController exists.
        # The generator should NOT crash and should NOT create the controller file.
        run_generator
        assert_no_file "app/controllers/application_controller.rb"
      end
    end
  end
end
