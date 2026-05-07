---
phase: 03
title: Ahoy Subscribers — UAT
status: complete
started: 2026-05-07
completed: 2026-05-07
total_tests: 3
passed: 3
failed: 0
skipped: 0
issues_count: 0
---

# Phase 03 UAT: Ahoy Subscribers + 0.3.0 Release

This phase ships server-side `TrackRelay::Subscribers::Ahoy` and client-side `AhoyJs` exports plus the 0.3.0 release (gem + npm package + CHANGELOG). Work is library-internal — no app/UI to interact with — so UAT focuses on confirming the release contents and shipped surface match your expectations.

## Tests

### P1-T1 — Confirm CHANGELOG 0.3.0 entry reads correctly

Open `CHANGELOG.md` and scan the new `## [0.3.0] - 2026-05-06` block. Confirm the wording, structure, and BREAKING-CHANGE callout match what you want shipped to consumers reading the release notes.

**Expected:** A clear `[0.3.0]` section above `[0.2.0]` with `### Added`, `### Changed (BREAKING)`, and `### Notes` sub-sections. The BREAKING note explains the `init({ manifestUrl })` migration. The Notes section documents the `visit.track` REQ-09 deviation rationale.

Result: pass

### P2-T1 — Confirm AhoyJs export shape feels consistent with Ga4Gtag

Open `client/src/index.js` and look at the new `AhoyJs` named export (added below `Ga4Gtag`). Confirm the shape, naming, and behavior parity with `Ga4Gtag` matches your design intent for cross-subscriber use.

**Expected:** `AhoyJs` is `Object.freeze({ name: "AhoyJs", handle(eventName, params) { ... } })`, mirrors `Ga4Gtag` styling, dispatches via `window.ahoy.track`, validates manifest events the same way `track()` does, guards on missing `window.ahoy` with `console.warn` + drop.

Result: pass

### P3-T1 — Confirm 0.3.0 BREAKING change is acceptable to ship

The `init()` API now allows `init({ manifestUrl })` without `measurementId`. Hosts that previously relied on the missing-measurementId throw to detect misconfiguration must migrate. Confirm this BREAKING change at the 0.3.0 boundary is what you intend (i.e., hosts using only AhoyJs can now omit measurementId; the migration friction for GA4-only hosts is acceptable).

**Expected:** You're comfortable shipping the BREAKING change at 0.3.0 (pre-1.0, SemVer-0.x conventions allow breaking minors), and the migration story documented in CHANGELOG `### Changed (BREAKING)` is sufficient.

Result: pass
