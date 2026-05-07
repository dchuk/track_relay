---
phase: 02
title: GA4 Subscribers — User Acceptance Tests
status: complete
total: 5
passed: 3
failed: 0
skipped: 2
created: 2026-05-06
completed: 2026-05-06
---

# Phase 02 UAT — GA4 Subscribers

5 checkpoints requiring human judgment. The full automated suite (383 Ruby + 31 JS = 414 tests) already passed; these scenarios verify the things QA can't: documentation quality, API surface readability, and live GA4 round-trip verification (when you have credentials).

## Tests

### P01-T01: Phase 02 release scope review ✓ PASS

**Plan:** 02-01 through 02-05 (overall release)

**Scenario:** Open `CHANGELOG.md` and read the `## [0.2.0] - 2026-05-06` section. Then read the new `## GA4 + client-side tracking` section in `README.md`.

**Expected:** The CHANGELOG and README accurately reflect what was built — subscriber filter DSL, client_id resolver chain, JSON manifest, GA4 MP server subscriber with retry/discard, npm client package — and a Rails developer arriving fresh could understand and use the new features.

**Result:** PASS

---

### P02-T01: Client-side npm package surface review ✓ PASS

**Plan:** 02-05

**Scenario:** Open `client/README.md` and `client/src/index.d.ts`. Trace the `init({measurementId, manifestUrl, env, onValidationError})` → `track(eventName, params)` flow. Look at the recommended ERB snippet wiring `measurementId` and `manifestUrl` from the Rails layer.

**Expected:** The public API is readable, the dev-throw / prod-warn validation behavior is clearly documented, and the Rails-side wiring snippet is one you'd be comfortable copying into a real `app/views/layouts/application.html.erb`.

**Result:** PASS

---

### P03-T01: Generated manifest output shape ✓ PASS

**Plan:** 02-03

**Scenario:** Run `bundle exec rake track_relay:manifest` against the dummy app inside `test/internal/`. Inspect the generated `test/internal/public/track_relay_catalog.json` (or wherever it lands). 

**Expected:** The JSON has top-level `version: "0.2.0"`, `generated_at`, and `events: {...}` keys; each event has `params: {name => type_string}` and `required: [...]`; the file is pretty-printed and parseable. If you don't want to run the rake task right now, you can also inspect a sample by reading `test/integration/manifest_rake_test.rb` to see what shape is asserted.

**Result:** PASS

---

### P04-T01: GA4 Measurement Protocol live round-trip *(deferred — needs real credentials)* ○ SKIP

**Plan:** 02-04

**Scenario:** With a real GA4 property's `G-XXX` measurement_id and an api_secret, configure `TrackRelay.config.ga4_measurement_id` + `ga4_api_secret`, register `Subscribers::Ga4MeasurementProtocol`, hit a controller action that calls `TrackRelay.track(:purchase, ...)`, and watch GA4 DebugView. This is the deferred validation captured in the phase known-issues registry.

**Expected:** The event appears in GA4 DebugView within ~60 seconds. Skip this checkpoint if you don't want to set up real credentials right now — the webmock-stubbed unit + integration tests cover the wire contract, and this can be verified once credentials are available.

**Result:** SKIP (deferred — needs real GA4 credentials; tracked as known issue)

---

### P05-T01: JS client browser smoke *(deferred — needs real credentials + browser)* ○ SKIP

**Plan:** 02-05

**Scenario:** In a Rails dummy app with `track_relay_catalog.json` served at a known path AND `TrackRelay.config.ga4_measurement_id` set to a real `G-XXX`, load the recommended ERB snippet in a layout and call `track("purchase", {value: 9.99, currency: "USD"})` from the browser console. Watch GA4 Realtime view.

**Expected:** The `track()` call dispatches via `window.gtag("event", "purchase", {...})` and the event shows up in GA4 Realtime within seconds. Skip this checkpoint if you don't want to set up real credentials right now — the headless happy-dom + vitest suite covers the contract.

**Result:** SKIP (deferred — needs real GA4 credentials + browser session; tracked as known issue)
