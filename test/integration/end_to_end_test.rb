# frozen_string_literal: true

require "test_helper"
require "tempfile"

# End-to-end integration test for the entire Phase-01 surface.
#
# This is the "everything works together" test — the canary that the
# pieces shipped in Plans 01-08 actually compose into the contract
# advertised by the README and CHANGELOG.
#
# Scope: catalog DSL → configure → track typed event → both subscribers
# (Test in-memory + Logger JSONL) receive it → fire untyped event →
# JSONL appended with the canonical five-key shape (event, params,
# controller, action, timestamp) → privacy contract verified (param
# VALUES never appear in the JSONL) → Linter reads the JSONL and
# reports the untyped event.
#
# Additional coverage: collect-then-swallow and collect-then-reraise
# dispatcher modes (Plan 05 contract); controller-context capture into
# the JSONL `action` field (Plan 04 contract).
class EndToEndTest < ActiveSupport::TestCase
  setup do
    @jsonl = Tempfile.new(["untyped", ".jsonl"])
    @jsonl.close

    TrackRelay.configure do |c|
      c.untyped_log_path = @jsonl.path
      c.untyped_events_allowed = true
      c.raise_on_validation_error = true
      c.subscribe(TrackRelay::Subscribers::Logger.new)
      c.subscribe(TrackRelay::Subscribers::Test.new)
    end

    TrackRelay.catalog do
      event :article_viewed do
        integer :article_id, required: true
        string :slug, required: true
      end
    end

    TrackRelay::Dispatcher.start!
  end

  teardown do
    @jsonl&.unlink
  end

  test "typed event flows through both subscribers; untyped event hits JSONL; linter reports untyped" do
    test_subscriber = TrackRelay.config.subscribers.find { |s| s.is_a?(TrackRelay::Subscribers::Test) }

    # Fire a typed event
    TrackRelay.track(:article_viewed, article_id: 42, slug: "hello-world")

    # Test subscriber captured it
    assert_equal 1, test_subscriber.events.size
    assert_equal :article_viewed, test_subscriber.events.first.name

    # JSONL is empty (typed events do NOT go to JSONL)
    assert_empty File.read(@jsonl.path).strip

    # Fire an untyped event
    TrackRelay.track(:adhoc_widget_clicked, widget_id: "btn-7", section: "header")

    # Test subscriber captured it too
    assert_equal 2, test_subscriber.events.size
    assert_equal :adhoc_widget_clicked, test_subscriber.events.last.name

    # JSONL has exactly one untyped line; values are absent (privacy contract)
    contents = File.read(@jsonl.path)
    assert_equal 1, contents.lines.size
    refute_match(/btn-7/, contents, "Param VALUES must never appear in JSONL — only NAMES")
    refute_match(/header/, contents)

    parsed = JSON.parse(contents.lines.first)
    assert_equal "adhoc_widget_clicked", parsed["event"]
    assert_equal %w[section widget_id], parsed["params"].sort
    # JSONL shape contract (Plan 05): exactly these five keys
    assert_equal %w[action controller event params timestamp], parsed.keys.sort

    # Linter reports the untyped event
    linter = TrackRelay::Linter.new(@jsonl.path)
    report = linter.report
    assert_equal 1, report.size
    assert_equal "adhoc_widget_clicked", report.first.event_name
    assert_equal 1, report.first.total
  end

  test "collect-then-swallow: peer subscribers receive even when a subscriber raises (quiet mode)" do
    boom = Class.new(TrackRelay::Subscribers::Base) do
      synchronous!
      def deliver(_)
        raise "boom from boom subscriber"
      end
    end.new

    test_sub = TrackRelay.config.subscribers.find { |s| s.is_a?(TrackRelay::Subscribers::Test) }
    TrackRelay.config.subscribers.unshift(boom)
    TrackRelay.config.swallow_subscriber_errors = true

    TrackRelay.track(:article_viewed, article_id: 1, slug: "x")

    # Test subscriber still received the event despite boom raising
    assert_equal 1, test_sub.events.size
  end

  test "collect-then-reraise: loudness mode raises AFTER all peers receive the event" do
    boom = Class.new(TrackRelay::Subscribers::Base) do
      synchronous!
      def deliver(_)
        raise "boom from boom subscriber"
      end
    end.new

    test_sub = TrackRelay.config.subscribers.find { |s| s.is_a?(TrackRelay::Subscribers::Test) }
    TrackRelay.config.subscribers.unshift(boom)
    TrackRelay.config.swallow_subscriber_errors = false

    err = assert_raises(RuntimeError) do
      TrackRelay.track(:article_viewed, article_id: 1, slug: "x")
    end
    assert_equal "boom from boom subscriber", err.message

    # Peer subscriber STILL received the event before the dispatcher re-raised
    assert_equal 1, test_sub.events.size
  end

  test "controller-context tracking populates JSONL action field with controller.action_name (Plan 04 contract)" do
    fake_controller = Class.new do
      def action_name
        "show"
      end
    end.new

    TrackRelay::Current.set(controller: fake_controller) do
      TrackRelay.track(:adhoc_in_controller, foo: "bar")
    end

    contents = File.read(@jsonl.path)
    parsed = JSON.parse(contents.lines.last)
    # Plan 04 requires payload.context[:action] = Current.controller&.action_name.
    # Plan 05's Logger writes that into the JSONL `action` field.
    # This test proves the controller→Current→payload.context→JSONL chain.
    assert_equal "show", parsed["action"],
      "JSONL action must equal Current.controller.action_name when fired in a controller context"
    assert_equal "adhoc_in_controller", parsed["event"]
  end
end
