# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

# Integration coverage for {TrackRelay::Subscribers::Logger}.
#
# Two outputs:
#
# 1. **Always** writes a human-readable line to `Rails.logger.info`:
#    `[track_relay] event=<name> kind=<typed|untyped> params=[...]`.
# 2. **Only when** {Configuration#untyped_log_path} is set AND the
#    payload is untyped, appends a JSONL line to that path with
#    EXACTLY these keys: event, params, controller, action, timestamp.
#    Param **values** are NEVER written — only param **names** (sorted,
#    stringified). This is the locked privacy contract from
#    01-CONTEXT.md.
#
# Tests use a tmpdir for `untyped_log_path` and a StringIO logger for
# Rails.logger so they leave no artifacts behind.
class SubscribersLoggerTest < ActiveSupport::TestCase
  setup do
    @log_io = StringIO.new
    @prior_logger = Rails.logger
    Rails.logger = ::Logger.new(@log_io)

    @tmpdir = Dir.mktmpdir("track_relay_logger_test")
    @jsonl_path = File.join(@tmpdir, "untyped.jsonl")
  end

  teardown do
    Rails.logger = @prior_logger
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  # ---- Helpers ------------------------------------------------------

  def build_typed_payload
    definition = TrackRelay::EventDefinition.new(
      name: :article_viewed,
      params: {
        article_id: TrackRelay::EventDefinition::ParamSchema.new(
          name: :article_id, type: :integer, required: true
        )
      }
    )
    TrackRelay::EventPayload.new(
      definition: definition,
      params: {article_id: 42},
      context: {controller: "ArticlesController", action: "show"},
      timestamp: Time.utc(2026, 5, 6, 12, 0, 0)
    )
  end

  def build_untyped_payload(params: {a: 1, b: 2}, context: {controller: "ArticlesController", action: "show"})
    TrackRelay::EventPayload.untyped(
      name: :adhoc_event,
      params: params,
      context: context,
      timestamp: Time.utc(2026, 5, 6, 12, 0, 0)
    )
  end

  def jsonl_lines
    return [] unless File.exist?(@jsonl_path)
    File.readlines(@jsonl_path, chomp: true)
  end

  # ---- synchronous! ------------------------------------------------

  test "Logger is synchronous! (delivers inline, never enqueues)" do
    assert TrackRelay::Subscribers::Logger.synchronous,
      "Subscribers::Logger must opt into synchronous!"
  end

  # ---- Typed event: human line only --------------------------------

  test "typed event: writes Rails.logger.info with kind=typed; never writes JSONL" do
    TrackRelay.config.untyped_log_path = @jsonl_path
    sub = TrackRelay::Subscribers::Logger.new

    sub.deliver(build_typed_payload)

    assert_match(/\[track_relay\] event=article_viewed kind=typed/, @log_io.string)
    assert_equal [], jsonl_lines, "JSONL is for untyped events only"
  end

  # ---- Untyped event, no path: human line only ---------------------

  test "untyped event, untyped_log_path unset: only human log line; no file write" do
    TrackRelay.config.untyped_log_path = nil
    sub = TrackRelay::Subscribers::Logger.new

    sub.deliver(build_untyped_payload)

    assert_match(/\[track_relay\] event=adhoc_event kind=untyped/, @log_io.string)
    refute File.exist?(@jsonl_path), "no JSONL file should be created when path is unset"
  end

  # ---- Untyped event, path set: JSONL line shape -------------------

  test "untyped event, path set: JSONL line keys are exactly [action, controller, event, params, timestamp]" do
    TrackRelay.config.untyped_log_path = @jsonl_path
    sub = TrackRelay::Subscribers::Logger.new

    sub.deliver(build_untyped_payload)

    lines = jsonl_lines
    assert_equal 1, lines.size

    parsed = JSON.parse(lines.first)
    assert_equal %w[action controller event params timestamp], parsed.keys.sort
  end

  test "untyped event JSONL: event is name string; params is sorted name array; controller/action populate; timestamp is ISO8601" do
    TrackRelay.config.untyped_log_path = @jsonl_path
    sub = TrackRelay::Subscribers::Logger.new

    sub.deliver(build_untyped_payload(params: {b: "x", a: "y"}))

    parsed = JSON.parse(jsonl_lines.first)
    assert_equal "adhoc_event", parsed["event"]
    assert_equal ["a", "b"], parsed["params"], "params is the sorted Array of param NAMES (strings)"
    assert_equal "ArticlesController", parsed["controller"]
    assert_equal "show", parsed["action"]
    assert_equal "2026-05-06T12:00:00Z", parsed["timestamp"]
  end

  test "untyped event JSONL: controller and action are null when context is missing them" do
    TrackRelay.config.untyped_log_path = @jsonl_path
    sub = TrackRelay::Subscribers::Logger.new

    sub.deliver(build_untyped_payload(context: {}))

    parsed = JSON.parse(jsonl_lines.first)
    assert_nil parsed["controller"]
    assert_nil parsed["action"]
  end

  # ---- Privacy regression ------------------------------------------

  test "PRIVACY: param VALUES are NEVER written to the JSONL — only param NAMES" do
    TrackRelay.config.untyped_log_path = @jsonl_path
    sub = TrackRelay::Subscribers::Logger.new

    sub.deliver(build_untyped_payload(params: {secret_token: "abc123", email: "user@example.com"}))

    raw = File.read(@jsonl_path)

    refute_includes raw, "abc123",
      "secret param VALUE leaked into JSONL — privacy contract violation"
    refute_includes raw, "user@example.com",
      "email param VALUE leaked into JSONL — privacy contract violation"
    # Names must still be present.
    assert_includes raw, "secret_token"
    assert_includes raw, "email"
  end

  # ---- Append semantics --------------------------------------------

  test "multiple untyped events append: line count grows by one per event" do
    TrackRelay.config.untyped_log_path = @jsonl_path
    sub = TrackRelay::Subscribers::Logger.new

    sub.deliver(build_untyped_payload(params: {a: 1}))
    sub.deliver(build_untyped_payload(params: {b: 2}))
    sub.deliver(build_untyped_payload(params: {c: 3}))

    assert_equal 3, jsonl_lines.size
  end
end
