---
phase: "01-core-mvp"
title: "Phase 01 Research — Rails Gem Convention Gaps"
type: research
confidence: high
date: "2026-05-06"
---

## Recommendations Summary

1. **Catalog autoload** — use the Rails guides' canonical `config.to_prepare` + `Dir.glob` + `load` pattern, combined with `Rails.autoloaders.main.ignore(catalog_dir)` to keep Zeitwerk out of the way. No third-party dependency.
2. **Minitest dummy app** — use **Combustion** (`test/internal/`) for integration tests, not a hand-rolled `test/dummy`. Ahoy itself uses this pattern. For pure unit tests (EventDefinition, validators, payload building) use plain `Minitest::Test` with no Rails boot at all.
3. **CI matrix** — use **Appraisal** for multi-Rails Gemfiles + `ruby/setup-ruby` with `bundler-cache: true`. No `actions/cache` shim needed. Matrix: Ruby 3.2/3.3/3.4 × Rails 7.1/7.2/8.0 (9 combinations). `BUNDLE_GEMFILE` set at workflow `env:` level.
4. **Subscriber base class** — roll our own `Subscribers::Base` (plain `Notifications.subscribe` block), not `ActiveSupport::Subscriber`. AS::Subscriber dispatches by method name from event name, which is wrong for our single-event-name design. Fan-out via Fanout is already guaranteed by `Notifications`; per-subscriber rescue belongs in our `deliver` wrapper.
5. **CurrentAttributes gotchas** — (a) include `ActiveSupport::CurrentAttributes::TestHelper` in `test_helper.rb` for auto-reset; (b) `JobTracking` must use `Current.set(...)` block form inside `perform` so attributes are re-populated after the Executor's pre-job reset; (c) Puma thread safety is handled by Rails automatically (thread-local storage).
6. **Gem release tooling** — `bundle gem track_relay --test=minitest --linter=standard --ci=github --mit`. StandardRB over RuboCop (zero config, Rails-friendly rule set). `Minitest::TestTask.create` in Rakefile (not deprecated `Rake::TestTask`). `bin/test` is generated automatically.

---

## 1. Railtie + Zeitwerk Autoload Pattern for `config/track_relay/*.rb`

### The problem

`config/` is NOT in Zeitwerk's default autoload paths. Files dropped there are not autoloaded — they need explicit `load` or `require` calls. The gem cannot simply add `config/track_relay/` to `autoload_paths` in the host app because those files contain DSL calls (`TrackRelay.catalog do ... end`), not constant definitions. Zeitwerk would try to infer constant names from filenames and fail.

### Canonical pattern (Rails guides, authoritative)

From Rails 8 Engines guide, section "Overriding Models and Controllers":

```ruby
# In host application's config/application.rb (or in gem's Railtie)
catalog_dir = Rails.root.join("config/track_relay")
Rails.autoloaders.main.ignore(catalog_dir)

config.to_prepare do
  Dir.glob("#{catalog_dir}/**/*.rb").sort.each do |file|
    load file
  end
end
```

Key points:
- `Rails.autoloaders.main.ignore(...)` prevents Zeitwerk from touching the directory at all.
- `config.to_prepare` runs once at boot in production/test and before every request reload in development — exactly the hot-reload behavior wanted.
- `load` (not `require`) forces re-evaluation on every `to_prepare` cycle; `require` would be a no-op on reload.
- `.sort` ensures deterministic load order across platforms.

**Where this lives in the gem**: the Railtie initializer, not the host app. The Railtie must compute `Rails.root.join("config/track_relay")` after Rails is booted:

```ruby
# lib/track_relay/railtie.rb
module TrackRelay
  class Railtie < Rails::Railtie
    initializer "track_relay.configure" do |app|
      catalog_dir = app.root.join("config", "track_relay")
      Rails.autoloaders.main.ignore(catalog_dir) if catalog_dir.exist?

      app.config.to_prepare do
        Dir.glob("#{catalog_dir}/**/*.rb").sort.each do |file|
          load file
        end
      end
    end
  end
end
```

`app.root` is correct here (not `Rails.root`) because the initializer block receives the application object before `Rails.root` is fully reliable.

### Why not `config.autoload_paths`?

Adding `config/track_relay` to `autoload_paths` would make Zeitwerk try to define `TrackRelay::Articles` from `articles.rb`, which is wrong — that file contains DSL calls, not a class definition. The `ignore` + `load` approach is the right separation.

### Prior art

- **Rails guides** (engines chapter) uses this exact `Dir.glob` + `load` inside `config.to_prepare` for engine overrides.
- **paper_trail** Railtie uses `ActiveSupport.on_load` hooks for component setup, not catalog-style loading — not applicable here.
- **ahoy** uses Combustion for tests and a straightforward Railtie for controller/AR integration — no catalog-style loading needed.
- **pghero** loads a YAML-based `file_config` inside an initializer, not Ruby DSL files.

No prior-art gem uses a `config/` Ruby DSL catalog, but the Rails guide pattern is authoritative and well-tested.

---

## 2. Minitest Test Scaffold for a Rails Gem with Railtie Integration

### Recommended layout

```
test/
  test_helper.rb          # single entry point
  internal/               # Combustion's minimal dummy app
    app/
      controllers/
        application_controller.rb
      jobs/
        application_job.rb
    config/
      application.rb      # Combustion fills most of this
      database.yml        # in-memory SQLite
    db/
      schema.rb           # if AR needed; omit if not
    log/
      .keep
  unit/
    catalog_test.rb
    event_definition_test.rb
    event_payload_test.rb
    validators/
      ga4_constraints_test.rb
  integration/
    railtie_test.rb
    controller_tracking_test.rb
    job_tracking_test.rb
    subscribers/
      logger_test.rb
      test_subscriber_test.rb
```

### `test/test_helper.rb` shape

```ruby
# test/test_helper.rb
require "bundler/setup"
require "combustion"

Combustion.path = "test/internal"
Combustion.initialize!(:action_controller, :active_job) do
  config.load_defaults Rails::VERSION::MAJOR.then { |v| "#{v}.0".to_f }
  config.active_job.queue_adapter = :test
  config.logger = ActiveSupport::Logger.new(nil)  # silence in tests
end

require "track_relay"
require "minitest/autorun"

class ActiveSupport::TestCase
  include ActiveSupport::CurrentAttributes::TestHelper

  # Flush the TrackRelay subscriber registry between tests so
  # test_mode!/restore! don't leak state.
  teardown do
    TrackRelay::Config.reset_subscribers! if defined?(TrackRelay::Config)
  end
end
```

**Why Combustion, not hand-rolled `test/dummy`?**

| | Combustion | Manual `test/dummy` |
|---|---|---|
| Setup cost | 1 gem, ~5 lines | Full Rails skeleton, migrations, routes, generators |
| Maintenance | Keep the gem updated | Must track Rails API changes manually |
| Minitest support | Experimental but works (ahoy uses it) | First-class |
| Boot granularity | Choose exactly which railties load | Full Rails stack unless carefully trimmed |
| Flexibility | `Combustion.initialize!(*frameworks)` | app/config/environment.rb |
| 2026 default for small gems | Ahoy (complex gem) uses it — safe bet | Only needed when Combustion doesn't cover a use case |

**Recommendation: Combustion.** `track_relay` doesn't need ActiveRecord (no DB), so `Combustion.initialize!(:action_controller, :active_job)` gives a minimal Rails boot with exactly the components needed. ahoy (a more complex gem) uses this pattern — it's proven.

For pure-unit tests (`EventDefinition`, `EventPayload`, catalog DSL, validators), omit Combustion entirely:

```ruby
# test/unit/event_definition_test.rb
require "test_helper"  # even this is optional for pure-unit
require "track_relay/event_definition"
# plain Minitest::Test, no Rails needed
```

### File naming

`*_test.rb` throughout. `test/**/*_test.rb` glob in Rakefile.

### Testing `ActiveSupport::Notifications.subscribed { }` flows

```ruby
class LoggerSubscriberTest < ActiveSupport::TestCase
  test "logs typed event" do
    events = []
    ActiveSupport::Notifications.subscribed(
      ->(event) { events << event },
      "track_relay.event"
    ) do
      TrackRelay.track(:article_viewed, article_id: 1, article_slug: "foo")
    end

    assert_equal 1, events.size
    assert_equal "track_relay.event", events.first.name
    assert_equal :article_viewed, events.first.payload[:event].name
  end
end
```

`ActiveSupport::Notifications.subscribed` takes a callable + event name, wraps a block, then unsubscribes — zero cleanup needed, no global state leaked.

### Resetting `CurrentAttributes` between tests

Include `ActiveSupport::CurrentAttributes::TestHelper` in the base test class (shown above). This module hooks into Minitest's `before_setup` / `after_teardown` to call `Current.reset` via the Rails Executor, mirroring request-boundary behavior. Without it, attributes set in one test bleed into the next.

**Do not** call `TrackRelay::Current.reset` manually in teardown — the TestHelper does this correctly through executor hooks.

---

## 3. GitHub Actions CI Matrix for Ruby 3.2+ × Rails 7.1/7.2/8.0

### Recommended: Appraisal + ruby/setup-ruby

**`Appraisals` file** (project root):

```ruby
appraise "rails-7.1" do
  gem "rails", "~> 7.1.0"
end

appraise "rails-7.2" do
  gem "rails", "~> 7.2.0"
end

appraise "rails-8.0" do
  gem "rails", "~> 8.0.0"
end
```

Run `bundle exec appraisal install` to generate `gemfiles/rails_7_1.gemfile` etc.

**`.github/workflows/ci.yml`**:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

env:
  BUNDLE_GEMFILE: ${{ github.workspace }}/Gemfile

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        ruby: ["3.2", "3.3", "3.4"]
        appraisal: ["rails-7.1", "rails-7.2", "rails-8.0"]
    env:
      BUNDLE_GEMFILE: ${{ github.workspace }}/gemfiles/${{ matrix.appraisal }}.gemfile
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
      - run: bundle exec appraisal ${{ matrix.appraisal }} rake test

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.4"
          bundler-cache: true
      - run: bundle exec standardrb --no-fix
```

**Key decisions:**

- **`ruby/setup-ruby@v1`** (not `actions/setup-ruby` which is deprecated) with `bundler-cache: true`. The built-in cache handles per-Gemfile gem caching automatically — no manual `actions/cache` needed.
- **`BUNDLE_GEMFILE` at job `env:` level** (not inside `steps:`). Bundler reads this env var before any step runs; setting it in a step is too late.
- **`fail-fast: false`** keeps all 9 matrix combinations running even if one fails — important for cross-version debugging.
- Appraisal gemfiles are committed to version control (`gemfiles/` directory).

**Why Appraisal over sibling Gemfiles?**

Sibling Gemfiles (`Gemfile.rails-7.1`) require hand-managing the base gem deps in each file. Appraisal inherits from the root `Gemfile` automatically, so only the Rails version line differs. The `appraisal install` / `appraisal update` workflow keeps everything in sync. Paper Trail uses Appraisal this way across Rails 7.1/7.2/8.0/8.1.

**No `rails-controller-testing` needed** — track_relay has no controller tests that need `assigns`; all controller testing goes through integration-style request flows with Combustion.

---

## 4. `ActiveSupport::Notifications` Subscriber Base Class Pattern

### Should we use `ActiveSupport::Subscriber`?

**No.** `ActiveSupport::Subscriber` (the built-in class) dispatches by extracting the event-name prefix before the `.` and calling `send(method_name, event)`. This is designed for namespace-based subscriptions like `sql.active_record` → `sql` method. For track_relay, all events share one notification name (`track_relay.event`), and each subscriber has a single `receive(event)` method. Using `AS::Subscriber` would require every subscriber to define a method named `track_relay` — ugly and wrong.

### Roll our own `Subscribers::Base`

```ruby
# lib/track_relay/subscribers/base.rb
module TrackRelay
  module Subscribers
    class Base
      class_attribute :synchronous, default: false

      def self.synchronous!
        self.synchronous = true
      end

      # Called by Railtie to wire this subscriber into Notifications.
      def self.subscribe!(notifier = ActiveSupport::Notifications)
        notifier.subscribe("track_relay.event") do |event|
          new.handle(event.payload[:event])
        end
      end

      # Override in subclasses.
      def deliver(payload)
        raise NotImplementedError
      end

      # Called by the subscription block. Wraps deliver with rescue.
      def handle(payload)
        if self.class.synchronous || TrackRelay.config.force_synchronous?
          safe_deliver(payload)
        else
          TrackRelay::DeliveryJob.perform_later(self.class.name, payload.to_h)
        end
      end

      private

      def safe_deliver(payload)
        deliver(payload)
      rescue StandardError => e
        Rails.logger.error(
          "[track_relay] subscriber=#{self.class.name} failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        )
        raise if TrackRelay.config.raise_on_subscriber_errors?
      end
    end
  end
end
```

### How AS::Notifications fan-out actually works

From `activesupport/lib/active_support/notifications/fanout.rb` (verified):

- `Fanout` stores subscribers in `@string_subscribers` (exact name match) and `@other_subscribers` (regex/nil).
- On publish, `all_listeners_for(name)` merges both sets via a `Concurrent::Map` cache.
- `iterate_guarding_exceptions` iterates ALL subscribers; if one raises, the exception is **collected but execution continues** for remaining subscribers. After all run, exceptions are re-raised (single → raise directly; multiple → `InstrumentationSubscriberError`).
- **This means**: if track_relay only has one `subscribe("track_relay.event")` block (the gem's single fan-out entry point), exceptions inside that block will propagate. We need our own per-subscriber rescue **inside** the subscription block, not relying on Fanout's exception guarding.
- The architecture above (each subscriber `safe_deliver` wrapping its own `deliver`) is correct — the outer `subscribe` block iterates configured subscribers; the inner rescue isolates failures.

### How to thread subscriber name through payload

Pass it in the `EventPayload` itself:

```ruby
# When instrumenting in TrackRelay.track:
ActiveSupport::Notifications.instrument("track_relay.event", event: payload)
# payload is an EventPayload which knows its definition name
```

Inside `safe_deliver`, `payload.definition.name` gives the event name. For the logger error line, `self.class.name` gives the subscriber identity. No extra metadata needed in the notification payload.

### Why not one `subscribe` block per subscriber?

One could register each subscriber directly: `Notifications.subscribe("track_relay.event") { |event| subscriber.handle(event.payload[:event]) }`. This is fine and simpler. The single-entry-point approach (one block that iterates `TrackRelay.config.subscribers`) is also fine and makes test_mode! swapping easier (swap the subscriber list, not the notification subscription). Either works; the planning doc's `config.subscribe(...)` API implies the single-entry approach.

---

## 5. `ActiveSupport::CurrentAttributes` Gotchas in Gems

### Test isolation

**Include `ActiveSupport::CurrentAttributes::TestHelper` in `ActiveSupport::TestCase`** (shown in Target 2). This module was added to Rails specifically for this problem. It hooks into `before_setup` / `after_teardown` via the Executor to reset all `CurrentAttributes` instances around each test, replicating request-boundary behavior.

Without it: attributes set in test A bleed into test B. The bug is subtle — tests pass in isolation but fail in specific orderings.

Source: `activesupport/test/current_attributes_test.rb` in Rails source uses exactly this include pattern.

**Do not** use `teardown { TrackRelay::Current.reset }` — this calls `reset` but doesn't run the Executor lifecycle callbacks, which can leave `resets { }` callbacks in a wrong state.

### Background jobs — the critical gotcha

ActiveJob wraps every `perform` with a Rails Executor. **The Executor calls `CurrentAttributes.clear_all` before the job runs.** This means any `Current.user` set in the controller (request A) is gone by the time `DeliveryJob#perform` runs, even in inline queue mode.

**Implication for `DeliveryJob`**: the job cannot rely on `TrackRelay::Current` being populated. It receives a `payload_hash` (serialized `EventPayload#to_h`) that already contains the context data (user_id, visitor_token, client_id) captured at `track` time. The job reconstructs a payload from the hash, not from Current.

**Implication for `JobTracking`**: `include TrackRelay::JobTracking` adds a `track` helper that calls `TrackRelay.track(...)`. Before calling `track`, the job should populate `Current.set(user: user, ...) { track ... }` using the block form of `Current.set`, which restores previous values after the block. This is the right pattern because `JobTracking#track` fires synchronously inside the job's `perform`, so Current is populated for the duration.

```ruby
# Example JobTracking usage (from planning doc)
def perform(user)
  TrackRelay::Current.set(user: user, visitor_token: user.last_visitor_token) do
    track :welcome_email_sent, template_version: "v3"
  end
end
```

The reserved-key extraction in `TrackRelay.track` sets `Current` from the call args before instrumenting — this also works, as long as it happens inside the same thread before `instrument` fires.

### Thread safety in Puma

`CurrentAttributes` uses `Thread.current[current_instances_key]` for storage (verified in source). Puma runs each request in its own thread. Between requests, the Executor calls `clear_all`, which iterates all `CurrentAttributes` subclasses and resets their thread-local instances. This is automatic — no gem-side work needed.

**Exception**: Ractors. Ruby 3+ Ractors do not share thread-local storage at all, but Puma uses threads, not Ractors. Not a concern for Phase 1.

### Rails 8 fiber isolation mode (issue #48279)

Rails 8 introduced optional fiber-level isolation for `CurrentAttributes`. If an app enables this (`config.active_support.isolation_level = :fiber`), `Current` is fiber-local rather than thread-local. Solid Queue uses fibers. For track_relay, this means: if a subscriber spawns fibers internally, `Current` won't be visible in the child fiber. The gem should document this. Phase 1 has no fiber-spawning subscribers (Logger and Test are synchronous), so this is a Phase 2/3 concern (GA4 async subscriber).

---

## 6. Gem Release Tooling

### `bundle gem` invocation

```bash
bundle gem track_relay \
  --test=minitest \
  --linter=standard \
  --ci=github \
  --mit \
  --changelog
```

This generates:
- `track_relay.gemspec` — `required_ruby_version = ">= 3.2"` to add manually
- `Rakefile` with `Minitest::TestTask.create` (not the deprecated `Rake::TestTask` form)
- `test/test_helper.rb` — minimal, no Rails boot (add Combustion manually)
- `test/track_relay_test.rb` — scaffold test file
- `.github/workflows/main.yml` — basic CI (replace with appraisal matrix)
- `.standard.yml` — StandardRB config file
- `bin/console`, `bin/setup` — standard gem scripts
- `CHANGELOG.md`, `LICENSE.txt`, `README.md`

**No `bin/test` is generated by `bundle gem`**. Add it manually:

```bash
#!/usr/bin/env ruby
# bin/test
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rake"
Rake.application.init
Rake.application.load_rakefile
Rake["test"].invoke
```

Or just use `bundle exec rake test` directly; `bin/test` is a convenience wrapper Rails apps have, but many gems skip it.

### StandardRB vs RuboCop

**Use StandardRB.** Rationale:
- Zero config — no `.rubocop.yml` to maintain. `.standard.yml` only needs Rails-specific overrides if wanted.
- StandardRB 1.x is built on RuboCop; switching later is a one-line gemspec change.
- Rails 7+ internal cops are included in `rubocop-rails` but StandardRB covers the most-used subset already.
- The `bundle gem --linter=standard` path generates correct `.standard.yml` and gemspec dev dependency.

If Rails-specific cop coverage is wanted later, add `standard-rails` gem (a StandardRB plugin for RuboCop Rails cops) without abandoning StandardRB.

### Rakefile shape (Minitest::TestTask)

The generated Rakefile uses `Minitest::TestTask.create` (available since Minitest 5.16+):

```ruby
require "minitest/test_task"
require "standard/rake"

Minitest::TestTask.create(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.warning = false
  t.test_globs = ["test/**/*_test.rb"]
end

task default: %i[standard test]
```

`Minitest::TestTask.create` is preferred over `Rake::TestTask` because it supports parallel test execution and has better Minitest integration. `warning = false` suppresses Ruby warning noise from upstream gems in the test matrix.

### Appraisal in gemspec

Add to `track_relay.gemspec`:

```ruby
spec.add_development_dependency "appraisal"
spec.add_development_dependency "combustion", "~> 1.3"
```

`combustion` 1.3+ supports Rails 8.0. Pin to `~> 1.3` to avoid breaking changes; check the combustion changelog when upgrading Rails CI targets.

### `.github/workflows/ci.yml` default target

The generated `main.yml` from `bundle gem --ci=github` runs only `bundle exec rake` (which hits `default` task = standard + test). Replace it with the Appraisal matrix from Target 3. Keep the generated workflow as a basis but restructure the `test` job.
