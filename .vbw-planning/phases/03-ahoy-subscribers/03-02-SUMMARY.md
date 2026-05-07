---
phase: 3
plan: "02"
title: AhoyJs client subscriber + 0.3.0 release
status: complete
completed: 2026-05-06
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - 751495f9
  - e20a4dc2
  - 8f751afe
  - 52f9e328
deviations: []
resolved_by_amendment:
  - "DEVN-01 Minor — tsc verification flag syntax: Plan Task 4's prescribed `tsc` invocation included `--allowImportingTsExtensions=false`, which `tsc` rejects with `error TS5025: Unknown compiler option`. Plan 03-02 Task 4 was amended in QA Remediation Round 01 (commit `323e183`, MH-21 plan-amendment) to drop the malformed flag and use an absolute import path. R01-VERIFICATION confirms the amendment. The on-disk Plan 03-02 now matches the implemented `tsc` invocation; this is no longer a contract deviation."
mechanical_clarifications:
  - "Gemfile.lock as fourth release-bump file: Plan must_have wording said the version bump touches exactly 3 files. Bundler regenerates `Gemfile.lock` automatically when the gemspec version changes (the lockfile pins `track_relay (0.3.0)` at line 4 and 422), so the release commit includes 4 tracked files. MH-22 (release commit touches exactly 4 files: CHANGELOG.md, Gemfile.lock, client/package.json, lib/track_relay/version.rb) PASSED in 03-VERIFICATION.md — the 4-file count is the accepted reality. Phase 02 release commit `4dd8c4a` set the same precedent. Not a contract deviation; recorded here as a mechanical clarification."
pre_existing_issues: []
ac_results:
  - criterion: "`AhoyJs` named export exists in `client/src/index.js` as `Object.freeze({ name: \"AhoyJs\", handle(eventName, params = {}) { ... } })` — matches the existing `Ga4Gtag` shape for cross-subscriber parity"
    verdict: pass
    evidence: "client/src/index.js:158-184 (commit 8f751af); test `AhoyJs.name === 'AhoyJs'` passes"
  - criterion: "`AhoyJs.handle(eventName, params)` validates against `_manifest.events[eventName]` via `validateParams(...)` (same path as `track()` lines 79-89), respects `_env === \"development\"` throw vs production warn-and-drop, and dispatches via `window.ahoy.track(eventName, params)`. Untyped events (no manifest entry) pass through unchanged (REQ-06 client-side parity)."
    verdict: pass
    evidence: "client/src/index.js:160-180 (commit 8f751af); tests #1, #2, #3, #4 in client/test/ahoy_js.test.js cover dispatch happy-path, dev-throws-on-missing-required, prod-warns-and-drops, and untyped passthrough"
  - criterion: "`AhoyJs.handle` guards on `typeof window === \"undefined\" || typeof window.ahoy?.track !== \"function\"` and emits `console.warn` + drops the event when guard fails — does NOT throw, does NOT call `window.gtag`, does NOT crash"
    verdict: pass
    evidence: "client/src/index.js:175-178 (commit 8f751af); test #5 in client/test/ahoy_js.test.js — `delete window.ahoy` then `expect(...).not.toThrow()` and `expect(warnSpy).toHaveBeenCalledWith(...window.ahoy.track not found.../)` pass"
  - criterion: "`init({ measurementId, manifestUrl, env, onValidationError })` in `client/src/index.js` is amended so `measurementId` is OPTIONAL: the throw-guard at line 47 changes from `if (!measurementId || !manifestUrl)` to `if (!manifestUrl)`. The error message is updated to drop the measurementId mention. `_flushConfigOnce()` (lines 111-119) already short-circuits when `_measurementId` is null, so GA4-only behavior is preserved when `measurementId` IS supplied."
    verdict: pass
    evidence: "client/src/index.js:50-54 (commit e20a4dc) — guard relaxed to `if (!manifestUrl)`; error string mentions only `manifestUrl`. `_flushConfigOnce()` body untouched (still has `if (!_measurementId) return` guard at line 113)."
  - criterion: "BREAKING-CHANGE NOTE for 0.3.0: `init({ manifestUrl })` (no measurementId) now succeeds. Previously this threw. Hosts that relied on the throw to detect missing config must migrate. CHANGELOG must call this out under `### Changed` for 0.3.0."
    verdict: pass
    evidence: "CHANGELOG.md `## [0.3.0]` block, `### Changed (BREAKING)` sub-section (commit 52f9e32) — explicitly documents the migration trigger and recommends host-app-side measurementId asserts as the workaround"
  - criterion: "`client/src/index.d.ts` declares `measurementId?: string` (was required) and exports `AhoyJs` with the same shape as `Ga4Gtag`: `{ readonly name: \"AhoyJs\"; handle(eventName: string, params?: TrackParams): void; }`. The `InitOptions.measurementId` JSDoc is updated to note it is optional and only required when a GA4 subscriber is in use."
    verdict: pass
    evidence: "client/src/index.d.ts:11-19 (commit e20a4dc) — `measurementId?: string` with updated JSDoc; client/src/index.d.ts:78-89 (commit 8f751af) — `AhoyJs` declaration mirrors `Ga4Gtag`. Verified via `tsc --noEmit --strict` typecheck against a synthetic call-site (Task 4)."
  - criterion: "Existing test that pins the `init()` measurementId-required throw is updated or replaced. Specifically: search `client/test/` for any `expect(() => init({ manifestUrl: ... })).toThrow` or `init({ measurementId: ... })` test that asserts the old throw-on-missing-measurementId behavior. If found, update it to assert the new contract: `init({ manifestUrl: ... })` resolves successfully without measurementId; `init({ measurementId: '...' })` (no manifestUrl) still throws. If not found, no test changes — but document the search result in the task summary."
    verdict: pass
    evidence: "client/test/index.test.js:33-65 (commit 751495f) — the `describe(\"init() required-both contract — Fix 3\", ...)` block was renamed to `describe(\"init() manifestUrl-required contract — 0.3.0 AhoyJs-only support\", ...)`. All six tests rewritten per the Task 1 table: tests #3/#5/#6 invert from throw → resolve (using `mockFetchManifest()` + `await expect(...).resolves.toBeUndefined()`); tests #1/#2/#4 keep the throw but tighten regex from `/measurementId.*manifestUrl/` to `/manifestUrl/` and add a negative `not.toThrow(/measurementId/)` assertion."
  - criterion: "`client/test/ahoy_js.test.js` (new) covers six cases per research §Test plan: (1) `AhoyJs.handle` dispatches via `window.ahoy.track` after `init({ manifestUrl })` (no measurementId); (2) typed event with missing required param in `env: \"development\"` throws; (3) same in `env: \"production\"` calls `console.warn` and does NOT call `window.ahoy.track`; (4) untyped event (not in manifest) passes through to `window.ahoy.track`; (5) when `window.ahoy` is undefined, `console.warn` is called and no exception is raised; (6) `AhoyJs.name === \"AhoyJs\"` (parity with `Ga4Gtag.name === \"Ga4Gtag\"`)."
    verdict: pass
    evidence: "client/test/ahoy_js.test.js (commit 8f751af) — six tests under `describe(\"AhoyJs named export — REQ-09 client-side half\", ...)`. All six pass under `cd client && npm test`."
  - criterion: "All client tests pass: `cd client && npm test` is GREEN — both new `ahoy_js.test.js` cases AND the existing `ga4_gtag.test.js`, `init.test.js`, `track.test.js` etc. tests still pass."
    verdict: pass
    evidence: "Final post-bump run: 4 test files (build_smoke, ga4_gtag, ahoy_js, index) → 37 passed (37). 23 in index.test.js + 4 in ga4_gtag.test.js + 6 in ahoy_js.test.js + 4 in build_smoke.test.js."
  - criterion: "Build still produces both `dist/index.mjs` and `dist/index.cjs` after the change: `cd client && npm run build` succeeds and the output contains both `Ga4Gtag` and `AhoyJs` exports (verify via `grep -E 'AhoyJs|Ga4Gtag' client/dist/index.mjs`)"
    verdict: pass
    evidence: "`tsup` build success at 4.47 KB ESM / 5.59 KB CJS. `grep -c AhoyJs client/dist/index.mjs` → 3 matches (export declaration, var binding, named export); same for `client/dist/index.cjs` → 4 matches. Same for `Ga4Gtag` in both files."
  - criterion: "`lib/track_relay/version.rb` is bumped from `\"0.2.0\"` to `\"0.3.0\"` (do NOT use `scripts/bump-version.sh` — the project rule forbids running it without explicit user request; edit the file directly)"
    verdict: pass
    evidence: "lib/track_relay/version.rb:4 (commit 52f9e32) — direct edit, `scripts/bump-version.sh` was not invoked"
  - criterion: "`client/package.json` `\"version\"` is bumped from `\"0.2.0\"` to `\"0.3.0\"`"
    verdict: pass
    evidence: "client/package.json:3 (commit 52f9e32)"
  - criterion: "`CHANGELOG.md` has a new `## [0.3.0] - <ISO date>` section above the previous `## [0.2.0]` entry, with sub-sections `### Added` (server `Subscribers::Ahoy`, client `AhoyJs` named export, `ahoy_matey` dev dependency), `### Changed` (BREAKING: `init()` `measurementId` is now optional), and `### Notes` (deviation from REQ-09's `visit.track` language — Ahoy has no `Visit#track` public API; routing via `controller.ahoy.track` only)."
    verdict: pass
    evidence: "CHANGELOG.md:10-22 (commit 52f9e32) — `## [0.3.0] - 2026-05-06` block with all three sub-sections: Added (3 bullets), Changed (BREAKING) (2 bullets), Notes (2 bullets). Reference link added at file foot."
  - criterion: "After release commits land: `bundle exec rake` GREEN, `cd client && npm test` GREEN, `cd client && npm run build` succeeds, `git diff` shows version bump touches exactly 3 files (`lib/track_relay/version.rb`, `client/package.json`, `CHANGELOG.md`)."
    verdict: partial
    evidence: "All three rake/test/build sweeps GREEN: `bundle exec rake` → 392 runs, 0 failures; appraisals rails_7_1/7_2/8_0 → 392 runs each, 0 failures; `cd client && npm test` → 37/37; `cd client && npm run build` succeeds. Version bump diff covers 4 tracked files (`lib/track_relay/version.rb`, `client/package.json`, `CHANGELOG.md`, `Gemfile.lock`) — see DEVN-01 (`Gemfile.lock` is the bundler-mirror, present by construction; same precedent set by 0.2.0 release commit 4dd8c4a)."
  - criterion: "DO NOT run `git push` or `npm publish` in any task. The user controls publishing; per project CLAUDE.md, do not push or publish without explicit user request. Phase 03 ships when verification passes — release publication is a separate step the user initiates."
    verdict: pass
    evidence: "`git push`, `gem push`, `npm publish`, and `scripts/bump-version.sh` were NOT invoked. All commits remain local on `main`."
---

Phase 03 complete: client-side `AhoyJs` named export shipped, `init()` `measurementId` is now optional (BREAKING for 0.3.0), and the gem + npm package are bumped to 0.3.0 with a full CHANGELOG entry. All three Rails appraisals GREEN at 392 tests; client suite GREEN at 37/37 (was 31/31 — +6 new ahoy_js cases).

## What Was Built

- `AhoyJs` named export in `client/src/index.js` — `Object.freeze({ name: "AhoyJs", handle(eventName, params) })` mirroring `Ga4Gtag`'s shape. Validates against the manifest (typed events fire `_onValidationError`, then dev-throws / prod-warns-and-drops), guards on `typeof window.ahoy?.track === "function"`, and dispatches via `window.ahoy.track(eventName, params)`.
- `init({ manifestUrl })` no longer requires `measurementId` — guard relaxed from `if (!measurementId || !manifestUrl)` to `if (!manifestUrl)`; error message reworded. `_flushConfigOnce()` already short-circuited on missing `_measurementId` so the GA4 surface stays dormant in AhoyJs-only hosts.
- `client/src/index.d.ts` updated: `InitOptions.measurementId?: string` (was required), `AhoyJs` declaration added with the same shape as `Ga4Gtag`, JSDoc on both updated. Verified end-to-end with `tsc --noEmit --strict`.
- Six new Vitest cases (`client/test/ahoy_js.test.js`) covering dispatch happy-path, dev-throws on missing-required, prod-warns-and-drops on missing-required, untyped passthrough, absent-window.ahoy guard, and `name === "AhoyJs"` parity. Six existing init-contract tests in `client/test/index.test.js` rewritten to pin the new manifestUrl-only contract (3 invert from throw→resolve, 3 keep the throw with tightened regex).
- Release: `lib/track_relay/version.rb` and `client/package.json` bumped to 0.3.0; `CHANGELOG.md` gets a full `[0.3.0] - 2026-05-06` block with Added (server `Subscribers::Ahoy`, client `AhoyJs`, `ahoy_matey` dev-dep), Changed (BREAKING: `init()` `measurementId` optional), and Notes (REQ-09 deviation around the missing `Ahoy::Visit#track`, plus the cross-subscriber name parity caveat).

## Files Modified

- `client/test/index.test.js` -- modify: rewrite the six init-contract tests under `describe("init() manifestUrl-required contract — 0.3.0 AhoyJs-only support", ...)` (commit 751495f)
- `client/src/index.js` -- modify: relax `init()` guard to require manifestUrl only; add inline `AhoyJs` named export below `Ga4Gtag` (commits e20a4dc + 8f751af)
- `client/src/index.d.ts` -- modify: `InitOptions.measurementId` → optional, add `AhoyJs` declaration mirroring `Ga4Gtag` (commits e20a4dc + 8f751af)
- `client/test/ahoy_js.test.js` -- create: six Vitest cases mirroring the `client/test/ga4_gtag.test.js` template (commit 8f751af)
- `lib/track_relay/version.rb` -- modify: `"0.2.0"` → `"0.3.0"` (commit 52f9e32)
- `client/package.json` -- modify: `"version": "0.2.0"` → `"0.3.0"` (commit 52f9e32)
- `CHANGELOG.md` -- modify: insert `## [0.3.0] - 2026-05-06` block with Added/Changed/Notes; add `[0.3.0]` reference link at foot (commit 52f9e32)
- `Gemfile.lock` -- modify: bundler-regenerated to mirror `track_relay (0.3.0)` at lines 4 and 422 (commit 52f9e32; mechanical mirror, see DEVN-01)
