# Phase 1: Core (MVP) — Context

Gathered: 2026-05-05
Calibration: architect

## Phase Boundary

Deliver the catalog DSL, ActiveSupport::Notifications-based dispatch, EventDefinition/EventPayload separation, TrackRelay::Current, controller+job tracking helpers, untyped-events linter, Test+Logger subscribers, and RSpec/Minitest matchers. Releasable as 0.1.0 on a private registry or local path.

In scope: the runtime track flow, validation, and the two stub subscribers that prove the bus works (Test + Logger). Out of scope: GA4 (Phase 2), Ahoy (Phase 3), generators (Phase 4), JS client package (Phase 2).

## Decisions Made

### Ruby + Rails support matrix
- **Decision:** Ruby >= 3.2 floor; CI matrix of Rails 7.1, 7.2, and 8.0.
- **Rationale:** Aligns with current LTS landscape as of 2026-05. Rails 8 is current, 7.2 is on bug-fix support, 7.1 covers the long tail. Ruby 3.2 is the oldest version still receiving security fixes.
- **Consequence:** gemspec `required_ruby_version = ">= 3.2"`; Rails dependency `>= 7.1`. CI matrix runs three Rails versions; gemspec does not pin a Rails upper bound (let SemVer break point us when the time comes). Anything Ruby-3.2-only (`Data.define`, etc.) is fair game.

### Failsafe rescue boundary
- **Decision:** Per-subscriber rescue inside the gem's `ActiveSupport::Notifications` subscriber base (effectively in `TrackRelay::Subscribers::Base#deliver`). On `StandardError`, log via `Rails.logger.error("[track_relay] subscriber=#{name} failed: #{e.message}")` and continue dispatching to remaining subscribers.
- **Rationale:** Standard fan-out pattern. One bad subscriber must not take down peers. Per-subscriber rescue keeps error context (which subscriber failed) without forcing each subscriber author to remember to rescue.
- **Dev/test behavior:** Re-raise unless `config.swallow_subscriber_errors = true` is explicitly set in the environment. This makes broken subscribers loud during development.
- **Consequence:** `Subscribers::Base` owns the rescue; subclass `deliver` methods do not need their own. Test subscriber assertions still see the event because capture happens before delivery dispatch.

### Test framework for the gem's own test suite
- **Decision:** Minitest.
- **Rationale:** Rails-core convention; lighter-weight; closer to how Rails itself tests `ActiveSupport::Notifications`. The gem still ships matchers for both RSpec and Minitest — picking one for the gem's own suite is independent of consumer choice. User has a `tdd-cycle` skill calibrated for Minitest + fixtures.
- **Consequence:** `spec/` becomes `test/` with `*_test.rb` files; `bin/test` runs via `rake test`; uses `Minitest::Test` + `ActiveSupport::TestCase` for the Rails-integration tests; no `spec_helper.rb` / `rails_helper.rb`.

### Untyped-event detection mechanism
- **Decision:** A Logger subscriber that writes to `Rails.logger` for human visibility AND appends a structured JSONL line to `tmp/track_relay_untyped.jsonl` (gitignored) for machine consumption. The `rake track_relay:lint` task reads the JSONL, dedupes by event-name + param-signature, and prints a report.
- **Rationale:** Robust against log format changes; queryable; testable. Tagged-log-prefix parsing is brittle. Pure in-memory capture is lossy across processes/restarts and useless in production for a "untyped events still happening on prod" audit.
- **Configuration:** Off by default. Enabled via `config.untyped_log_path = Rails.root.join("tmp/track_relay_untyped.jsonl")` (or `config.capture_untyped = true` for the default path). When the path is unset, the Logger subscriber only writes the human-readable warning line.
- **JSONL line shape:** `{"event":"...","params":["param_a","param_b"],"controller":"...","action":"...","timestamp":"2026-05-05T..."}` — param values are NOT logged, only param names, to avoid leaking PII.
- **Consequence:** Phase 1 ships the Logger subscriber + JSONL writer + `rake track_relay:lint`. The linter rake task is part of the v0.1.0 release. The default `tmp/` location is auto-gitignored by Rails.

### Open (Claude's discretion)

- **Catalog hot-reload in dev:** default to reloading via `Rails.application.reloader.to_prepare` (standard pattern) so editing `config/track_relay/*.rb` rebuilds the catalog without a server restart. Trivial DX win.
- **`untyped_events_allowed` default:** `true` per the planning doc (incremental adoption-friendly).
- **Reserved key collision:** if a catalog event defines `:user`/`:visitor_token`/`:client_id`/`:request` as a param, raise at catalog-load time with a clear message ("reserved key — use a different name like `actor_user_id`"). Prevents silent shadowing.
- **Async vs sync subscriber default:** async via `TrackRelay::DeliveryJob`. Test and Logger subscribers opt into `synchronous!` because they need immediate visibility.
- **Test subscriber test-mode swap:** `TrackRelay.test_mode!` REPLACES the configured subscriber list with `[Subscribers::Test.new]` for the duration of the example, then restores. Real subscribers do not fire during tests.

## Deferred Ideas

- **Privacy/GDPR built-ins** (IP masking, DNT respect, consent gating) — leaning toward opt-in, off by default, configurable per-subscriber. Defer to Phase 2 (GA4) where IP/consent actually matters.
- **Subscriber ordering / `after:` option** — defer to Phase 2 when the GA4 subscriber needs Ahoy's `visit_id` from a prior subscriber.
- **Custom Rubocop cop** for raw `gtag(...)` / `ahoy.track(...)` calls — Phase 4 polish.
- **Multi-tenant catalogs** — punted to v2 per planning doc.
- **Optional engine mount for `/track_relay/events`** (ad-blocker resilience) — Phase 4.
- **Naming validation** on RubyGems — pre-1.0 release task, not Phase 1 work.
