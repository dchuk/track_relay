# frozen_string_literal: true

require "json"
require "track_relay/validators/ga4_constraints"

module TrackRelay
  # Audits the JSONL untyped-event sink written by
  # {Subscribers::Logger} and produces a deduped report grouped by
  # event name + sorted-param-name signature.
  #
  # ## Input contract (locked in Plan 05 / 01-CONTEXT.md)
  #
  # The JSONL sink contains one event per line. Each line is JSON with
  # the canonical shape:
  #
  #   {"event":"...", "params":["a","b"], "controller":"...", "action":"...", "timestamp":"..."}
  #
  # `params` carries only sorted, stringified parameter NAMES — values
  # are never written to the sink (privacy contract from
  # 01-CONTEXT.md). The linter reads the same shape and dedupes only on
  # `event` + sorted `params`; `controller`, `action`, and `timestamp`
  # are accepted but ignored for grouping (they are useful breadcrumbs
  # for the human reading the JSONL directly, not signal for dedup).
  #
  # ## Output
  #
  # - {#report} → Array of {Report} structs, sorted by total occurrences
  #   descending. Each Report bundles every distinct param signature
  #   seen for that event name.
  # - {#print} → human-readable summary written to an IO.
  # - {#to_json} → machine-readable JSON with stable keys
  #   `{event, total, signatures: [{params, count}]}`. Plan 09's
  #   CHANGELOG references this contract.
  #
  # ## Resilience
  #
  # - Missing files return an empty report (the JSONL may legitimately
  #   not exist yet on a fresh app).
  # - Lines that are not valid JSON are skipped and counted in
  #   {#malformed_lines}.
  # - Blank lines are silently skipped (not malformed).
  class Linter
    # One report entry per distinct event name.
    #
    # @!attribute [rw] event_name
    #   The event name as it appeared in the JSONL `event` field.
    # @!attribute [rw] signatures
    #   Array of {Signature} structs, sorted by `count` descending.
    # @!attribute [rw] total
    #   Sum of all signature counts for this event.
    Report = Struct.new(:event_name, :signatures, :total, keyword_init: true)

    # One signature per distinct sorted-param-name shape under an event.
    #
    # @!attribute [rw] params
    #   Sorted array of parameter NAMES (no values).
    # @!attribute [rw] count
    #   How many times this exact signature was seen.
    Signature = Struct.new(:params, :count, keyword_init: true)

    # @return [Integer] count of lines that failed JSON parsing
    attr_reader :malformed_lines

    def initialize(jsonl_path)
      @jsonl_path = jsonl_path
      @malformed_lines = 0
    end

    # Build the deduped report.
    #
    # @return [Array<Report>] sorted by total occurrences descending
    def report
      groups = Hash.new { |h, k| h[k] = Hash.new(0) }
      read_lines do |entry|
        event = entry["event"]
        signature = Array(entry["params"]).sort
        groups[event][signature] += 1
      end

      groups.map { |event, signatures|
        sig_list = signatures.map { |params, count| Signature.new(params: params, count: count) }
        total = sig_list.sum(&:count)
        Report.new(
          event_name: event,
          signatures: sig_list.sort_by { |s| -s.count },
          total: total
        )
      }.sort_by { |r| -r.total }
    end

    # Write a human-readable summary to `io`.
    #
    # @param io [IO] writer; defaults to `$stdout`
    # @return [void]
    def print(io = $stdout)
      reports = report
      io.puts "# track_relay untyped event audit"
      io.puts "# source: #{@jsonl_path}"
      io.puts "# events: #{reports.size}; total occurrences: #{reports.sum(&:total)}"
      io.puts ""
      reports.each do |r|
        io.puts "event :#{r.event_name}  (#{r.total} total)"
        r.signatures.each do |sig|
          io.puts "  - params=[#{sig.params.join(", ")}]  count=#{sig.count}"
        end
        io.puts ""
      end
      io.puts "# #{@malformed_lines} malformed line(s) skipped" if @malformed_lines.positive?
    end

    # Emit machine-readable JSON.
    #
    # Keys (`event`, `total`, `signatures`, `params`, `count`) are
    # stable — Plan 09's CHANGELOG references this contract.
    #
    # @return [String] JSON
    def to_json(*)
      JSON.generate(report.map { |r|
        {
          event: r.event_name,
          total: r.total,
          signatures: r.signatures.map { |s| {params: s.params, count: s.count} }
        }
      })
    end

    # One row in the GA4 lint report.
    #
    # @!attribute [rw] event_name
    #   The event name as it appeared in the JSONL `event` field.
    # @!attribute [rw] reason
    #   Human-readable description of the GA4 rule that was violated.
    # @!attribute [rw] count
    #   How many JSONL lines contained this event name (regardless of
    #   param signature — the GA4 lint groups purely by event name).
    Ga4Violation = Struct.new(:event_name, :reason, :count, keyword_init: true)

    # Audit each unique event name in the JSONL sink against
    # {Validators::Ga4Constraints} (REQ-28, Plan 02-04 / Scout §8).
    #
    # Only the event-name shape is checked here:
    #
    #   - snake_case regex (`/\A[a-z][a-z0-9_]*\z/`)
    #   - max 40 chars
    #   - not in `GA4_RESERVED_NAMES`
    #
    # Param-name validation is intentionally OUT OF SCOPE for this
    # method — `params` in the JSONL is a sorted-NAMES-only privacy
    # snapshot, but param-name shape is a per-line fact (each occurrence
    # could fail differently) and the linter's grouping model is built
    # around event names. Use the call-time validation in
    # {Subscribers::Ga4MeasurementProtocol#deliver} for per-payload
    # checks; this method is the audit trail for "what event names did
    # we ship that GA4 will silently drop?".
    #
    # @return [Array<Ga4Violation>] sorted by `count` descending. Empty
    #   when every event name in the JSONL passes.
    def ga4_violations
      counts = Hash.new(0)
      read_lines do |entry|
        name = entry["event"]
        next if name.nil? || name.empty?
        counts[name] += 1
      end

      counts.map { |name, count|
        begin
          Validators::Ga4Constraints.validate_event_name!(name)
          nil
        rescue Ga4ConstraintError => e
          Ga4Violation.new(event_name: name, reason: e.message, count: count)
        end
      }.compact.sort_by { |v| -v.count }
    end

    # Write the GA4 violation report to `io`.
    #
    # Returns `true` when there were no violations (rake task should
    # exit 0), `false` otherwise (rake task exits non-zero).
    #
    # @param io [IO] writer; defaults to `$stdout`
    # @return [Boolean] `true` ⇒ clean, `false` ⇒ violations found
    def print_ga4(io = $stdout)
      violations = ga4_violations
      io.puts "# track_relay GA4 event-name audit"
      io.puts "# source: #{@jsonl_path}"
      io.puts "# violations: #{violations.size}"
      io.puts ""

      if violations.empty?
        io.puts "# clean — every event name passes GA4 constraints"
        return true
      end

      violations.each do |v|
        io.puts "event :#{v.event_name}  (#{v.count} occurrence#{"s" unless v.count == 1})"
        io.puts "  reason: #{v.reason}"
        io.puts ""
      end
      false
    end

    private

    def read_lines
      return unless File.exist?(@jsonl_path.to_s)
      File.foreach(@jsonl_path.to_s) do |line|
        line = line.strip
        next if line.empty?
        begin
          yield JSON.parse(line)
        rescue JSON::ParserError
          @malformed_lines += 1
        end
      end
    end
  end
end
