---
phase: "03"
title: "Ahoy Subscribers"
type: research
confidence: high
date: 2026-05-06
---

# Phase 03 Research: Ahoy Subscribers

## Existing patterns to mirror

### Entry point: `lib/track_relay.rb`

The file is the canonical require manifest. Every new subscriber gets two lines added here — a `require` for the file itself, and it flows into `Configuration#reset!` as a known subscriber class. GA4 is the pattern:

```ruby
require "track_relay/subscribers/ga4_measurement_protocol"
```

The Ahoy server subscriber will be:
```ruby
require "track_relay/subscribers/ahoy"
```

It should be conditionally required only if Ahoy is defined, OR the file itself should duck-type around Ahoy's absence (the codebase already uses duck-typing for `ClientId::AhoyVisitor` — see below). The latter is strongly preferred so the gem loads cleanly in non-Ahoy apps.

### `lib/track_relay/configuration.rb`

Subscribers are registered via:
```ruby
TrackRelay.configure do |c|
  c.subscribe(TrackRelay::Subscribers::Ahoy.new)
end
```

`config.subscribe(subscriber)` appends to `@subscribers`. No symbolic/keyword registration exists — the host app always instantiates the subscriber class explicitly. There is no auto-subscription via Railtie at Phase 02 level; the host app's initializer is the registration surface.

No new `Configuration` attributes are needed for the Ahoy subscriber — unlike GA4 which needs `ga4_measurement_id` / `ga4_api_secret`, Ahoy reads from `Current.controller.ahoy` (runtime context), not static config.

### `lib/track_relay/subscribers/base.rb`

Full contract for any new subscriber:

- Inherit from `TrackRelay::Subscribers::Base`
- Implement `#deliver(payload)` — the only required override
- `Base#handle(payload)` routes to sync or async path automatically
- `Base.synchronous!` opts the class into inline delivery
- `Base#safe_deliver` wraps deliver with the REQ-23 rescue contract
- `DeliveryRetriableError` and `DeliveryDiscardableError` are re-raised (carve-out) so `DeliveryJob`'s retry/discard macros fire
- `Base.filter(only:, except:)` class DSL for event-name filtering

The Ahoy subscriber MUST follow this contract exactly. No new base behavior is needed.

### `lib/track_relay/subscribers/ga4_measurement_protocol.rb` — closest analog

The GA4 subscriber is the canonical async server-side subscriber. Key structural points:

**Constructor:** No custom `initialize`. Stateless. GA4 reads credentials from `TrackRelay.config` at delivery time (not load time) to support late-bound / lambda configs.

**Async by default:** Does not call `.synchronous!`. `#handle` therefore enqueues `DeliveryJob.perform_later(self.class.name, payload.to_h)`. The job reconstructs a fresh subscriber instance and calls `safe_deliver(payload)`.

**Skip-not-raise pattern for missing config:**
```ruby
def deliver(payload)
  if measurement_id.nil? || api_secret.nil?
    warn_missing_credentials(measurement_id, api_secret)
    return   # <-- log and skip, do NOT raise
  end
  # ... actual delivery
end
```
The Ahoy subscriber mirrors this exact pattern for the no-controller / no-visit case.

**`Rails.logger.warn` for skip conditions:**
```ruby
def warn_missing_credentials(measurement_id, api_secret)
  return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
  Rails.logger.warn("[track_relay] Ga4MeasurementProtocol skipping delivery — ...")
end
```
The Ahoy subscriber will use `[track_relay] Ahoy skipping delivery — no controller or visit in context` as its warning.

**Reads `payload.context`, not `TrackRelay::Current`:** Because `DeliveryJob` runs after the Rails Executor clears `CurrentAttributes`, the async subscriber MUST read from `payload.context` (snapshotted at track time). GA4 reads `payload.context[:client_id]`. The Ahoy subscriber will read `payload.context[:controller_instance]` — see critical note below.

### `lib/track_relay/current.rb`

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :request, :visit, :controller, :client_id
end
```

- `Current.controller` — the live controller instance (present during request, nil in jobs)
- `Current.visit` — an Ahoy-style visit record (nil unless host app explicitly sets it)

### `lib/track_relay/instrumenter.rb` — context snapshot

The `current_context` method snapshots `Current` at track time:

```ruby
def current_context
  controller = Current.controller
  action = controller.respond_to?(:action_name) ? controller.action_name : nil
  {
    user: Current.user,
    controller: controller&.class&.name,   # String, e.g. "ArticlesController"
    action: action,
    client_id: Current.client_id,
    visit: Current.visit,                  # Ahoy::Visit record or nil
    request_id: Current.request&.request_id
  }
end
```

**Critical design implication:** `payload.context[:controller]` is a **String** (the controller class name), NOT the live controller instance. The live controller instance is gone by the time a DeliveryJob runs.

This means the Ahoy subscriber CANNOT use `payload.context[:controller]` to call `controller.ahoy.track(...)` in the async path. The tracker must be called synchronously — `#deliver` must execute on the request thread while `Current.controller` is still live, OR the subscriber must run synchronously.

Two viable designs:

1. **Force synchronous:** Call `Subscribers::Ahoy.synchronous!` so `deliver` always runs inline on the calling thread, where `Current.controller` is available.
2. **Snapshot the visit record:** The `payload.context[:visit]` IS the `Ahoy::Visit` record (or nil). If we can call `visit.track(name, properties)` we avoid needing the controller. However — see Section 2 below — `visit.track` does NOT exist on `Ahoy::Visit`. The `Ahoy::Tracker` is the only public tracking surface.

**Recommended approach: synchronous!** The Ahoy subscriber calls `.synchronous!` because `Ahoy::Tracker` is bound to the request lifecycle. The subscriber reads `Current.controller` directly in `deliver` (not from `payload.context`), which is safe on the synchronous path.

This is distinct from GA4 which is async because it makes an external HTTP call. Ahoy's `tracker.track` is an in-process write to the host app's database — synchronous is idiomatic, matches how Ahoy itself works (it IS a before-action / inline write), and avoids the serialization problem entirely.

### `lib/track_relay/controller_tracking.rb`

Populates `Current.controller`, `Current.request`, `Current.client_id` via `before_action :_track_relay_set_current`. Does NOT set `Current.visit` — that is the host app's responsibility (or the Ahoy subscriber can derive it from `controller.ahoy.current_visit` at deliver time).

### `lib/track_relay/job_tracking.rb`

Intentionally minimal — `JobTracking` does NOT auto-populate `Current`. The comment is explicit: "the Rails Executor calls `CurrentAttributes.clear_all` BEFORE the job runs." So `Current.controller` and `Current.visit` are nil in job context by design.

### `lib/track_relay/client_id/ahoy_visitor.rb` — duck-typing precedent

This file is the critical precedent for how to integrate with Ahoy without requiring it:

```ruby
def call(controller:, **)
  return nil unless controller&.respond_to?(:ahoy, true)
  controller.ahoy&.current_visit&.visitor_token
end
```

The Ahoy subscriber MUST follow the exact same duck-typing pattern:
- Do NOT `require "ahoy"` at the top of the file
- Check `controller.respond_to?(:ahoy, true)` before calling `controller.ahoy`
- Use `&.` safe navigation throughout

### `lib/track_relay/delivery_job.rb`

Since the Ahoy subscriber will be **synchronous**, it will never enqueue a `DeliveryJob`. The job infrastructure is still present (it's on the base class) but the synchronous path bypasses it. No new retry/discard macros are needed.

### Client files

**`client/src/index.js`** — module structure for the AhoyJs subscriber:

```javascript
// Module-private state
let _manifest = null;
let _env = "production";

// Named export — mirroring Ga4Gtag
export const AhoyJs = Object.freeze({
  name: "AhoyJs",
  handle(eventName, params = {}) { ... }
});

// Test reset helper (not in public API / index.d.ts)
export function _resetForTests() { ... }
```

The `Ga4Gtag` named export shape is the template:
```javascript
export const Ga4Gtag = Object.freeze({
  name: "Ga4Gtag",
  handle(eventName, params = {}) {
    track(eventName, params);
  }
});
```

`AhoyJs` will have the same `{ name, handle }` shape.

**`client/src/validator.js`** — reuse as-is. The `validateParams(eventName, schema, params)` function is generic. AhoyJs will call it the same way `track()` in index.js does.

**`client/package.json`** — `"version": "0.2.0"`. Will bump to `"0.3.0"` for this release. The `exports` map and `files` array need no structural changes; `AhoyJs` is a named export from the same entry point (`./dist/index.mjs` / `./dist/index.cjs`).

### `client/test/ga4_gtag.test.js` — test pattern

The pattern to mirror exactly:
```javascript
import { init, Ga4Gtag, _resetForTests } from "../src/index.js";

beforeEach(() => {
  _resetForTests();
  window.gtag = vi.fn();
});

describe("Ga4Gtag named export", () => {
  test("handle dispatches via gtag", async () => {
    mockFetchManifest();
    await init({ measurementId: "G-GA4", manifestUrl: "/m.json" });
    Ga4Gtag.handle("purchase", { value: 19.99, currency: "EUR" });
    // assert window.gtag called
  });
});
```

For AhoyJs the equivalent is:
```javascript
import { init, AhoyJs, _resetForTests } from "../src/index.js";

beforeEach(() => {
  _resetForTests();
  window.ahoy = { track: vi.fn() };
});

describe("AhoyJs named export", () => {
  test("handle dispatches via window.ahoy.track", async () => {
    mockFetchManifest();
    await init({ manifestUrl: "/m.json" });   // no measurementId needed
    AhoyJs.handle("purchase", { value: 19.99, currency: "EUR" });
    expect(window.ahoy.track).toHaveBeenCalledWith("purchase", { ... });
  });
});
```

---

## Server-side Ahoy subscriber design

### File location

`lib/track_relay/subscribers/ahoy.rb`

### Constructor

No custom `initialize`. Inherits from `Base`. Stateless, all runtime data read from `Current` at deliver time.

### Synchronous

```ruby
class TrackRelay::Subscribers::Ahoy < TrackRelay::Subscribers::Base
  synchronous!
  ...
end
```

Because `Ahoy::Tracker` is bound to the request (it wraps the controller's cookie jar and visit lifecycle), calling it must happen on the request thread. `synchronous!` ensures `deliver` runs inline from `Instrumenter#track` rather than being serialized into a `DeliveryJob`.

### The `#deliver` method

```ruby
def deliver(payload)
  controller = TrackRelay::Current.controller

  unless controller&.respond_to?(:ahoy, true)
    log_skip("no controller or ahoy tracker in context")
    return
  end

  tracker = controller.ahoy

  unless tracker
    log_skip("controller.ahoy returned nil")
    return
  end

  tracker.track(payload.name.to_s, payload.params)
end
```

Key decisions:

1. **Read `Current.controller` directly** (not `payload.context[:controller]`) because `current_context` only snapshots the controller class name as a String, not the live instance. On the synchronous path `Current.controller` is still set when `deliver` runs.

2. **Duck-type `respond_to?(:ahoy, true)`** — same pattern as `ClientId::AhoyVisitor`. The `true` argument includes private methods, matching the precedent.

3. **Event name as String:** `payload.name.to_s` — Ahoy stores event names as strings in the database; the tracker's `track` method accepts a String. The catalog uses Symbols; coerce at the boundary.

4. **Properties:** `payload.params` — the already-validated, coerced Hash from `EventPayload`. Ahoy stores arbitrary JSON properties, so no transformation is needed.

5. **No `user_id` injection:** Ahoy's tracker auto-attaches `current_user` via `Ahoy.user_method`. We do not pass `user:` because that would bypass the host app's Ahoy user-method configuration. If the host app has `Ahoy.user_method = :current_user` set, `tracker.track` picks it up automatically.

### The `visit.track` question

There is NO `track` method on `Ahoy::Visit` (the ActiveRecord model). The `Ahoy::Tracker` is the sole public tracking surface. The `visit` method on `Ahoy::Tracker` returns the `@visit` ActiveRecord record; `visit_or_create` also just returns a visit record. Neither the visit model nor the store exposes a `track(name, props)` method at the instance level.

The success criteria says "routes via `TrackRelay::Current.controller.ahoy.track` or `visit.track` only." The `visit.track` language appears to have been written anticipating that Ahoy might expose that method. It does not. The implementation should use only `controller.ahoy.track` and should log-and-skip when no controller is present (the job-context case).

### Job-context behavior (the skip path)

When `Current.controller` is nil (background job, rake task, console):

```ruby
unless controller&.respond_to?(:ahoy, true)
  log_skip("no controller or ahoy tracker in context")
  return
end
```

`log_skip` logs at `Rails.logger.warn` level (matching `warn_missing_credentials` in GA4):

```ruby
def log_skip(reason)
  return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
  Rails.logger.warn("[track_relay] Ahoy subscriber skipping delivery — #{reason}")
end
```

This matches the success criterion: "Job-context calls without a controller or visit log and skip rather than fabricate a write."

The test for this path creates a payload and calls `subscriber.safe_deliver(payload)` WITHOUT setting `Current.controller`, then asserts `safe_deliver` returns `nil` (no error) and no Ahoy event was written.

### Async vs sync tradeoff note

Ahoy `tracker.track` writes to the database synchronously (it calls `@store.track_event(data)` which does `event_model.create!` or equivalent). This is an in-process DB write, not a network call. Synchronous delivery is idiomatic for Ahoy and adds negligible overhead to the request. The GA4 async path exists specifically because of the external HTTP call; that concern does not apply here.

### Graceful Ahoy gem absence

If the host app does not have Ahoy installed, `controller.respond_to?(:ahoy, true)` returns `false` (the `Ahoy::Controller` module was never included in `ApplicationController`). The subscriber logs and skips. It does NOT raise. The gem loads cleanly because the subscriber file does NOT `require "ahoy"`.

---

## Client-side AhoyJs subscriber design

### File location

`client/src/ahoy_js.js` — a new file, mirroring the single-responsibility of `validator.js`. The `AhoyJs` named export is then re-exported from `client/src/index.js`.

Alternatively (and simpler), `AhoyJs` can be defined inline in `client/src/index.js` alongside `Ga4Gtag`, since index.js is already the module entry point and all Ga4Gtag state (manifest, env) is module-private there. The inline approach avoids a separate file and is what Ga4Gtag does. **Recommend inline in index.js.**

### Export shape

```javascript
export const AhoyJs = Object.freeze({
  name: "AhoyJs",
  handle(eventName, params = {}) {
    // 1. Validate against manifest (same path as track())
    const schema = _manifest?.events?.[eventName];
    if (schema) {
      const errors = validateParams(eventName, schema, params);
      if (errors.length > 0) {
        _onValidationError?.(errors);
        if (_env === "development") {
          throw new Error(`${PREFIX}: ${errors.join("; ")}`);
        }
        console.warn(`${PREFIX}:`, ...errors);
        return;
      }
    }

    // 2. Guard: window.ahoy must be present
    if (typeof window === "undefined" || typeof window.ahoy?.track !== "function") {
      console.warn(`${PREFIX}: window.ahoy.track not found — event dropped: ${eventName}`);
      return;
    }

    // 3. Dispatch
    window.ahoy.track(eventName, params);
  }
});
```

### Integration with `init()`

`init({ manifestUrl })` is the initialization gate for AhoyJs just as it is for Ga4Gtag. However, AhoyJs does NOT need a `measurementId`. Two options:

**Option A:** Make `measurementId` optional in `init()` (only required when a Ga4 subscriber is also in use). Change the guard from:
```javascript
if (!measurementId || !manifestUrl) { throw ... }
```
to:
```javascript
if (!manifestUrl) { throw ... }
```
And only call `_flushConfigOnce()` / `window.gtag('config', ...)` when `_measurementId` is non-null.

**Option B:** Introduce a separate `initAhoy({ manifestUrl })` function that only loads the manifest without the GA4 measurement ID requirement.

**Recommendation: Option A.** It is simpler, avoids a second init surface, and the manifest fetch is shared across all subscribers. The `_flushConfigOnce` guard already checks `if (!_measurementId) return` so GA4 config only flushes when a measurement ID is set. This is the minimal change.

### Event name alignment

`window.ahoy.track(eventName, params)` — Ahoy.js posts the event name as-is to `/ahoy/events`. The server-side `Ahoy` subscriber also passes `payload.name.to_s` directly to `tracker.track`. Event names are identical on both sides, which satisfies the success criterion "using the same event names as the server."

### `window.ahoy` availability

Ahoy.js auto-initializes on page load when loaded via `<script src="ahoy.js">` or the Rails asset pipeline. When loaded as an ES module import (`import ahoy from 'ahoy.js'`), the host app must call `ahoy.configure()` if defaults need overriding, but `window.ahoy` (or the imported `ahoy` object) is available immediately. The `typeof window.ahoy?.track !== "function"` guard handles the case where Ahoy.js is not loaded at all.

### TypeScript declaration update

`client/src/index.d.ts` must export `AhoyJs`:
```typescript
export declare const AhoyJs: {
  readonly name: "AhoyJs";
  handle(eventName: string, params?: Record<string, unknown>): void;
};
```

---

## Test plan

### Server-side unit tests

**File:** `test/unit/subscribers/ahoy_test.rb`

Test cases:

1. **Controller present with ahoy tracker** — `Current.controller` set to a double that `respond_to?(:ahoy, true)` returns true; `controller.ahoy.track` is called with `(event_name_string, params_hash)`. Assert `safe_deliver` returns nil.

2. **Controller present but ahoy not included** — controller does NOT `respond_to?(:ahoy, true)`; assert deliver returns nil (skips), no tracker.track called, warn logged.

3. **No controller (job context)** — `Current.controller` is nil; assert deliver returns nil, warn logged.

4. **controller.ahoy returns nil** — `respond_to?(:ahoy)` is true but `controller.ahoy` returns nil; assert deliver skips gracefully.

5. **Event name coercion** — catalog event `:purchase` (Symbol) → `"purchase"` (String) passed to `tracker.track`.

6. **Filtered events** — use `filter only: [:purchase]`; call with `:page_view`; assert tracker.track not called (Base filter gate).

7. **synchronous! is set** — `assert TrackRelay::Subscribers::Ahoy.synchronous`.

### Server-side integration tests

**File:** `test/integration/ahoy_delivery_test.rb`

Test cases:

1. **Full pipeline with dispatcher** — call `TrackRelay.track(:purchase, ...)` with `Current.controller` set to a controller double that has `ahoy.track`; assert `tracker.track` was called inline (no `DeliveryJob` enqueued).

2. **Job-context skip** — call `TrackRelay.track(:purchase, ...)` without setting `Current.controller` (simulates job); assert no `DeliveryJob` enqueued, no tracker.track called, no exception raised.

3. **Ahoy gem absent** — controller that does NOT `respond_to?(:ahoy)`; assert no crash, warn logged.

The integration test setup mirrors `ga4_synchronous_opt_in_test.rb`:
```ruby
setup do
  TrackRelay.configure { |c| c.subscribe(TrackRelay::Subscribers::Ahoy.new) }
  TrackRelay::Dispatcher.start!
end
```

For controller doubles, use a `Struct` or `OpenStruct` that implements `respond_to?(:ahoy, true)` and exposes a mock `ahoy` tracker. No Combustion controller request is needed — the subscriber reads `Current.controller` directly, so:
```ruby
mock_tracker = Minitest::Mock.new
mock_tracker.expect(:track, true, ["purchase", { value: 9.99 }])
mock_controller = Object.new
mock_controller.define_singleton_method(:ahoy) { mock_tracker }
TrackRelay::Current.controller = mock_controller
```

### Client-side tests

**File:** `client/test/ahoy_js.test.js`

Test cases:

1. **`AhoyJs.handle` dispatches via `window.ahoy.track`** — after `init({ manifestUrl })`, call `AhoyJs.handle("purchase", {...})`; assert `window.ahoy.track` called with `("purchase", {...})`.

2. **Validation: typed event — dev throws** — `init({ manifestUrl, env: "development" })`; call `AhoyJs.handle("purchase", {})` (missing required params); assert throws with error message.

3. **Validation: typed event — prod warns and drops** — same but env=production; assert `console.warn` called, `window.ahoy.track` NOT called.

4. **Untyped event passes through** — event not in manifest; assert `window.ahoy.track` called.

5. **`window.ahoy` absent** — delete `window.ahoy`; assert `console.warn`, no crash.

6. **`AhoyJs.name` equals `"AhoyJs"`** (server-parity check, mirrors the existing Ga4Gtag name test).

### Gemfile / Appraisal updates

The Appraisals currently include Rails 7.1, 7.2, 8.0 with no optional Ahoy entry. Two actions needed:

1. **Add `ahoy` as a development dependency in `track_relay.gemspec`:**
   ```ruby
   spec.add_development_dependency "ahoy_matey"
   ```
   This ensures the Ahoy gem is available in the test suite for the unit/integration tests that use a real `Ahoy::Tracker`.

2. **Add an optional Appraisal matrix entry** (or add `ahoy_matey` to each gemfile). Simplest approach: add to each existing gemfile:
   ```ruby
   gem "ahoy_matey"
   ```
   This does not require a separate "with_ahoy" / "without_ahoy" appraisal split because the subscriber's duck-typing means it degrades gracefully without Ahoy — but the tests that assert tracking behavior need the gem present.

   If a "without Ahoy" test is desired to pin the skip behavior, a separate `appraise "rails_8_0_no_ahoy"` could be added, but this is optional.

3. **Combustion internal app (`test/internal`)** — the dummy app may need `Ahoy::Controller` included in ApplicationController and the Ahoy migrations run for integration tests. This needs verification at Bash-time (see Open Questions).

---

## Open questions / live validation needed

1. **`⚠ REQUIRES LIVE VALIDATION` — `test/internal` app structure.** Reading the directory was blocked (EISDIR). The Combustion dummy app at `test/internal` may need `Ahoy::Controller` included in its `ApplicationController` and Ahoy's visit/event tables migrated for integration tests to work. Must run: `ls test/internal/app/controllers/` and `ls test/internal/db/` before implementation.

2. **`⚠ REQUIRES LIVE VALIDATION` — `ahoy_matey` gem version pinning.** The gemspec does not currently declare `ahoy_matey` as a dev dependency; `gemfiles/rails_8_0.gemfile` has no Ahoy entry. Before adding the dependency, confirm compatibility: run `bundle exec gem list ahoy_matey` after adding it to the gemspec to verify the version that resolves under Rails 7.1/7.2/8.0.

3. **`⚠ REQUIRES LIVE VALIDATION` — `controller.ahoy` on a minimal controller double.** The unit test plan uses a plain `Object` double with a `define_singleton_method(:ahoy)`. Verify that `respond_to?(:ahoy, true)` returns true on this double (it should, since `define_singleton_method` creates a public method), and that the `Base` filter path does not interfere.

4. **`⚠ REQUIRES LIVE VALIDATION` — `init()` `measurementId` optionality in the client.** Currently `init()` throws synchronously if `measurementId` is falsy. Making it optional (for AhoyJs-only hosts) changes an existing public API contract. Check whether any existing test pins the `!measurementId` throw path. If it does, that test must be updated when `measurementId` is made optional.

5. **`⚠ REQUIRES LIVE VALIDATION` — Ahoy exclude? behavior in test context.** `Ahoy::BaseStore#exclude?` checks for bots and `Rails::HealthController`. In the test harness (no real request), `exclude?` may return true or raise depending on the Ahoy version. The unit tests should stub `tracker.track` rather than going through a real `Ahoy::Tracker` instance to avoid this variable.

6. **`⚠ REQUIRES LIVE VALIDATION` — `client_id/ahoy_visitor.rb` uses `current_visit`.** The `AhoyVisitor` resolver calls `controller.ahoy.current_visit.visitor_token`, but `Ahoy::Tracker#current_visit` is not in the public API fetched above — the tracker exposes `visit` and `visit_or_create`, not `current_visit`. Verify whether `current_visit` is a public alias in the version of Ahoy that will be pinned, or whether the resolver needs to call `.visit` instead. This is pre-existing code (Phase 02), not new work, but it may surface a bug in the Ahoy subscriber's tracker access pattern.

7. **`⚠ REQUIRES LIVE VALIDATION` — `payload.context[:visit]` type after `DeliveryJob` serialization.** `current_context` stores `Current.visit` (an `Ahoy::Visit` ActiveRecord object) in `payload.context[:visit]`. `EventPayload#to_h` serializes context via `@context` which is a raw Hash — it does NOT call `.to_h` on nested values. ActiveRecord objects are NOT GlobalID-serializable through plain Hash serialization, so the visit record in `context` would be lost or corrupt after `DeliveryJob` round-trips through JSON. This confirms that the Ahoy subscriber MUST be synchronous and MUST NOT rely on `payload.context[:visit]` in the async path.

---

## Recommended task decomposition for Lead

These are proposed atomic tasks for the Lead to turn into PLAN tasks. Each is independently committable.

**Task 1 — Server subscriber skeleton**
Create `lib/track_relay/subscribers/ahoy.rb` with `class TrackRelay::Subscribers::Ahoy < Base; synchronous!; end`. Add `require` line to `lib/track_relay.rb`. All tests should still pass (no behavior yet). Verify `TrackRelay::Subscribers::Ahoy.synchronous` is true.

**Task 2 — Server subscriber `#deliver` with controller path**
Implement `deliver(payload)`: duck-type `Current.controller.respond_to?(:ahoy, true)`, call `controller.ahoy.track(payload.name.to_s, payload.params)`, add `log_skip` helper. Cover with unit tests: controller present (tracker called), no controller (skip + warn), ahoy not included (skip + warn).

**Task 3 — Server integration test**
Add `test/integration/ahoy_delivery_test.rb`. Test full pipeline: dispatcher → subscriber → tracker.track called inline. Test job-context: dispatcher → subscriber → skip (no enqueue, no crash). Requires deciding Combustion dummy app changes (validate open question 1 first).

**Task 4 — Gemfile / Appraisal updates**
Add `ahoy_matey` to `track_relay.gemspec` dev dependencies and to the generated gemfiles. Run `bundle exec appraisal generate` to regenerate gemfiles if needed. Validate all three Rails appraisals still pass.

**Task 5 — Client AhoyJs subscriber**
Add `AhoyJs` named export to `client/src/index.js` (inline alongside `Ga4Gtag`). Make `measurementId` optional in `init()` (only required when `_measurementId` will be used). Update `client/src/index.d.ts` to export `AhoyJs` type. Bump `client/package.json` version to `0.3.0`.

**Task 6 — Client AhoyJs tests**
Add `client/test/ahoy_js.test.js` covering: dispatch via `window.ahoy.track`, typed validation (dev throws, prod warns+drops), untyped passthrough, absent `window.ahoy` guard, `name` field parity.

**Task 7 — Version bump and CHANGELOG**
Bump `lib/track_relay/version.rb` to `"0.3.0"`. Update `CHANGELOG.md` with Phase 03 entry. Bump `client/package.json` to `"0.3.0"` (can be combined with Task 5).

**Task 8 — (Optional) Combustion dummy app Ahoy wiring**
If the integration tests (Task 3) require it: add `include Ahoy::Controller` to `test/internal/app/controllers/application_controller.rb` and add Ahoy migration to `test/internal/db/`. This task is conditional on live validation of open question 1.
