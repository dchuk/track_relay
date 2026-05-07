---
phase: 02
round: 01
title: QA round 01 — reconcile plan bodies with shipped code (DEV-01, DEV-03) and accept DEV-02 as process exception
type: remediation
status: complete
completed: 2026-05-06
tasks_completed: 3
tasks_total: 3
commit_hashes:
  - 7720de4
  - 1ff4206
files_modified:
  - .vbw-planning/phases/02-ga4-subscribers/02-02-PLAN.md
  - .vbw-planning/phases/02-ga4-subscribers/02-03-PLAN.md
deviations: []
known_issue_outcomes:
  - '{"test":"manual GA4 DebugView verification","file":"test/integration/ga4_delivery_retry_test.rb","error":"Requires real G-XXX measurement_id + api_secret — deferred to UAT; webmock-stubbed unit + integration tests cover the wire contract","disposition":"accepted-process-exception","rationale":"Verifies in UAT only; real GA4 credentials (measurement_id + api_secret) are user-supplied and not present in this session. Webmock-stubbed unit + integration tests cover the wire contract (URL, query params, JSON body, retry behavior). Carrying as a verified non-blocking known issue for Phase 02."}'
  - '{"test":"manual GA4 Realtime browser smoke","file":"client/test/index.test.js","error":"Requires real measurement_id + browser session — deferred to UAT; happy-dom + vitest cover the contract","disposition":"accepted-process-exception","rationale":"Verifies in UAT only; real GA4 measurement_id plus a live browser session are required and out of scope for the headless Vitest suite. happy-dom + vitest tests cover the gtag dispatch contract, init/track lifecycle, and validation behavior. Carrying as a verified non-blocking known issue for Phase 02."}'
---

Reconciled two Phase 02 plan bodies with the shipped (and verified-correct) code: dropped a contradictory test-stability directive in Plan 02-02 (DEV-01) and specified the `defined?(Rake) &&` guard with Combustion-boot rationale in Plan 02-03 (DEV-03). DEV-02 captured exclusively as an accepted process exception per R01-PLAN.md `fail_classifications` — no Dev work executed and main commit history not rewritten.

## Task 1: Amend Plan 02-02 body to reconcile DEV-01 (Phase-1 test migration documentation)

### What Was Built
- Removed the contradictory directive in task 4 that "the existing `controller_tracking` tests should still pass because the default chain's `ClientId::Ga` reproduces Phase 1 behavior bit-for-bit"
- Added a "Phase-1 → Phase-2 test reconciliation (REQUIRED)" sub-section documenting the three Phase-1 cases:
  - Cookie-present parity test at `test/integration/controller_tracking_test.rb:62` — MUST remain untouched (still asserts `"123456789.1700000000"`)
  - Missing-cookie test at ~line 75 — intentionally migrated from `assert_nil` to `refute_nil` + `assert_match(/\A[0-9a-f-]{36}\z/, snapshot)` to satisfy MH-15 (Session-fallback UUID minting)
  - Malformed-cookie test at ~line 92 — same migration
- Cross-linked the renamed test names ("missing _ga cookie falls through to Session UUID (Phase 02 chain)", "malformed _ga cookie falls through to Session UUID (Phase 02 chain)") so the reconciliation is unambiguous

### Files Modified
- `.vbw-planning/phases/02-ga4-subscribers/02-02-PLAN.md` -- amend: drop contradictory directive in task 4 and document the intentional Phase-1 → Phase-2 assertion migration with line-number cross-links

### Known Issue Outcomes
- (No carried known issues are tied to this task — both UAT-deferred issues are recorded once at the round level, per R01-PLAN.md `known_issue_resolutions`.)

### Deviations
None

## Task 2: Amend Plan 02-03 body to reconcile DEV-03 (defined?(Rake) guard specification)

### What Was Built
- Replaced the bare `Rake::Task.task_defined?("assets:precompile")` reference with `defined?(Rake) && Rake::Task.task_defined?("assets:precompile")` in both the "Files Touched" bullet describing the `track_relay.enhance_assets_precompile` initializer AND task 4's implementation note for the same initializer
- Added a Combustion-boot rationale in both locations: the gem's dummy app at `test/internal/` boots with `:action_controller, :active_job` only, so a bare `Rake::Task` reference would raise `NameError: uninitialized constant Rake` during the test suite's app-initialization phase
- Noted that the guard mirrors `task_defined?`'s own defensive posture (it tolerates an undefined task) and matches the AP-03–verified shipped code at `lib/track_relay/railtie.rb:85-87`

### Files Modified
- `.vbw-planning/phases/02-ga4-subscribers/02-03-PLAN.md` -- amend: spec `defined?(Rake) &&` guard in Files Touched bullet + task 4 implementation note, with Combustion-boot rationale

### Known Issue Outcomes
- (No carried known issues are tied to this task — both UAT-deferred issues are recorded once at the round level.)

### Deviations
None

## Task 3: Re-run full Ruby + JS suites to confirm planning amendments did not perturb code state

### What Was Built
- Re-ran `bundle exec rake` from repo root: **383 runs, 857 assertions, 0 failures, 0 errors, 0 skips** — identical to source MH-08 evidence
- Re-ran `npm test` from `client/`: **31 passed across 3 test files** (`build_smoke` 4 + `ga4_gtag` 4 + `index` 23) — identical to source MH-49 evidence
- Verified via `git diff --stat -- lib/ test/ app/ client/` that no product code was touched by either committed amendment; `git status --short` shows only `.vbw-planning/` paths

### Files Modified
- (None — verification-only task)

### Known Issue Outcomes
- `manual GA4 DebugView verification` (`test/integration/ga4_delivery_retry_test.rb`) — `accepted-process-exception`: real GA4 credentials are user-supplied and out of scope for this session; webmock-stubbed unit + integration tests cover the wire contract.
- `manual GA4 Realtime browser smoke` (`client/test/index.test.js`) — `accepted-process-exception`: real measurement_id + a live browser session are out of scope for the headless Vitest suite; happy-dom + vitest cover the gtag dispatch contract, init/track lifecycle, and validation behavior.

### Deviations
None

## DEV-02 Process Exception (no Dev task executed)

Per R01-PLAN.md `fail_classifications`, Tasks 1 and 2 of Plan 02-03 (`Manifest.generate` + `Manifest.write!`) shipped in a single combined commit (`4f6aa3d` on main) rather than two separate commits. All must_haves MH-18 through MH-27 PASS, the two methods share one source file (`lib/track_relay/manifest.rb`) and one test file (`test/unit/manifest_test.rb`), Plan 02-03 says "one commit per task is preferred" (preference, not mandate), and splitting now would require rebasing public history. Captured here as an accepted process exception — no commit rewrite, no dev task.
