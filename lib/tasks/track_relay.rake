# frozen_string_literal: true

# Audit untyped (non-catalog) events captured in the JSONL sink written
# by {TrackRelay::Subscribers::Logger}.
#
# Both tasks ABORT WITH NONZERO exit when
# `TrackRelay.config.untyped_log_path` is unset. From 01-CONTEXT.md /
# the plan's must_haves: a silent exit-0 on a misconfigured audit task
# is a footgun (the user thinks the audit "passed" when in fact nothing
# was ever recorded). When the path IS set, the task exits 0 — lint is
# a report, not a gate.

# Loaded via require_relative (not the gem's umbrella `require
# "track_relay"`) so this rake file stays file-disjoint with Plan 02-02
# — `lib/track_relay.rb` is owned by that plan in the same wave.
require_relative "../track_relay/manifest"

namespace :track_relay do
  desc "Audit untyped events captured in the JSONL sink (config.untyped_log_path)"
  task lint: :environment do
    path = TrackRelay.config.untyped_log_path
    if path.nil?
      abort <<~MSG
        track_relay: untyped_log_path is not configured.
        Set it in config/initializers/track_relay.rb:

          TrackRelay.configure do |c|
            c.untyped_log_path = Rails.root.join("tmp/track_relay_untyped.jsonl")
            c.subscribe TrackRelay::Subscribers::Logger.new
          end
      MSG
    end

    TrackRelay::Linter.new(path).print
  end

  desc "Audit untyped events and emit JSON report to stdout"
  task "lint:json" => :environment do
    path = TrackRelay.config.untyped_log_path
    abort "track_relay: untyped_log_path is not configured" if path.nil?

    puts TrackRelay::Linter.new(path).to_json
  end

  desc "Audit untyped events for GA4 event-name constraint violations"
  task "lint:ga4" => :environment do
    path = TrackRelay.config.untyped_log_path
    if path.nil?
      abort <<~MSG
        track_relay: untyped_log_path is not configured.
        Set it in config/initializers/track_relay.rb:

          TrackRelay.configure do |c|
            c.untyped_log_path = Rails.root.join("tmp/track_relay_untyped.jsonl")
            c.subscribe TrackRelay::Subscribers::Logger.new
          end
      MSG
    end

    clean = TrackRelay::Linter.new(path).print_ga4
    # Exit non-zero when violations exist, zero when clean. Lets CI
    # pipelines gate on `rake track_relay:lint:ga4` without parsing
    # output.
    exit(clean ? 0 : 1)
  end

  desc "Generate public/track_relay_catalog.json from the loaded catalog"
  task manifest: :environment do
    # Footgun guard (RISK-04): an empty manifest tells the JS client
    # "no schema, accept everything" — silently. Abort loudly so the
    # operator notices the catalog never loaded.
    if TrackRelay::Catalog.all.empty?
      abort "[track_relay] aborting: catalog is empty (no events registered — check config/track_relay/**/*.rb)"
    end

    path = TrackRelay::Manifest.write!
    count = TrackRelay::Catalog.all.size
    puts "[track_relay] manifest written to #{path} (#{count} #{(count == 1) ? "event" : "events"})"
  end
end
