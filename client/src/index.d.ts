// Public type signatures for @track_relay/client.
//
// Hand-maintained — the JS source is plain ES2020 with no TypeScript
// build step. Generated types from the manifest (REQ-15) are a Phase 4
// deliverable; for now the params object on `track()` is loosely typed.

export type TrackRelayEnv = "development" | "production";

export interface InitOptions {
  /**
   * GA4 Measurement ID, e.g. `"G-XXXXXXXXXX"`. Sourced from
   * `TrackRelay.config.ga4_measurement_id` in the Rails layout.
   * Optional. Only required when a GA4 subscriber is in use; AhoyJs-only
   * hosts can omit it. When omitted (or empty-string / null) the GA4
   * dispatch surface stays dormant — `track()` and `Ga4Gtag.handle()`
   * still validate against the manifest but `gtag('config', ...)` is
   * never emitted.
   */
  measurementId?: string;

  /**
   * URL of the typed JSON manifest written by `rake track_relay:manifest`.
   * Sourced from `<%= asset_path('track_relay_catalog.json') %>` in
   * the Rails layout. REQUIRED — passing nullish or empty-string throws
   * synchronously.
   */
  manifestUrl: string;

  /**
   * `"development"` throws `Error` on validation failure.
   * `"production"` (default) calls `console.warn` and silently drops.
   */
  env?: TrackRelayEnv;

  /**
   * Optional callback invoked with the validation-error array BEFORE
   * the throw/warn branch — gives hosts a hook into a logging or
   * monitoring pipeline without intercepting `console.warn`.
   */
  onValidationError?: (errors: string[]) => void;
}

export type TrackParams = Record<string, string | number | boolean | Date | null | undefined>;

/**
 * Initialize the client. Validates `manifestUrl` synchronously, then
 * fetches and parses the manifest. `measurementId` is optional —
 * AhoyJs-only hosts can omit it. The returned Promise resolves once
 * state is populated; subsequent `track()` / `Ga4Gtag.handle()` /
 * `AhoyJs.handle()` calls validate against the loaded manifest.
 */
export function init(options: InitOptions): Promise<void>;

/**
 * Validate `params` against the manifest entry for `eventName` (when
 * one exists) and dispatch via `window.gtag("event", eventName, params)`.
 * Untyped events pass through unchanged (REQ-06). Missing
 * `window.gtag` warns and drops the event.
 */
export function track(eventName: string, params?: TrackParams): void;

/**
 * Update the resolved client_id. The next `track()` call re-emits
 * `gtag("config", measurementId, {client_id})` so GA4 routes events
 * to the right user.
 */
export function setClientId(clientId: string | null | undefined): void;

/**
 * Server-subscriber-shaped wrapper around `track()` — mirrors the
 * Ruby `TrackRelay::Subscribers::Ga4MeasurementProtocol#deliver` shape.
 * Reads the same module-private state populated by `init({...})`.
 */
export const Ga4Gtag: {
  readonly name: "Ga4Gtag";
  handle(eventName: string, params?: TrackParams): void;
};

/**
 * Server-subscriber-shaped wrapper around `window.ahoy.track` —
 * mirrors the Ruby `TrackRelay::Subscribers::Ahoy#deliver` shape.
 * Reads the same module-private state populated by `init({...})`.
 * Validates against the manifest (typed events) and passes untyped
 * events through unchanged. Missing `window.ahoy.track` warns and
 * drops the event without throwing.
 */
export const AhoyJs: {
  readonly name: "AhoyJs";
  handle(eventName: string, params?: TrackParams): void;
};
