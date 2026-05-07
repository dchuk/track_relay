---
phase: 03
tier: standard
result: FAIL
passed: 28
failed: 3
total: 31
date: 2026-05-07
verified_at_commit: 52f9e3200d3c066f982224570350e0d1836ae1ee
writer: write-verification.sh
plans_verified:
  - 03-01
  - 03-02
---

## Must-Have Checks

| # | ID | Truth/Condition | Status | Evidence |
|---|-----|-----------------|--------|----------|
| 1 | MH-01 | track_relay.gemspec contains add_development_dependency "ahoy_matey" | PASS | track_relay.gemspec:33 — spec.add_development_dependency "ahoy_matey" present |
| 2 | MH-02 | ahoy_matey resolves in all three appraisal lockfiles (DEVN-01: not in .gemfile directly, resolves transitively) | FAIL | DEVN-01 declared deviation: gemfiles/rails_7_1.gemfile.lock:91 (5.4.2), gemfiles/rails_7_2.gemfile.lock:85 (5.5.0), gemfiles/rails_8_0.gemfile.lock:83 (5.5.0) — transitively resolved. Plan must_have said 'appears in each generated gemfile under gemfiles/' but appraisal-generated files only contain gemspec path:"../". Deviation recorded in SUMMARY deviations array as DEVN-01. |
| 3 | MH-03 | lib/track_relay/subscribers/ahoy.rb exists, inherits Subscribers::Base, calls synchronous!, no require ahoy or require ahoy_matey | PASS | File present at lib/track_relay/subscribers/ahoy.rb:68 — class Ahoy < Base; line 69 synchronous!; negative grep for require ahoy/ahoy_matey returns zero code-level matches |
| 4 | MH-04 | require track_relay/subscribers/ahoy added to lib/track_relay.rb directly after GA4 require | PASS | lib/track_relay.rb:20 has GA4 require, :21 has ahoy require — correct order confirmed |
| 5 | MH-05 | #deliver reads Current.controller directly, checks respond_to?(:ahoy, true), dispatches via controller.ahoy.track(payload.name.to_s, payload.params) only — never Ahoy::Event.create! or internal APIs | PASS | lib/track_relay/subscribers/ahoy.rb:78-92 — controller=Current.controller, unless controller&.respond_to?(:ahoy,true), tracker=controller.ahoy, tracker.track(payload.name.to_s, payload.params). No Ahoy::Event.create! or Ahoy::Tracker.new anywhere in non-comment lines. |
| 6 | MH-06 | DEVIATION RECORDED (DEVN-02): routes via controller.ahoy.track only — no Ahoy::Visit#track exists. Documented in SUMMARY deviations array AND CHANGELOG Notes | FAIL | DEVN-02 declared deviation per task description. SUMMARY.md deviations[0] contains DEVN-02 entry. CHANGELOG.md Notes section (line 25) documents the visit.track absence and substitute skip path. Per QA protocol, all declared deviations are FAIL checks in the contract record regardless of whether the underlying behavior is correct. |
| 7 | MH-07 | Skip-not-raise: nil controller / no ahoy / nil tracker -> Rails.logger.warn + return; no raise, no enqueue, no Ahoy API call | PASS | ahoy.rb:80-89 implements three skip paths with log_skip helper at :104-107; guard mirrors GA4 warn_missing_credentials pattern (defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger). All skip unit tests pass. |
| 8 | MH-08 | Synchronous dispatch: TrackRelay::Subscribers::Ahoy.synchronous returns true | PASS | ahoy.rb:69 — synchronous! called at class body. test_synchronous_flag_is_set asserts this and passes. |
| 9 | MH-09 | Unit tests in test/unit/subscribers/ahoy_test.rb cover all 7 cases (a-g): dispatch, skip-no-ahoy, skip-nil-controller, skip-nil-tracker, coercion, filter-gate, synchronous-flag | PASS | All 7 tests present and named. test file at 7.4K. All pass under bundle exec rake test TEST=test/unit/subscribers/ahoy_test.rb. |
| 10 | MH-10 | Unit tests use stubbed tracker (Minitest::Mock or define_singleton_method) — no real Ahoy::Tracker instantiated | PASS | ahoy_test.rb:67-71 — build_controller_with_tracker uses Object.new + define_singleton_method(:ahoy). mock_tracker is Minitest::Mock throughout. No Ahoy::Tracker instantiation in file. |
| 11 | MH-11 | Integration tests cover (1) full pipeline + assert_no_enqueued_jobs; (2) job-context skip: no enqueue, no crash, warn logged | PASS | test/integration/ahoy_delivery_test.rb — 2 test cases present. Full pipeline: mock_tracker.verify + assert_no_enqueued_jobs. Job-context: assert_nothing_raised + assert_no_enqueued_jobs + assert_match warn. Both pass. |
| 12 | TEST-01 | bundle exec rake test TEST=test/unit/subscribers/ahoy_test.rb GREEN | PASS | 392 runs, 0 failures — confirmed by direct test run |
| 13 | TEST-02 | bundle exec rake test TEST=test/integration/ahoy_delivery_test.rb GREEN | PASS | 392 runs, 0 failures — confirmed by direct test run |
| 14 | TEST-03 | bundle exec rake (full suite) GREEN | PASS | 392 runs, 882 assertions, 0 failures, 0 errors, 0 skips — confirmed by direct run |
| 15 | TEST-04 | bundle exec appraisal rails_8_0 rake GREEN (direct run); SUMMARY evidence for rails_7_1 and rails_7_2 | PASS | rails_8_0: 392 runs, 882 assertions, 0 failures (direct run confirmed). SUMMARY evidence: rails_7_1 -> 392 runs 0 failures; rails_7_2 -> 392 runs 0 failures. |
| 16 | MH-12 | init() guard relaxed: if (!manifestUrl) only; error message no longer mentions measurementId | PASS | client/src/index.js:55 — if (!manifestUrl); error string at :57 mentions only manifestUrl. Confirmed by source read. |
| 17 | MH-13 | AhoyJs named export exists, frozen, name:AhoyJs, handle(eventName, params={}) — matches Ga4Gtag shape | PASS | client/src/index.js:164-189 — export const AhoyJs = Object.freeze({ name: 'AhoyJs', handle(eventName, params = {}) {...} }) |
| 18 | MH-14 | AhoyJs.handle validates against manifest, respects dev-throws/prod-warns, dispatches window.ahoy.track; guards on typeof window.ahoy?.track !== function with console.warn + drop | PASS | index.js:167-188 — validateParams via schema check, dev-throws on errors.length>0 + _env==='development', prod-warns and returns. Guard at :182: typeof window === 'undefined' &#124;&#124; typeof window.ahoy?.track !== 'function' -> console.warn + return. Dispatch at :187: window.ahoy.track(eventName, params). |
| 19 | MH-15 | client/src/index.d.ts declares measurementId?: string (optional) and exports AhoyJs with shape mirroring Ga4Gtag | PASS | index.d.ts:19 — measurementId?: string with updated JSDoc noting optional. :87-90 — export const AhoyJs: { readonly name: 'AhoyJs'; handle(eventName: string, params?: TrackParams): void; } |
| 20 | MH-16 | client/test/ahoy_js.test.js exists with all 6 test cases per plan must_haves | PASS | File exists at 3.2K. 6 tests under describe('AhoyJs named export — REQ-09 client-side half'): dispatch-no-measurementId, dev-throws-missing-required, prod-warns+drops-missing-required, untyped-passthrough, window.ahoy-undefined-guard, name===AhoyJs parity |
| 21 | MH-17 | client/test/index.test.js init() contract block updated per plan Task 1 table (6 tests rewritten for manifestUrl-only contract) | PASS | index.test.js:33-67 — describe block renamed to 'init() manifestUrl-required contract — 0.3.0 AhoyJs-only support'. Tests #1/#2/#4 tightened regex to /manifestUrl/ with .not.toThrow(/measurementId/); tests #3/#5/#6 inverted throw->resolve with mockFetchManifest(). |
| 22 | TEST-05 | cd client && npm test GREEN — 37 tests (was 31, +6 ahoy_js) | PASS | 4 test files, 37 passed (37): build_smoke 4, ga4_gtag 4, ahoy_js 6, index 23. Direct run confirmed. |
| 23 | TEST-06 | cd client && npm run build succeeds; dist/index.mjs and dist/index.cjs both contain AhoyJs and Ga4Gtag symbols | PASS | Build succeeded (4.47 KB ESM / 5.59 KB CJS). AhoyJs: 3 matches in index.mjs, 4 in index.cjs. Ga4Gtag: 3 matches in index.mjs, 4 in index.cjs. |
| 24 | MH-18 | lib/track_relay/version.rb = 0.3.0 and client/package.json version = 0.3.0 | PASS | lib/track_relay/version.rb:4 — VERSION = '0.3.0'; client/package.json:3 — version: 0.3.0 |
| 25 | MH-19 | CHANGELOG.md has [0.3.0] block with ### Added, ### Changed (BREAKING), ### Notes sub-sections | PASS | CHANGELOG.md:10-26 — ## [0.3.0] - 2026-05-06 with Added (server Subscribers::Ahoy, client AhoyJs, ahoy_matey), Changed (BREAKING: measurementId optional), Notes (visit.track deviation + cross-subscriber name parity). |
| 26 | MH-20 | CHANGELOG ### Changed (BREAKING) calls out measurementId-now-optional migration explicitly | PASS | CHANGELOG.md:18-21 — 'init({ manifestUrl }) no longer requires measurementId. Hosts using only AhoyJs can omit it... Hosts that relied on the missing-measurementId throw to detect misconfiguration must migrate.' |
| 27 | MH-21 | DEVIATION RECORDED (DEVN-01): tsc --allowImportingTsExtensions=false rejected (TS5025). Resolved by omitting flag. tsc --noEmit exits 0. Documented in SUMMARY. | FAIL | Declared deviation from Plan 03-02 task description. SUMMARY.md deviations[0] documents TS5025 error and resolution (flag omitted; absolute path used). Underlying acceptance criterion (tsc --noEmit exits 0) met per SUMMARY evidence. Per QA protocol, all declared deviations are FAIL checks in the contract record. |
| 28 | MH-22 | Release commit 52f9e32 touches exactly 4 files (CHANGELOG.md, Gemfile.lock, client/package.json, lib/track_relay/version.rb); no git push or npm publish | PASS | git show --stat 52f9e32: 4 files changed — CHANGELOG.md, Gemfile.lock, client/package.json, lib/track_relay/version.rb. No git remote configured. SUMMARY confirms no push/publish. scripts/bump-version.sh not invoked. |

## Anti-Pattern Scan

| # | ID | Pattern | Status | Evidence |
|---|-----|---------|--------|----------|
| 1 | NEG-01 | No Ahoy::Event.create!, Ahoy::Tracker.new, or require ahoy/require ahoy_matey in lib/track_relay/subscribers/ahoy.rb non-comment lines | PASS | grep -nE on non-comment lines returned exit 1 (zero matches). These patterns only appear in inline documentation comments as negative examples. |
| 2 | NEG-02 | No git push, gem push, npm publish, or scripts/bump-version.sh ran during phase | PASS | git remote -v returns empty (no remotes configured). Commit message documents 'Release publication is user's call per project CLAUDE.md'. SUMMARY ac_results confirms none of these were invoked. |

## Convention Compliance

| # | ID | Convention | File | Status | Detail |
|---|-----|------------|------|--------|--------|
| 1 | LINT-01 | bundle exec standardrb zero violations on new server-side files | lib/track_relay/subscribers/ahoy.rb, test/unit/subscribers/ahoy_test.rb, test/integration/ahoy_delivery_test.rb | PASS | bundle exec standardrb on new files returned no output (zero violations). Full bundle exec standardrb also clean. |

## Summary

**Tier:** standard
**Result:** FAIL
**Passed:** 28/31
**Failed:** MH-02, MH-06, MH-21
