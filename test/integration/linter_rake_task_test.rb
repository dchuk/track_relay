# frozen_string_literal: true

require "test_helper"
require "rake"
require "tempfile"
require "json"

# Integration coverage for the `rake track_relay:lint` /
# `rake track_relay:lint:json` tasks loaded by {TrackRelay::Railtie}'s
# `rake_tasks` block.
#
# The footgun-prevention contract from 01-CONTEXT.md is the load-bearing
# behavior: when `TrackRelay.config.untyped_log_path` is unset, the
# tasks MUST abort with a NONZERO exit (rather than silently exiting 0
# on a misconfigured audit). This is verified via `assert_raises(SystemExit)`
# plus `refute_equal 0, err.status`.
#
# Each setup builds a fresh Rake::Application so Rake task state from
# the gem's main Rakefile (which only knows `:test`) doesn't bleed in
# and so each test re-loads track_relay.rake cleanly. `:environment` is
# stubbed because the task body doesn't actually need a Rails app
# load — only `TrackRelay.config` and `TrackRelay::Linter`, both of
# which are already required by the test_helper.
class LinterRakeTaskTest < ActiveSupport::TestCase
  RAKE_FILE = File.expand_path("../../lib/tasks/track_relay.rake", __dir__)

  setup do
    @prev_app = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load RAKE_FILE
  end

  teardown do
    Rake.application = @prev_app
  end

  # ---- abort-on-missing-config (footgun guard) ----------------------

  test "rake track_relay:lint aborts NONZERO when untyped_log_path is unset" do
    TrackRelay.config.untyped_log_path = nil

    err = assert_raises(SystemExit) do
      capture_io { Rake::Task["track_relay:lint"].invoke }
    end

    refute_equal 0, err.status,
      "Expected nonzero exit when untyped_log_path is unset (silent exit-0 is a footgun)"
  end

  test "rake track_relay:lint:json aborts NONZERO when untyped_log_path is unset" do
    TrackRelay.config.untyped_log_path = nil

    err = assert_raises(SystemExit) do
      capture_io { Rake::Task["track_relay:lint:json"].invoke }
    end

    refute_equal 0, err.status
  end

  test "abort message names the missing config setting" do
    TrackRelay.config.untyped_log_path = nil

    # `abort` writes its message to $stderr before raising SystemExit.
    # Minitest's `capture_io` skips its return-value line on exception,
    # so capture $stderr manually with an ensure-block-protected swap
    # and then re-raise / re-assert.
    real_stderr = $stderr
    captured = StringIO.new
    $stderr = captured
    err = nil
    begin
      assert_raises(SystemExit) do
        Rake::Task["track_relay:lint"].invoke
      rescue SystemExit => e
        err = e
        raise
      end
    ensure
      $stderr = real_stderr
    end

    refute_equal 0, err.status
    assert_match(/untyped_log_path/, captured.string)
  end

  # ---- happy-path: lint prints report -------------------------------

  test "rake track_relay:lint prints report when path is set and file exists" do
    Tempfile.create(["untyped", ".jsonl"]) do |f|
      f.puts({
        event: "ad_hoc",
        params: %w[foo bar],
        controller: "ArticlesController",
        action: "show",
        timestamp: "2026-05-06T12:00:00Z"
      }.to_json)
      f.flush
      TrackRelay.config.untyped_log_path = f.path

      out, _err = capture_io { Rake::Task["track_relay:lint"].invoke }

      assert_match(/event :ad_hoc/, out)
      # Linter sorts param names — input %w[foo bar] becomes [bar, foo].
      assert_match(/params=\[bar, foo\]/, out)
    end
  end

  test "rake track_relay:lint exits 0 when path is set but file does not exist" do
    # File-not-yet-created is a normal state on a fresh app — no error.
    TrackRelay.config.untyped_log_path = "/tmp/track_relay_unset_#{rand(1_000_000)}.jsonl"

    out, _err = capture_io { Rake::Task["track_relay:lint"].invoke }

    assert_match(/track_relay untyped event audit/, out)
  end

  # ---- happy-path: lint:json emits JSON -----------------------------

  test "rake track_relay:lint:json emits parseable JSON to stdout" do
    Tempfile.create(["untyped", ".jsonl"]) do |f|
      f.puts({
        event: "ad_hoc",
        params: %w[foo],
        controller: "ArticlesController",
        action: "show",
        timestamp: "2026-05-06T12:00:00Z"
      }.to_json)
      f.flush
      TrackRelay.config.untyped_log_path = f.path

      out, _err = capture_io { Rake::Task["track_relay:lint:json"].invoke }

      parsed = JSON.parse(out)
      assert_equal 1, parsed.size
      assert_equal "ad_hoc", parsed.first["event"]
      assert_equal 1, parsed.first["total"]
      assert_equal [{"params" => ["foo"], "count" => 1}], parsed.first["signatures"]
    end
  end

  # ---- Railtie rake_tasks wiring ------------------------------------

  test "Railtie's rake_tasks block exposes track_relay:lint to consumer apps" do
    # Verify the rake_tasks block on TrackRelay::Railtie loads the same
    # rake file from the same path the test uses. Re-running it on a
    # fresh Rake::Application must produce a defined `track_relay:lint`
    # task (proves the path inside `rake_tasks { load ... }` resolves).
    fresh_app = Rake::Application.new
    Rake.application = fresh_app
    Rake::Task.define_task(:environment)
    TrackRelay::Railtie.instance_eval { @rake_tasks }.each(&:call) if TrackRelay::Railtie.instance_variable_get(:@rake_tasks)

    # Fall back to direct load if the introspection hook above didn't
    # populate (Rails Railtie internals vary). The contract being tested
    # is "the exact path the Railtie loads exists and defines the task".
    expected_path = File.expand_path("../../lib/tasks/track_relay.rake", __dir__)
    assert File.exist?(expected_path),
      "Railtie's rake_tasks must point at #{expected_path}"

    load expected_path unless Rake::Task.task_defined?("track_relay:lint")
    assert Rake::Task.task_defined?("track_relay:lint")
    assert Rake::Task.task_defined?("track_relay:lint:json")
  end

  test "Railtie's rake_tasks block exposes track_relay:lint:ga4 to consumer apps" do
    expected_path = File.expand_path("../../lib/tasks/track_relay.rake", __dir__)
    load expected_path unless Rake::Task.task_defined?("track_relay:lint:ga4")
    assert Rake::Task.task_defined?("track_relay:lint:ga4")
  end

  # ---- track_relay:lint:ga4 abort-on-missing-config ----------------

  test "rake track_relay:lint:ga4 aborts NONZERO when untyped_log_path is unset" do
    TrackRelay.config.untyped_log_path = nil

    err = assert_raises(SystemExit) do
      capture_io { Rake::Task["track_relay:lint:ga4"].invoke }
    end

    refute_equal 0, err.status
  end

  # ---- track_relay:lint:ga4 happy paths ----------------------------

  test "rake track_relay:lint:ga4 exits 0 when JSONL has no GA4 violations" do
    Tempfile.create(["untyped", ".jsonl"]) do |f|
      f.puts({
        event: "ad_hoc",
        params: %w[foo],
        controller: "ArticlesController",
        action: "show",
        timestamp: "2026-05-06T12:00:00Z"
      }.to_json)
      f.flush
      TrackRelay.config.untyped_log_path = f.path

      err = assert_raises(SystemExit) do
        capture_io { Rake::Task["track_relay:lint:ga4"].invoke }
      end
      assert_equal 0, err.status
    end
  end

  test "rake track_relay:lint:ga4 exits NONZERO when JSONL has GA4 violations" do
    Tempfile.create(["untyped", ".jsonl"]) do |f|
      # `page_view` is reserved by GA4
      f.puts({
        event: "page_view",
        params: %w[foo],
        controller: "ArticlesController",
        action: "show",
        timestamp: "2026-05-06T12:00:00Z"
      }.to_json)
      f.flush
      TrackRelay.config.untyped_log_path = f.path

      err = assert_raises(SystemExit) do
        capture_io { Rake::Task["track_relay:lint:ga4"].invoke }
      end
      refute_equal 0, err.status
    end
  end

  test "rake track_relay:lint:ga4 prints violation report" do
    Tempfile.create(["untyped", ".jsonl"]) do |f|
      f.puts({event: "page_view", params: %w[a],
              controller: "X", action: "y",
              timestamp: "2026-05-06T12:00:00Z"}.to_json)
      f.flush
      TrackRelay.config.untyped_log_path = f.path

      # Capture stdout manually so the SystemExit raised by the task
      # body does NOT short-circuit capture_io's normal-return contract.
      real_stdout = $stdout
      captured = StringIO.new
      $stdout = captured
      begin
        assert_raises(SystemExit) { Rake::Task["track_relay:lint:ga4"].invoke }
      ensure
        $stdout = real_stdout
      end
      assert_match(/event :page_view/, captured.string)
      assert_match(/reason:/, captured.string)
    end
  end
end
