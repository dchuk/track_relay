# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require "track_relay/version"
require "track_relay/catalog"

module TrackRelay
  # Generate a typed JSON manifest of the loaded catalog for the
  # `@track_relay/client` JS package (Plan 02-05) to fetch and validate
  # events client-side. The on-disk artifact is written by either:
  #
  #   * `rake track_relay:manifest` (production / CI), or
  #   * `config.to_prepare` in development (regenerated on every reload),
  #
  # both of which delegate to {.write!}. The generated shape is stable
  # and consumed by the JS client:
  #
  #   {
  #     "version": "<gem version>",
  #     "generated_at": "<ISO8601 timestamp>",
  #     "events": {
  #       "<event_name>": {
  #         "params":   {"<param>" => "<type>"},   # all 5 ParamSchema types
  #         "required": ["<required_param_name>"]  # may be []
  #       }
  #     }
  #   }
  #
  # Phase 2 ships `params` (types) + `required[]` only — richer
  # constraints (max/in/format) land in Phase 4 alongside generators.
  module Manifest
    DEFAULT_FILENAME = "track_relay_catalog.json"

    class << self
      # Build the manifest Hash from a catalog-like object.
      #
      # @param catalog [#all] anything responding to `all` and returning
      #   an Array of {EventDefinition}; defaults to {TrackRelay::Catalog}
      # @return [Hash] frozen-shape manifest (NOT frozen — callers may
      #   mutate before serialization if needed)
      def generate(catalog: Catalog)
        {
          version: TrackRelay::VERSION,
          generated_at: Time.now.utc.iso8601,
          events: catalog.all.each_with_object({}) do |defn, h|
            h[defn.name.to_s] = {
              params: defn.params.transform_keys(&:to_s).transform_values { |s| s.type.to_s },
              required: defn.params.select { |_, s| s.required }.keys.map(&:to_s)
            }
          end
        }
      end

      # Write the manifest to `path` as pretty-printed JSON.
      #
      # `FileUtils.mkdir_p(File.dirname(path))` is called first so a fresh
      # checkout (e.g. the Combustion dummy app at `test/internal/`, which
      # has no `public/` directory) does NOT crash with `Errno::ENOENT` on
      # the first call.
      #
      # @param path [String, Pathname] target file; defaults to
      #   `Rails.root.join("public", "track_relay_catalog.json")` when
      #   Rails is loaded
      # @param catalog [#all] forwarded to {.generate}
      # @return [String, Pathname] the path that was written
      def write!(path: default_path, catalog: Catalog)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(generate(catalog: catalog)))
        path
      end

      private

      def default_path
        unless defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          raise ArgumentError,
            "TrackRelay::Manifest.write! requires a `path:` argument when Rails.root is unavailable"
        end
        Rails.root.join("public", DEFAULT_FILENAME)
      end
    end
  end
end
