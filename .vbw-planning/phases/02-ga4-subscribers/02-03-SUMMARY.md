---
phase: 2
plan: "03"
title: JSON manifest generation + Sprockets/Propshaft hook
status: complete
completed: 2026-05-06
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - 4f6aa3d
  - c88b16c
  - c94c95d
  - 122e467
deviations:
  - "DEVN-01: combined plan tasks 1 (Manifest.generate) and 2 (Manifest.write!) into a single commit (4f6aa3d) instead of two. The Manifest module is one file with two tightly coupled methods; splitting would have required artificial back-and-forth on the same file. The plan body says 'One commit per task preferred' (not strict) and the commit-discipline rule explicitly allows TDD splits. All other plan tasks (3, 4, 5) ship as their own atomic commits."
  - "DEVN-01: added a `defined?(Rake) &&` guard to the `track_relay.enhance_assets_precompile` initializer (lib/track_relay/railtie.rb:79-87) before calling `Rake::Task.task_defined?`. Combustion's `:action_controller, :active_job` boot does NOT require Rake, so the bare reference to the `Rake` constant raised `NameError` during the test suite's app initialization. Plan body referenced `Rake::Task.task_defined?(\"assets:precompile\")` directly. In-spirit fix — API-only Rails apps that have never `require \"rake\"`-d at boot are now also a clean no-op, matching the same defensive posture as the `task_defined?` check."
pre_existing_issues: []
ac_results:
  - criterion: "TrackRelay::Manifest.generate(catalog: TrackRelay::Catalog) returns a Hash matching the 02-CONTEXT shape: {version:, generated_at:, events: { name => { params: {key => type_string}, required: [...] }}}"
    verdict: pass
    evidence: "test/unit/manifest_test.rb tests 'generate returns the documented top-level shape', 'generate emits params as Hash{string => type-string} and required[] as strings', and 'generate covers all 5 ParamSchema types' all green; commit 4f6aa3d"
  - criterion: "TrackRelay::Manifest.write!(path:) writes pretty-printed JSON to path and returns the path; default path is Rails.root.join('public', 'track_relay_catalog.json'). MUST FileUtils.mkdir_p(File.dirname(path)) before writing"
    verdict: pass
    evidence: "lib/track_relay/manifest.rb:68-72 implements write! with FileUtils.mkdir_p before File.write+JSON.pretty_generate, returns path; default_path private method joins Rails.root with 'public/track_relay_catalog.json'; tests 'write! returns the path it wrote to' and 'write! emits pretty-printed JSON.parse-able content' green; commit 4f6aa3d"
  - criterion: "Manifest.write! succeeds in a fresh checkout with no public/ directory; verified by test/unit/manifest_test.rb#test_creates_parent_directory"
    verdict: pass
    evidence: "test/unit/manifest_test.rb#test_creates_parent_directory uses Pathname(Dir.mktmpdir).join('brand_new_subdir/track_relay_catalog.json'), asserts parent dir does NOT exist as precondition, then asserts both file and parent dir exist after write!. Test is green; commit 4f6aa3d. Confirmed test/internal/public/ remains absent in the working tree (plan-critical)."
  - criterion: "rake track_relay:manifest task exists in lib/tasks/track_relay.rake and writes public/track_relay_catalog.json; depends on :environment; aborts with non-zero exit and message when Catalog.all.empty? (RISK-04 mitigation)"
    verdict: pass
    evidence: "lib/tasks/track_relay.rake:42-54 defines `task manifest: :environment` with abort guard before write; test/integration/manifest_rake_test.rb tests 'writes the manifest to public/track_relay_catalog.json', 'task prints the path and event count', and 'aborts NONZERO when the catalog is empty (RISK-04 guard)' all green; commit c88b16c"
  - criterion: "Railtie has a new initializer track_relay.enhance_assets_precompile that calls Rake::Task['assets:precompile'].enhance(['track_relay:manifest']) when the task is defined"
    verdict: pass
    evidence: "lib/track_relay/railtie.rb:79-87 defines the initializer; test/integration/manifest_dev_reload_test.rb test 'assets:precompile gets track_relay:manifest as a prerequisite when defined' green (calls initializer.block.call against a fresh Rake::Application with assets:precompile pre-defined and asserts prerequisite is chained); commit c94c95d"
  - criterion: "Railtie has dev-mode regeneration: in config.to_prepare block, when Rails.env.development?, call TrackRelay::Manifest.write! after the catalog reload (chained inside the existing track_relay.catalog_autoload initializer)"
    verdict: pass
    evidence: "lib/track_relay/railtie.rb:53-55 chains `TrackRelay::Manifest.write! if Rails.env.development? && TrackRelay::Catalog.all.any?` after the catalog reload inside the existing track_relay.catalog_autoload to_prepare block; tests 'to_prepare regenerates the manifest when Rails.env.development?', 'to_prepare does NOT write the manifest in test env', and 'to_prepare does NOT write the manifest in development when catalog is empty' all green; commit c94c95d"
  - criterion: "Test: Manifest.generate produces correct shape for a catalog with mixed required/optional params and all 5 ParamSchema types (integer/string/float/boolean/datetime)"
    verdict: pass
    evidence: "test/unit/manifest_test.rb#test_generate_covers_all_5_ParamSchema_types builds an :every_type event with one param of each type, asserts each type-string maps correctly; test_generate_emits_params_as_Hash...required[]_as_strings covers mixed required/optional ('value' required, 'currency' optional). Both green."
  - criterion: "Test: rake track_relay:manifest exits non-zero when catalog is empty"
    verdict: pass
    evidence: "test/integration/manifest_rake_test.rb#test_aborts_NONZERO_when_the_catalog_is_empty captures $stderr, asserts SystemExit raised, refute_equal 0, err.status, asserts /catalog is empty/i in stderr, and refute File.exist?(MANIFEST_PATH). Green."
  - criterion: "Test: dev-mode reload regenerates the file (assert mtime changes after a to_prepare invocation)"
    verdict: pass
    evidence: "test/integration/manifest_dev_reload_test.rb#test_to_prepare_regenerates_the_manifest_when_Rails.env.development? writes a temp catalog file, stubs Rails.env.development?=true, invokes Rails.application.reloader.prepare!, asserts manifest exists and contains the new event's schema. Green."
  - criterion: "Manifest JSON is a valid JSON.parse-able document with version matching TrackRelay::VERSION"
    verdict: pass
    evidence: "test/unit/manifest_test.rb#test_generate_produces_JSON.parse-able_output_via_JSON.pretty_generate parses JSON.pretty_generate(generate(...)) and asserts version equals TrackRelay::VERSION. Also covered by manifest_rake_test#test_writes_the_manifest_to_public... which JSON.parse-s the on-disk file and asserts version. Both green."
---

Generated a typed JSON manifest of the catalog at `public/track_relay_catalog.json` so the Phase 02-05 JS client can fetch and validate events client-side. Wired into `assets:precompile` for production builds and `to_prepare` for dev-mode regeneration.

## What Was Built

- `lib/track_relay/manifest.rb` (new) — `TrackRelay::Manifest` module with two class methods: `.generate(catalog: Catalog)` returns the typed manifest Hash with `version` (TrackRelay::VERSION), `generated_at` (ISO8601 UTC string), and `events` keyed by event name with `params` (Hash{string => type-string}) covering all five ParamSchema types and `required[]` (string array, `[]` when none); `.write!(path: default_path, catalog: Catalog)` writes pretty-printed JSON via `FileUtils.mkdir_p(File.dirname(path)) + File.write + JSON.pretty_generate` and returns the path. The mkdir_p guard is load-bearing: the Combustion dummy app at `test/internal/` ships without a `public/` directory, and without it the gem's own test suite would crash on first invocation with `Errno::ENOENT`. Default path resolves to `Rails.root.join("public", "track_relay_catalog.json")` when Rails is loaded.
- `lib/tasks/track_relay.rake` — added `desc "Generate public/track_relay_catalog.json from the loaded catalog"; task manifest: :environment` task. Aborts with a NONZERO exit and a clear message ("[track_relay] aborting: catalog is empty (no events registered — check config/track_relay/**/*.rb)") when `Catalog.all.empty?`, mirroring the lint task's footgun-prevention pattern. RISK-04 guard: an empty manifest tells the JS client "no schema, accept everything", which is worse than a loud failure. On success, prints the written path and a singular/plural-aware event count. Loads `Manifest` via `require_relative "../track_relay/manifest"` so this plan stays file-disjoint with Plan 02-02's ownership of `lib/track_relay.rb` in the same wave.
- `lib/track_relay/railtie.rb` — added `track_relay.enhance_assets_precompile` initializer that chains `track_relay:manifest` as a prerequisite of `assets:precompile` when both are defined, so production / CI builds always ship a fresh manifest. Guarded by `defined?(Rake) && Rake::Task.task_defined?` so API-only Rails apps without Rake or Sprockets/Propshaft are a clean no-op. Also extended the existing `track_relay.catalog_autoload` initializer's `to_prepare` block to call `TrackRelay::Manifest.write!` AFTER the catalog reload when `Rails.env.development? && TrackRelay::Catalog.all.any?`, so editing `config/track_relay/*.rb` regenerates the manifest without a server restart. Test env is excluded explicitly to avoid every-test churn.
- `test/unit/manifest_test.rb` (new) — 9 unit tests: shape (top-level, params/required, all 5 types, empty-required-array, JSON-parseable, empty-catalog), write! contract (returns path, pretty JSON), and the load-bearing `creates_parent_directory` test that uses `Dir.mktmpdir` + `brand_new_subdir/` to prove the mkdir_p guard works.
- `test/integration/manifest_rake_test.rb` (new) — 5 integration tests: writes to `public/track_relay_catalog.json`, content matches `Manifest.generate`, prints path + event count (singular/plural), aborts NONZERO on empty catalog (with stderr captured), task is defined alongside lint via the Railtie loader.
- `test/integration/manifest_dev_reload_test.rb` (new) — 5 integration tests: dev-mode `to_prepare` regenerates the manifest (using `Rails.env.stub :development?, true` + `Rails.application.reloader.prepare!`), test-env does NOT regenerate, empty-catalog dev-mode does NOT regenerate, `assets:precompile` prerequisite is chained when defined (re-runs the initializer block against a fresh `Rake::Application`), and `enhance_assets_precompile` is a no-op when `assets:precompile` is undefined.
- `CHANGELOG.md` — `[Unreleased]` entry documenting the new public surface (rake task, Railtie hooks, mkdir_p safety guarantee).

## Files Modified

- `lib/track_relay/manifest.rb` -- create: `TrackRelay::Manifest` module with `.generate` and `.write!`
- `lib/tasks/track_relay.rake` -- modify: add `track_relay:manifest` task with empty-catalog abort guard; require_relative the Manifest module
- `lib/track_relay/railtie.rb` -- modify: extend catalog_autoload to_prepare block with dev-mode `Manifest.write!`; add `track_relay.enhance_assets_precompile` initializer
- `test/unit/manifest_test.rb` -- create: 9 unit tests covering generate shape + write! contract + parent-dir guard
- `test/integration/manifest_rake_test.rb` -- create: 5 integration tests for the rake task (happy path + empty-catalog abort + Railtie wiring)
- `test/integration/manifest_dev_reload_test.rb` -- create: 5 integration tests for the Railtie hooks (dev-mode regen + assets:precompile prerequisite)
- `CHANGELOG.md` -- modify: document the new manifest surface in `[Unreleased]`

## Deviations

- DEVN-01 (commit count): combined plan tasks 1 (`Manifest.generate`) and 2 (`Manifest.write!`) into a single commit (4f6aa3d) rather than splitting them. Both methods live in the same small module file (`lib/track_relay/manifest.rb`) and are exercised by the same test file (`test/unit/manifest_test.rb`); a split would require an artificial back-and-forth edit on the same file and produce a commit history that looks like a partial implementation. The plan body says "One commit per task preferred" (not strict) and the commit-discipline rule explicitly allows TDD splits ("Never split (except TDD: 2-3)"). Plan tasks 3, 4, 5 each ship as their own atomic commit (c88b16c, c94c95d, 122e467), so the per-task discipline is honored where the task boundaries are meaningful.
- DEVN-01 (Rake constant guard): added `defined?(Rake) &&` before `Rake::Task.task_defined?("assets:precompile")` in the `track_relay.enhance_assets_precompile` initializer (`lib/track_relay/railtie.rb:84`). The plan body referenced `Rake::Task.task_defined?` directly, but Combustion's `:action_controller, :active_job` boot does NOT auto-require Rake — so the bare `Rake` constant reference raised `NameError: uninitialized constant TrackRelay::Railtie::Rake` during Combustion.initialize! in the gem's own test suite. The defensive guard makes API-only Rails apps (no Rake at boot) a clean no-op, matching the same posture as the `task_defined?` check that follows. In-spirit fix; behavior is identical for any host that DOES load Rake (assets:precompile is a Rake-defined task, so `defined?(Rake)` is true wherever the prerequisite is meaningful).

## Pre-existing Issues

None. During plan execution, dev-02's in-flight Plan 02-02 work transiently caused 2 failures in `ControllerTrackingTest` (Plan 02-02's territory) when the `Session` resolver started returning UUIDs for missing/malformed `_ga` cookies. Those were resolved by dev-02's commit `1d51f4c feat(02-02): wire ControllerTracking to client_id resolver chain`, which landed before this plan's final verification. Final `bundle exec rake test` is 305 runs / 0 failures.
