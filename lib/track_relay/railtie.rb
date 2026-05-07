# frozen_string_literal: true

require "rails/railtie"
require "track_relay/catalog"
require "track_relay/dispatcher"
# Direct require of Manifest (rather than going through `lib/track_relay.rb`)
# keeps this plan file-disjoint with Plan 02-02 in the same wave —
# Plan 02-02 owns the umbrella file's require list.
require "track_relay/manifest"

module TrackRelay
  # Rails integration boundary for the gem.
  #
  # Three responsibilities, all wired in initializer blocks:
  #
  #   1. Tell Zeitwerk to ignore `Rails.root/config/track_relay` so that
  #      DSL files in that directory (which call {TrackRelay.catalog}
  #      rather than defining constants) don't trip Rails autoloading.
  #
  #   2. Register a `config.to_prepare` callback that calls
  #      {Catalog.clear!} and then `Dir.glob/load`s every `*.rb` file
  #      under `config/track_relay/`. {Catalog.clear!} runs FIRST so
  #      editing a catalog file in dev produces a clean rebuild rather
  #      than a duplicate-registration error from {Catalog#register}.
  #      `to_prepare` runs once at boot in test/production and before
  #      every request reload in development — exactly the hot-reload
  #      contract this gem needs.
  #
  #   3. Call {Dispatcher.start!} exactly once via
  #      `config.after_initialize` so the AS::Notifications fan-out
  #      subscription is registered before the host app handles its
  #      first request. {Dispatcher.start!} is idempotent so this is
  #      safe even when the Railtie is loaded multiple times.
  #
  # The Railtie is required from `lib/track_relay.rb` only when
  # `Rails::Railtie` is defined, so the gem still loads cleanly in
  # non-Rails contexts (plain `require "track_relay"` from a script).
  class Railtie < Rails::Railtie
    initializer "track_relay.catalog_autoload" do |app|
      catalog_dir = app.root.join("config", "track_relay")

      # Conditional ignore avoids a Zeitwerk warning when the directory
      # doesn't exist yet (host app hasn't created it).
      Rails.autoloaders.main.ignore(catalog_dir) if catalog_dir.exist?

      # Clear before reload so editing config/track_relay/foo.rb in dev
      # produces a clean catalog rebuild rather than double-registration
      # errors from Catalog.register's defensive duplicate guard.
      #
      # In development, regenerate `public/track_relay_catalog.json`
      # after the catalog rebuild so the JS client picks up DSL changes
      # without a server restart. The test env is excluded explicitly to
      # avoid every-test churn — production builds the manifest via
      # `assets:precompile` (see the next initializer).
      app.config.to_prepare do
        TrackRelay::Catalog.clear!
        Dir.glob("#{catalog_dir}/**/*.rb").sort.each do |file|
          load file
        end

        if Rails.env.development? && TrackRelay::Catalog.all.any?
          TrackRelay::Manifest.write!
        end
      end
    end

    initializer "track_relay.start_dispatcher" do |app|
      app.config.after_initialize do
        TrackRelay::Dispatcher.start!
      end
    end

    # Chain `track_relay:manifest` as a prerequisite of
    # `assets:precompile` so production / CI builds always ship a fresh
    # `public/track_relay_catalog.json`. The conditional avoids a
    # Rake::Task-not-defined error in non-asset apps (API-only Rails
    # without Sprockets/Propshaft). Mirrors cssbundling-rails /
    # jsbundling-rails patterns.
    initializer "track_relay.enhance_assets_precompile" do
      # `defined?(Rake)` guards against API-only Rails apps that have
      # never `require "rake"`-d at boot — the initializer is a no-op
      # there. When Rake IS loaded, the `task_defined?` check then
      # silently skips when the host app uses neither Sprockets nor
      # Propshaft.
      if defined?(Rake) && Rake::Task.task_defined?("assets:precompile")
        Rake::Task["assets:precompile"].enhance(["track_relay:manifest"])
      end
    end

    # Make `rake track_relay:lint` and `rake track_relay:lint:json`
    # available in any consumer app. `__dir__` is `lib/track_relay`;
    # `..` walks to `lib`; the rake file lives at `lib/tasks/track_relay.rake`.
    rake_tasks do
      load File.expand_path("../tasks/track_relay.rake", __dir__)
    end
  end
end
