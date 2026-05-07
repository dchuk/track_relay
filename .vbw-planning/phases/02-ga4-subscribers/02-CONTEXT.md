# Phase 2: GA4 Subscribers — Context

Gathered: 2026-05-06
Calibration: architect

## Phase Boundary
Add server-side `Ga4MeasurementProtocol` subscriber (async via `DeliveryJob`), client-side `Ga4Gtag` subscriber in the `@track_relay/client` npm package, and JSON manifest generation. Releasable as 0.2.0.

Covers REQ-08, REQ-10, REQ-11, REQ-12. Out of scope for this phase: Ahoy subscribers (Phase 3), generators / additional v2 vendors / TypeScript types generation (Phase 4).

## Decisions Made

### Server↔client routing (which subscribers fire for which events)
- **Decision:** Subscriber-side filters. `TrackRelay.subscribe Ga4MeasurementProtocol, only: %i[...]` / `except: %i[...]`. No filter = fires for every event.
- **Filter execution point:** Inside `Subscribers::Base#deliver`, before the per-subscriber `StandardError` rescue boundary established in Phase 1 (REQ-23).
- **Catalog DSL stays vendor-neutral:** events describe `name` + typed params only; no `send_to:` key. Preserves the "one catalog, many destinations" core value and keeps Phase 4 v2 vendors (PostHog, Plausible, Webhook) wireable without DSL changes.

### client_id fallback chain
- **Decision:** Configurable resolver array — `config.client_id_resolvers = [TrackRelay::ClientId::Ga, TrackRelay::ClientId::AhoyVisitor, TrackRelay::ClientId::Session]`. Each resolver is callable returning `String | nil`. First non-nil wins. Resolved once per request and memoized in `TrackRelay::Current.client_id`.
- **`_ga` cookie parsing:** split on `.`, take the last two segments — e.g. `GA1.2.123456789.1700000000` → `"123456789.1700000000"` (matches GA4 Measurement Protocol's documented `client_id` format). Malformed or missing cookie → `nil`, chain continues.
- **Session-bound fallback:** lazy UUID stored in `session[:track_relay_client_id]`, generated on first miss, stable across the Rails session. Rides existing session storage — no new top-level cookie.
- **Rationale for configurability:** consumers without Ahoy must be able to drop or replace that resolver; some shops will plug in a custom cookie/header resolver.

### GA4 constraint enforcement (REQ-10)
- **Decision:** Split enforcement by concern.
  - **Boot-time (Catalog DSL):** validate event **names** — snake_case, ≤40 chars, not in GA4's reserved-name list. Always raises (catalog refuses to load on violation). Reserved-name list shipped as a frozen constant sourced from Google's GA4 reserved-events docs.
  - **Call-time (`Ga4MeasurementProtocol` subscriber, before delivery):** validate the **payload** — ≤25 custom params actually sent, param-name shape. Follows REQ-05: raise in dev/test, log in production.
- **Linter (`rake track_relay:lint`):** extends today's untyped-events JSONL scan (REQ-22) to flag GA4 violations on untyped events too.
- **Rationale:** boot-only would miss runtime payload overruns from dynamic merges (`track :purchase, **extra_attrs`). Call-only would defer name typos to production traffic. Splitting puts each rule where its data lives.

### JSON manifest shape (`public/track_relay_catalog.json`)
- **Decision:** Full typed schema with `required[]`, mirroring the catalog DSL's typed param schemas (REQ-01).

  ```json
  {
    "version": "0.2.0",
    "generated_at": "<ISO8601>",
    "events": {
      "purchase":  { "params": { "value": "float", "currency": "string" }, "required": ["value", "currency"] },
      "sign_up":   { "params": { "method": "string" } }
    }
  }
  ```

- **JS validation behavior (`@track_relay/client`):** mirrors REQ-05 — throw in dev, `console.warn` + drop in prod. Configurable via client init.
- **Cache-busting:** Railtie hooks `assets:precompile`; manifest is a Sprockets asset and gets fingerprinted. JS fetches `/assets/track_relay_catalog-<hash>.json` (or imports the static asset). Fingerprint busts the JS-side cache automatically.
- **Dev regeneration:** file watcher on `config/track_relay/**/*.rb` re-runs the manifest task on catalog changes.
- **TypeScript types generation:** deferred to Phase 4 (aligns with REQ-15 generators). Phase 2 ships the runtime validator only.

### Open (Claude's discretion)
- **DeliveryJob queue name + ActiveJob `retry_on` policy** for `Ga4MeasurementProtocol` — research-time decision. Defaults expected: queue `:track_relay`, retry on transient 5xx with exponential backoff, drop on 4xx (GA4 validation failures should not retry indefinitely).
- **`@track_relay/client` package format** — research-time decision. Defaults expected: dual ESM + CJS, ES2020 target, no TypeScript types in this phase, manifest loaded via `fetch` at boot with the Sprockets fingerprint URL configurable.
- **Synchronous-delivery opt-out wiring** for the Ga4 server subscriber (REQ-11 says subscribers may opt-in to sync) — research/plan-time decision: per-subscriber config flag vs per-call override.

## Deferred Ideas
_(None new this round — Phase 1 deferred items remain: privacy/GDPR built-ins, subscriber ordering with `after:`, custom Rubocop cop. Privacy/IP anonymization for GA4 specifically may resurface in Phase 4 polish.)_
