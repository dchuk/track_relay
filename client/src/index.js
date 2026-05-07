// @track_relay/client — public API
//
// Phase 02 Plan 02-05 client-side half of REQ-08:
//   * `init({measurementId, manifestUrl})` fetches the typed manifest
//     produced by the Rails-side `track_relay:manifest` rake task.
//   * `track(eventName, params)` validates against the manifest entry
//     (when one exists) and dispatches via `window.gtag("event", ...)`.
//   * `setClientId(clientId)` updates the resolved client_id for
//     subsequent gtag('config', ...) calls.
//   * `Ga4Gtag` named export — server-subscriber-shaped wrapper around
//     `track()` for hosts that prefer object dispatch.
//
// State is module-private; `init` is the single source of truth for
// `_measurementId` and `_manifest`. `manifestUrl` is REQUIRED — the
// Rails layer is the source of truth (asset_path('track_relay_catalog.json'))
// and the JS package cannot read Ruby config. Misconfiguration MUST be
// loud. `measurementId` is OPTIONAL as of 0.3.0 — AhoyJs-only hosts
// (no GA4 in use) can omit it. When supplied it is stored and used by
// the GA4 dispatch path; when nullish/empty `_flushConfigOnce()` short
// -circuits and the GA4 surface stays dormant.

import { validateParams } from "./validator.js";

let _measurementId = null;
let _manifest = null;
let _env = "production";
let _onValidationError = null;
let _clientId = null;
let _configFlushed = false;

const PREFIX = "@track_relay/client";

/**
 * Initialize the client by fetching the manifest. `manifestUrl` is
 * required — passing nullish or empty-string throws SYNCHRONOUSLY (not
 * via a rejected promise) BEFORE any fetch is attempted, so
 * misconfiguration is loud at the call site.
 *
 * `measurementId` is OPTIONAL as of 0.3.0. AhoyJs-only hosts (no GA4
 * subscriber in use) can omit it. When supplied, the GA4 dispatch path
 * picks it up via `_flushConfigOnce()`; when omitted, the GA4 surface
 * stays dormant and only AhoyJs / non-GA4 paths fire.
 *
 * Returns a Promise that resolves once the manifest has been fetched
 * and parsed. Callers can `await init({...})` and `.catch()` network
 * failures.
 *
 * Implementation note: this function is intentionally NOT declared
 * `async`. An `async` wrapper would convert the synchronous validation
 * throw into a rejected promise, defeating the purpose. We do
 * validation synchronously and delegate the fetch to an internal
 * async helper.
 */
export function init({ measurementId, manifestUrl, env = "production", onValidationError } = {}) {
  if (!manifestUrl) {
    throw new Error(
      `${PREFIX}: init requires manifestUrl (e.g. served by \`rake track_relay:manifest\`)`
    );
  }

  return _initAsync({ measurementId, manifestUrl, env, onValidationError });
}

async function _initAsync({ measurementId, manifestUrl, env, onValidationError }) {
  const resp = await fetch(manifestUrl);
  if (!resp.ok) {
    throw new Error(`${PREFIX}: manifest fetch failed (HTTP ${resp.status}) for ${manifestUrl}`);
  }

  _manifest = await resp.json();
  _measurementId = measurementId;
  _env = env;
  _onValidationError = typeof onValidationError === "function" ? onValidationError : null;
  _configFlushed = false;
}

/**
 * Validate the event against the manifest (if typed) and dispatch via
 * `window.gtag("event", name, params)`. Untyped events pass through
 * (REQ-06). On validation failure, dev-mode throws and prod-mode
 * `console.warn`s — mirrors REQ-05 server-side semantics.
 */
export function track(eventName, params = {}) {
  const schema = _manifest?.events?.[eventName];

  // Typed event — validate. Untyped events pass through (REQ-06).
  if (schema) {
    const errors = validateParams(eventName, schema, params);
    if (errors.length > 0) {
      _onValidationError?.(errors);
      if (_env === "development") {
        throw new Error(`${PREFIX}: ${errors.join("; ")}`);
      }
      console.warn(`${PREFIX}:`, ...errors);
      return; // drop in production
    }
  }

  if (typeof window === "undefined" || typeof window.gtag !== "function") {
    console.warn(`${PREFIX}: window.gtag not found — event dropped: ${eventName}`);
    return;
  }

  _flushConfigOnce();
  window.gtag("event", eventName, params);
}

/**
 * Update the resolved client_id. The next `track()` call will re-emit
 * `gtag('config', measurementId, {client_id})` so GA4 routes events to
 * the right user. Calling before `init()` stages the value for the
 * first post-init dispatch.
 */
export function setClientId(clientId) {
  _clientId = clientId == null ? null : String(clientId);
  _configFlushed = false;
}

function _flushConfigOnce() {
  if (_configFlushed) return;
  if (!_measurementId) return;
  if (typeof window === "undefined" || typeof window.gtag !== "function") return;

  const configParams = _clientId ? { client_id: _clientId } : {};
  window.gtag("config", _measurementId, configParams);
  _configFlushed = true;
}

/**
 * Named export: client-side mirror of the server-side
 * `TrackRelay::Subscribers::Ga4MeasurementProtocol`. Validates against
 * the manifest and dispatches via `window.gtag`. Reads the same
 * module-private state populated by `init({...})` — no separate
 * subscriber-side initialization needed.
 *
 * `Ga4Gtag.handle(name, params)` is the server-subscriber-shaped
 * counterpart to plain `track(name, params)`. Use whichever feels
 * more idiomatic in the host app.
 */
export const Ga4Gtag = Object.freeze({
  name: "Ga4Gtag",
  handle(eventName, params = {}) {
    track(eventName, params);
  }
});

/**
 * Named export: client-side mirror of the server-side
 * `TrackRelay::Subscribers::Ahoy`. Validates against the manifest and
 * dispatches via `window.ahoy.track(eventName, params)`. Reads the
 * same module-private state populated by `init({...})` — no separate
 * subscriber-side initialization needed.
 *
 * Validation semantics match `track()`/`Ga4Gtag.handle()`:
 *   - Typed event with validation errors → `_onValidationError(errors)`,
 *     then dev-throws / prod-warns-and-drops (REQ-05 mirror).
 *   - Untyped event → passes through unchanged (REQ-06 client-side parity).
 *
 * Guards on `window.ahoy.track` availability and emits `console.warn`
 * + drops the event when missing — matches the `window.gtag` guard in
 * `track()`. Does NOT throw, does NOT call `window.gtag`, does NOT crash
 * when the host hasn't loaded `ahoy.js`.
 */
export const AhoyJs = Object.freeze({
  name: "AhoyJs",
  handle(eventName, params = {}) {
    const schema = _manifest?.events?.[eventName];

    // Typed event — validate. Untyped events pass through (REQ-06).
    if (schema) {
      const errors = validateParams(eventName, schema, params);
      if (errors.length > 0) {
        _onValidationError?.(errors);
        if (_env === "development") {
          throw new Error(`${PREFIX}: ${errors.join("; ")}`);
        }
        console.warn(`${PREFIX}:`, ...errors);
        return; // drop in production
      }
    }

    if (typeof window === "undefined" || typeof window.ahoy?.track !== "function") {
      console.warn(`${PREFIX}: window.ahoy.track not found — event dropped: ${eventName}`);
      return;
    }

    window.ahoy.track(eventName, params);
  }
});

// Test-only helper: reset module state between tests so suites do not
// leak `_manifest` / `_configFlushed` flags across cases. NOT part of
// the public API — `index.d.ts` deliberately omits it.
export function _resetForTests() {
  _measurementId = null;
  _manifest = null;
  _env = "production";
  _onValidationError = null;
  _clientId = null;
  _configFlushed = false;
}
