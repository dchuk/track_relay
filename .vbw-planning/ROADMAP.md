# track_relay Roadmap

**Goal:** track_relay

**Scope:** 4 phases

## Progress
| Phase | Status | Plans | Tasks | Commits |
|-------|--------|-------|-------|---------|
| 01 | ○ Planned |
| 2 | Pending | 0 | 0 | 0 |
| 3 | Pending | 0 | 0 | 0 |
| 4 | Pending | 0 | 0 | 0 |

---

## Phase List
- [ ] [Phase 1: Core (MVP)](#phase-1-core-mvp)
- [ ] [Phase 2: GA4 subscribers](#phase-2-ga4-subscribers)
- [ ] [Phase 3: Ahoy subscribers](#phase-3-ahoy-subscribers)
- [ ] [Phase 4: Polish](#phase-4-polish)

---

## Phase 1: Core (MVP)

**Goal:** Deliver the catalog DSL, ActiveSupport::Notifications-based dispatch, EventDefinition/EventPayload separation, TrackRelay::Current, controller+job tracking helpers, untyped-events linter, Test+Logger subscribers, and RSpec/Minitest matchers. Releasable as 0.1.0.

**Requirements:** REQ-01, REQ-02, REQ-03, REQ-04, REQ-05, REQ-06, REQ-07, REQ-13, REQ-14

**Success Criteria:**
- track :name, params validates against the catalog and instruments via ActiveSupport::Notifications
- Test subscriber captures events; have_tracked matcher passes against in-memory captures
- Untyped events emit a linter warning; rake track_relay:lint reports them
- Validation raises in dev/test and logs in production; no silent mutation
- Released and installable as 0.1.0 on a private registry or local path

**Dependencies:** None

---

## Phase 2: GA4 subscribers

**Goal:** Add server-side Ga4MeasurementProtocol subscriber (async via DeliveryJob), client-side Ga4Gtag subscriber in the @track_relay/client npm package, and JSON manifest generation. Releasable as 0.2.0.

**Requirements:** REQ-08, REQ-10, REQ-11, REQ-12

**Success Criteria:**
- Server-side track call results in a POST to https://www.google-analytics.com/mp/collect with the correct payload shape
- client_id is derived from _ga cookie, then Ahoy visitor_token, then session-bound fallback
- JS package validates events against the JSON manifest before dispatching to gtag
- rake track_relay:manifest regenerates public/track_relay_catalog.json; Railtie hooks asset precompile
- Released as 0.2.0

**Dependencies:** Phase 1

---

## Phase 3: Ahoy subscribers

**Goal:** Add server-side Ahoy subscriber (public API only, no internal Ahoy::Event.create!) and client-side AhoyJs subscriber in the npm package. Releasable as 0.3.0.

**Requirements:** REQ-09

**Success Criteria:**
- Server Ahoy subscriber routes via TrackRelay::Current.controller.ahoy.track or visit.track only
- Job-context calls without a controller or visit log and skip rather than fabricate a write
- Client AhoyJs subscriber wraps window.ahoy.track using the same event names as the server
- Released as 0.3.0

**Dependencies:** Phase 2

---

## Phase 4: Polish

**Goal:** Generators (install, event, subscriber), additional v2 subscribers (PostHog, Plausible, Webhook), optional engine mount for ad-blocker resilience, performance benchmarks, custom Rubocop cop for raw gtag/ahoy.track calls. Path to 1.0.0.

**Requirements:** REQ-15, REQ-19

**Success Criteria:**
- rails g track_relay:install scaffolds the initializer, catalog directory, and ApplicationController include
- rails g track_relay:event and track_relay:subscriber generators produce working scaffolds
- At least one v2 subscriber (PostHog or Plausible) shipped
- Benchmarks documented; 1.0.0 released

**Dependencies:** Phase 3

