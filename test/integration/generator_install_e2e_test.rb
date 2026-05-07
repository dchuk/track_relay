# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "fileutils"
require "generators/track_relay/install/install_generator"
require "track_relay/testing/helpers"

# End-to-end happy-path test for the `track_relay:install` generator.
#
# This test proves the generator's "works out of the box" claim by
# exercising the full pipeline:
#
#   1. Invoke `Rails::Generators.invoke("track_relay:install", ...)`
#      programmatically into a clean tmpdir. The tmpdir has no
#      ApplicationController, so the inject_into_class step from plan
#      04-01 hits the "controller not found" skip branch — the test
#      does NOT depend on inject behavior.
#   2. Copy ONLY the generated catalog (config/track_relay/sample.rb)
#      and ApplicationSubscriber (app/track_relay/subscribers/...) into
#      the live `test/internal/` Combustion app. The initializer is
#      excluded — `test_helper.rb` manages config explicitly, and
#      re-loading an initializer mid-test risks subscriber double-
#      registration that the global teardown can't fully clean up.
#      The inject output is also not copied — `application_controller.rb`
#      already includes `TrackRelay::ControllerTracking` as fixture state.
#   3. Force a catalog reload so `:hello_world` is registered.
#   4. Activate `test_mode!` and (re)start the Dispatcher — the global
#      teardown in `test_helper.rb` calls `Dispatcher.stop!` after every
#      test, and `test_mode!` only swaps the subscriber list, it does
#      NOT (re)start dispatch.
#   5. Hit the real HelloController action via `get hello_path(...)` and
#      assert the Test subscriber captured the event with the typed
#      payload via `assert_tracked`.
#
# Teardown removes all files written into `test/internal/` and the
# tmpdir so subsequent test runs start clean. The global teardown
# (`test_helper.rb:43-49`) handles `Catalog.clear!`, `Dispatcher.stop!`,
# and `reset_config!` — no need to repeat that here.
class GeneratorInstallE2ETest < ActionDispatch::IntegrationTest
  include TrackRelay::Testing::Helpers

  TMPDIR = File.expand_path("../../tmp/generator_e2e", __dir__)
  INTERNAL_ROOT = File.expand_path("../internal", __dir__)
  CATALOG_DIR = File.join(INTERNAL_ROOT, "config/track_relay")
  SUBSCRIBERS_DIR = File.join(INTERNAL_ROOT, "app/track_relay/subscribers")
  GENERATED_FILES = [
    File.join(CATALOG_DIR, "sample.rb"),
    File.join(SUBSCRIBERS_DIR, "application_subscriber.rb")
  ].freeze

  setup do
    # 1. Run the install generator into a clean tmpdir.
    FileUtils.rm_rf(TMPDIR)
    FileUtils.mkdir_p(TMPDIR)
    Rails::Generators.invoke(
      "track_relay:install",
      [],
      destination_root: TMPDIR,
      shell: Thor::Shell::Basic.new # silence color output in CI
    )

    # 2. Copy ONLY the generator's catalog + subscriber output into
    #    test/internal. Do NOT copy the generated initializer
    #    (test/internal manages its own config; the initializer would
    #    force load order issues against the already-booted Combustion
    #    app). Do NOT copy the inject_into_class output for
    #    ApplicationController — test/internal already has the include,
    #    and the generator's idempotency guard skipped it anyway.
    FileUtils.mkdir_p(CATALOG_DIR)
    FileUtils.cp(
      File.join(TMPDIR, "config/track_relay/sample.rb"),
      File.join(CATALOG_DIR, "sample.rb")
    )
    FileUtils.mkdir_p(SUBSCRIBERS_DIR)
    FileUtils.cp(
      File.join(TMPDIR, "app/track_relay/subscribers/application_subscriber.rb"),
      File.join(SUBSCRIBERS_DIR, "application_subscriber.rb")
    )

    # 3. Force the Railtie to_prepare-style catalog reload.
    TrackRelay::Catalog.clear!
    Dir.glob(File.join(CATALOG_DIR, "**/*.rb")).sort.each { |f| load f }

    # 4. test_mode! activates the Test subscriber for assert_tracked.
    #    (TrackRelay::Testing::Helpers also calls this in its own setup
    #    block — test_mode! is idempotent so the redundancy is safe and
    #    keeps this setup block self-documenting.)
    TrackRelay.test_mode!

    # 5. Restart the dispatcher so events fan out to subscribers.
    #    test_helper.rb's global teardown called Dispatcher.stop! after
    #    the previous test, and TrackRelay.test_mode! does NOT (re)start
    #    dispatch — it only swaps the subscriber list. start! is
    #    idempotent.
    TrackRelay::Dispatcher.start!
  end

  teardown do
    GENERATED_FILES.each { |f| File.delete(f) if File.exist?(f) }
    # Tear down empty dirs in reverse order. Defensive rescue because
    # rmdir raises if a dir is non-empty — if a future test adds files
    # to those dirs, we don't want this teardown to spuriously fail.
    [CATALOG_DIR, SUBSCRIBERS_DIR, File.dirname(SUBSCRIBERS_DIR)].each do |dir|
      Dir.rmdir(dir) if Dir.exist?(dir) && Dir.empty?(dir)
    rescue Errno::ENOENT, Errno::ENOTEMPTY
      # ignore
    end
    FileUtils.rm_rf(TMPDIR)
    TrackRelay.test_mode_off!
    # ActiveSupport::TestCase global teardown (test_helper.rb:43-49)
    # handles Catalog.clear!, Dispatcher.stop!, and reset_config! — no
    # repeat needed here.
  end

  test "install generator output: tracked controller call captured by Test subscriber" do
    get hello_path(message: "hi from e2e")
    assert_response :ok
    assert_tracked :hello_world, message: "hi from e2e"
  end
end
