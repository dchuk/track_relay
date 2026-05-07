# State

**Project:** track_relay
**Milestone:** Core (MVP)

## Current Phase
Phase: 3 of 3 (Ahoy Subscribers)
Plans: 2/2
Progress: 100%
Status: complete

## Phase Status
- **Phase 1 (Core Mvp):** Complete
- **Phase 2 (Ga4 Subscribers):** Complete
- **Phase 3 (Ahoy Subscribers):** Complete

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
