# frozen_string_literal: true

require "test_helper"
require "rake"
require "json"

# Integration coverage for the `rake track_relay:manifest` task loaded by
# {TrackRelay::Railtie}'s `rake_tasks` block.
#
# Two contracts:
#
#   1. Happy path: with a populated catalog, the task writes a JSON file
#      at `Rails.root.join("public", "track_relay_catalog.json")` whose
#      contents match `Manifest.generate(catalog: TrackRelay::Catalog)`.
#      The file's parent directory is created if missing — the Combustion
#      dummy app at `test/internal/` ships without `public/`, and the
#      `mkdir_p` guard inside `Manifest.write!` makes this transparent.
#
#   2. Footgun guard (RISK-04): when the catalog is empty (fresh install,
#      no catalog files yet), invoking the task with no events would
#      silently emit an empty manifest the JS client treats as
#      "all-events-allowed". To prevent that, the task aborts with a
#      NONZERO exit and a clear message, mirroring the lint task's
#      footgun-prevention contract.
#
# Each setup builds a fresh Rake::Application so prior task state from
# other test files (or the gem's main Rakefile) doesn't bleed in.
class ManifestRakeTaskTest < ActiveSupport::TestCase
  RAKE_FILE = File.expand_path("../../lib/tasks/track_relay.rake", __dir__)
  MANIFEST_PATH = Rails.root.join("public", "track_relay_catalog.json")

  setup do
    @prev_app = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load RAKE_FILE
    TrackRelay::Catalog.clear!
    FileUtils.rm_f(MANIFEST_PATH)
  end

  teardown do
    Rake.application = @prev_app
    FileUtils.rm_f(MANIFEST_PATH)
  end

  # ---- happy path ---------------------------------------------------------

  test "writes the manifest to public/track_relay_catalog.json" do
    TrackRelay.catalog do
      event :purchase do
        float :value, required: true
        string :currency
      end
    end

    capture_io { Rake::Task["track_relay:manifest"].invoke }

    assert File.exist?(MANIFEST_PATH),
      "rake track_relay:manifest should have written #{MANIFEST_PATH}"

    content = JSON.parse(File.read(MANIFEST_PATH))
    assert_equal TrackRelay::VERSION, content["version"]
    assert_equal "float", content.dig("events", "purchase", "params", "value")
    assert_equal ["value"], content.dig("events", "purchase", "required")
  end

  test "writes content matching Manifest.generate" do
    TrackRelay.catalog do
      event :purchase do
        float :value, required: true
      end
    end

    capture_io { Rake::Task["track_relay:manifest"].invoke }

    file_content = JSON.parse(File.read(MANIFEST_PATH))
    expected = JSON.parse(JSON.pretty_generate(
      TrackRelay::Manifest.generate(catalog: TrackRelay::Catalog)
    ))

    # generated_at differs by milliseconds between invocations; compare
    # everything else.
    file_content.delete("generated_at")
    expected.delete("generated_at")
    assert_equal expected, file_content
  end

  test "task prints the path and event count" do
    TrackRelay.catalog do
      event :sign_up do
        string :method
      end
    end

    out, _err = capture_io { Rake::Task["track_relay:manifest"].invoke }
    assert_match(/track_relay/, out)
    assert_match(/manifest written/, out)
    assert_match(/1 event/, out)
  end

  # ---- footgun guard: empty catalog --------------------------------------

  test "aborts NONZERO when the catalog is empty (RISK-04 guard)" do
    TrackRelay::Catalog.clear!

    real_stderr = $stderr
    captured = StringIO.new
    $stderr = captured
    err = nil
    begin
      assert_raises(SystemExit) do
        Rake::Task["track_relay:manifest"].invoke
      rescue SystemExit => e
        err = e
        raise
      end
    ensure
      $stderr = real_stderr
    end

    refute_equal 0, err.status,
      "Expected nonzero exit when catalog is empty (silent empty manifest is a footgun)"
    assert_match(/catalog is empty/i, captured.string)
    refute File.exist?(MANIFEST_PATH),
      "Empty catalog should NOT produce a manifest file"
  end

  # ---- Railtie rake_tasks wiring -----------------------------------------

  test "track_relay:manifest is defined alongside lint tasks via the Railtie loader" do
    assert Rake::Task.task_defined?("track_relay:manifest"),
      "track_relay:manifest should be defined after loading the rake file"
    assert Rake::Task.task_defined?("track_relay:lint"),
      "Existing track_relay:lint should remain defined alongside the new task"
  end
end
