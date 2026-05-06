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
end
