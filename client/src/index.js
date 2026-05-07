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
// `_measurementId` and `_manifest`. Both fields on `init({...})` are
// REQUIRED — the Rails layer is the source of truth (TrackRelay.config
// .ga4_measurement_id + asset_path('track_relay_catalog.json')) and the
// JS package cannot read Ruby config. Misconfiguration MUST be loud.

import { validateParams } from "./validator.js";

let _measurementId = null;
let _manifest = null;
let _env = "production";
let _onValidationError = null;
let _clientId = null;
let _configFlushed = false;

const PREFIX = "@track_relay/client";

/**
 * Initialize the client by fetching the manifest. Both `measurementId`
 * and `manifestUrl` are required — passing nullish for either throws
 * synchronously BEFORE any fetch is attempted.
 */
export async function init({ measurementId, manifestUrl, env = "production", onValidationError } = {}) {
  if (measurementId == null || manifestUrl == null) {
    throw new Error(
      `${PREFIX}: init requires both measurementId (e.g. 'G-XXXXXXXXXX') and manifestUrl`
    );
  }

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
