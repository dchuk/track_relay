# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-05-07

### Added
- `rails g track_relay:install` — opinionated scaffold: richly commented
  initializer (`config/initializers/track_relay.rb`), sample catalog
  (`config/track_relay/sample.rb`), ApplicationSubscriber base class
  (`app/track_relay/subscribers/application_subscriber.rb`), and
  `include TrackRelay::ControllerTracking` injected idempotently into
  ApplicationController. `bundle exec rake test` passes cleanly
  immediately after running this generator.
- `rails g track_relay:event NAME` — scaffolds a typed catalog entry
  stub at `config/track_relay/<name>.rb`. Each event is its own file;
  the Railtie merges them at boot.
- `rails g track_relay:subscriber NAME` — scaffolds a subscriber class
  stub at `app/track_relay/subscribers/<name>_subscriber.rb`.
- Getting-started guide at [USAGE.md](USAGE.md).
- Migration notes at [UPGRADING.md](UPGRADING.md).
- E2E happy-path test exercising the install generator's output through
  the live Combustion harness (controller call → Test subscriber capture).
- README sections: Generators, Ahoy subscriber, Public API stability.

### Changed
- Targeting 1.0.0 (pending release); public-API stability is
  established for this release. See
  [UPGRADING.md](UPGRADING.md) for migration paths from 0.1.0 / 0.2.0
  / 0.3.0 to 1.0.0.

### Notes
- **Public API stability:** Public-API stability for `TrackRelay.track`, `.configure`,
  `.catalog`, `.subscribe`, `.identify`, `.test_mode!`,
  `TrackRelay::Subscribers::Base` (and the `synchronous!`,
  `filter only:`, `filter except:` macros),
  `TrackRelay::Subscribers::{Test,Logger,Ga4MeasurementProtocol,Ahoy}`,
  `TrackRelay::ControllerTracking`, `TrackRelay::JobTracking`,
  `TrackRelay::Testing::Helpers`, the catalog DSL
  (`event`, `integer`, `string`, `float`, `boolean`, `datetime`,
  `user_property` + `required:`/`max:`/`in:`/`format:`/`sanitize:`
  validators), the three generators, and the four rake tasks
  (`track_relay:lint`, `track_relay:lint:json`,
  `track_relay:lint:ga4`, `track_relay:manifest`) is established for
  the 1.0.0 release. Internal classes (`EventPayload`, `Instrumenter`,
  `Dispatcher`, `Catalog`, `Current`, `DeliveryJob`, `ClientId::*`)
  are not part of the public API contract.
- No breaking changes from 0.3.0. The `init({ manifestUrl })`
  JS-client breaking change recorded in 0.3.0 still applies — see the
  [0.3.0] entry below.

## [0.3.0] - 2026-05-06

### Added

- `TrackRelay::Subscribers::Ahoy` — server-side synchronous subscriber that routes catalog events through `controller.ahoy.track(payload.name.to_s, payload.params)` (Ahoy's only public tracking surface — there is no `Ahoy::Visit#track`). Duck-types `controller.respond_to?(:ahoy, true)` so the gem loads cleanly in non-Ahoy host apps; calls without a controller in scope (background jobs, rake tasks, console) skip-log via `Rails.logger.warn` rather than fabricate a write. Stateless — no constructor args; reads `TrackRelay::Current.controller` directly at deliver time (safe on the synchronous path, mandatory because `payload.context[:controller]` is the controller class name as a String, not the live instance).
- `AhoyJs` named export in `@track_relay/client` — client-side mirror of `Subscribers::Ahoy`. `Object.freeze({ name: "AhoyJs", handle(eventName, params) })` shape matches the existing `Ga4Gtag` export. Validates against the manifest (typed events: dev-throws / prod-warns-and-drops per REQ-05; untyped passes through per REQ-06), then dispatches via `window.ahoy.track(eventName, params)`. Guards on `typeof window.ahoy?.track === "function"` and emits `console.warn` + drops when missing — never throws when `ahoy.js` is absent.
- `ahoy_matey` added as a development dependency in `track_relay.gemspec`. Resolves to 5.4.2 under Rails 7.1 and 5.5.0 under Rails 7.2 / 8.0; lockfiles in `gemfiles/` confirm. The gem is required by the unit/integration test suites only; runtime hosts pull `ahoy_matey` themselves via their own Gemfile.

### Changed (BREAKING)

- `init({ manifestUrl })` no longer requires `measurementId`. Hosts using only `AhoyJs` (no GA4 subscriber in use) can now omit the GA4 measurement ID and call `init({ manifestUrl: "/track_relay_catalog.json" })`. Previously this threw synchronously; now it succeeds and leaves the GA4 dispatch surface dormant (`_flushConfigOnce()` already short-circuits on missing `_measurementId`, so `track()` and `Ga4Gtag.handle()` continue to validate but do not emit `gtag('config', ...)`). Hosts that relied on the missing-`measurementId` throw to detect misconfiguration must migrate — assert their own `measurementId` (or any other host-app-side invariant) before calling `init`. The error message thrown when `manifestUrl` is missing is also reworded to mention `manifestUrl` only.
- `client/src/index.d.ts`: `InitOptions.measurementId` typed as `measurementId?: string` (was required `string`). Existing TypeScript hosts that pass `measurementId` continue to typecheck unchanged; AhoyJs-only hosts can now omit it without a type error.

### Notes

- REQ-09 success criteria mention `Ahoy::Visit#track` as a fallback dispatch path. This method does not exist on `Ahoy::Visit` (the ActiveRecord model). The `Ahoy::Tracker` is the sole public tracking surface, and it is bound to the request lifecycle (it wraps the controller cookie jar / visit auto-create). The Ahoy subscriber therefore routes through `controller.ahoy.track` only; the no-controller skip path (with a `Rails.logger.warn` line) is the substitute for the missing `visit.track` route. See `phases/03-ahoy-subscribers/03-RESEARCH.md` §"The visit.track question" for full rationale.
- Cross-subscriber name parity: server `TrackRelay::Subscribers::Ahoy.name` returns `"TrackRelay::Subscribers::Ahoy"` (Ruby `Class#name`); client `AhoyJs.name` returns `"AhoyJs"`. The names differ but the dispatched event-name strings are byte-identical on both sides — server `payload.name.to_s` → `tracker.track`, client `eventName` → `window.ahoy.track`. REQ-09's "same event names as the server" criterion is about the event-name string, not the subscriber class name.

## [0.2.0] - 2026-05-06

### Added

- `@track_relay/client` v0.2.0 — companion JS package living at `client/` in the repo. Ships dual ESM (`dist/index.mjs`) + real CommonJS (`dist/index.cjs`) builds via `tsup` so both `import "@track_relay/client"` and `require("@track_relay/client")` work; the `package.json` `exports` map points at the built artifacts (not the unbuilt source). Hand-written `src/index.d.ts` documents the public types.
- `init({measurementId, manifestUrl, env, onValidationError})` is the single entry point — both `measurementId` and `manifestUrl` are REQUIRED and the function throws synchronously (not via a rejected promise) when either is nullish or empty-string, so misconfiguration is loud at the call site. The Rails layer is the source of truth: `measurementId` from `TrackRelay.config.ga4_measurement_id`, `manifestUrl` from `asset_path('track_relay_catalog.json')` — wire both via an inline ERB `<script type="module">` block in the layout (see `client/README.md`).
- `track(name, params)` validates against the manifest entry and dispatches via `window.gtag("event", name, params)`. Untyped events pass through unchanged (REQ-06). Missing `window.gtag` warns and drops the event without throwing. `Ga4Gtag.handle(name, params)` is a server-subscriber-shaped wrapper around `track()` for hosts that prefer object dispatch — covers REQ-08's client-side half.
- JS-side validation mirrors REQ-05: `env: "development"` throws on validation failure (missing required, wrong type), `env: "production"` calls `console.warn` and silently drops. The optional `onValidationError(errors)` callback fires before the throw/warn branch so hosts can route errors to a logging pipeline.
- `setClientId(id)` updates the resolved `client_id`; the next `track()` re-emits `gtag("config", measurementId, {client_id})` so GA4 attributes events to the right user. The `config` call fires once per page lifecycle until the client_id changes.
- CI: new `js-test` job in `.github/workflows/ci.yml` runs `npm ci && npm run build && npm test` on Node 22 (build BEFORE test so `build_smoke.test.js` sees a populated `dist/`). Vitest + happy-dom test harness with 31 test cases covering init/track/validation/Ga4Gtag.
- `TrackRelay::Subscribers::Ga4MeasurementProtocol` — async server-side GA4 Measurement Protocol subscriber. POSTs to `https://www.google-analytics.com/mp/collect?measurement_id=...&api_secret=...` with the canonical Scout §2 web-stream body shape (`{client_id, user_id?, timestamp_micros, events: [{name, params}]}`). EU-region toggle via `config.ga4_use_eu_endpoint = true` switches to `region1.google-analytics.com`. Net::HTTP from Ruby stdlib (no new gem dependency). Default 5s open / 10s read timeout. Async-by-default; hosts opt in inline via `Ga4MeasurementProtocol.synchronous!` per REQ-11. When `client_id` is missing from `payload.context`, falls back to a synthesized `<rand>.<unix_ts>` value so server-only events without a `_ga` cookie still post.
- `TrackRelay::DeliveryRetriableError` and `TrackRelay::DeliveryDiscardableError` — typed exceptions raised by `Ga4MeasurementProtocol#deliver` to signal retriable (HTTP 5xx, `Net::OpenTimeout`, `Net::ReadTimeout`, `Errno::ECONNREFUSED`, `SocketError`) vs. permanent (HTTP 4xx — defensive coverage) failures. `DeliveryJob` declares `retry_on TrackRelay::DeliveryRetriableError, wait: :polynomially_longer, attempts: TrackRelay::DeliveryJob::DEFAULT_GA4_DELIVERY_ATTEMPTS` (`= 5`) and `discard_on TrackRelay::DeliveryDiscardableError`. The attempt cap is a class-local constant (NOT `config.ga4_delivery_attempts`) because `retry_on` runs at class-body load time before any host initializer fires — runtime configurability is deferred to a future minor.
- `Subscribers::Base#safe_deliver` carve-out for the typed retry/discard exceptions: those two classes RE-RAISE through the rescue boundary even when `config.swallow_subscriber_errors = true` (the production default). Without this narrow exception to the REQ-23 blanket-rescue, ActiveJob's `retry_on`/`discard_on` macros would never see the typed exceptions because `safe_deliver` would catch them and return them as values. Arbitrary `StandardError`s still flow through the existing log-and-return path — REQ-23's contract is preserved for everything outside the carve-out.
- Configurable `config.ga4_measurement_id` / `config.ga4_api_secret` (read at delivery time so credentials lambdas / late-bound configs work) and `config.ga4_use_eu_endpoint` (default `false`). When either credential is `nil` at delivery time the subscriber emits a single `Rails.logger.warn` and returns — gem-loaded-but-not-configured apps must not crash. `config.ga4_delivery_attempts` is INTENTIONALLY NOT shipped in 0.2.0 (load-order hazard documented above).
- Call-time GA4 payload validation in `Ga4MeasurementProtocol#deliver` (REQ-27 split, call-time half): `payload.params.size <= 25` and param-name reserved-prefix check (`firebase_`, `ga_`, `google_`). Honors `config.raise_on_validation_error` — raises `Ga4ConstraintError` in dev/test, `Rails.logger.warn` + skip-POST in prod. Boot-time event-name validation (snake_case + reserved-name list) is the existing `Validators::Ga4Constraints` check at catalog load — Plan 02-04 does not duplicate it.
- `rake track_relay:lint:ga4` audits the JSONL untyped sink for GA4 event-name violations (snake_case shape, max length, reserved names) and exits non-zero when any are found, so CI can gate on it. The new `TrackRelay::Linter#ga4_violations` and `#print_ga4` methods power the task; both honor the same `untyped_log_path`-must-be-set abort contract as the existing `track_relay:lint` tasks.
- Subscriber-side `only:` / `except:` event-name filters via the `filter` class DSL or the new `TrackRelay.subscribe(klass_or_instance, only:, except:)` registration helper. Filters short-circuit at the top of `Subscribers::Base#handle` BEFORE the sync/async branch and BEFORE `safe_deliver`'s rescue boundary, so a filtered event with a buggy `#deliver` neither runs nor logs. Per-instance overrides on `TrackRelay.subscribe` are stored on the singleton class so they do not mutate either the class-level defaults or other instances of the same subscriber.
- `webmock ~> 3.23` as a development dependency. `test_helper.rb` requires `webmock/minitest` and calls `WebMock.disable_net_connect!(allow_localhost: true)` so HTTP-stubbed subscriber tests (Phase 02 GA4 measurement protocol) can register expected calls without leaking to the live network.
- JSON manifest generation: `rake track_relay:manifest` writes a typed `public/track_relay_catalog.json` (version + `generated_at` + `events: { name => { params: {key => type}, required: [...] } }`) for the `@track_relay/client` JS package to validate events client-side. The task aborts with a nonzero exit when the catalog is empty (RISK-04 footgun guard). The Railtie auto-runs `track_relay:manifest` before `assets:precompile` for production / CI builds and regenerates the file on every `to_prepare` reload in development, so editing `config/track_relay/*.rb` produces a fresh manifest without a server restart. `Manifest.write!` `mkdir_p`s the parent directory so a fresh checkout without a `public/` directory does not crash on first run.
- Configurable `config.client_id_resolvers` chain (`ClientId::Ga`, `ClientId::AhoyVisitor`, `ClientId::Session` defaults). First non-nil wins; resolved once per request inside `ControllerTracking#_resolve_client_id`; resolver exceptions are isolated (each `#call` is wrapped in `rescue StandardError` and logged via `Rails.logger.warn`, so a single buggy resolver cannot block the chain). `ClientId::Ga` reproduces Phase 01's `_ga`-cookie parser bit-for-bit, preserving existing behavior; the new `Session` fallback mints a `SecureRandom.uuid` into `session[:track_relay_client_id]` so visitors without a `_ga` cookie still get a session-stable identifier. Hosts can prepend custom resolvers via `TrackRelay.config.client_id_resolvers.unshift(...)` for native-app traffic, request-header overrides, etc.

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

[1.0.0]: https://github.com/dchuk/track_relay/compare/v0.3.0...v1.0.0
[0.3.0]: https://github.com/dchuk/track_relay/releases/tag/v0.3.0
[0.2.0]: https://github.com/dchuk/track_relay/releases/tag/v0.2.0
[0.1.0]: https://github.com/dchuk/track_relay/releases/tag/v0.1.0
