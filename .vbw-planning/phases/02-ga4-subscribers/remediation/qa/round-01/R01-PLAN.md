---
phase: 02
round: 01
plan: R01
title: QA round 01 — reconcile plan bodies with shipped code (DEV-01, DEV-03) and accept DEV-02 as process exception
type: remediation
autonomous: true
effort_override: balanced
skills_used:
  - tdd-cycle
  - rails-architecture
  - simplify
files_modified:
  - .vbw-planning/phases/02-ga4-subscribers/02-02-PLAN.md
  - .vbw-planning/phases/02-ga4-subscribers/02-03-PLAN.md
forbidden_commands: []
fail_classifications:
  - {id: "DEV-01", type: "plan-amendment", rationale: "Plan 02-02 task 4 contained a self-contradictory note (existing controller_tracking tests must still pass with no changes) while its own must_haves required Session-fallback UUID at exactly those Phase-1 assertion sites. The shipped behavior at test/integration/controller_tracking_test.rb lines 75-99 (refute_nil + assert_match UUID regex) is correct and satisfies MH-15. Cookie-present parity test at line 62 is untouched. Amend the plan body to drop the contradictory guidance and document the intentional test updates.", source_plan: "02-02-PLAN.md"}
  - {id: "DEV-02", type: "process-exception", rationale: "Tasks 1 and 2 of Plan 02-03 (Manifest.generate and Manifest.write!) were combined into commit 4f6aa3d on main rather than two separate commits. All must_haves MH-18 through MH-27 PASS. The two methods share one source file (lib/track_relay/manifest.rb) and one test file (test/unit/manifest_test.rb); splitting now would require rebasing public history. Plan body says one commit per task is preferred (preference, not mandate). Combined commit is well-scoped and atomic. Accepted as process exception - no Dev work required."}
  - {id: "DEV-03", type: "plan-amendment", rationale: "Plan 02-03 task 4 specified bare Rake::Task.task_defined? for the track_relay.enhance_assets_precompile initializer. Combustion boots the dummy app with :action_controller, :active_job - neither requires Rake - so the bare reference raised NameError during the test suite app initialization. The shipped guard at lib/track_relay/railtie.rb:85 (defined?(Rake) && Rake::Task.task_defined?) is a defensive in-spirit fix matching task_defined own posture and is already validated by AP-03 (anti-pattern scan PASS). Amend the plan body to specify the guard and document the Combustion boot rationale.", source_plan: "02-03-PLAN.md"}
known_issues_input:
  - '{"test":"manual GA4 DebugView verification","file":"test/integration/ga4_delivery_retry_test.rb","error":"Requires real G-XXX measurement_id + api_secret — deferred to UAT; webmock-stubbed unit + integration tests cover the wire contract"}'
  - '{"test":"manual GA4 Realtime browser smoke","file":"client/test/index.test.js","error":"Requires real measurement_id + browser session — deferred to UAT; happy-dom + vitest cover the contract"}'
known_issue_resolutions:
  - '{"test":"manual GA4 DebugView verification","file":"test/integration/ga4_delivery_retry_test.rb","error":"Requires real G-XXX measurement_id + api_secret — deferred to UAT; webmock-stubbed unit + integration tests cover the wire contract","disposition":"accepted-process-exception","rationale":"Verifies in UAT only; real GA4 credentials (measurement_id + api_secret) are user-supplied and not present in this session. Webmock-stubbed unit + integration tests cover the wire contract (URL, query params, JSON body, retry behavior). Carrying as a verified non-blocking known issue for Phase 02."}'
  - '{"test":"manual GA4 Realtime browser smoke","file":"client/test/index.test.js","error":"Requires real measurement_id + browser session — deferred to UAT; happy-dom + vitest cover the contract","disposition":"accepted-process-exception","rationale":"Verifies in UAT only; real GA4 measurement_id plus a live browser session are required and out of scope for the headless Vitest suite. happy-dom + vitest tests cover the gtag dispatch contract, init/track lifecycle, and validation behavior. Carrying as a verified non-blocking known issue for Phase 02."}'
must_haves:
  truths:
    - "Plan 02-02 body no longer contains the contradictory directive that existing controller_tracking tests must remain unchanged; instead it explicitly documents that two Phase-1 assertions at test/integration/controller_tracking_test.rb (~lines 75-99) were intentionally updated from assert_nil to refute_nil + UUID-format assert_match to satisfy MH-15."
    - "Plan 02-03 body specifies the implementation as `if defined?(Rake) && Rake::Task.task_defined?(\"assets:precompile\")` (matching lib/track_relay/railtie.rb:85) and documents the Combustion-boot rationale for the additional `defined?(Rake)` guard."
    - "DEV-02 is recorded as an accepted process exception in fail_classifications with no Dev task; no commit is rewritten and main history is not rebased."
    - "Both carried known issues remain present in known_issues_input AND known_issue_resolutions with disposition `accepted-process-exception`."
    - "No product code under lib/, app/, test/, or client/ is touched by this round — only planning artifacts under .vbw-planning/."
    - "After amendments, `bundle exec rake` is still 383 runs / 0 failures / 0 errors and the JS suite is still 31/31 passing — verified by re-run, not assumed."
  artifacts:
    - {path: ".vbw-planning/phases/02-ga4-subscribers/02-02-PLAN.md", provides: "amended Plan 02-02 body", contains: "intentionally updated"}
    - {path: ".vbw-planning/phases/02-ga4-subscribers/02-03-PLAN.md", provides: "amended Plan 02-03 body", contains: "defined?(Rake) &&"}
    - {path: ".vbw-planning/phases/02-ga4-subscribers/remediation/qa/round-01/R01-SUMMARY.md", provides: "round-01 outcome summary", contains: "DEV-01"}
  key_links:
    - {from: "02-02-PLAN.md task 4", to: "test/integration/controller_tracking_test.rb:75-99", via: "documented test-update note"}
    - {from: "02-03-PLAN.md task 4", to: "lib/track_relay/railtie.rb:85", via: "Rake guard spec match"}
---
<objective>
Reconcile two Phase 02 plan bodies with the shipped (and verified-correct) code so the planning record matches reality, and formally accept the DEV-02 commit-batching deviation as a process exception. No product code changes; no test changes; no commit history rewrite. The two plan-amendment tasks update planning artifacts only — Plan 02-02 (DEV-01: drop contradictory test-stability note, document the intentional Phase-1 → Phase-2 assertion migration) and Plan 02-03 (DEV-03: spec the `defined?(Rake) &&` guard with Combustion-boot rationale). DEV-02 is captured exclusively in fail_classifications and the round summary. Verification step at the end re-runs the full Ruby + JS suites to confirm 383/0 and 31/0 still hold after planning edits.
</objective>

<context>
@.vbw-planning/phases/02-ga4-subscribers/02-VERIFICATION.md
@.vbw-planning/phases/02-ga4-subscribers/02-02-PLAN.md
@.vbw-planning/phases/02-ga4-subscribers/02-03-PLAN.md
@.vbw-planning/phases/02-ga4-subscribers/remediation/qa/round-01/R01-KNOWN-ISSUES.json
@lib/track_relay/railtie.rb
@test/integration/controller_tracking_test.rb
</context>

<tasks>
<task type="auto">
  <name>Amend Plan 02-02 body to reconcile DEV-01 (Phase-1 test migration documentation)</name>
  <files>
    .vbw-planning/phases/02-ga4-subscribers/02-02-PLAN.md
  </files>
  <action>
Edit `.vbw-planning/phases/02-ga4-subscribers/02-02-PLAN.md`. In task 4 ("Rewire `ControllerTracking` to use the chain"), remove the trailing sentence claim that "the existing `controller_tracking` tests should still pass because the default chain's `ClientId::Ga` reproduces Phase 1 behavior bit-for-bit" and the implied "no changes to existing tests" directive. Replace it with explicit language documenting the intentional update: the Phase-1 cookie-present parity test at `test/integration/controller_tracking_test.rb:62` MUST remain untouched (still asserts `"123456789.1700000000"`), but the two Phase-1 missing-cookie / malformed-cookie cases (at ~lines 75 and 92) are intentionally migrated from `assert_nil` to `refute_nil` + `assert_match(/\A[0-9a-f-]{36}\z/, snapshot)` because MH-15 requires the Session resolver to mint a stable UUID when no `_ga` cookie is present — Phase-1 returned nil at exactly those assertion sites, so they must change to satisfy the new must_have. Cross-link the two updated test names ("missing _ga cookie falls through to Session UUID (Phase 02 chain)", "malformed _ga cookie falls through to Session UUID (Phase 02 chain)") so the reconciliation is unambiguous. Do NOT modify must_haves or any other plan section. Do NOT change any product code or test files.
  </action>
  <verify>
`grep -n "bit-for-bit" .vbw-planning/phases/02-ga4-subscribers/02-02-PLAN.md` returns nothing. `grep -n "intentionally migrated\|refute_nil\|UUID regex" .vbw-planning/phases/02-ga4-subscribers/02-02-PLAN.md` returns at least one match inside task 4. `git diff --stat -- lib/ test/ app/ client/` shows zero changes.
  </verify>
  <done>
Plan 02-02 body explicitly documents the two intentionally-updated Phase-1 tests, the cookie-present parity test is called out as untouched, and the contradictory directive is gone. Only `.vbw-planning/phases/02-ga4-subscribers/02-02-PLAN.md` is modified.
  </done>
</task>

<task type="auto">
  <name>Amend Plan 02-03 body to reconcile DEV-03 (defined?(Rake) guard specification)</name>
  <files>
    .vbw-planning/phases/02-ga4-subscribers/02-03-PLAN.md
  </files>
  <action>
Edit `.vbw-planning/phases/02-ga4-subscribers/02-03-PLAN.md`. In the bullet at the top of "Files Touched" describing the `track_relay.enhance_assets_precompile` initializer, and in task 4's implementation note for that initializer, replace the bare `Rake::Task.task_defined?("assets:precompile")` reference with `defined?(Rake) && Rake::Task.task_defined?("assets:precompile")`. Add a one- or two-sentence rationale immediately after the spec explaining: Combustion boots the gem's dummy app with `:action_controller, :active_job` only — `rake` is not required at app boot in that path — so the bare `Rake::Task` reference raises `NameError` during the test suite's load phase; the `defined?(Rake) &&` guard mirrors the defensive posture of `task_defined?` itself (which also tolerates an undefined task) and matches the shipped code at `lib/track_relay/railtie.rb:85-87`. Update the matching must_have entry only if needed for consistency; otherwise leave must_haves alone. Do NOT modify any product code or test files.
  </action>
  <verify>
`grep -n "defined?(Rake) &&" .vbw-planning/phases/02-ga4-subscribers/02-03-PLAN.md` returns at least two matches (Files Touched bullet + task 4). `grep -n "Combustion" .vbw-planning/phases/02-ga4-subscribers/02-03-PLAN.md` returns at least one match in the rationale text. `git diff --stat -- lib/ test/ app/ client/` shows zero changes.
  </verify>
  <done>
Plan 02-03 body specifies `defined?(Rake) && Rake::Task.task_defined?(...)` in both the Files Touched description and task 4's implementation note, and includes a Combustion-boot rationale. Only `.vbw-planning/phases/02-ga4-subscribers/02-03-PLAN.md` is modified.
  </done>
</task>

<task type="auto">
  <name>Re-run full Ruby + JS suites to confirm planning amendments did not perturb code state</name>
  <files>
  </files>
  <action>
From the repo root, run `bundle exec rake` and capture the final tally line. From `client/`, run `npm test` and capture the Vitest summary. The amendments above only touched `.vbw-planning/` planning artifacts, so both suites MUST report identical totals to the source verification: 383 runs / 0 failures / 0 errors / 0 skips for Ruby, and 31/31 passing across `build_smoke` (4) + `index` (23) + `ga4_gtag` (4) for JS. If either suite regresses, STOP and surface the diff — a regression here would indicate an accidental product-code edit and must be investigated before R01-SUMMARY.md is written.
  </action>
  <verify>
Ruby: terminal output contains `383 runs, 857 assertions, 0 failures, 0 errors, 0 skips`. JS: terminal output reports `31 passed` across 3 test files. `git status` shows only the two planning files under `.vbw-planning/phases/02-ga4-subscribers/` as modified, with no `lib/`, `test/`, `app/`, or `client/` changes.
  </verify>
  <done>
Both suites pass at the same totals as the source verification. The git working tree is clean of any non-planning edits.
  </done>
</task>
</tasks>

<verification>
1. `bundle exec rake` returns 383 runs / 857 assertions / 0 failures / 0 errors / 0 skips (matches 02-VERIFICATION.md MH-08 evidence).
2. `cd client && npm test` returns 31 passed across 3 test files (matches MH-49 evidence).
3. `git diff --stat` shows only `.vbw-planning/phases/02-ga4-subscribers/02-02-PLAN.md` and `.vbw-planning/phases/02-ga4-subscribers/02-03-PLAN.md` as modified.
4. `grep -n "bit-for-bit" .vbw-planning/phases/02-ga4-subscribers/02-02-PLAN.md` returns nothing; the contradictory directive is fully removed.
5. `grep -n "defined?(Rake) &&" .vbw-planning/phases/02-ga4-subscribers/02-03-PLAN.md` returns at least two matches and the Combustion rationale is present.
6. R01-SUMMARY.md (written by the executor at the end of this round) carries forward both known issues with `accepted-process-exception` disposition and records DEV-02 as an accepted process exception with no Dev task executed.
</verification>

<success_criteria>
- Plan 02-02 body no longer contains a self-contradictory test-stability directive; the two intentionally-migrated Phase-1 assertions are documented inline.
- Plan 02-03 body specifies the `defined?(Rake) && Rake::Task.task_defined?(...)` guard with Combustion-boot rationale, matching the shipped code at `lib/track_relay/railtie.rb:85`.
- DEV-02 is captured exclusively as a process exception in `fail_classifications` and the round summary; main commit history is not rewritten.
- Both carried known issues remain in `known_issues_input` and `known_issue_resolutions` with `accepted-process-exception` disposition.
- `bundle exec rake` still reports 383/0 and `npm test` still reports 31/31 after the planning amendments — confirming no product code or test was touched.
- `git status` shows only the two `.vbw-planning/` plan files as modified at the end of the round.
</success_criteria>

<known_issue_workflow>
- Copy every carried known issue from the remediation input backlog into `known_issues_input` using the canonical `{test,file,error}` shape.
- Add a matching `known_issue_resolutions` entry for every carried known issue. Use `resolved` when this round fixes it, `accepted-process-exception` when QA should treat it as a verified non-blocking carryover for this phase, and `unresolved` only when the issue is intentionally carried into the next round.
- Do not omit a carried known issue from these arrays. The deterministic gate treats missing coverage as a failed remediation round.
</known_issue_workflow>

<output>
R01-SUMMARY.md
</output>
