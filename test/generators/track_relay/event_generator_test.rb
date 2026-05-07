# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/track_relay/event/event_generator"

module TrackRelay
  module Generators
    class EventGeneratorTest < Rails::Generators::TestCase
      tests TrackRelay::Generators::EventGenerator
      destination File.expand_path("../../../tmp/generator_test", __dir__)
      setup :prepare_destination

      test "snake_cases the NAME argument and writes a single catalog file" do
        run_generator ["ArticleViewed"]
        assert_file "config/track_relay/article_viewed.rb" do |content|
          assert_match(/TrackRelay\.catalog do/, content)
          assert_match(/event :article_viewed do/, content)
          assert_match(/ArticleViewed event/, content)
        end
      end

      test "accepts an already-snake_case NAME argument" do
        run_generator ["purchase_completed"]
        assert_file "config/track_relay/purchase_completed.rb" do |content|
          assert_match(/event :purchase_completed do/, content)
        end
      end

      test "includes commented-out type stubs for all 5 supported types" do
        run_generator ["sample_event"]
        assert_file "config/track_relay/sample_event.rb" do |content|
          assert_match(/# integer :/, content)
          assert_match(/# string\s+:/, content)
          assert_match(/# float\s+:/, content)
          assert_match(/# boolean :/, content)
          assert_match(/# datetime :/, content)
        end
      end
    end
  end
end
