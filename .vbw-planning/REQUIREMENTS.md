# Requirements

Defined: 2026-05-05

## Requirements

### REQ-01: Catalog DSL with typed param schemas (integer/string/float/boolean/datetime) for event definitions
**Must-have**

### REQ-02: Multi-file catalog autoloading via Railtie from config/track_relay/**/*.rb
**Must-have**

### REQ-03: ActiveSupport::Notifications-based dispatch as the internal event bus (no custom Dispatcher)
**Must-have**

### REQ-04: TrackRelay::Current built on ActiveSupport::CurrentAttributes for context (user, request, visit, controller, client_id)
**Must-have**

### REQ-05: Catalog validation: raise in dev/test, log in production. No silent mutation; sanitizers opt-in and explicit
**Must-have**

### REQ-06: Untyped events allowed with linter rake task to surface them for incremental formalization
**Must-have**

### REQ-07: Built-in v1 subscribers: Test (in-memory capture) and Logger (Rails.logger)
**Must-have**

### REQ-08: GA4 subscribers: Ga4MeasurementProtocol (server, async ActiveJob) and Ga4Gtag (client, in npm package)
**Must-have**

### REQ-09: Ahoy subscribers: Ahoy (server, public API only) and AhoyJs (client)
**Must-have**

### REQ-10: GA4 constraint enforcement: snake_case event names, max 40 chars, max 25 custom params per event, reserved-name refusal
**Must-have**

### REQ-11: Async delivery via TrackRelay::DeliveryJob (ActiveJob); subscribers may opt-in to synchronous! delivery
**Must-have**

### REQ-12: JS client package @track_relay/client with JSON manifest generated to public/track_relay_catalog.json (Rake task + Railtie hook)
**Must-have**

### REQ-13: Test helpers + RSpec/Minitest matchers: have_tracked(:event).with(params), test_mode! swap-in
**Must-have**

### REQ-14: Reserved keys (user, visitor_token, client_id, request) extracted into TrackRelay::Current; everything else is a param
**Must-have**

### REQ-15: Generators: track_relay:install, track_relay:event, track_relay:subscriber
**Should-have**

### REQ-16: TrackRelay.identify(user, **user_properties) for GA4 user_properties and Ahoy attribution
**Should-have**

### REQ-17: Phased gem releases: 0.1.0 core, 0.2.0 GA4, 0.3.0 Ahoy, 1.0.0 polish
**Should-have**

### REQ-18: v2+ subscribers: PostHog, Mixpanel, Plausible, Segment, Webhook
**Future**

### REQ-19: Optional engine mount for /track_relay/events POST endpoint (ad-blocker resilience) — Phase 4
**Future**

### REQ-20: Out of scope: event-sourcing replacement, Segment competitor, generic instrumentation library, Turbo/ActionCable/AR-callback integrations in v1
**Out of scope**

## Out of Scope

_(To be defined)_

