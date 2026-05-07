# frozen_string_literal: true

require "rails/generators"

module TrackRelay
  module Generators
    class EventGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Creates a typed catalog entry stub at config/track_relay/<name>.rb."

      def create_event_file
        template "event.rb.tt", "config/track_relay/#{file_name}.rb"
      end
    end
  end
end
