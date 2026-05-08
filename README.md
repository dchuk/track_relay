# track_relay

Unified, typed event tracking for Rails apps. One catalog, multiple destinations, built on `ActiveSupport::Notifications`.

## Status

**Version:** 1.0.0 (pending release) — public API is being stabilized for the 1.0.0 cut. See [CHANGELOG.md](CHANGELOG.md) for release history and [UPGRADING.md](UPGRADING.md) for migration notes.

## Why

Modern Rails apps that want both marketing analytics (GA4) and product analytics (your DB) end up with two parallel event vocabularies. `track_relay` defines events once in a typed catalog and fans them out to every destination, server-side and client-side, without copy-paste.

## Installation

Add to your Gemfile:

```ruby
gem "track_relay", "~> 1.0"
```

Then `bundle install`.

Then run the install generator to scaffold a working configuration:

```bash
bin/rails generate track_relay:install
bundle exec rake test  # passes cleanly out of the box
```

See [USAGE.md](USAGE.md) for a full walkthrough.

Requires Ruby 3.2+ and Rails 7.1, 7.2, or 8.0.

For client-side tracking, also install the companion JS package:

```bash
npm install @track_relay/client
```

See [GA4 + client-side tracking](#ga4--client-side-tracking) below.

## Quick start

> **Tip:** `bin/rails g track_relay:install` scaffolds the five files below for you. Read on if you'd rather wire them up by hand.

```ruby
# config/initializers/track_relay.rb
TrackRelay.configure do |c|
  c.untyped_log_path = Rails.root.join("tmp/track_relay_untyped.jsonl")
  c.subscribe TrackRelay::Subscribers::Logger.new
end

# config/track_relay/articles.rb
TrackRelay.catalog do
  event :article_viewed do
    integer :article_id, required: true
    string  :slug,       required: true
    string  :category
  end
end

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include TrackRelay::ControllerTracking
end

# app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  def show
    @article = Article.find(params[:id])
    track :article_viewed, article_id: @article.id, slug: @article.slug
    # ...
  end
end
```

That is the full path from `bundle install` to a fired event — five files, no generators required.

## Catalog DSL

Declare events in `config/track_relay/*.rb`. The Railtie autoloads the directory at boot and reloads it on every code reload in development (Zeitwerk-friendly: the directory is explicitly ignored by the autoloader so DSL files never look like constant definitions).

| Type | Example |
|------|---------|
| integer | `integer :count, required: true` |
| string | `string :name, max: 100` |
| float | `float :amount` |
| boolean | `boolean :flag` |
| datetime | `datetime :occurred_at` |

Validators: `required:`, `max:`, `in:`, `format:`, `sanitize:` (callable, runs before validation — no silent truncation). Validation runs at `track` time on the calling thread; failures raise `TrackRelay::ValidationError` when `config.raise_on_validation_error` is true (the default in dev/test).

Each catalog entry produces a `TrackRelay::EventDefinition` (the schema) which is used at `track` time to build a `TrackRelay::EventPayload` (the runtime instance). `EventDefinition` and `EventPayload` are intentionally separate classes so the schema is shareable and immutable across calls while the payload owns the per-call params, context, and timestamp.

### GA4 constraints (applied automatically)

- snake_case event names
- max 40 characters per event name
- max 25 custom params per event
- GA4 reserved names (`page_view`, `session_start`, `screen_view`, etc.) are refused at catalog load with `TrackRelay::Ga4ConstraintError`

### Reserved keys

Four keys are reserved and partitioned out of `params` automatically by `TrackRelay.track`:

- `:user`, `:request`, `:client_id` — bound on `TrackRelay::Current` for the duration of the call (block-scoped via `Current.set`).
- `:visitor_token` — written directly to `payload.context[:visitor_token]`. It is intentionally **not** a `Current` attribute: `Current` carries `:visit` (an Ahoy-style visit record), not a raw token.

Defining any of these four as a catalog param raises `TrackRelay::ReservedKeyError` at boot, so the conflict surfaces before any event is fired.

### Identify

```ruby
TrackRelay.identify(current_user, plan: "pro", country: "US")
```

`identify` is a thin pass-through in 0.1.0: it instruments `track_relay.identify` with `{user:, properties:}` so subscribers can route the user property update wherever they need to. Per-adapter user-property validation (GA4 `user_properties`, etc.) lands in 0.2.0.

## Subscribers

`TrackRelay::Subscribers::Base` is the base class for every subscriber. It exposes a `synchronous!` macro (opts the subclass out of the async `DeliveryJob` path) and a per-subscriber `safe_deliver` rescue that returns the exception instead of re-raising — so one bad subscriber never blocks peers from receiving the event.

```ruby
class MySubscriber < TrackRelay::Subscribers::Base
  synchronous!  # opt out of async DeliveryJob

  def deliver(payload)
    # payload.name, payload.params, payload.context, payload.timestamp
  end
end
```

Async subscribers automatically dispatch via `TrackRelay::DeliveryJob` (an `ActiveJob::Base` subclass). Use Solid Queue, Sidekiq, or any other ActiveJob adapter as your backend.

`TrackRelay::Dispatcher` is the single `ActiveSupport::Notifications` subscription that fans `track_relay.event` notifications out to `config.subscribers`. Its **collect-then-reraise** error contract means: every peer receives the payload, then if `config.swallow_subscriber_errors` is `false` (the default in dev/test), the first collected exception is re-raised after fan-out completes. In production (`swallow_subscriber_errors=true`), exceptions are logged and swallowed so a single broken adapter doesn't take the application down. The Dispatcher is started automatically by the Railtie on `after_initialize`.

Built-in subscribers:

- `Subscribers::Test` — in-memory capture for specs. Per-instance state, no class-level globals.
- `Subscribers::Logger` — writes a one-line summary to `Rails.logger`; appends untyped events to `config.untyped_log_path` JSONL with the canonical shape `{event, params, controller, action, timestamp}` (param NAMES only — values are never written, by design, to avoid leaking PII).

### Ahoy subscriber (server-side)

`TrackRelay::Subscribers::Ahoy` routes events through the host app's
ahoy_matey instrumentation using only the public Ahoy API
(`controller.ahoy.track`). It never calls `Ahoy::Event.create!`
directly.

Requires the `ahoy_matey` gem in your Gemfile. Wire it in the
initializer:

```ruby
TrackRelay.configure do |config|
  config.subscribe TrackRelay::Subscribers::Ahoy.new
end
```

Job-context calls (no controller, no visit) are logged and skipped;
the Ahoy subscriber will never fabricate a write without a real visit.

> **Heads up — Ahoy bot exclusion.** ahoy_matey silently drops events
> from requests whose user-agent doesn't look like a real browser
> (logged as `[ahoy] Event excluded`). If you're smoke-testing via
> `curl` or Postman and no row appears in `ahoy_events`, pass a real
> browser User-Agent header. This is Ahoy's default behavior — see
> ahoy_matey's `exclude_method` config to customize.

### Subscribing directly to AS::Notifications

Because every event is published through `ActiveSupport::Notifications.instrument("track_relay.event", event: payload)`, host apps can subscribe directly without writing a `Subscribers::Base` subclass at all:

```ruby
ActiveSupport::Notifications.subscribe("track_relay.event") do |*, payload|
  Rails.logger.tagged("analytics") { Rails.logger.info(payload[:event].name) }
end
```

This is useful for one-off integrations and for debugging — your existing `ActiveSupport::Notifications` tooling (lograge, the Rails event reporter, etc.) just works.

## Generators

`track_relay` ships three Rails generators.

- `bin/rails g track_relay:install` — opinionated scaffold: richly
  commented initializer (`config/initializers/track_relay.rb`),
  sample catalog (`config/track_relay/sample.rb`),
  ApplicationSubscriber base class
  (`app/track_relay/subscribers/application_subscriber.rb`), and
  `include TrackRelay::ControllerTracking` injected into
  ApplicationController (idempotent — no-ops if the include already
  exists).

- `bin/rails g track_relay:event NAME` — scaffolds a typed catalog
  entry stub at `config/track_relay/<name>.rb` with a
  `TrackRelay.catalog do event :name do ... end end` block. Each
  event lives in its own file; the Railtie merges them at boot.

- `bin/rails g track_relay:subscriber NAME` — scaffolds a subscriber
  class stub at
  `app/track_relay/subscribers/<name>_subscriber.rb`.

See [USAGE.md](USAGE.md) for a full walkthrough.

### Controller and Job helpers

```ruby
class ApplicationController < ActionController::Base
  include TrackRelay::ControllerTracking
  # adds a `track` instance method + a before_action that populates
  # Current.controller / Current.request / Current.client_id (from the _ga cookie)
end

class WelcomeEmailJob < ApplicationJob
  include TrackRelay::JobTracking
  # adds a `track` instance method; use Current.set { ... } block form
  # inside `perform` to populate context (the Rails Executor clears
  # CurrentAttributes before every job, by design).

  def perform(user)
    TrackRelay::Current.set(user: user) do
      track :welcome_email_sent, template_version: "v3"
    end
  end
end
```

## Test helpers

The testing surface is **opt-in**. Add `require "track_relay/testing"` to your `test_helper.rb` (Minitest) or `rails_helper.rb` (RSpec) — `lib/track_relay.rb` does NOT require it automatically, so the `Subscribers::Test` swap and RSpec matchers stay out of production runtime.

`TrackRelay.test_mode!` atomically replaces the configured subscriber list with a single `Subscribers::Test` instance and forces synchronous delivery; `TrackRelay.test_mode_off!` restores the previous list. Tests assert against the captured events without spinning up real adapters or external services.

### Minitest

```ruby
# test/test_helper.rb
require "track_relay/testing"
# OR (just the Minitest helpers)
require "track_relay/testing/helpers"

class MyTest < ActiveSupport::TestCase
  include TrackRelay::Testing::Helpers  # auto test_mode! / test_mode_off! per test

  test "fires article_viewed" do
    get article_path(@article)
    assert_tracked :article_viewed, article_id: @article.id
  end

  test "does not double-fire" do
    refute_tracked :article_viewed, article_id: 99
  end
end
```

### RSpec

```ruby
# spec/rails_helper.rb
require "track_relay/testing"

RSpec.configure do |c|
  c.before(:each) { TrackRelay.test_mode! }
  c.after(:each)  { TrackRelay.test_mode_off! }
end

it "fires outbound_click" do
  click_link "External"
  expect(track_relay).to have_tracked(:outbound_click).with(destination_domain: "example.com")
end
```

The RSpec matchers are loaded only when `RSpec` is already defined, so the gem stays test-framework-agnostic.

## Untyped events + linter

Untyped events (events that aren't in the catalog) are allowed by default — `config.untyped_events_allowed = true` — so teams can adopt the catalog incrementally. Set `config.untyped_log_path` to capture every untyped fire to a JSONL file:

```ruby
TrackRelay.configure do |c|
  c.untyped_log_path = Rails.root.join("tmp/track_relay_untyped.jsonl")
end
```

Then audit with the bundled rake tasks:

```bash
$ bundle exec rake track_relay:lint
# track_relay untyped event audit
# events: 3; total occurrences: 47
event :outbound_click  (32 total)
  - params=[destination_url, link_text, source_path]  count=32
event :search_executed  (12 total)
  - params=[filters, query]  count=12
event :modal_dismissed  (3 total)
  - params=[modal_id]  count=3
```

`bundle exec rake track_relay:lint:json` emits the same data as JSON for consumption by external tooling (Slack notifiers, dashboards, CI gates).

The linter (`TrackRelay::Linter`) dedupes by event name + sorted-param-name signature: two firings of `:outbound_click` with the same param names collapse into one row, while different param shapes count separately so you can spot drift.

If `config.untyped_log_path` is unset, both rake tasks abort with a nonzero exit code and a configuration message — by design, so a misconfigured audit pipeline doesn't silently exit 0.

The JSONL captures only sorted, stringified parameter NAMES (never values) for the same privacy reason.

## GA4 + client-side tracking

0.2.0 ships a complete GA4 path — server-side via `Subscribers::Ga4MeasurementProtocol`, client-side via the [`@track_relay/client`](client/README.md) JS package. They share one catalog and one validation contract.

### Server-side: GA4 Measurement Protocol subscriber

```ruby
# config/initializers/track_relay.rb
TrackRelay.configure do |c|
  c.ga4_measurement_id = ENV.fetch("GA4_MEASUREMENT_ID")
  c.ga4_api_secret     = ENV.fetch("GA4_API_SECRET")
  # c.ga4_use_eu_endpoint = true  # opt-in for EU residency

  # Send all events that need server-side fan-out
  c.subscribe TrackRelay::Subscribers::Ga4MeasurementProtocol.new
end
```

The subscriber POSTs to `https://www.google-analytics.com/mp/collect` with the canonical `{client_id, user_id?, timestamp_micros, events: [{name, params}]}` body. Async-by-default through `TrackRelay::DeliveryJob` (an `ActiveJob::Base` subclass) — typed `DeliveryRetriableError` / `DeliveryDiscardableError` exceptions wire `retry_on :polynomially_longer, attempts: 5` and `discard_on` so 5xx errors retry and 4xx errors are dropped without retrying. Hosts can opt the subscriber into synchronous delivery for in-process consistency: `Ga4MeasurementProtocol.synchronous!`.

When either credential is `nil` at delivery time the subscriber emits a single `Rails.logger.warn` and returns — gem-loaded-but-not-configured apps must not crash.

Subscriber-side filters via `only:` / `except:` keep noisy events out of GA4:

```ruby
TrackRelay.subscribe(
  TrackRelay::Subscribers::Ga4MeasurementProtocol.new,
  only: %i[purchase signup outbound_click]
)
```

### `client_id` resolver chain

`TrackRelay::Current.client_id` is resolved via a configurable chain of `client_id_resolvers`. The default chain checks the GA `_ga` cookie, then any Ahoy visitor token, then mints a session-stable UUID into `session[:track_relay_client_id]` so visitors without a `_ga` cookie still get a stable identifier. First non-nil wins; per-resolver exceptions are isolated so a single buggy resolver cannot block the chain.

```ruby
TrackRelay.configure do |c|
  # Prepend a custom resolver for native-app traffic
  c.client_id_resolvers.unshift(->(req) { req.headers["X-Native-App-Id"] })
end
```

### JSON manifest

`rake track_relay:manifest` writes a typed JSON snapshot of the catalog to `public/track_relay_catalog.json`:

```json
{
  "version": "0.2.0",
  "generated_at": "2026-05-06T12:00:00Z",
  "events": {
    "purchase": {
      "params": {"value": "float", "currency": "string", "coupon": "string"},
      "required": ["value", "currency"]
    }
  }
}
```

The Railtie auto-runs `track_relay:manifest` before `assets:precompile` (production / CI) and regenerates the file on every `to_prepare` reload in development. The manifest is the contract the JS package consumes for client-side validation.

### Client-side: `@track_relay/client`

The JS package fetches the manifest at boot and dispatches events via `window.gtag` after validating against the same typed schema as the server. The Rails layer owns the configuration; the layout wires both `measurementId` and `manifestUrl`:

```erb
<%# app/views/layouts/application.html.erb %>
<script type="module">
  import { init } from "@track_relay/client";
  init({
    measurementId: "<%= TrackRelay.config.ga4_measurement_id %>",
    manifestUrl: "<%= asset_path('track_relay_catalog.json') %>"
  });
</script>
```

Then track events from anywhere in your JS:

```javascript
import { track } from "@track_relay/client";

document.querySelector("#buy-button").addEventListener("click", () => {
  track("purchase", { value: 9.99, currency: "USD" });
});
```

Validation behavior mirrors REQ-05: in development a missing required field or wrong type throws an Error; in production it calls `console.warn` and silently drops the event. Untyped events (not in the manifest) pass through unchanged. See [`client/README.md`](client/README.md) for the full API and the `Ga4Gtag` named export.

## Compatibility

- Ruby 3.2, 3.3, 3.4
- Rails 7.1, 7.2, 8.0
- Test framework: any (gem ships matchers for both Minitest and RSpec; gem itself uses Minitest)

CI runs the full Ruby × Rails matrix (9 combinations) on every push via Appraisal + GitHub Actions.

## Roadmap

### Shipped
- 0.1.0 — Core (catalog DSL, dispatch, Test + Logger subscribers, Minitest/RSpec helpers)
- 0.2.0 — GA4 (server-side Measurement Protocol subscriber, client-side `Ga4Gtag`, JSON manifest)
- 0.3.0 — Ahoy (server-side `Subscribers::Ahoy`, client-side `AhoyJs`)

### Pending release
- 1.0.0 (pending release) — Polish: generators, doc audit, public-API stability guarantee

### Future (post-1.0.0)
- Additional v2 subscribers: PostHog, Mixpanel, Plausible, Webhook, Segment
- Optional engine mount for `/track_relay/events` POST endpoint (ad-blocker resilience)
- Performance benchmarks
- Companion `rubocop-track_relay` cop for raw `gtag` / `ahoy.track` call detection

## Public API stability

As of 1.0.0, the following surface is covered by SemVer guarantees:

- Module entry points: `TrackRelay.track`, `.configure`, `.catalog`,
  `.subscribe`, `.identify`, `.test_mode!`, `.test_mode_off!`
- Subscriber base class and class macros: `TrackRelay::Subscribers::Base`,
  `synchronous!`, `filter only:`, `filter except:`
- Built-in subscribers: `TrackRelay::Subscribers::Test`, `Logger`,
  `Ga4MeasurementProtocol`, `Ahoy`
- Concerns: `TrackRelay::ControllerTracking`, `TrackRelay::JobTracking`
- Test helpers: `TrackRelay::Testing::Helpers`, `assert_tracked`,
  `refute_tracked`
- Catalog DSL keywords (`event`, `integer`, `string`, `float`,
  `boolean`, `datetime`, `user_property`) and validators
  (`required:`, `max:`, `in:`, `format:`, `sanitize:`)
- Generators: `track_relay:install`, `track_relay:event`,
  `track_relay:subscriber`
- Rake tasks: `track_relay:lint`, `track_relay:lint:json`,
  `track_relay:lint:ga4`, `track_relay:manifest`

Internal classes (`TrackRelay::EventPayload`, `Instrumenter`,
`Dispatcher`, `Catalog`, `Current`, `DeliveryJob`, `ClientId::*`)
are not part of the public API contract and may change without a
major version bump.

See [UPGRADING.md](UPGRADING.md) for migration notes from 0.x.

## Contributing

```bash
bundle install
bundle exec rake          # default = standard + test
bundle exec appraisal install   # one-time, generates gemfiles/*.gemfile
```

The test harness boots a minimal Combustion-backed dummy app under `test/internal/`. CI runs Ruby 3.2/3.3/3.4 × Rails 7.1/7.2/8.0 (9 combinations) via Appraisal. Linting uses StandardRB (`bundle exec standardrb`).

## License

MIT — see [LICENSE.txt](LICENSE.txt).
