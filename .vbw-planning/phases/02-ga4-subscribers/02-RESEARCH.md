---
phase: 2
title: "GA4 Subscribers — Phase 02 Research"
type: research
confidence: high
date: 2026-05-06
---

## 1. Existing Gem Surface (Phase 1)

### Top-level entry points (`lib/track_relay.rb`)

| Symbol | Signature | Responsibility |
|--------|-----------|----------------|
| `TrackRelay.track` | `track(name, **params) → void` | Delegates to `Instrumenter.track`; partitions reserved keys, validates, instruments |
| `TrackRelay.identify` | `identify(user, **user_properties) → void` | Thin pass-through to `Instrumenter.identify`; no user_property validation in Phase 1 |
| `TrackRelay.catalog` | `catalog(&block) → void` | Evaluates block against `DSL::EventBuilder`; this is where event definitions are registered |
| `TrackRelay.configure` | `configure { |c| } → Configuration` | Yields the config singleton |
| `TrackRelay.config` | `config → Configuration` | Returns the config singleton |
| `TrackRelay.reset_config!` | `reset_config! → Configuration` | Replaces singleton; used in tests |
| `TrackRelay::GA4_RESERVED_NAMES` | `Array<String>` (37 entries, frozen) | Canonical list already shipped at `lib/track_relay.rb:47-86` |
| `TrackRelay::RESERVED_KEYS` | `%i[user visitor_token client_id request]` | Param names that cannot appear in the catalog |

### Dispatcher (`lib/track_relay/dispatcher.rb`)

| Symbol | Signature | Responsibility |
|--------|-----------|----------------|
| `Dispatcher::NOTIFICATION` | `"track_relay.event"` | The AS::Notifications event name used by both `Instrumenter` and the subscription in `Dispatcher` |
| `Dispatcher.start!` | `start!(notifier = AS::Notifications) → subscription_handle` | Subscribes one block to `"track_relay.event"`; idempotent |
| `Dispatcher.stop!` | `stop!(notifier) → void` | Unsubscribes; idempotent |
| `Dispatcher.dispatch` (private) | `dispatch(payload) → void` | Iterates `config.subscribers`, calls `subscriber.handle(payload)`, collects errors, re-raises first after fan-out if `!swallow_subscriber_errors` |

**Subscribe path today:** `Dispatcher.start!` calls `AS::Notifications.subscribe("track_relay.event") do |*, payload| dispatch(payload[:event]) end` (`dispatcher.rb:42-44`). There is NO `TrackRelay.subscribe(klass, only:, except:)` public method today. Registration of subscriber instances goes through `Configuration#subscribe(subscriber)` which appends to `@subscribers`. Phase 2 needs to add subscriber-side filter support around — or inside — `handle`.

### Subscribers::Base (`lib/track_relay/subscribers/base.rb`)

| Symbol | Signature | Responsibility |
|--------|-----------|----------------|
| `Base.synchronous!` | `class method → true` | Sets `class_attribute :synchronous = true` on the subclass |
| `Base#handle` | `handle(payload) → nil \| StandardError` | Routes to `safe_deliver` (sync) or `DeliveryJob.perform_later` (async). Returns nil on success, StandardError on sync failure |
| `Base#safe_deliver` | `safe_deliver(payload) → nil \| StandardError` | Wraps `deliver` in rescue; logs via `Rails.logger.error`; **never re-raises** |
| `Base#deliver` | `deliver(payload) → void` | Abstract; raises `NotImplementedError` |

**Filter gate placement:** subscriber-side `only:`/`except:` filtering belongs at the TOP of `handle` (`base.rb:56-63`), BEFORE the sync/async branch, and therefore also BEFORE `safe_deliver`'s rescue boundary. The 02-CONTEXT.md decision is: filter inside `handle`, before the rescue. This means if the event is filtered, `handle` returns `nil` immediately without touching `safe_deliver` at all — correct behavior, no error-swallowing ambiguity.

### DeliveryJob (`lib/track_relay/delivery_job.rb`)

| Symbol | Line | Note |
|--------|------|------|
| `queue_as :track_relay` | `delivery_job.rb:27` | Queue name already set; consistent with Phase 2 decision |
| `perform(subscriber_class_name, payload_hash)` | `delivery_job.rb:34-43` | Constantizes the class, calls `EventPayload.from_h`, calls `safe_deliver`, re-raises if `!swallow_subscriber_errors` |
| No `retry_on` / `discard_on` | — | **Not present in Phase 1.** Phase 2 must add these to `DeliveryJob` or to a `Ga4DeliveryJob` subclass |

### Instrumenter (`lib/track_relay/instrumenter.rb`)

| Symbol | Line | Note |
|--------|------|------|
| `NOTIFICATION = "track_relay.event"` | `instrumenter.rb:44` | Used in `ActiveSupport::Notifications.instrument` call |
| `current_context` | `instrumenter.rb:204-215` | Snapshots `Current.*` at instrument time; includes `client_id: Current.client_id`. Async delivery reads from `payload.context`, not Current |
| `CURRENT_ATTR_KEYS = %i[user request client_id]` | `instrumenter.rb:53` | These are extracted from `params` and bound to `Current.set` |
| `DIRECT_CONTEXT_KEYS = %i[visitor_token]` | `instrumenter.rb:57` | Goes straight to `payload.context[:visitor_token]`, not Current |

### Catalog DSL validation (`lib/track_relay/validators/`)

**Boot-time validation path:**
```
TrackRelay.catalog { event :name do ... end }
  → DSL::EventBuilder#event (event_builder.rb:38-50)
    → ParamBuilder accumulates schemas
    → EventDefinition.new(name:, params:, user_properties:)
    → Validators::CatalogValidator.validate!(definition)  ← validation site (catalog_validator.rb:33-45)
      → Ga4Constraints.validate_event_name!(definition.name)  ← snake_case + length + reserved (ga4_constraints.rb:37-54)
      → Ga4Constraints.validate_param_count!(definition.params)  ← ≤25 check (ga4_constraints.rb:57-63)
      → definition.params.each_key → Ga4Constraints.validate_param_name!  ← param shape + length (ga4_constraints.rb:66-82)
    → Catalog.register(definition)
```

Phase 1 already ships name snake_case/length/reserved-name checking AND param-name shape/length checking AND param-count (≤25) checking **at catalog-load time**. The boot-time constraint enforcement for REQ-10 / REQ-27 is **fully implemented** — Phase 2 does NOT need to add any boot-time name validation. The only Phase 2 addition at call-time is: check the **actual number of params being sent** (after dynamic merges) inside `Ga4MeasurementProtocol#deliver`, because the ≤25 catalog check only validates the declared schema, not runtime overruns from dynamic `**extra_attrs`.

### GA4 reserved names constant (`lib/track_relay.rb:47-86`)

Already shipped as `GA4_RESERVED_NAMES` — 37 entries. See Section 2 below for the canonical list including a few web-stream reserved names Phase 1 **did not include** (`ad_impression`, `firebase_*` family, `dynamic_link_*`). These are Firebase/App-stream-only names. For a **web-stream-only** gem targeting standard GA4 web properties, the existing list at `lib/track_relay.rb:47-86` covers the web-stream reserved events. The Lead should decide whether to add the full Firebase set for completeness; the web-only list is defensible for v0.2.0.

### TrackRelay::Current (`lib/track_relay/current.rb:31`)

```ruby
attribute :user, :request, :visit, :controller, :client_id
```

`client_id` is a first-class attribute. It is set by `ControllerTracking`'s `before_action` via `_track_relay_client_id_from_cookie` (`controller_tracking.rb:59,62-72`). The **Phase 1 implementation already parses the `_ga` cookie**: splits on `.`, requires ≥4 segments, returns `parts[-2].#{parts[-1]}` (`controller_tracking.rb:67-71`). Phase 2's configurable resolver chain replaces this hardcoded single-path parse with a first-non-nil chain, but the parsing logic itself is already correct and reusable.

### ControllerTracking concern (`lib/track_relay/controller_tracking.rb`)

- `before_action :_track_relay_set_current` sets `Current.controller`, `Current.request`, `Current.client_id`
- `Current.client_id` is set to the parsed `_ga` cookie value, or `nil`
- Phase 2 must extend `_track_relay_set_current` (or replace it) so it runs the resolver chain instead of the single cookie parse

### Configuration (`lib/track_relay/configuration.rb`)

| Attribute | Default | Note |
|-----------|---------|------|
| `subscribers` | `[]` | Subscriber instances, insertion-ordered |
| `force_synchronous` | `false` | When true, all subscribers go sync |
| `swallow_subscriber_errors` | `production_env?` | Controls re-raise after fan-out |
| `raise_on_validation_error` | `development_or_test_env?` | REQ-05 gate |

Phase 2 must add: `client_id_resolvers`, `ga4_measurement_id`, `ga4_api_secret`, potentially `delivery_queue`.

### Test harness (`test/test_helper.rb`)

- Combustion dummy app at `test/internal/` (`test_helper.rb:24`)
- `Combustion.initialize!(:action_controller, :active_job)` — AR not loaded (`test_helper.rb:25`)
- Queue adapter: `:test` (`test_helper.rb:26`)
- `ActiveSupport::CurrentAttributes::TestHelper` included in `ActiveSupport::TestCase` (`test_helper.rb:33-34`)
- Teardown resets Dispatcher subscription, Catalog, and config (`test_helper.rb:36-43`)
- **webmock is NOT in the gemspec** (`track_relay.gemspec:30-40`). Phase 2 must add `webmock` as a dev dependency for HTTP stubbing in GA4 subscriber tests.

### EventPayload serialization (`lib/track_relay/event_payload.rb`)

- `to_h` → `{name:, params:, context:, timestamp:}` (`event_payload.rb:157-163`)
- `from_h` always returns an untyped payload (definition: nil); validation already happened at track time (`event_payload.rb:75-89`)
- `payload.context[:client_id]` is the snapshotted `Current.client_id` at instrument time — this is what `Ga4MeasurementProtocol` reads for the GA4 `client_id` field

---

## 2. GA4 Measurement Protocol — What to Send

Source: Google MP Reference (https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference?client_type=gtag), validation docs (https://developers.google.com/analytics/devguides/collection/protocol/ga4/validating-events)

### Endpoint

```
POST https://www.google-analytics.com/mp/collect
  ?measurement_id=G-XXXXXXXXXX
  &api_secret=<secret>
Content-Type: application/json
```

EU variant: `https://region1.google-analytics.com/mp/collect`

Debug/validation endpoint: `https://www.google-analytics.com/_debug_/mp/collect` — same params, same payload, returns `{"validationMessages": [...]}` without recording events. Use in dev/test.

### Query parameters

| Param | Required | Source |
|-------|----------|--------|
| `measurement_id` | Yes (web stream) | `G-XXXXXXXXXX` from Admin > Data Streams |
| `api_secret` | Yes | Admin > Data Streams > Measurement Protocol > Create |

Note: Firebase app streams use `firebase_app_id` instead of `measurement_id`. This gem targets web streams only. The API secret is per-stream and must be stored in Rails credentials or env var — never committed.

### Request body shape (web stream)

```json
{
  "client_id": "123456789.1700000000",
  "user_id": "user_42",
  "timestamp_micros": 1700000000000000,
  "non_personalized_ads": false,
  "events": [
    {
      "name": "purchase",
      "params": {
        "value": 9.99,
        "currency": "USD",
        "session_id": "abc123",
        "engagement_time_msec": 100
      }
    }
  ]
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `client_id` | string | Yes | Format: two positive numbers joined by `.` (e.g. `"rand.timestamp"`) |
| `user_id` | string | No | Persistent user identifier; UTF-8 |
| `timestamp_micros` | number | No | Unix timestamp in µs; events backdatable up to 72 hours |
| `non_personalized_ads` | bool | No | GDPR/privacy opt-out signal |
| `events[]` | array | Yes | Max 25 events per POST; for track_relay, always 1 event per POST |
| `events[].name` | string | Yes | Max 40 chars, snake_case |
| `events[].params` | object | No | Max 25 keys; key max 40 chars, value max 100 chars (500 for GA360) |

Payload size limit: 130 kB. For track_relay's single-event-per-call model, this is never a concern.

### GA4 reserved event names — canonical list

Already in `lib/track_relay.rb:47-86` as `GA4_RESERVED_NAMES` (37 names). The complete GA4 docs list includes additional Firebase/App-stream-only names not currently in the constant:

**Web stream reserved (subset — already in constant):**
`click`, `file_download`, `first_visit`, `form_start`, `form_submit`, `page_view`, `scroll`, `session_start`, `user_engagement`, `video_complete`, `video_progress`, `video_start`, `view_search_results`

**App-stream-only (not currently in constant — consider adding for future-proofing):**
`ad_impression`, `dynamic_link_app_open`, `dynamic_link_app_update`, `dynamic_link_first_open`, `firebase_campaign`, `firebase_in_app_message_*`, `fiam_*`, `first_open`, `os_update`, `screen_view`

**Recommendation:** keep the existing constant for v0.2.0 (web-stream-focused). Append app-stream names in Phase 4 or when the gem adds optional Firebase support.

### GA4 reserved parameter names

Cannot use: `firebase_conversion`, or any name beginning with `_`, `firebase_`, `ga_`, `google_`, `gtag.`

The existing `Ga4Constraints::NAME_PATTERN = /\A[a-z][a-z0-9_]*\z/` (ga4_constraints.rb:23) already blocks names starting with `_` and names with dots. It does NOT block names starting with `firebase_`, `ga_`, or `google_` (those would pass the regex). For Phase 2, add a reserved-prefix check inside `Ga4MeasurementProtocol#deliver`'s payload validation, or extend `Ga4Constraints.validate_param_name!` with prefix guards.

### `client_id` format

Format: `"<random_integer>.<unix_timestamp>"` — the last two dot-separated segments of the `_ga` cookie. Example: cookie `GA1.2.860784081.1732738496` → client_id `"860784081.1732738496"`.

As of May 2025, Google has begun rolling out a new `GS2` format for session cookies (`_ga_<measurement_id>`) but the root `_ga` cookie remains in the stable `GA1.N.rand.timestamp` format. Phase 1's parsing logic (`controller_tracking.rb:62-71`) is correct: `parts = cookie.split("."); "#{parts[-2]}.#{parts[-1]}"`. Malformed (< 4 segments) → `nil`.

### Error / retry semantics

- GA4 returns **2xx even on malformed payloads** ("The Measurement Protocol doesn't return an error code if the payload is malformed"). The `validationMessages` array is only returned by the `_debug_` endpoint.
- Auth failure (`api_secret` wrong): GA4 still returns 2xx and silently drops the event. There is NO 4xx for bad credentials.
- Network errors (5xx, `Errno::ECONNREFUSED`, timeouts): these are the only retriable conditions.
- Retry policy implication: standard `retry_on(SocketError, Timeout::Error, Errno::ECONNREFUSED, Net::OpenTimeout)` with `discard_on` for everything else (no value retrying bad payloads since GA4 accepts them anyway).

⚠ REQUIRES AUTHENTICATED LIVE VALIDATION — the actual POST to `https://www.google-analytics.com/mp/collect` with a real `api_secret` and `measurement_id` must be performed in the execute stage (Dev job) to confirm end-to-end delivery. Scout cannot test this.

---

## 3. ActiveJob + DeliveryJob Design

Source: Rails API (https://api.rubyonrails.org/classes/ActiveJob/Exceptions/ClassMethods.html)

### Existing DeliveryJob (Phase 1)

`DeliveryJob` already uses `queue_as :track_relay` (`delivery_job.rb:27`). It has **no `retry_on` or `discard_on`** — Phase 1 relies on the subscriber's `safe_deliver` rescue + the queue backend's own dead-letter behavior.

### Phase 2 design options

**Option A: Add retry/discard to the base `DeliveryJob`.**
Simple, one change. But GA4-specific retry semantics (retry on 5xx, discard on 4xx-equivalent) may not match future subscribers (Ahoy has no HTTP call; Logger has no HTTP call). Pollutes the base job with vendor-specific policy.

**Option B: `Ga4MeasurementProtocol` raises typed exceptions; base `DeliveryJob` declares `retry_on`/`discard_on` per-exception class.**
Cleaner separation. `Ga4MeasurementProtocol#deliver` raises `TrackRelay::DeliveryRetriableError` on 5xx/network and `TrackRelay::DeliveryDiscardableError` on anything else. `DeliveryJob` maps these:

```ruby
class DeliveryJob < ActiveJob::Base
  queue_as :track_relay
  retry_on TrackRelay::DeliveryRetriableError, wait: :polynomially_longer, attempts: 5
  discard_on TrackRelay::DeliveryDiscardableError
  ...
end
```

This keeps retry logic in the subscriber (who knows the semantics) and job-configuration in the job class (where ActiveJob expects it). Recommended.

**Wait algorithm:** `:polynomially_longer` (not `:exponentially_longer` — deprecated alias). Produces ~3s, ~18s, ~83s, ~258s progression with 15% default jitter. This is appropriate for GA4 — no strict ordering requirement, idempotent sends, 72-hour backdating window means late retries still arrive correctly.

**Attempts:** 5 (default). Covers transient infrastructure blips without accumulating indefinitely. Adjust via `config.ga4_delivery_attempts` if the Lead wants it configurable.

### Synchronous opt-in (REQ-11)

Phase 1 already implements this. `Subscribers::Base.synchronous!` sets a class-level flag; `handle` checks `self.class.synchronous || TrackRelay.config.force_synchronous`. The sync path calls `safe_deliver` inline (`base.rb:57-58`). `Subscribers::Test` already calls `synchronous!` (`subscribers/test.rb:25`).

For `Ga4MeasurementProtocol`, the default should be **async** (HTTP call, don't block the request thread). To opt into sync: `Ga4MeasurementProtocol.synchronous!` in the initializer. No new API is needed — the existing `synchronous!` class method covers REQ-11.

### Backend-agnostic patterns

- `DeliveryJob` must NOT set `self.queue_adapter` — that's for the host app to configure
- `queue_as :track_relay` is already set; the host app maps `:track_relay` to a real queue (Sidekiq, Solid Queue, GoodJob) via `config.active_job.queue_name_prefix` or adapter-specific configuration
- Do NOT require `sidekiq` or any specific adapter gem in the gemspec
- For tests: the Combustion harness already sets `queue_adapter: :test` (`test_helper.rb:26`). `assert_enqueued_with(job: DeliveryJob)` works out of the box

---

## 4. ActiveSupport::Notifications Subscriber-Filter Mechanics

Source: Rails API (https://api.rubyonrails.org/classes/ActiveSupport/Notifications.html)

### AS::Notifications API

```ruby
# Subscribe to a specific event name (string, NOT symbol)
subscription = AS::Notifications.subscribe("track_relay.event") do |name, start, finish, id, payload|
  # payload[:event] is the EventPayload instance
end

# Or single-argument form (recommended — less boilerplate):
subscription = AS::Notifications.subscribe("track_relay.event") do |event|
  event.payload[:event]  # EventPayload
end

# Instrument
AS::Notifications.instrument("track_relay.event", event: payload)

# Unsubscribe
AS::Notifications.unsubscribe(subscription)
```

Pattern rules: must be String or Regexp; symbols are not permitted by AS::Notifications.

### Phase 1's instrument name

`Dispatcher::NOTIFICATION = "track_relay.event"` (`dispatcher.rb:32`). This is the **only** instrument name for event tracking. `Instrumenter::NOTIFICATION = "track_relay.event"` (`instrumenter.rb:44`) is the same string — they agree. The subscriber at `dispatcher.rb:42-44` subscribes to this one string.

`Instrumenter::IDENTIFY_NOTIFICATION = "track_relay.identify"` — separate; subscribers are not expected to handle this in Phase 2.

### Subscriber-side filter: two mechanisms

**Mechanism A: Pattern-based subscription** — build a regexp from the `only:` filter list and pass it to `AS::Notifications.subscribe`. E.g. `only: %i[purchase sign_up]` → subscribe to `/track_relay\.event\#(purchase|sign_up)/` with some name encoding. Problem: `instrument("track_relay.event", event: payload)` does not embed the event name in the notification name — it's always `"track_relay.event"`. So pattern filtering would require changing the instrument name to embed the event name (e.g. `"track_relay.event.purchase"`). That is a breaking change to the Phase 1 contract.

**Mechanism B: Subscribe to the broad `"track_relay.event"` pattern; filter inside `Base#handle`** — the `payload.name` (`EventPayload#name`) tells you the event name. `only:`/`except:` are class-level sets stored on the subscriber instance; `handle` returns `nil` immediately if filtered. This is the **correct choice** per 02-CONTEXT.md decision and requires zero changes to the instrument call. Implementation sketch:

```ruby
class Base
  class_attribute :only_events, default: nil    # Set<Symbol> | nil
  class_attribute :except_events, default: nil  # Set<Symbol> | nil

  def handle(payload)
    return nil if filtered?(payload.name)  # <- before rescue boundary
    if self.class.synchronous || TrackRelay.config.force_synchronous
      safe_deliver(payload)
    else
      DeliveryJob.perform_later(self.class.name, payload.to_h)
      nil
    end
  end

  private

  def filtered?(event_name)
    only = self.class.only_events
    except = self.class.except_events
    return false if only.nil? && except.nil?
    return !only.include?(event_name) if only
    except.include?(event_name)
  end
end
```

The `TrackRelay.subscribe(klass, only:, except:)` class-level registration method (which does not yet exist) would call `klass.only_events = Set.new(only)` etc. and then `config.subscribe(klass.new)`. Alternatively, filters can be set in the subscriber class body itself with a `filter only: %i[...]` DSL method.

**Recommendation:** expose both: (a) DSL on the class (`Ga4MeasurementProtocol.filter only: %i[purchase sign_up]`), and (b) override at registration time (`config.subscribe(Ga4MeasurementProtocol.new, only: %i[purchase])`). The instance stores the filter; the class provides defaults.

---

## 5. `_ga` Cookie + client_id Resolver Chain

### `_ga` cookie format

Stable format (pre-May 2025): `GA1.<domain_depth>.<random_int>.<first_visit_unix_ts>`

Example: `GA1.2.860784081.1732738496` → client_id = `"860784081.1732738496"` (last two segments).

As of May 2025, Google began rolling out the `GS2` format for **session-scoped** cookies (`_ga_<measurement_id>`), but the root `_ga` cookie that encodes the client_id remains in `GA1` format. Phase 1's parser at `controller_tracking.rb:62-71` handles this correctly and defensively (requires ≥4 segments, otherwise nil).

Edge cases:
- Missing cookie → `nil` (resolver returns nil, chain continues)
- `_ga` is empty string → `nil` (guard at `controller_tracking.rb:64`)
- `_ga` has `< 4` segments → `nil` (guard at `controller_tracking.rb:69`)
- `_ga` set by a custom server-side cookie writer (not gtag.js) may include extra segments — the `parts[-2].parts[-1]` approach is robust since it always takes the last two segments

### Rails cookie access

```ruby
# Idiomatic — works in controllers and concerns
cookies["_ga"]         # or cookies[:_ga] — both work in Rails
request.cookies["_ga"] # alternative for non-controller contexts (job, middleware)
```

`request.cookie_jar["_ga"]` vs `request.cookies["_ga"]`: for plain string values, `request.cookies` is simpler and doesn't unwrap signed/encrypted cookies. Since `_ga` is a plain unencrypted cookie written by GA's JS, `request.cookies` is correct.

### Resolver chain design

As decided in 02-CONTEXT.md, resolvers are callable objects (`call → String | nil`). Each receives the current request context. Standard resolvers:

**`TrackRelay::ClientId::Ga` (default, position 0)**
```ruby
module TrackRelay
  module ClientId
    class Ga
      def call(controller:, **)
        cookie = controller&.request&.cookies&.dig("_ga")
        return nil if cookie.nil? || cookie.empty?
        parts = cookie.split(".")
        return nil if parts.size < 4
        "#{parts[-2]}.#{parts[-1]}"
      end
    end
  end
end
```

This is nearly identical to Phase 1's `_track_relay_client_id_from_cookie` — extract and reuse.

**`TrackRelay::ClientId::AhoyVisitor` (position 1)**
Ahoy exposes `ahoy` (a controller helper) which provides `ahoy.visit` (the current Ahoy::Visit record). The visit record has `visitor_token`. Idiomatic access from a controller context:

```ruby
def call(controller:, **)
  visit = controller&.respond_to?(:ahoy, true) && controller.ahoy&.current_visit
  visit&.visitor_token
end
```

Note: `ahoy` is available in controllers that include `Ahoy::Trackable` (or the gem's auto-include). If Ahoy is not loaded, `controller.respond_to?(:ahoy, true)` returns false. The `current_visit` method returns an `Ahoy::Visit` record (ActiveRecord model) with a `visitor_token` string attribute. This is the public Ahoy API — no internal `Ahoy::Event.create!` calls.

**`TrackRelay::ClientId::Session` (position 2, fallback)**
```ruby
def call(controller:, **)
  session = controller&.session
  return nil unless session
  session[:track_relay_client_id] ||= SecureRandom.uuid
end
```

Session write is lazy on first miss. Safe across requests (session storage is idempotent). Uses Rails session, so it inherits whatever session storage the host app configures (cookie store, Redis, etc.). No session encryption failure risk since we're writing a plain UUID string.

### Memoizing client_id in TrackRelay::Current

`Current.client_id` is already a first-class attribute (`current.rb:31`). Phase 2's `_track_relay_set_current` callback (`controller_tracking.rb:56-60`) should resolve the chain **once** and assign to `Current.client_id`. `Current` is a `CurrentAttributes` subclass — it auto-resets between requests. No additional memoization layer is needed; the assignment at `before_action` time IS the memoization.

```ruby
def _track_relay_set_current
  TrackRelay::Current.controller = self
  TrackRelay::Current.request = request
  TrackRelay::Current.client_id = _resolve_client_id
end

def _resolve_client_id
  TrackRelay.config.client_id_resolvers.each do |resolver|
    result = resolver.call(controller: self)
    return result if result
  end
  nil
end
```

---

## 6. JSON Manifest Generation + Sprockets Asset Hook

### Where catalog autoloading fires today (Phase 1)

`Railtie` has two relevant initializers (`railtie.rb:35-65`):

1. `"track_relay.catalog_autoload"` — calls `app.config.to_prepare { Catalog.clear!; Dir.glob(...).sort.each { |f| load f } }` (`railtie.rb:45-49`). Fires: once at boot in prod/test, before every reload in dev.

2. `"track_relay.start_dispatcher"` — calls `app.config.after_initialize { Dispatcher.start! }` (`railtie.rb:53-55`). Fires after the app is fully booted.

**Manifest regeneration hook:** For Phase 2, manifest generation must fire after the catalog is loaded. The right trigger is a new Railtie initializer that `enhance`s the `"assets:precompile"` Rake task. At the point `assets:precompile` runs, the Rails environment is fully loaded (catalog populated). The dev-reload hook should use `config.to_prepare` to regenerate on catalog file changes.

### `rake track_relay:manifest`

```ruby
# lib/tasks/track_relay.rake (addition)
namespace :track_relay do
  desc "Generate public/track_relay_catalog.json from the loaded catalog"
  task manifest: :environment do
    require "json"
    output = {
      version: TrackRelay::VERSION,
      generated_at: Time.now.utc.iso8601,
      events: TrackRelay::Catalog.all.each_with_object({}) do |defn, h|
        h[defn.name.to_s] = {
          params: defn.params.transform_values(&:type),
          required: defn.params.select { |_, s| s.required }.keys.map(&:to_s)
        }
      end
    }
    path = Rails.root.join("public", "track_relay_catalog.json")
    File.write(path, JSON.pretty_generate(output))
    puts "[track_relay] manifest written to #{path} (#{TrackRelay::Catalog.all.size} events)"
  end
end
```

When `task manifest: :environment`, Rails has booted and `config.to_prepare` has already run the catalog load — the catalog is populated.

### Sprockets `assets:precompile` hook

```ruby
# In Railtie, a new initializer:
initializer "track_relay.enhance_assets_precompile" do
  if Rake::Task.task_defined?("assets:precompile")
    Rake::Task["assets:precompile"].enhance(["track_relay:manifest"])
  end
end
```

`enhance(["track_relay:manifest"])` inserts `track_relay:manifest` as a **prerequisite** that runs before `assets:precompile`. This is the canonical pattern used by cssbundling-rails, jsbundling-rails, and others.

**Propshaft compatibility:** Propshaft does not use Sprockets, but it does still expose an `assets:precompile` Rake task (inherited from `actionpack`). The same `enhance` works. However, Propshaft serves assets from `app/assets/` and `public/assets/` — writing to `public/track_relay_catalog.json` (not `public/assets/`) means Propshaft does NOT fingerprint it. This is fine for Phase 2: the manifest is a static JSON file at a well-known URL, and the JS client's `init({manifestUrl: ...})` is the cache-busting mechanism. If the Lead wants Sprockets fingerprinting, the manifest must be placed at `app/assets/javascripts/track_relay_catalog.json` and added to `config.assets.precompile`. Recommend: `public/` path for simplicity in Phase 2, revisit for Propshaft fingerprinting in Phase 4.

**Detection pattern:**
```ruby
if defined?(::Sprockets)
  app.config.assets.precompile += %w[track_relay_catalog.json]
end
```

### Dev file watcher

`config.to_prepare` fires on every reload in development when any autoloaded file changes. Since catalog files are in `config/track_relay/**/*.rb` (Zeitwerk-ignored, loaded manually), they do NOT trigger the standard autoload watcher.

Two options:
1. **Add an `ActiveSupport::EventedFileUpdateChecker` on `config/track_relay/**/*.rb`** — the Right Way, but requires wiring at Railtie init time and handling the case where the directory doesn't exist yet.
2. **Regenerate manifest inside `config.to_prepare` always** — simpler: the manifest Rake task can be called directly (not via Rake) as a Ruby method. Since `to_prepare` runs before every request in dev, this adds a file-write on every reload, but that's acceptable (catalog rebuilds are already happening on every reload).

**Recommendation for Phase 2:** regenerate the manifest in `config.to_prepare` in development only (`Rails.env.development?`). Production manifest is written by `assets:precompile`. This is the simplest correct approach.

### Catalog DSL → manifest type mapping

`EventDefinition#params` is a `Hash{Symbol => ParamSchema}`. `ParamSchema` has a `type` attribute (`event_definition.rb:45-59`). Types are `:integer`, `:string`, `:float`, `:boolean`, `:datetime`.

Manifest generation:
```ruby
params: defn.params.transform_values { |s| s.type.to_s }  # {"article_id" => "integer", ...}
required: defn.params.select { |_, s| s.required }.keys.map(&:to_s)
```

The `Catalog.all` method (`catalog.rb:72-74`) returns a frozen array of all `EventDefinition` objects — the manifest task iterates this.

---

## 7. `@track_relay/client` npm Package

Sources: npm dual-package conventions (https://mayank.co/blog/dual-packages/, https://dev.to/snyk/building-an-npm-package-compatible-with-esm-and-cjs-in-2024-88m), Vitest docs (https://vitest.dev/guide/environment)

### Module format decision

**Recommendation: ship plain ESM only** for Phase 2. Reasoning:
- The primary consumer is Rails with importmap-rails (no bundler). importmap works with bare ESM modules.
- Node.js 23+ can `require()` static ESM natively, eliminating the dual-package hazard.
- A CJS build adds a build step complexity not justified for a tiny client package in Phase 2.
- Phase 4 can add CJS if bundler-based Rails apps (Webpack, esbuild) demand it.

If dual ESM+CJS is required (consumer explicitly needs CJS), the minimal `package.json` exports map is:
```json
{
  "type": "module",
  "main": "./dist/cjs/index.cjs",
  "module": "./dist/esm/index.js",
  "types": "./dist/types/index.d.ts",
  "exports": {
    ".": {
      "import": { "types": "./dist/types/index.d.ts", "default": "./dist/esm/index.js" },
      "require": { "types": "./dist/types/index.d.ts", "default": "./dist/cjs/index.cjs" }
    }
  }
}
```

Build tool: `swc` for transpile (fast, no TS required), `tsc --emitDeclarationOnly` for `.d.ts`.

### ESM-only `package.json` (Phase 2 recommendation)

```json
{
  "name": "@track_relay/client",
  "version": "0.2.0",
  "type": "module",
  "description": "Client-side event tracker for track_relay Rails gem",
  "main": "./src/index.js",
  "exports": { ".": "./src/index.js" },
  "files": ["src", "dist"],
  "scripts": {
    "test": "vitest run",
    "build": "echo 'No build step for ESM-only Phase 2'"
  },
  "devDependencies": {
    "vitest": "^3.x",
    "@vitest/browser": "^3.x"
  }
}
```

No TypeScript build step. Plain `.js` with a hand-written `src/index.d.ts`.

### Build target

ES2020 is the safe baseline for Phase 2 (wide browser and Node.js support, no top-level await required). Document in `package.json` `browserslist` or a `jsr.json` note if publishing to JSR in future.

### TypeScript types (REQ-15 deferred to Phase 4)

Ship a hand-written `src/index.d.ts` for the Phase 2 public API:

```typescript
export interface InitOptions {
  manifestUrl: string;
  env?: "development" | "production";
}

export interface TrackOptions {
  [key: string]: string | number | boolean;
}

export function init(options: InitOptions): Promise<void>;
export function track(eventName: string, params?: TrackOptions): void;
export function setClientId(clientId: string): void;
```

No TypeScript compiler needed — ship this `.d.ts` directly as a hand-maintained file.

### Manifest loading pattern

The JS client must fetch the manifest at `init` time. The fingerprinted URL is known only to Rails (Sprockets/Propshaft fingerprint is computed at asset compile time). Rails layout passes it via a `<meta>` tag or inline script:

```erb
<%# app/views/layouts/application.html.erb %>
<script type="module">
  import { init } from "@track_relay/client";
  await init({ manifestUrl: "<%= asset_path('track_relay_catalog.json') %>" });
</script>
```

Or via a `<meta>` tag for importmap consumers:

```erb
<meta name="track-relay-manifest-url" content="<%= asset_path('track_relay_catalog.json') %>">
```

```javascript
// In application.js
import { init } from "@track_relay/client";
const manifestUrl = document.querySelector('meta[name="track-relay-manifest-url"]')?.content;
if (manifestUrl) await init({ manifestUrl });
```

The `meta` tag approach is cleaner for importmap-rails where `application.js` imports happen before the inline `<script type="module">` can reference Rails helpers.

### gtag dispatch

`window.gtag` must exist before `track()` is called. The JS client should check:

```javascript
export function track(eventName, params = {}) {
  if (typeof window.gtag !== "function") {
    console.warn("[track_relay] window.gtag not found — event dropped:", eventName);
    return;
  }
  window.gtag("event", eventName, params);
}
```

The client does NOT inject the gtag script — that's the host app's responsibility (GA snippet in the layout).

### Validation behavior (REQ-05 client-side mirror)

```javascript
let manifest = null;

export async function init({ manifestUrl, env = "production" }) {
  const resp = await fetch(manifestUrl);
  manifest = await resp.json();
  _env = env;
}

export function track(eventName, params = {}) {
  const defn = manifest?.events?.[eventName];
  if (defn) {
    const errors = validateParams(eventName, defn, params);
    if (errors.length > 0) {
      if (_env === "development") throw new Error(`[track_relay] ${errors.join("; ")}`);
      console.warn("[track_relay]", ...errors);
      return;  // drop in production
    }
  }
  if (typeof window.gtag !== "function") { ... }
  window.gtag("event", eventName, params);
}
```

### Test harness recommendation

**Vitest + happy-dom** is the 2025/2026 idiomatic choice for testing a tiny ES module with browser-like globals (`window.gtag`, `fetch`, `document`):

```javascript
// vitest.config.js
export default { test: { environment: "happy-dom" } };
```

Advantages: no bundler needed, fast, ESM-native, minimal config. Running in CI requires Node — Phase 2 must add a `node` step to the GitHub Actions CI matrix (separate job, not inside the Ruby matrix). Example:

```yaml
# .github/workflows/ci.yml addition
js-test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with: { node-version: 22 }
    - run: cd packages/client && npm install && npm test
```

---

## 8. Constraint Enforcement Code Paths (REQ-27)

### Boot-time name validation — already implemented

Path: `TrackRelay.catalog { event :name }` → `DSL::EventBuilder#event` (`event_builder.rb:38`) → `CatalogValidator.validate!` (`catalog_validator.rb:33`) → `Ga4Constraints.validate_event_name!` (`ga4_constraints.rb:37`).

Checks: snake_case regex (`/\A[a-z][a-z0-9_]*\z/`, `ga4_constraints.rb:23`), ≤40 chars (`ga4_constraints.rb:45`), not in `GA4_RESERVED_NAMES` (`ga4_constraints.rb:50`).

**Phase 2 does NOT need to extend this.** The existing boot-time checks are sufficient per the split-enforcement decision in 02-CONTEXT.md.

### Call-time payload validation — new in Phase 2

Location: `Ga4MeasurementProtocol#deliver(payload)`, before the HTTP call. Checks:
1. `payload.params.size <= 25` — guard against dynamic runtime overruns not caught by the catalog schema's ≤25 check
2. Param names do not start with reserved GA4 prefixes (`firebase_`, `ga_`, `google_`) — not covered by `NAME_PATTERN`

Implementation in `Ga4MeasurementProtocol#deliver`:
```ruby
def deliver(payload)
  validate_ga4_payload!(payload)
  # ... build HTTP request, POST to GA4 ...
end

def validate_ga4_payload!(payload)
  if payload.params.size > Validators::Ga4Constraints::MAX_PARAMS_PER_EVENT
    msg = "GA4 payload for #{payload.name.inspect} has #{payload.params.size} params; GA4 max is 25"
    raise Ga4ConstraintError, msg if TrackRelay.config.raise_on_validation_error
    Rails.logger.error("[track_relay] #{msg}")
    return
  end
  # prefix check
  payload.params.each_key do |k|
    as_str = k.to_s
    if as_str.start_with?("firebase_", "ga_", "google_")
      msg = "Param #{k.inspect} on event #{payload.name.inspect} uses a GA4-reserved prefix"
      raise Ga4ConstraintError, msg if TrackRelay.config.raise_on_validation_error
      Rails.logger.warn("[track_relay] #{msg}")
    end
  end
end
```

This follows the REQ-05 pattern: raise in dev/test (`raise_on_validation_error = true`), log in prod.

### Linter extension (REQ-28)

`rake track_relay:lint` today reads the JSONL untyped-event sink (`linter.rb`). Phase 2 extends it to also check GA4 constraint violations on events in the JSONL. The linter already has access to event names; it can call `Ga4Constraints.validate_event_name!(entry["event"])` on each unique event name and report violations. Add a `lint:ga4` subtask or extend the existing report output.

---

## 9. Test-Strategy Notes

### Framework

Phase 1 uses Minitest (REQ-21). No RSpec for gem-internal tests (RSpec matchers are in `lib/track_relay/testing/rspec_matchers.rb` but the gem's own test suite is Minitest-only). Combustion dummy app at `test/internal/` with `:action_controller, :active_job` (`test_helper.rb:25`).

### Testing subscriber dispatch with AS::Notifications

Existing teardown in `ActiveSupport::TestCase` already handles: `Dispatcher.stop!`, `Catalog.clear!`, `TrackRelay.reset_config!` (`test_helper.rb:36-43`). Tests can call `Dispatcher.start!` in setup to wire the subscription, then call `TrackRelay.track(...)` and assert against subscriber state.

For GA4 subscriber tests, the pattern:
```ruby
def setup
  @subscriber = TrackRelay::Subscribers::Ga4MeasurementProtocol.new
  TrackRelay.configure { |c| c.subscribe(@subscriber) }
  TrackRelay::Dispatcher.start!
end
```

### HTTP stubbing for GA4

**webmock is NOT in the gemspec.** Phase 2 must add:
```ruby
spec.add_development_dependency "webmock", "~> 3.23"
```

In `test_helper.rb`:
```ruby
require "webmock/minitest"
WebMock.disable_net_connect!
```

Then stub in tests:
```ruby
stub_request(:post, "https://www.google-analytics.com/mp/collect")
  .to_return(status: 200, body: "{}", headers: {"Content-Type" => "application/json"})
```

### JS test CI step

Phase 1 CI is Ruby-only (`.github/workflows/ci.yml`). Phase 2 must add a `js-test` job (see Section 7). This is a separate job, not inside the Ruby matrix. The JS test job uses `actions/setup-node@v4`.

---

## 10. Risk Register / Open Questions for Lead

**RISK-01: `_ga` cookie GS2 format rollout**
Google is rolling out a new `GS2` format for session cookies (`_ga_<measurement_id>`). The root `_ga` cookie (which encodes client_id) remains `GA1.N.rand.ts` as of Phase 2 research, but Google has not formally committed to this. The current parser (`parts[-2].#{parts[-1]}`) is robust — it always takes the last two segments, which is resilient to prefix segment count changes. However, if Google changes the `_ga` root cookie format, the `ClientId::Ga` resolver will silently produce `nil` (or malformed values). Consider adding a format guard: `return nil unless parts[0] == "GA1" || parts[0] == "GS2"`.

**RISK-02: `api_secret` not rotatable at runtime**
GA4's `api_secret` is read from `TrackRelay.config.ga4_api_secret` (or Rails credentials). The gem does not support live rotation without a Rails restart. For v0.2.0, "restart on rotation" is acceptable — document it. A future improvement would be a lambda-based `config.ga4_api_secret = -> { fetch_from_vault }`, but that's Phase 4 scope.

**RISK-03: importmap-rails ESM module resolution**
Rails importmap-rails works with ESM modules pinned via `config/importmap.rb`. `@track_relay/client` must be pinnable: `pin "@track_relay/client", to: "https://cdn.example.com/@track_relay/client/src/index.js"`. The `fetch()` call for the manifest works in all modern browsers. However, importmap does NOT support top-level `await` in all Safari versions (pre-15.4). Since `init()` returns a Promise, callers must `await init(...)` — document that `<script type="module">` is required and that Safari 15+ is the minimum for top-level await.

**RISK-04: `track_relay:manifest` fails silently with zero events**
If the catalog has zero events (freshly installed gem, no catalog files yet), the manifest task writes an empty events object. The JS client fetches this and silently passes all events (no schema to validate against). The Lead should decide: abort the task if `Catalog.all.empty?` and no `--force` flag, or emit a warning and write the manifest anyway. Aborting loudly is safer during CI.

**RISK-05: Propshaft apps get no fingerprinted manifest URL**
`public/track_relay_catalog.json` is not fingerprinted by Propshaft (which fingerprints assets in `app/assets/`). The JS client receives a static URL with no cache-busting hash. Workaround: the host app sets a long cache TTL on the manifest with an ETag; or uses the version string in the manifest body to invalidate. For Phase 2, document this limitation and recommend Sprockets for apps needing fingerprinting.

**RISK-06: webmock absent from gemspec**
GA4 subscriber tests require HTTP stubbing. Without webmock, the test suite will either make real HTTP calls (flaky, requires network, consumes GA4 quota) or fail. This must be added as a dev dependency in Phase 2 Plan 1.

Sources:
- [GA4 Measurement Protocol Reference](https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference?client_type=gtag)
- [GA4 Measurement Protocol Validation](https://developers.google.com/analytics/devguides/collection/protocol/ga4/validating-events)
- [GA4 Reserved Event Names](https://support.google.com/analytics/answer/9234069)
- [GA4 _ga Cookie Format](https://optimizesmart.com/blog/understanding-google-analytics-4-cookies-_ga-cookie/)
- [ActiveJob Exceptions API](https://api.rubyonrails.org/classes/ActiveJob/Exceptions/ClassMethods.html)
- [ActiveSupport::Notifications API](https://api.rubyonrails.org/classes/ActiveSupport/Notifications.html)
- [Dual ESM+CJS npm packages](https://mayank.co/blog/dual-packages/)
- [Vitest environment (happy-dom)](https://vitest.dev/guide/environment)
- [Ahoy gem controller API](https://github.com/ankane/ahoy/blob/master/README.md)
- [GA4 _ga cookie parser note (GS2 update)](https://www.trkkn.com/insights/ga4-cookie-format-has-changed-what-you-need-to-know-about-ga-measurement-id-and-session-id/)
