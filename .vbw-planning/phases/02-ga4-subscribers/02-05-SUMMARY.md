---
phase: 2
plan: "05"
title: "@track_relay/client npm package + Ga4Gtag subscriber + 0.2.0 release"
status: complete
completed: 2026-05-06
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - a11bb8b
  - 37c0a84
  - b0c8963
  - 5c3257f
  - 4dd8c4a
deviations: []
pre_existing_issues:
  - '{"test": "manual GA4 Realtime browser smoke", "file": "client/test/index.test.js", "error": "Requires real measurement_id + browser session — deferred to UAT; happy-dom + vitest cover the contract"}'
ac_results:
  - criterion: "client/package.json with name @track_relay/client, version 0.2.0, type module, dual ESM+CJS exports map pointing at real built artifacts (./dist/index.mjs, ./dist/index.cjs); files: [dist, src/index.d.ts]"
    verdict: pass
    evidence: "client/package.json + ls client/dist/index.{mjs,cjs} (both non-empty post-build)"
  - criterion: "tsup is the dev dep producing both dist/index.mjs AND dist/index.cjs from src/index.js; build_smoke.test.js asserts both exist + non-empty + correct module markers"
    verdict: pass
    evidence: "client/tsup.config.js + client/test/build_smoke.test.js (4 tests: exists/non-empty/ESM marker/CJS marker)"
  - criterion: "client/src/index.js exports init/track/setClientId/Ga4Gtag; init() throws synchronously (not via rejected promise) when measurementId or manifestUrl is nullish/empty-string, BEFORE any fetch"
    verdict: pass
    evidence: "client/src/index.js:46-54 (sync throw, async delegate to _initAsync) + client/test/index.test.js:33-65 (6 required-both contract tests, including fetch-not-called assertion)"
  - criterion: "client/src/index.d.ts hand-written with full public type signatures matching the Phase-02 surface"
    verdict: pass
    evidence: "client/src/index.d.ts (InitOptions, TrackParams, init, track, setClientId, Ga4Gtag — 70 lines)"
  - criterion: "init() fetches manifest URL, parses JSON, stores it AND measurementId in module-private state; subsequent track() validates and dispatches via window.gtag('event', ...); first track() emits gtag('config', measurementId, {client_id}) once per page lifecycle"
    verdict: pass
    evidence: "client/src/index.js:75-119 + tests 'gtag(config,...) fires once per page lifecycle' and 'setClientId AFTER init causes the next track() to re-emit gtag(config)'"
  - criterion: "Validation mirrors REQ-05: env=development throws Error on validation failure; env=production console.warns and drops"
    verdict: pass
    evidence: "client/src/validator.js + client/src/index.js:75-89 + 8 validation tests in client/test/index.test.js (dev-throw / prod-warn for missing required + wrong type)"
  - criterion: "track() calls window.gtag('event', name, params) after validation passes; missing window.gtag warns and drops"
    verdict: pass
    evidence: "client/src/index.js:91-94 + test 'missing window.gtag — warn + drop, never throw'"
  - criterion: "Ga4Gtag named export with handle(name, params) — covers REQ-08 client-side half; reads same module-private state as init"
    verdict: pass
    evidence: "client/src/index.js:121-137 + client/test/ga4_gtag.test.js (4 tests covering dispatch/validation/untyped pass-through/name field)"
  - criterion: "Vitest suite covers init fetches manifest, init throws on missing fields, track validates, dev throws / prod warns, unknown event passes through, missing gtag warns+drops, gtag(config,...) called once with resolved client_id"
    verdict: pass
    evidence: "31 tests across 3 files (build_smoke 4, index 23, ga4_gtag 4) all pass"
  - criterion: ".github/workflows/ci.yml adds js-test job running cd client && npm ci && npm run build && npm test on Node 22 (build BEFORE test)"
    verdict: pass
    evidence: ".github/workflows/ci.yml:36-53 (defaults working-directory: client; npm ci → npm run build → npm test in that order; cache npm with cache-dependency-path: client/package-lock.json)"
  - criterion: "lib/track_relay/version.rb bumped to 0.2.0"
    verdict: pass
    evidence: "lib/track_relay/version.rb:4 + Gemfile.lock track_relay (0.2.0)"
  - criterion: "CHANGELOG.md has [0.2.0] - <date> heading collecting all [Unreleased] bullets from plans 02-01 through 02-05"
    verdict: pass
    evidence: "CHANGELOG.md:10 ## [0.2.0] - 2026-05-06 with 6 new client-package bullets prepended above the existing 02-01 through 02-04 entries; [0.2.0] link footer added"
  - criterion: "README.md has new section documenting GA4 subscriber, client_id_resolvers, manifest, and @track_relay/client install + init with the ERB snippet wiring measurementId AND manifestUrl"
    verdict: pass
    evidence: "README.md 'GA4 + client-side tracking' section covers server subscriber config, client_id chain, manifest shape, JS package install + ERB snippet (canonical inline-module form per Task 4 contract)"
---

Ships the client-side half of REQ-08 — `@track_relay/client` npm package living at `client/` with real dual ESM+CJS builds via `tsup`, a required-both `init({measurementId, manifestUrl})` contract that throws synchronously on misconfiguration, manifest-driven validation mirroring the server-side REQ-05 dev-throw / prod-warn semantics, and the `Ga4Gtag` named export shaped like the server subscriber. Cuts the v0.2.0 release: version bump, Gemfile.lock follow, CHANGELOG converted from `[Unreleased]` to `[0.2.0] - 2026-05-06` aggregating all Phase 02 deliverables, README adds a new GA4 + client-side tracking section, CI adds a `js-test` job on Node 22 (build before test). Phase 02 closes out at 383 Ruby tests + 31 JS tests, all green.

## What Was Built

- `client/` npm package — flat directory at repo root, `name: "@track_relay/client"`, `version: "0.2.0"`. `tsup` produces real dual ESM (`dist/index.mjs`) + real CommonJS (`dist/index.cjs`) artifacts so both `import` and `require` work; the `package.json` `exports` map points at the built files, not the unbuilt source. `files: ["dist", "src/index.d.ts", "README.md"]` ships the artifacts plus types.
- `init({measurementId, manifestUrl, env, onValidationError})` — REQUIRED-BOTH contract. Throws synchronously (NOT via rejected promise) on nullish OR empty-string for either field, BEFORE any `fetch` call. The function is intentionally not declared `async`; it does sync validation then delegates to a private `_initAsync` for the manifest fetch — an `async` wrapper would have converted the sync throw into a rejected promise, defeating misconfiguration loudness.
- `track(eventName, params)` — looks up the manifest entry, runs `validateParams()` from the new `client/src/validator.js`, branches on env: dev throws, prod calls `console.warn` and drops. Untyped events (not in the manifest) pass through unchanged per REQ-06. Missing `window.gtag` warns and drops the event without throwing.
- `setClientId(id)` — updates the resolved `client_id` and unsets the `_configFlushed` latch. The next `track()` re-emits `gtag("config", measurementId, {client_id})`. Per-page lifecycle the config call fires exactly once unless the client_id changes.
- `Ga4Gtag` named export — frozen `{name: "Ga4Gtag", handle(name, params)}` object that wraps `track()`. Mirrors the server-side `Subscribers::Ga4MeasurementProtocol` shape so hosts who prefer object dispatch get the same surface; reads the same module-private state `init` populates.
- Hand-written `client/src/index.d.ts` documents the full public type surface (no TypeScript build step; generated types from the manifest stay deferred to Phase 4 per REQ-15).
- `client/src/validator.js` — manifest schema validator. Five JS type checks mirror the Ruby ParamSchema types (integer / float / string / boolean / datetime). Required-param check fires when value is nullish; extra params not in the schema are allowed silently (the catalog stays opt-in for typing).
- `client/test/build_smoke.test.js` — single guard against accidentally shipping an ESM file under a `.cjs` extension. Asserts both `dist/` files exist, are non-empty, and carry the correct `export` / `module.exports` markers. Verified locally: `node -e "const m = require('./dist/index.cjs'); console.log(typeof m.init)"` prints `function`.
- 31 vitest tests across 3 files (build_smoke 4, index 23, ga4_gtag 4) — covering the required-both contract, happy-path dispatch, validation REQ-05 mirror, gtag config lifecycle, setClientId reflush, untyped pass-through, missing-gtag fallback, and the `Ga4Gtag` shape parity with the server subscriber.
- CI: `.github/workflows/ci.yml` adds a `js-test` job on Node 22 that runs `npm ci → npm run build → npm test` with `cache: npm` and `cache-dependency-path: client/package-lock.json`. Build before test is non-negotiable so `build_smoke.test.js` sees a populated `dist/`.
- v0.2.0 release: `lib/track_relay/version.rb` bumped, Gemfile.lock follows, CHANGELOG `[Unreleased]` rolled to `## [0.2.0] - 2026-05-06` with 6 new `@track_relay/client` bullets prepended above the 02-01 through 02-04 server-side entries, README Status updated, install snippet adds `npm install @track_relay/client`, new "GA4 + client-side tracking" section documents the server subscriber, `client_id_resolvers` chain, manifest shape, and the canonical inline-ERB snippet wiring both `measurementId` AND `manifestUrl`. New `client/README.md` (full API docs for the npm package).

## Files Modified

- `client/package.json` -- create: package metadata, dual ESM+CJS exports, files manifest, devDeps (tsup, vitest, happy-dom, typescript)
- `client/package-lock.json` -- create: pinned dep tree (npm install output)
- `client/tsup.config.js` -- create: dual-format build config (esm + cjs, es2020, clean, .mjs/.cjs extensions)
- `client/vitest.config.js` -- create: happy-dom environment, test/**/*.test.js include
- `client/.gitignore` -- create: node_modules/ and dist/
- `client/src/index.js` -- create: init/track/setClientId/Ga4Gtag public API + module-private state + lazy gtag('config',...) flush
- `client/src/index.d.ts` -- create: hand-written TypeScript types for the public surface
- `client/src/validator.js` -- create: manifest schema validator covering five ParamSchema types
- `client/test/build_smoke.test.js` -- create: 4 tests guarding the dual-build artifacts
- `client/test/index.test.js` -- create: 23 tests covering init/track/validation/setClientId/gtag config lifecycle
- `client/test/ga4_gtag.test.js` -- create: 4 tests covering the Ga4Gtag named export
- `client/README.md` -- create: full API documentation for npm consumers
- `.github/workflows/ci.yml` -- modify: add js-test job (Node 22, build before test, cached npm)
- `lib/track_relay/version.rb` -- modify: bump VERSION 0.1.0 → 0.2.0
- `Gemfile.lock` -- modify: track_relay (0.2.0) follow
- `CHANGELOG.md` -- modify: convert [Unreleased] to [0.2.0] - 2026-05-06; prepend 6 new @track_relay/client bullets; add [0.2.0] link footer
- `README.md` -- modify: Status line, install snippet, new GA4 + client-side tracking section, Roadmap (0.2.0 marked shipped)

## Deviations

None. Every must_have shipped as planned. The 02-CONTEXT line 52 commitment to real dual ESM+CJS is honored — `tsup` produces actual CommonJS (verified with `node -e "require('./dist/index.cjs')"`), not an ESM file with a misleading extension. The plan's manual GA4 Realtime browser smoke is recorded in `pre_existing_issues` and deferred to UAT — vitest + happy-dom coverage of the contract is sufficient to gate the QA review for 0.2.0.
