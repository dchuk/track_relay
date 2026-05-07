# frozen_string_literal: true

require "rails/generators"

module TrackRelay
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates a TrackRelay initializer, sample catalog, and ApplicationSubscriber, and includes TrackRelay::ControllerTracking in ApplicationController."

      def create_initializer
        template "initializer.rb.tt", "config/initializers/track_relay.rb"
      end

      def create_sample_catalog
        template "sample_catalog.rb.tt", "config/track_relay/sample.rb"
      end

      def create_application_subscriber
        template "application_subscriber.rb.tt", "app/track_relay/subscribers/application_subscriber.rb"
      end

      def inject_controller_tracking
        controller_path = "app/controllers/application_controller.rb"
        unless File.exist?(File.join(destination_root, controller_path))
          say_status :skip, "#{controller_path} not found; add `include TrackRelay::ControllerTracking` manually", :yellow
          return
        end

        existing = File.read(File.join(destination_root, controller_path))
        if existing.include?("TrackRelay::ControllerTracking")
          say_status :identical, "#{controller_path} already includes TrackRelay::ControllerTracking", :blue
          return
        end

        inject_into_class controller_path, "ApplicationController", "  include TrackRelay::ControllerTracking\n"
      end

      def post_install_message
        say ""
        say "TrackRelay installed.", :green
        say "  Edit config/initializers/track_relay.rb to wire subscribers."
        say "  Edit config/track_relay/sample.rb (or rails g track_relay:event NAME) to define events."
        say "  Run `bundle exec rake test` — it should pass cleanly out of the box."
      end
    end
  end
end
