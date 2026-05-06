# Gem Plan: `track_relay` (Revised)

A Rails gem for unified, typed event tracking that fans out to multiple destinations from a single source-of-truth catalog, built on Rails instrumentation primitives.

> **Revision note:** This plan was revised after a code review. Major architectural change: `ActiveSupport::Notifications` is now the internal event bus. Adapters are subscribers. Several abstractions removed in favor of Rails primitives. Naming kept as `track_relay` pending availability check; treat naming as a final-step decision.

## Problem statement

Modern Rails apps that want both marketing-style analytics (GA4 UI, search console integration, demographic cohorts) and product-style analytics (SQL-queryable event store for ranking algorithms, recommendation systems, internal dashboards) end up with two parallel, drifting event vocabularies. An `outbound_click` in GA4 might be `link_clicked` in Ahoy. Property names diverge. Six months in, the data sources can't be reconciled.

Existing solutions miss this niche:

- **Segment** solves multi-destination but requires a paid third-party routing layer and doesn't write to your own database.
- **ga_events** is GA-only and unmaintained.
- **ahoy_matey** is excellent but single-destination (your DB).
- **Custom facades** (the thoughtbot pattern) get rewritten in every project. None is extracted as a gem.

`track_relay` fills the gap: a typed event catalog defined once, dispatched through `ActiveSupport::Notifications` to many subscribers, with first-class GA4 + Ahoy support and a pluggable subscriber interface for everything else.

## Core design principles

1. **Catalog is the value proposition, instrumentation is the runtime.** The catalog is what justifies the gem's existence (single source of truth, validation, GA4-compat). But the runtime flow is `ActiveSupport::Notifications`-first: track → instrument → subscribers. The catalog is metadata that gates and enriches notification payloads.
2. **GA4 constraints win.** The catalog enforces GA4's stricter naming and parameter rules so any event can flow to GA4 without surprise.
3. **Symmetric server and client tracking.** Events fired in Ruby and events fired in JavaScript share the same catalog, exposed to JS as a JSON manifest at build time.
4. **Adapters are passive subscribers, not part of a custom dispatcher.** Subscribers can be `track_relay`-provided, app-provided, or third-party.
5. **Fail-safe.** Tracking errors never break user flow. Validation errors raise in development, log in production. No silent mutation.
6. **Adoption-friendly.** Untyped events allowed (with linter warning) so teams can incrementally formalize their catalog.
7. **Test-first ergonomics.** Built-in test subscriber that captures events for RSpec/Minitest assertions.

## Architecture

```
                ┌───────────────────────────────────────────┐
                │ TrackRelay.catalog (Ruby)                 │
                │  - event definitions (EventDefinition)    │
                │  - param schemas                          │
                │  - validation rules                       │
                │  - GA4 user_property opts                 │
                └────────────────────┬──────────────────────┘
                                     │
                ┌────────────────────▼──────────────────────┐
                │ TrackRelay.track(name, **params)          │
                │  - validate against catalog               │
                │  - coerce/normalize                       │
                │  - enrich from CurrentAttributes          │
                │  - build EventPayload                     │
                │  - instrument                             │
                └────────────────────┬──────────────────────┘
                                     │
                                     ▼
            ┌────────────────────────────────────────────────────┐
            │ ActiveSupport::Notifications.instrument(           │
            │   "track_relay.event", event: payload              │
            │ )                                                  │
            └─────┬────────────┬──────────────┬───────────┬──────┘
                  │            │              │           │
           ┌──────▼──┐  ┌──────▼─────┐  ┌─────▼──────┐  ┌─▼────────┐
           │ GA4 sub │  │ Ahoy sub   │  │ Test sub   │  │ App sub  │
           │ (built) │  │ (built)    │  │ (test env) │  │ (custom) │
           └─────────┘  └────────────┘  └────────────┘  └──────────┘
```

The `TrackRelay::Dispatcher` from the original plan is gone. `ActiveSupport::Notifications` is the bus. Subscribers register themselves; adapter classes are just thin wrappers that subscribe and translate.

## Public API

### Defining the catalog (multi-file from day one)

```ruby
# config/initializers/track_relay.rb
TrackRelay.configure do |config|
  config.environment = Rails.env
  config.raise_on_validation_error = Rails.env.development? || Rails.env.test?
  config.untyped_events_allowed = true   # default true, linter warns

  # Subscribers (adapters)
  config.subscribe TrackRelay::Subscribers::Ga4MeasurementProtocol.new(
    measurement_id: Rails.application.credentials.dig(:ga4, :measurement_id),
    api_secret: Rails.application.credentials.dig(:ga4, :api_secret)
  )
  config.subscribe TrackRelay::Subscribers::Ahoy.new
end
```

```ruby
# config/track_relay/articles.rb
TrackRelay.catalog do
  event :article_viewed do
    integer :article_id,    required: true
    string  :article_slug,  required: true
    string  :category
  end
end
```

```ruby
# config/track_relay/links.rb
TrackRelay.catalog do
  event :outbound_click do
    string :destination_url,    required: true
    string :destination_domain, required: true
    string :link_text,          max: 100
    string :source_path,        required: true
    string :source_section
  end
end
```

```ruby
# config/track_relay/users.rb
TrackRelay.catalog do
  event :sign_up do  # GA4 recommended event name
    string :method, in: %w[email google github]
    string :plan
  end

  user_property :user_plan,     :string
  user_property :signup_cohort, :string
end
```

Catalog files are auto-loaded from `config/track_relay/**/*.rb` via Zeitwerk-style discovery in the Railtie.

### Untyped events (incremental adoption)

```ruby
# Works without catalog definition, but logs a warning in dev
track :some_event, foo: "bar"
```

A linter task (`rake track_relay:lint`) reports all untyped events seen in production logs (via the logger subscriber) so you can formalize them later.

### Firing events from Ruby

The installer generator adds this line to `ApplicationController`:

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include TrackRelay::ControllerTracking
end
```

Then:

```ruby
class ArticlesController < ApplicationController
  def show
    @article = Article.find(params[:id])
    track :article_viewed,
      article_id: @article.id,
      article_slug: @article.slug,
      category: @article.category
  end
end
```

`track` validates against the catalog, enriches from `TrackRelay::Current` (request, user, visit, GA client_id), and instruments. Subscribers handle the rest.

For background jobs:

```ruby
class WelcomeEmailJob < ApplicationJob
  include TrackRelay::JobTracking

  def perform(user)
    UserMailer.welcome(user).deliver_now
    track :welcome_email_sent,
      user: user,                    # reserved key, sets TrackRelay::Current.user
      visitor_token: user.last_visitor_token,  # reserved key, for attribution
      template_version: "v3"         # regular event param
  end
end
```

Reserved keys (`user`, `visitor_token`, `client_id`, `request`) are extracted into `TrackRelay::Current` for the duration of the call; everything else is a param.

### Module-level call (no controller/job context)

```ruby
TrackRelay.track(:welcome_email_sent, template_version: "v3", user: user)
```

Same semantics as the helpers. Useful from rake tasks, services, or anywhere outside controllers/jobs.

### Setting user properties

```ruby
TrackRelay.identify(current_user,
  user_plan: current_user.plan,
  signup_cohort: current_user.created_at.strftime("%Y-%m")
)
```

This emits a `track_relay.identify` notification that subscribers handle (GA4 sets `user_properties`, Ahoy stores attribution on the visit).

### Firing events from JavaScript

JS reads from a generated JSON manifest at `public/track_relay_catalog.json` (or wherever asset config dictates):

```javascript
import { track, identify } from "track_relay/client"

track("outbound_click", {
  destination_url: link.href,
  destination_domain: new URL(link.href).hostname,
  link_text: link.innerText.slice(0, 100),
  source_path: window.location.pathname
})
```

The JS package is published separately to npm (`@track_relay/client`) and works with importmap, esbuild, vite, or jsbundling-rails. It validates against the JSON manifest at runtime and dispatches to configured client-side targets (gtag.js, ahoy.js, custom).

The Rake task `rake track_relay:manifest` regenerates the JSON. Railtie hooks it to run after assets are precompiled.

### Test helpers

```ruby
# spec/rails_helper.rb
require "track_relay/testing"

RSpec.configure do |config|
  config.include TrackRelay::Testing::Helpers
  config.before(:each) { TrackRelay.test_mode! }
end

# In a spec
it "fires outbound_click on external link" do
  visit article_path(article)
  click_link "External Source"

  expect(track_relay).to have_tracked(:outbound_click)
    .with(destination_domain: "example.com")
end
```

`test_mode!` swaps in a test subscriber that captures events in-memory; matchers query that capture.

## Built-in subscribers (v1)

### `TrackRelay::Subscribers::Ga4MeasurementProtocol`

Server-side. POSTs to `https://www.google-analytics.com/mp/collect`. Handles:

- Client ID derivation from `_ga` cookie via `TrackRelay::Current.client_id`, fallback to Ahoy visitor_token, fallback to a random session-bound ID
- Async dispatch via `TrackRelay::DeliveryJob.perform_later(payload)`
- No custom retry/batching/buffering. ActiveJob and the underlying queue handle that.
- GA4 constraint validation as a defense-in-depth check (catalog should already enforce, but never trust the upstream)

### `TrackRelay::Subscribers::Ahoy`

Server-side. Calls `TrackRelay::Current.controller.ahoy.track(name, params)` when in a request, or `TrackRelay::Current.visit&.track(name, params)` from a job context with explicit visitor_token. **Uses Ahoy public APIs only**, no `Ahoy::Event.create!` or other internal poking. If a job has no controller and no visit, the subscriber logs and skips rather than fabricating a write.

### `TrackRelay::Subscribers::Test`

In-memory capture for specs. Resets per-example.

### `TrackRelay::Subscribers::Logger`

Logs every event via `Rails.logger` (configurable). Useful in development and for the linter (parses logs to find untyped events).

### `TrackRelay::Subscribers::Ga4Gtag` (client-side, in JS package)

Wraps `window.gtag('event', name, params)`. Auto-handles user_property propagation when `identify` is called.

### `TrackRelay::Subscribers::AhoyJs` (client-side, in JS package)

Wraps `window.ahoy.track(name, params)`.

## Future subscribers (v2+)

- `TrackRelay::Subscribers::PostHog` (server + client)
- `TrackRelay::Subscribers::Mixpanel`
- `TrackRelay::Subscribers::Plausible`
- `TrackRelay::Subscribers::Segment`
- `TrackRelay::Subscribers::Webhook`

Note: no `ActiveSupport::Notifications` subscriber needed because the system already uses it. Apps can subscribe directly to `track_relay.event` notifications without going through the gem.

## Validation rules (catalog DSL)

| Constraint    | Example                                        | Behavior                                                              |
|---------------|------------------------------------------------|-----------------------------------------------------------------------|
| Type          | `integer :count`                               | Coerces if possible, raises in dev/test, logs in production          |
| Required      | `string :url, required: true`                  | Raises in dev/test, logs in production if missing                    |
| Max length    | `string :text, max: 100`                       | **Raises** by default (no silent truncation)                         |
| Sanitizer     | `string :text, max: 100, sanitize: ->(v){ v.truncate(100) }` | Explicit sanitization, runs before validation               |
| Inclusion     | `string :method, in: %w[a b c]`                | Raises/logs on mismatch                                              |
| Format        | `string :slug, format: /\A[a-z]/`              | Raises/logs on mismatch                                              |
| GA4 reserved  | (automatic on event name)                      | Refuses GA4 reserved names like `page_view` for custom events        |
| GA4 character | (automatic)                                    | Enforces snake_case, max 40 chars, alphanumeric + underscore         |
| Param count   | (automatic)                                    | Caps custom params at 25 per event for GA4 compatibility             |

Type DSL: `integer`, `string`, `float`, `boolean`, `datetime`. Mirrors ActiveModel attributes / migration syntax. No silent mutation anywhere; sanitizers are opt-in and explicit.

## Object model

Two distinct concepts, separated from day one:

- **`TrackRelay::EventDefinition`**: the catalog entry. Schema, validation rules, metadata. Static, defined at boot.
- **`TrackRelay::EventPayload`**: a runtime instance. Carries the validated/coerced params, context (user, visit, client_id, timestamp), and a reference to its definition.

Subscribers receive `EventPayload`. They never touch `EventDefinition` directly except to read metadata.

## Context: `TrackRelay::Current`

Built on `ActiveSupport::CurrentAttributes`:

```ruby
class TrackRelay::Current < ActiveSupport::CurrentAttributes
  attribute :user, :request, :visit, :controller, :client_id
end
```

`ControllerTracking` and `JobTracking` populate this around their tracking calls. The `track` helper reads from it to enrich payloads. Subscribers read from it for adapter-specific needs (e.g. GA4 needs `client_id`, Ahoy needs `controller` or `visit`).

This replaces all the manual context threading from the original plan.

## Async delivery

```ruby
class TrackRelay::DeliveryJob < ApplicationJob
  queue_as :track_relay

  def perform(subscriber_class, payload_hash)
    subscriber_class.constantize.new.deliver(payload_hash)
  end
end
```

That's it. No retry abstraction, no buffering, no batch flushing. ActiveJob (with Solid Queue or Sidekiq) handles all of that. If a subscriber wants synchronous delivery, it overrides:

```ruby
class MySubscriber < TrackRelay::Subscribers::Base
  synchronous!
end
```

## Generators

```bash
rails g track_relay:install
```

Creates:
- `config/initializers/track_relay.rb`
- `config/track_relay/.keep` (empty directory for catalog files)
- Adds `include TrackRelay::ControllerTracking` to `ApplicationController` directly (one line, no extra Tracking concern indirection)

```bash
rails g track_relay:event articles/article_viewed article_id:integer article_slug:string category:string
```

Creates `config/track_relay/articles.rb` with the event definition, or appends if it exists.

```bash
rails g track_relay:subscriber posthog
```

Scaffolds a subscriber class.

## File layout

```
track_relay/
├── lib/
│   ├── track_relay.rb                         # Main module, configure, track entry point
│   ├── track_relay/
│   │   ├── version.rb
│   │   ├── catalog.rb                         # Multi-file loader, registry
│   │   ├── event_definition.rb                # Schema metadata (was event.rb)
│   │   ├── event_payload.rb                   # Runtime instance
│   │   ├── current.rb                         # CurrentAttributes
│   │   ├── configuration.rb
│   │   ├── controller_tracking.rb             # `track` helper for controllers
│   │   ├── job_tracking.rb                    # `track` helper for jobs
│   │   ├── delivery_job.rb                    # ActiveJob for async subscribers
│   │   ├── manifest.rb                        # JSON manifest generator
│   │   ├── railtie.rb                         # Catalog autoload, hooks
│   │   ├── testing.rb                         # Test subscriber + helpers
│   │   ├── linter.rb                          # Untyped event audit
│   │   ├── dsl/
│   │   │   ├── event_builder.rb               # event do ... end DSL
│   │   │   └── param_builder.rb               # integer/string/etc DSL
│   │   ├── subscribers/
│   │   │   ├── base.rb                        # Subscription, sync/async, deliver()
│   │   │   ├── ga4_measurement_protocol.rb
│   │   │   ├── ahoy.rb
│   │   │   ├── test.rb
│   │   │   └── logger.rb
│   │   └── validators/
│   │       ├── ga4_constraints.rb
│   │       └── catalog_validator.rb
├── lib/generators/track_relay/
│   ├── install/
│   ├── event/
│   └── subscriber/
├── lib/tasks/track_relay.rake                 # manifest, lint
├── client/                                    # JS package, published separately to npm
│   ├── package.json                           # @track_relay/client
│   ├── src/
│   │   ├── index.js                           # track(), identify()
│   │   ├── manifest.js                        # JSON manifest loader/validator
│   │   └── subscribers/
│   │       ├── ga4_gtag.js
│   │       └── ahoy_js.js
├── spec/
├── README.md
├── CHANGELOG.md
└── track_relay.gemspec
```

Note: no `engine.rb`. Railtie only.

## Dependencies

Hard:
- `rails` (>= 7.1, given current LTS landscape)
- `activejob` (in Rails)

Optional (only loaded if a subscriber that needs them is configured):
- `ahoy_matey` for the Ahoy subscriber
- `net/http` (stdlib) for the GA4 Measurement Protocol subscriber

No `dry-schema`, no `dry-validation`, no `httparty`. Validation is hand-rolled and small. HTTP is stdlib.

## Implementation phases

### Phase 1: Core (MVP, ~1 weekend)

- Catalog DSL with type-keyword syntax (`integer`, `string`, etc.)
- Multi-file catalog autoloading via Railtie
- `EventDefinition` and `EventPayload` separation
- `TrackRelay::Current` via `ActiveSupport::CurrentAttributes`
- `TrackRelay.track`, `ControllerTracking`, `JobTracking`
- Internal instrumentation via `ActiveSupport::Notifications`
- Built-in subscribers: `Test`, `Logger`
- RSpec/Minitest matchers
- Untyped-events-allowed mode + linter rake task
- Tests, README
- Releasable as 0.1.0

This validates the API shape against engineered.at before building real adapters.

### Phase 2: GA4 subscribers (~2 days)

- `Ga4MeasurementProtocol` server subscriber with async delivery
- `Ga4Gtag` client subscriber in `@track_relay/client` npm package
- JSON manifest generation (Rake task + Railtie hook)
- Documentation
- Releasable as 0.2.0

### Phase 3: Ahoy subscribers (~1 day)

- `Ahoy` server subscriber (public API only)
- `AhoyJs` client subscriber
- Documentation
- Releasable as 0.3.0

### Phase 4: Polish (ongoing)

- Generators for install, events, subscribers
- More built-in subscribers (PostHog, Plausible, Webhook)
- Optional engine mount for a `/track_relay/events` POST endpoint (ad-blocker resilience)
- Rubocop cop or custom linter rule that flags raw `gtag(...)` and `ahoy.track(...)` calls
- Performance benchmarks
- 1.0.0

## Open design questions

Reduced from the original plan since several were resolved by the review.

1. **Naming.** Validate `track_relay` on RubyGems before 1.0. Cheap to rename pre-1.0.

2. **JS package distribution.** Publish to npm as `@track_relay/client` separately from the Ruby gem? Or ship JS in `app/javascript/` for importmap consumers and skip npm? Probably both: importmap-friendly distribution from the gem itself, npm package for esbuild/vite users. Decide after Phase 1.

3. **Untyped event linter UX.** What's the right way to surface "you have 47 untyped events in production logs from the last 7 days" — a rake task, a Rails console method, an exportable report? Lean toward rake task with optional CSV/JSON output.

4. **Privacy / GDPR.** Should the gem ship with built-in IP masking, DNT respect, consent gating? Lean toward yes for opt-in, off by default, configurable per-subscriber.

5. **Multi-tenant catalogs.** Some apps want different catalogs per tenant. v1 punts on this. v2 if there's demand.

6. **Subscriber ordering / dependencies.** When subscribers run in order (notifications fan out roughly sequentially), should there be a way to declare ordering? E.g. "Ahoy runs before GA4 so we can put the Ahoy visit_id in the GA4 payload." Probably yes, via an `after:` option on subscribe. Decide in Phase 2 when the need actually emerges.

## Risks and non-goals

**Non-goals:**
- This is not an event-sourcing framework. Use `rails_event_store` for that.
- This is not a replacement for Ahoy or GA4. It's a coordination layer above them.
- This is not a Segment competitor.
- This is not a generic instrumentation library. It's analytics-flavored, with GA4 constraints baked in. Use raw `ActiveSupport::Notifications` for non-analytics instrumentation.
- This is not an integration framework. No Turbo helpers, no ActionCable hooks, no ActiveRecord callbacks in v1. Add them only if real use cases demand.

**Risks:**
- **Catalog drift** if developers bypass it. Mitigation: untyped mode allowed but linter nags. Custom Rubocop cop in Phase 4 for raw `gtag` / `ahoy.track` calls.
- **Ahoy API changes.** Mitigation: public API only, integration tests against multiple Ahoy versions in CI.
- **GA4 spec changes.** Mitigation: validation rules versioned, test against documented constraints.
- **Niche audience.** Acceptable. This is a tool for me first, others second.

## Success criteria

1. Adding a new event type is a small change in one catalog file plus one `track :name, params` call. No copy-paste between GA4 and Ahoy implementations.
2. Both GA4 and Ahoy show the event with identical names and parameter shapes.
3. A new project can install it, configure it, and start tracking in under 15 minutes.
4. Removing a subscriber is a one-line config change. Adding a new destination is a one-class subscriber.
5. Tests assert on tracked events without hitting any external service.
6. The runtime is debuggable via standard Rails instrumentation tooling (because we use `ActiveSupport::Notifications`).
7. Apps can subscribe to `track_relay.event` notifications themselves without forking the gem.
