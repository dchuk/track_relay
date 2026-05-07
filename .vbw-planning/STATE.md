# State

**Project:** track_relay
**Milestone:** Core (MVP)

## Current Phase
Phase: 4 of 4 (Polish)
Plans: 5/5
Progress: 100%
Status: complete

## Phase Status
- **Phase 1 (Core Mvp):** Complete
- **Phase 2 (Ga4 Subscribers):** Complete
- **Phase 3 (Ahoy Subscribers):** Complete
- **Phase 4 (Polish):** Complete

## Key Decisions
| Decision | Date | Rationale |
|----------|------|-----------|
| Ruby >= 3.2 floor; CI matrix Rails 7.1 / 7.2 / 8.0 | 2026-05-05 | Aligns with current LTS landscape; lets us use Ruby-3.2-only features (Data.define, etc.); no Rails upper bound — let SemVer break point us |
| Minitest for the gem's own test suite | 2026-05-05 | Rails-core convention; Combustion-based dummy app; user has tdd-cycle skill calibrated for Minitest+fixtures. Gem still ships matchers for both RSpec and Minitest for consumers |

## Todos
_(No todos)_

- [KNOWN-ISSUE] manual GA4 DebugView verification (test/integration/ga4_delivery_retry_test.rb): Requires real G-XXX measurement_id + api_secret — deferred to UAT; webmock-st... — accepted as process-exception for this phase (phase 02, seen 1x) (see remediation/qa/round-01/R01-SUMMARY.md) (added 2026-05-06) (ref:ec81aef3)
- [KNOWN-ISSUE] manual GA4 Realtime browser smoke (client/test/index.test.js): Requires real measurement_id + browser session — deferred to UAT; happy-dom +... — accepted as process-exception for this phase (phase 02, seen 1x) (see remediation/qa/round-01/R01-SUMMARY.md) (added 2026-05-06) (ref:05d7522b)

## Blockers
_(No blockers)_

## Activity Log
- 2026-05-05: Created Core (MVP) milestone (4 phases)
- 2026-05-05: Phase 01 discussion captured (Ruby/Rails matrix, failsafe boundary, test framework, untyped detection) — see `phases/01-core-mvp/01-CONTEXT.md`
- 2026-05-06: Phase 01 planning complete — Scout research (489 lines) + Lead decomposition into 9 plans / 33 tasks / 9 waves (fully serialized due to shared `lib/track_relay.rb` module growth)
- 2026-05-06: Phase 02 discussion captured (subscriber-side filters, configurable client_id chain, split constraint enforcement, full typed manifest) — see `phases/02-ga4-subscribers/02-CONTEXT.md`
- 2026-05-06: Phase 02 planning complete — Scout research (813 lines) + Lead decomposition into 5 plans / 25 tasks / 4 waves (DAG: 02-01 → {02, 03} → 04 → 05; Wave 2 parallel safe, Wave 3-4 serialized)
- 2026-05-06: Phase 03 planning complete — Scout research (542 lines) + Lead decomposition into 2 plans / 10 tasks / 2 waves (03-01 server subscriber → 03-02 client AhoyJs + 0.3.0 release; sequential — release verification depends on server-side green)
- 2026-05-06: Phase 03 plans revised after codex Plan Reviewer pass — 4 fixes: appraisal slugs `rails-X-Y` → `rails_X_Y` (matches actual `Appraisals` file); 03-01 task 2 filter test now calls `subscriber.handle(payload)` instead of `safe_deliver` (Base filter gate runs in `#handle`, not `safe_deliver`); 03-02 task 1 enumerates the six specific tests in `client/test/index.test.js:33-60` instead of grep-and-update; 03-02 task 4 replaces "scratch .ts file" with concrete `npx tsc --noEmit` command using a `/tmp/` temp file
- 2026-05-06: Phase 03 execution complete — Plan 03-01 (server `Subscribers::Ahoy` + ahoy_matey dev-dep, 4 commits) and Plan 03-02 (`AhoyJs` client export + 0.3.0 release, 4 commits) shipped; full appraisal matrix GREEN (rails_7_1/7_2/8_0, 392 tests each); client GREEN (37 tests, +6 ahoy_js); 0.3.0 released (gem version + npm package + CHANGELOG with BREAKING `init({manifestUrl})`-now-optional)
- 2026-05-06: Phase 03 QA Remediation Round 01 — 3 plan-amendments to formalize MH-02 (lockfile-based `ahoy_matey` resolution wording), MH-06 (replace self-deviation with affirmative `controller.ahoy.track`-only must_haves + skip-path substitute for missing `Ahoy::Visit#track`), MH-21 (drop malformed `tsc --allowImportingTsExtensions=false` flag); commit `323e183`; R01-VERIFICATION PASS; UAT 3/3 pass
- 2026-05-06: Phase 04 discussion captured (Phase 4 scope = generators + doc audit + Combustion E2E; engine mount/perf benchmarks/Rubocop cop/v2 subscribers deferred to follow-up milestone; 1.0.0 cuts AFTER Phase 4 UAT inside this same milestone; opinionated Devise/ActiveAdmin-style scaffolds; layered structural+E2E test plan; standard 1.0.0 doc set with USAGE.md + UPGRADING.md migration notes) — see `phases/04-polish/04-CONTEXT.md`
- 2026-05-07: Phase 04 planning complete — Scout research (lib/ surface, Combustion harness inventory, README/CHANGELOG state, Devise/ActiveAdmin generator conventions) + Lead decomposition into 5 plans / 22 tasks / 4 waves (Wave 1 parallel-safe: 04-01 install generator + 04-05 doc audit; Wave 2: 04-02 event/subscriber generators; Wave 3: 04-03 generator structural tests; Wave 4: 04-04 E2E happy-path); 7 open questions resolved inline (subscriber path = `app/track_relay/subscribers/`, inject guard = `File.read` + `String#include?`, E2E approach = programmatic `Rails::Generators.invoke` into tmpdir, sample event = `:hello_world`, doc path = `USAGE.md` at root, Ahoy initializer = comment-only with gem note)
- 2026-05-07: Phase 04 plans revised after codex Plan Reviewer pass — 6 fixes verified against repo: (1) `bundle exec rails test` → `bundle exec rake test ...` in 04-03/04-04 (Rakefile uses `Minitest::TestTask`, no `bin/rails`); (2) dropped `bundle exec rails generators` discovery probe from 04-01/04-02 task 5 (gem repo has no `bin/rails`; the Ruby load probe IS the discovery test); (3) added `require "track_relay/testing/helpers"` to 04-04 E2E test (`test_helper.rb` requires `track_relay/testing` which does NOT auto-require helpers); (4) added `TrackRelay::Dispatcher.start!` to 04-04 E2E setup (global teardown calls `Dispatcher.stop!`; `test_mode!` alone does not restart dispatch); (5) replaced 04-03 install-test buggy duplicate `File.write` block with single canonical version; (6) reframed 04-05 CHANGELOG/Roadmap to "1.0.0 (pending release)" wording and dropped the `[Unreleased] → v1.0.0...HEAD` retarget (the `v1.0.0` tag is cut post-UAT during milestone archive)
- 2026-05-07: Phase 04 plans patched again after codex re-review — 2 follow-ups: (a) per-file scoping `rake test TEST=path` → `bundle exec ruby -Ilib -Itest path` across 04-03/04-04 (`Minitest::TestTask` ignores `ENV["TEST"]`, only honors `N`/`X`/`A`/`TESTOPTS`/`FILTER`; verified empirically by running `rake test TEST=...` and observing the full 392-test suite execute); (b) corrected 04-04 idempotency rationale — the install generator runs against an empty tmpdir, so the inject step hits the controller-missing `say_status :skip` branch (not the idempotency-already-included branch); test/internal's pre-existing `include TrackRelay::ControllerTracking` is independent fixture state, not generator output
- 2026-05-07: Phase 04 execution complete — 5 plans / 17 commits / 405 tests passing. Wave 1 (04-01 install generator + 04-05 doc audit): 8 commits across 4 files of generator scaffolding and 4 files of 1.0.0 docs (README, CHANGELOG `[1.0.0]`, USAGE.md, UPGRADING.md). Wave 2 (04-02 event+subscriber generators): 4 commits. Wave 3 (04-03 generator structural tests): 3 commits, +12 tests using `Rails::Generators::TestCase` with tmpdir destination. Wave 4 (04-04 E2E happy-path): 2 commits, +1 integration test invoking install generator into tmpdir, copying outputs into Combustion app, asserting `assert_tracked :hello_world`.
- 2026-05-07: Phase 04 QA Remediation Round 01 — 2 plan-amendments resolving DEV-01 (04-05 task 1 dropped reference to non-existent "0.x version cell" in README Compatibility matrix) and DEV-02 (04-05 task 2 replaced brittle exact-count grep with semantic `grep -q`); commits `d2e444a`, `28cf7d3`; R01-VERIFICATION PASS (10/10).
- 2026-05-07: Phase 04 UAT complete — 6/6 checkpoints pass (install generator UX, event+subscriber generator UX, structural test approach, E2E approach, README+CHANGELOG 1.0.0 read, USAGE+UPGRADING docs). Phase ready for milestone archive + 1.0.0 release cut.
