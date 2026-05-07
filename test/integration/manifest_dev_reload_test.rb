# frozen_string_literal: true

require "test_helper"
require "rake"

# Integration coverage for {TrackRelay::Railtie}'s manifest hooks.
#
# Two contracts:
#
#   1. Dev-mode regeneration: when `Rails.env.development?` is true, the
#      `to_prepare` callback (chained inside the existing
#      `track_relay.catalog_autoload` initializer) regenerates the
#      `public/track_relay_catalog.json` after the catalog reload, so
#      editing a catalog file in dev produces a fresh manifest on the
#      next request without a server restart.
#
#   2. assets:precompile prerequisite: when the host app defines an
#      `assets:precompile` rake task (Sprockets / Propshaft do this), the
#      `track_relay.enhance_assets_precompile` initializer chains
#      `track_relay:manifest` as a prerequisite so production CI builds
#      always ship a fresh manifest.
#
# A guard for the test environment (`Rails.env.test?`) prevents
# every-test churn — the to_prepare branch must NOT write the manifest
# in tests.
class ManifestDevReloadTest < ActiveSupport::TestCase
  CATALOG_DIR = Rails.root.join("config", "track_relay")
  TEMP_FILE = CATALOG_DIR.join("articles_manifest_reload_test.rb")
  MANIFEST_PATH = Rails.root.join("public", "track_relay_catalog.json")

  setup do
    FileUtils.mkdir_p(CATALOG_DIR)
    FileUtils.rm_f(MANIFEST_PATH)
  end

  teardown do
    FileUtils.rm_f(TEMP_FILE)
    FileUtils.rm_f(MANIFEST_PATH)
    TrackRelay::Catalog.clear!
  end

  # ---- dev-mode regeneration --------------------------------------------

  test "to_prepare regenerates the manifest when Rails.env.development?" do
    File.write(TEMP_FILE, <<~RUBY)
      TrackRelay.catalog do
        event :loaded_via_railtie_for_manifest do
          string :title, required: true
        end
      end
    RUBY

    Rails.env.stub :development?, true do
      Rails.application.reloader.prepare!
    end

    assert File.exist?(MANIFEST_PATH),
      "to_prepare should have regenerated the manifest in development mode"

    content = JSON.parse(File.read(MANIFEST_PATH))
    assert_equal "string",
      content.dig("events", "loaded_via_railtie_for_manifest", "params", "title")
  end

  test "to_prepare does NOT write the manifest in test env (avoid churn)" do
    File.write(TEMP_FILE, <<~RUBY)
      TrackRelay.catalog do
        event :loaded_in_test_env do
          string :title
        end
      end
    RUBY

    # Rails.env.test? is the default in this suite — leave it alone.
    Rails.application.reloader.prepare!

    refute File.exist?(MANIFEST_PATH),
      "to_prepare should NOT regenerate the manifest in test env (every-test churn guard)"
  end

  test "to_prepare does NOT write the manifest in development when catalog is empty" do
    # No temp file written; directory may exist but contains no events.
    TrackRelay::Catalog.clear!

    Rails.env.stub :development?, true do
      Rails.application.reloader.prepare!
    end

    refute File.exist?(MANIFEST_PATH),
      "Empty catalog should not produce a manifest even in development mode"
  end

  # ---- assets:precompile enhancement ------------------------------------

  test "assets:precompile gets track_relay:manifest as a prerequisite when defined" do
    # Define `assets:precompile` against a fresh Rake::Application, then
    # re-run the `track_relay.enhance_assets_precompile` initializer's
    # body — the Railtie wires it idempotently and only when the task is
    # already defined.
    prev_app = Rake.application
    Rake.application = Rake::Application.new
    begin
      Rake::Task.define_task(:environment)
      Rake::Task.define_task("assets:precompile")
      Rake::Task.define_task("track_relay:manifest")

      # Re-execute the Railtie initializer's body. The Rails::Railtie
      # initializer object's `block` lambda re-runs the wiring against
      # the current Rake.application.
      initializer = TrackRelay::Railtie.initializers.find do |i|
        i.name == "track_relay.enhance_assets_precompile"
      end
      refute_nil initializer, "Railtie should declare track_relay.enhance_assets_precompile"
      initializer.block.call

      assert_includes Rake::Task["assets:precompile"].prerequisites,
        "track_relay:manifest",
        "Railtie should chain track_relay:manifest as a prerequisite of assets:precompile"
    ensure
      Rake.application = prev_app
    end
  end

  test "enhance_assets_precompile is a no-op when assets:precompile is undefined" do
    prev_app = Rake.application
    Rake.application = Rake::Application.new
    begin
      Rake::Task.define_task(:environment)
      # Intentionally do NOT define assets:precompile.

      initializer = TrackRelay::Railtie.initializers.find do |i|
        i.name == "track_relay.enhance_assets_precompile"
      end
      refute_nil initializer

      assert_nothing_raised do
        initializer.block.call
      end
    ensure
      Rake.application = prev_app
    end
  end
end
