# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "json"
require "stringio"
require "track_relay/linter"

# Pure-Minitest unit coverage for {TrackRelay::Linter}.
#
# The linter is a plain-Ruby class with no Rails dependency, so these
# tests load `track_relay/linter` directly and run without Combustion.
#
# Each fixture line uses the canonical Logger JSONL shape locked in
# Plan 05 / 01-CONTEXT.md:
#
#   {event:, params:, controller:, action:, timestamp:}
#
# `params` carries only sorted, stringified NAMES — the privacy contract
# from 01-CONTEXT.md says values are NEVER written to the sink. The
# linter dedupes on `event` + sorted `params`; `controller`, `action`,
# and `timestamp` are accepted but ignored for grouping.
class LinterTest < Minitest::Test
  def with_jsonl(lines)
    Tempfile.create(["untyped", ".jsonl"]) do |f|
      lines.each { |line| f.puts(line) }
      f.flush
      yield f.path
    end
  end

  def line(event:, params:, controller: "ArticlesController", action: "show",
    timestamp: "2026-05-06T12:00:00Z")
    JSON.generate(
      event: event,
      params: params,
      controller: controller,
      action: action,
      timestamp: timestamp
    )
  end

  # ---- empty / missing input ----------------------------------------

  def test_empty_file_returns_empty_report
    with_jsonl([]) do |path|
      linter = TrackRelay::Linter.new(path)
      assert_equal [], linter.report
      assert_equal 0, linter.malformed_lines
    end
  end

  def test_missing_file_returns_empty_report_without_error
    linter = TrackRelay::Linter.new("/tmp/track_relay_does_not_exist_#{rand(1_000_000)}.jsonl")
    assert_equal [], linter.report
    assert_equal 0, linter.malformed_lines
  end

  # ---- single-event, single-shape grouping --------------------------

  def test_one_event_one_shape_yields_one_report_with_one_signature
    fixture = [line(event: "ad_hoc", params: %w[article_id slug])]
    with_jsonl(fixture) do |path|
      linter = TrackRelay::Linter.new(path)
      reports = linter.report

      assert_equal 1, reports.size
      assert_equal "ad_hoc", reports.first.event_name
      assert_equal 1, reports.first.signatures.size
      assert_equal %w[article_id slug], reports.first.signatures.first.params
      assert_equal 1, reports.first.signatures.first.count
      assert_equal 1, reports.first.total
    end
  end

  # ---- single event, multiple param shapes (signatures) -------------

  def test_same_event_two_shapes_groups_into_one_report_with_two_signatures
    fixture = [
      line(event: "ad_hoc", params: %w[a b]),
      line(event: "ad_hoc", params: %w[a b]),  # bumps count to 2
      line(event: "ad_hoc", params: %w[a b c]) # different shape, count 1
    ]
    with_jsonl(fixture) do |path|
      reports = TrackRelay::Linter.new(path).report

      assert_equal 1, reports.size
      assert_equal "ad_hoc", reports.first.event_name
      assert_equal 3, reports.first.total
      assert_equal 2, reports.first.signatures.size
      # Signatures sorted by count desc.
      assert_equal %w[a b], reports.first.signatures.first.params
      assert_equal 2, reports.first.signatures.first.count
      assert_equal %w[a b c], reports.first.signatures.last.params
      assert_equal 1, reports.first.signatures.last.count
    end
  end

  # ---- multi-event sort order ---------------------------------------

  def test_multiple_events_sort_by_total_desc
    fixture = [
      line(event: "minor", params: %w[x]),
      line(event: "major", params: %w[a]),
      line(event: "major", params: %w[a]),
      line(event: "major", params: %w[a])
    ]
    with_jsonl(fixture) do |path|
      reports = TrackRelay::Linter.new(path).report

      assert_equal 2, reports.size
      assert_equal "major", reports.first.event_name
      assert_equal 3, reports.first.total
      assert_equal "minor", reports.last.event_name
      assert_equal 1, reports.last.total
    end
  end

  # ---- malformed input ----------------------------------------------

  def test_malformed_lines_are_skipped_and_counted
    fixture = [
      line(event: "ad_hoc", params: %w[a]),
      "this is not json",
      "{",  # incomplete JSON
      line(event: "ad_hoc", params: %w[a])
    ]
    with_jsonl(fixture) do |path|
      linter = TrackRelay::Linter.new(path)
      reports = linter.report

      assert_equal 1, reports.size
      assert_equal 2, reports.first.total
      assert_equal 2, linter.malformed_lines
    end
  end

  def test_blank_lines_are_silently_skipped
    fixture = [
      line(event: "ad_hoc", params: %w[a]),
      "",
      "   ",
      line(event: "ad_hoc", params: %w[a])
    ]
    with_jsonl(fixture) do |path|
      linter = TrackRelay::Linter.new(path)
      reports = linter.report

      assert_equal 1, reports.size
      assert_equal 2, reports.first.total
      # Blank lines are NOT malformed JSON — the linter just skips them.
      assert_equal 0, linter.malformed_lines
    end
  end

  # ---- print (human-readable output) --------------------------------

  def test_print_writes_human_readable_report_to_io
    fixture = [
      line(event: "ad_hoc", params: %w[article_id]),
      line(event: "ad_hoc", params: %w[article_id])
    ]
    with_jsonl(fixture) do |path|
      io = StringIO.new
      TrackRelay::Linter.new(path).print(io)

      out = io.string
      assert_match(/event :ad_hoc/, out)
      assert_match(/params=\[article_id\]/, out)
      assert_match(/count=2/, out)
      assert_match(/2 total/, out)
    end
  end

  def test_print_includes_malformed_warning_when_lines_were_skipped
    fixture = [line(event: "ad_hoc", params: %w[a]), "garbage"]
    with_jsonl(fixture) do |path|
      io = StringIO.new
      TrackRelay::Linter.new(path).print(io)

      assert_match(/1 malformed line/, io.string)
    end
  end

  # ---- to_json (machine-readable output, stable contract) -----------

  def test_to_json_emits_stable_machine_readable_structure
    fixture = [
      line(event: "ad_hoc", params: %w[bar foo]),
      line(event: "ad_hoc", params: %w[bar foo])
    ]
    with_jsonl(fixture) do |path|
      json = TrackRelay::Linter.new(path).to_json
      parsed = JSON.parse(json)

      assert_equal 1, parsed.size
      entry = parsed.first
      # Stable keys — Plan 09's CHANGELOG references this contract.
      assert_equal "ad_hoc", entry["event"]
      assert_equal 2, entry["total"]
      assert_equal 1, entry["signatures"].size
      assert_equal %w[bar foo], entry["signatures"].first["params"]
      assert_equal 2, entry["signatures"].first["count"]
    end
  end

  # ---- privacy / contract: ignored fields ---------------------------

  def test_controller_action_timestamp_are_accepted_but_ignored_for_grouping
    fixture = [
      line(event: "ad_hoc", params: %w[a], controller: "ArticlesController", action: "show", timestamp: "2026-05-06T12:00:00Z"),
      line(event: "ad_hoc", params: %w[a], controller: "PostsController", action: "index", timestamp: "2026-05-07T01:23:45Z")
    ]
    with_jsonl(fixture) do |path|
      reports = TrackRelay::Linter.new(path).report

      assert_equal 1, reports.size
      assert_equal 1, reports.first.signatures.size,
        "Different controller/action/timestamp must NOT split a signature group"
      assert_equal 2, reports.first.total
    end
  end
end
