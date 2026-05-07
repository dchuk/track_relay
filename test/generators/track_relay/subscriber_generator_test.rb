# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/track_relay/subscriber/subscriber_generator"

module TrackRelay
  module Generators
    class SubscriberGeneratorTest < Rails::Generators::TestCase
      tests TrackRelay::Generators::SubscriberGenerator
      destination File.expand_path("../../../tmp/generator_test", __dir__)
      setup :prepare_destination

      test "writes subscriber to app/track_relay/subscribers/<name>_subscriber.rb" do
        run_generator ["Slack"]
        assert_file "app/track_relay/subscribers/slack_subscriber.rb" do |content|
          assert_match(/class SlackSubscriber < TrackRelay::Subscribers::Base/, content)
          assert_match(/def deliver\(payload\)/, content)
        end
      end

      test "includes registration-in-initializer comment with class_name interpolated" do
        run_generator ["MyAnalytics"]
        assert_file "app/track_relay/subscribers/my_analytics_subscriber.rb" do |content|
          assert_match(/config\.subscribe MyAnalyticsSubscriber\.new/, content)
        end
      end

      test "includes commented-out synchronous! and filter examples" do
        run_generator ["webhook_relay"]
        assert_file "app/track_relay/subscribers/webhook_relay_subscriber.rb" do |content|
          assert_match(/# synchronous!/, content)
          assert_match(/# filter only: %i\[webhook_relay\]/, content)
        end
      end
    end
  end
end
