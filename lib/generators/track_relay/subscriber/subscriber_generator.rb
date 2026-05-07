# frozen_string_literal: true

require "rails/generators"

module TrackRelay
  module Generators
    class SubscriberGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Creates a subscriber class stub at app/track_relay/subscribers/<name>_subscriber.rb."

      def create_subscriber_file
        template "subscriber.rb.tt", "app/track_relay/subscribers/#{file_name}_subscriber.rb"
      end
    end
  end
end
