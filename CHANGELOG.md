# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-06

### Added

- Catalog DSL with `event` blocks and typed params (`integer`, `string`, `float`, `boolean`, `datetime`) plus validators (`required`, `max`, `in`, `format`, `sanitize`).
- `TrackRelay::EventDefinition` (catalog metadata) and `TrackRelay::EventPayload` (runtime instance) as separate classes.
- `TrackRelay::Current` via `ActiveSupport::CurrentAttributes` with `:user, :request, :visit, :controller, :client_id`.
- `TrackRelay::Configuration` with `subscribe`, `swallow_subscriber_errors`, `untyped_log_path`, `untyped_events_allowed`, `force_synchronous`, `raise_on_validation_error`.
- `TrackRelay.track(name, **params)` — validates against catalog (when defined) or accepts untyped, instruments `track_relay.event` via `ActiveSupport::Notifications`.
- `TrackRelay.identify(user, **properties)` — instruments `track_relay.identify`.
- Reserved-key partitioning: `:user, :visitor_token, :client_id, :request` are routed to `Current` / payload context, never appear in `payload.params`.
- Reserved-key collision detection at catalog load (`TrackRelay::ReservedKeyError`).
- GA4 constraint enforcement: snake_case event names, max 40 chars, max 25 custom params, refusal of GA4-reserved names.
- `TrackRelay::Subscribers::Base` with `synchronous!` macro and per-subscriber rescue (`safe_deliver` returns the StandardError on failure rather than re-raising inline).
- `TrackRelay::Subscribers::Test` — in-memory capture, synchronous, per-instance state.
- `TrackRelay::Subscribers::Logger` — writes to `Rails.logger`; appends untyped-event JSONL (`{event, params, controller, action, timestamp}` — param NAMES only, never values) to `config.untyped_log_path`.
- `TrackRelay::DeliveryJob < ActiveJob::Base` for async subscriber delivery.
- `TrackRelay::Dispatcher` — single `ActiveSupport::Notifications` subscription that fans out to `config.subscribers` with collect-then-reraise semantics; idempotent `start!` / `stop!`.
- `TrackRelay::Railtie` — autoloads `config/track_relay/**/*.rb` via `Rails.autoloaders.main.ignore` + `config.to_prepare` + `Dir.glob`/`load`; clears the catalog before each reload for hot-reload safety; starts the Dispatcher on `after_initialize`; loads rake tasks via the `rake_tasks` block.
- `TrackRelay::ControllerTracking` concern — `track` instance method + `before_action` that sets `Current.controller` / `Current.request` / `Current.client_id` (from the `_ga` cookie).
- `TrackRelay::JobTracking` concern — `track` instance method (job authors use `Current.set` block form for context, since the Rails Executor clears `CurrentAttributes` before every job).
- `TrackRelay.test_mode!` / `test_mode_off!` — atomic subscriber swap for test isolation. **Opt-in**: load via `require "track_relay/testing"` (not auto-required by `lib/track_relay.rb`).
- `TrackRelay::Testing::Helpers` (Minitest assertions) — `assert_tracked`, `refute_tracked`, with auto setup/teardown.
- RSpec matchers — `have_tracked(:event).with(**params)` (gated by `defined?(RSpec)`).
- `TrackRelay::Linter` + `rake track_relay:lint` and `rake track_relay:lint:json` — audit untyped events from the JSONL sink with dedupe by event name + sorted-param-signature. Both rake tasks abort with a nonzero exit when `config.untyped_log_path` is unset (footgun prevention).
- Collect-then-reraise dispatcher: peer subscribers always receive each event; in dev/test (`swallow_subscriber_errors=false`) the first failed subscriber's exception is re-raised AFTER fan-out, so loudness is preserved without breaking the bus.
- CI matrix: Ruby 3.2/3.3/3.4 × Rails 7.1/7.2/8.0 (9 combinations) via Appraisal + `ruby/setup-ruby@v1` + `bundler-cache: true`.
- Combustion-backed Minitest test harness; `ActiveSupport::CurrentAttributes::TestHelper` mixed into `ActiveSupport::TestCase` for automatic `Current` reset between tests.
- StandardRB linting via `bundle exec standardrb` (and `bundle exec rake` default = standard + test).

### Notes

- Privacy: untyped JSONL captures param NAMES only (never VALUES) to avoid leaking PII.
- Naming: `track_relay` availability on RubyGems will be re-validated before 1.0.

[0.1.0]: https://github.com/dchuk/track_relay/releases/tag/v0.1.0
