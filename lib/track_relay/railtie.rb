# frozen_string_literal: true

require "rails/railtie"
require "track_relay/catalog"
require "track_relay/dispatcher"

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
      app.config.to_prepare do
        TrackRelay::Catalog.clear!
        Dir.glob("#{catalog_dir}/**/*.rb").sort.each do |file|
          load file
        end
      end
    end

    initializer "track_relay.start_dispatcher" do |app|
      app.config.after_initialize do
        TrackRelay::Dispatcher.start!
      end
    end
  end
end
