---
phase: 1
plan: "08"
title: Linter + rake track_relay:lint task
status: complete
completed: 2026-05-06
tasks_completed: 2
tasks_total: 2
commit_hashes:
  - 5f607e2
  - 0870d14
deviations: []
pre_existing_issues: []
ac_results:
  - criterion: "TrackRelay::Linter.new(jsonl_path) reads the JSONL sink and groups by event name"
    verdict: pass
    evidence: "test_one_event_one_shape_yields_one_report_with_one_signature, test_multiple_events_sort_by_total_desc (test/unit/linter_test.rb)"
  - criterion: "Each group is deduped by sorted-param-names signature; output is Report struct (event_name, signatures, total)"
    verdict: pass
    evidence: "test_same_event_two_shapes_groups_into_one_report_with_two_signatures (test/unit/linter_test.rb)"
  - criterion: "Linter#report sorted by total occurrences desc; #print writes human-readable summary; #to_json writes machine-readable JSON"
    verdict: pass
    evidence: "test_print_writes_human_readable_report_to_io, test_to_json_emits_stable_machine_readable_structure (test/unit/linter_test.rb)"
  - criterion: "rake track_relay:lint aborts NONZERO when config.untyped_log_path is unset"
    verdict: pass
    evidence: "test_rake_track_relay:lint_aborts_NONZERO_when_untyped_log_path_is_unset, test_abort_message_names_the_missing_config_setting (test/integration/linter_rake_task_test.rb)"
  - criterion: "Linter resilient to malformed lines: skips, prints warning count"
    verdict: pass
    evidence: "test_malformed_lines_are_skipped_and_counted, test_print_includes_malformed_warning_when_lines_were_skipped (test/unit/linter_test.rb)"
  - criterion: "Railtie loads lib/tasks/track_relay.rake via rake_tasks block"
    verdict: pass
    evidence: "lib/track_relay/railtie.rb rake_tasks block (commit 0870d14); test_Railtie's_rake_tasks_block_exposes_track_relay:lint_to_consumer_apps (test/integration/linter_rake_task_test.rb)"
  - criterion: "lib/track_relay/linter.rb provides Linter class with `def report`"
    verdict: pass
    evidence: "lib/track_relay/linter.rb:67 (commit 5f607e2)"
  - criterion: "lib/tasks/track_relay.rake provides track_relay:lint rake task"
    verdict: pass
    evidence: "lib/tasks/track_relay.rake:15 (commit 0870d14)"
  - criterion: "test/integration/linter_rake_task_test.rb provides Rake::Task test"
    verdict: pass
    evidence: "test/integration/linter_rake_task_test.rb (commit 0870d14)"
  - criterion: "Linter consumes Subscribers::Logger JSONL format (NAMES only — value PII never appears)"
    verdict: pass
    evidence: "test_controller_action_timestamp_are_accepted_but_ignored_for_grouping (test/unit/linter_test.rb); see lib/track_relay/linter.rb header comment"
  - criterion: "Rake task reads TrackRelay.config.untyped_log_path"
    verdict: pass
    evidence: "lib/tasks/track_relay.rake:16 (commit 0870d14)"
---

Shipped TrackRelay::Linter (pure-Ruby JSONL audit) and the `rake track_relay:lint` / `track_relay:lint:json` rake tasks wired through the Railtie's rake_tasks block, closing Phase 01's incremental-adoption loop: untyped event → Logger JSONL → linter report.

## What Was Built

- `TrackRelay::Linter` — parses the JSONL sink written by `Subscribers::Logger`, groups by event name, dedupes by sorted-param-name signature, and emits both human-readable (`#print`) and machine-readable (`#to_json`) reports. Resilient to missing files, blank lines, and malformed JSON (counted in `#malformed_lines`). Privacy contract preserved: only param NAMES, never values.
- `rake track_relay:lint` and `rake track_relay:lint:json` — both abort with NONZERO exit when `TrackRelay.config.untyped_log_path` is unset (footgun-prevention contract from 01-CONTEXT.md). The `:lint` task's abort message includes a copy-pasteable initializer snippet.
- Railtie `rake_tasks { load ... }` block exposes both tasks to any consumer Rails app automatically.
- 18 new tests (11 pure-Ruby unit on the linter, 7 Combustion-integration on the rake tasks). Full suite: 237 runs / 0 failures (was 219 / 0).

## Files Modified

- `lib/track_relay/linter.rb` -- new: `Linter`, `Report`, `Signature` structs; parses JSONL, dedupes, emits reports
- `lib/track_relay.rb` -- modified: added `require "track_relay/linter"` to the umbrella file
- `lib/tasks/track_relay.rake` -- new: `track_relay:lint` and `track_relay:lint:json` rake tasks with footgun-guard abort
- `lib/track_relay/railtie.rb` -- modified: added `rake_tasks { load File.expand_path("../tasks/track_relay.rake", __dir__) }` block so consumer apps see the tasks
- `test/unit/linter_test.rb` -- new: 11 pure-Minitest tests covering grouping, signature dedup, sort order, missing/empty/malformed input, `#print`, `#to_json`, and the privacy contract (controller/action/timestamp ignored for grouping)
- `test/integration/linter_rake_task_test.rb` -- new: 7 Combustion-integration tests covering nonzero abort, abort message content, happy-path print, missing-file-no-error, JSON emission, and Railtie path resolution

## Deviations

None.
