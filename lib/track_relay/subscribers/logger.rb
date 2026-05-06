# frozen_string_literal: true

require "json"
require "track_relay/subscribers/base"

module TrackRelay
  module Subscribers
    # Two-output subscriber that surfaces every event in development /
    # production logs and persists untyped (non-catalog) events to a
    # JSONL sidecar for the linter (Plan 08) and the end-to-end test
    # (Plan 09) to consume.
    #
    # **Outputs:**
    #
    # 1. **Always** writes a human-readable line to `Rails.logger.info`:
    #    `[track_relay] event=<name> kind=<typed|untyped> params=[...]`
    #
    # 2. **Only when** {Configuration#untyped_log_path} is set AND the
    #    payload is untyped (`payload.definition.nil?`), appends a JSONL
    #    line to that path. The line shape is locked at:
    #
    #    ```json
    #    {
    #      "event":      "<event_name>",
    #      "params":     ["param_a", "param_b"],
    #      "controller": "ArticlesController",
    #      "action":     "show",
    #      "timestamp":  "2026-05-06T12:00:00Z"
    #    }
    #    ```
    #
    #    **Privacy contract (locked in 01-CONTEXT.md):** param VALUES are
    #    NEVER written. Only sorted, stringified param NAMES. The
    #    JSONL is a "what events fired" audit trail, not a payload log.
    #
    # The same line shape is read by `TrackRelay::Linter` (Plan 08) and
    # asserted by the end-to-end test (Plan 09). Keep these three sites
    # in sync if the shape ever needs to change.
    class Logger < Base
      synchronous!

      def deliver(payload)
        log_human(payload)
        log_untyped_jsonl(payload) if untyped?(payload) && jsonl_path
      end

      private

      def log_human(payload)
        return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        marker = untyped?(payload) ? "untyped" : "typed"
        Rails.logger.info(
          "[track_relay] event=#{payload.name} kind=#{marker} params=#{payload.params.keys.sort.inspect}"
        )
      end

      def log_untyped_jsonl(payload)
        line = {
          event: payload.name.to_s,
          params: payload.params.keys.map(&:to_s).sort,
          controller: payload.context[:controller],
          action: payload.context[:action],
          timestamp: payload.timestamp.iso8601
        }
        File.open(jsonl_path, "a") do |f|
          f.puts(JSON.generate(line))
        end
      end

      def untyped?(payload)
        payload.definition.nil?
      end

      def jsonl_path
        TrackRelay.config.untyped_log_path
      end
    end
  end
end
