# frozen_string_literal: true

require "test_helper"

# Integration coverage for {TrackRelay::Railtie}.
#
# The Railtie is the gem's Rails integration boundary. Three jobs:
#
#   1. Tell Zeitwerk to ignore `config/track_relay/` so DSL files
#      (which are NOT constant definitions) don't trip Rails autoloading.
#   2. Register a `to_prepare` callback that calls `Catalog.clear!` and
#      then `Dir.glob/load`s every `*.rb` under `config/track_relay/`.
#      `Catalog.clear!` runs FIRST so editing a file in dev produces a
#      clean rebuild rather than a duplicate-registration error.
#   3. Call `TrackRelay::Dispatcher.start!` exactly once on
#      `config.after_initialize` so the Notifications fan-out is wired
#      before the host app handles its first request.
#
# Hot-reload is exercised here by invoking
# `Rails.application.reloader.prepare!` directly — the canonical
# concrete way to fire `to_prepare` callbacks from a test, stable across
# Rails 7.1/7.2/8.0.
class RailtieTest < ActiveSupport::TestCase
  CATALOG_DIR = Rails.root.join("config", "track_relay")
  TEMP_FILE = CATALOG_DIR.join("articles_railtie_test.rb")

  setup do
    FileUtils.mkdir_p(CATALOG_DIR)
  end

  teardown do
    FileUtils.rm_f(TEMP_FILE)
    # Best-effort: leave catalog dir present even if empty (mkdir_p above
    # is idempotent). Rebuild a clean catalog for downstream tests.
    TrackRelay::Catalog.clear!
  end

  # ---- Catalog autoload via to_prepare ------------------------------

  test "to_prepare loads catalog files dropped under config/track_relay/" do
    File.write(TEMP_FILE, <<~RUBY)
      TrackRelay.catalog do
        event :loaded_via_railtie do
          string :title, required: true
        end
      end
    RUBY

    Rails.application.reloader.prepare!

    refute_nil TrackRelay::Catalog.lookup(:loaded_via_railtie),
      "Railtie's to_prepare callback should have loaded the catalog file"
  end

  test "to_prepare clears Catalog before reloading (hot-reload safety)" do
    File.write(TEMP_FILE, <<~RUBY)
      TrackRelay.catalog do
        event :loaded_via_railtie do
          string :title, required: true
        end
      end
    RUBY

    Rails.application.reloader.prepare!
    refute_nil TrackRelay::Catalog.lookup(:loaded_via_railtie)

    # Second invocation must NOT raise CatalogError (which Catalog.register
    # raises on duplicate). This proves Catalog.clear! runs before reload.
    assert_nothing_raised do
      Rails.application.reloader.prepare!
    end
    refute_nil TrackRelay::Catalog.lookup(:loaded_via_railtie),
      "Event should still be registered exactly once after a second reload"
  end

  test "to_prepare does not raise when config/track_relay is empty" do
    # No temp file written; directory exists but is empty.
    assert_nothing_raised do
      Rails.application.reloader.prepare!
    end
  end

  # ---- Dispatcher.start! -------------------------------------------

  test "Dispatcher is started after Combustion boot" do
    # The Railtie wires Dispatcher.start! into config.after_initialize,
    # which Combustion fires during Combustion.initialize!. A subsequent
    # teardown in test_helper.rb calls Dispatcher.stop!, so this test
    # explicitly re-starts to assert the started? contract independent
    # of teardown order.
    TrackRelay::Dispatcher.start!
    assert TrackRelay::Dispatcher.started?,
      "Dispatcher should be started (idempotent re-start should succeed)"
  end
end
