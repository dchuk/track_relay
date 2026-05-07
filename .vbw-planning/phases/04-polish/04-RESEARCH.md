---
phase: "04-polish"
title: "Phase 4 Research — Generators, Docs, Integration Test"
type: research
confidence: high
date: 2026-05-06
---

# Phase 4 Research

## Existing gem surface

### Core public API the install generator must wire up

**`TrackRelay.configure` — config keys** (`lib/track_relay/configuration.rb:53-61`)
- `subscribe(subscriber)` — append a subscriber instance
- `swallow_subscriber_errors` — bool, default: `true` in prod, `false` in dev/test
- `untyped_events_allowed` — bool, default: `true`
- `untyped_log_path` — Pathname/String or nil; drives Logger JSONL + lint tasks
- `force_synchronous` — bool; test-mode override
- `raise_on_validation_error` — bool, default: `true` in dev/test
- `ga4_measurement_id` — string or nil
- `ga4_api_secret` — string or nil
- `ga4_use_eu_endpoint` — bool, default: `false`
- `client_id_resolvers` — ordered array; default `[ClientId::Ga, ClientId::AhoyVisitor, ClientId::Session]`

**Catalog DSL** (`lib/track_relay/dsl/event_builder.rb`, `lib/track_relay/dsl/param_builder.rb`)
- Entry point: `TrackRelay.catalog do ... end` (called inside `config/track_relay/*.rb` files)
- Types: `integer`, `string`, `float`, `boolean`, `datetime`
- Validators: `required:`, `max:`, `in:`, `format:`, `sanitize:`
- Top-level: `user_property :name, :type`
- Example idiom for catalog file:
  ```ruby
  TrackRelay.catalog do
    event :article_viewed do
      integer :article_id, required: true
      string  :slug,       required: true
    end
  end
  ```

**Controller concern** (`lib/track_relay/controller_tracking.rb:42`)
- Module name: `TrackRelay::ControllerTracking`
- Provides: `before_action :_track_relay_set_current` + `track(name, **params)` instance method
- NOT auto-included; host apps must `include TrackRelay::ControllerTracking` in `ApplicationController`

**Railtie behavior** (`lib/track_relay/railtie.rb`)
- Ignores `config/track_relay/` from Zeitwerk autoloading
- `config.to_prepare`: `Catalog.clear!` then `Dir.glob("config/track_relay/**/*.rb").sort.each { load }`
- `config.after_initialize`: `Dispatcher.start!`
- Dev: auto-regenerates `public/track_relay_catalog.json` on every reload if catalog is non-empty
- Production: chains `track_relay:manifest` before `assets:precompile`

**Subscribers available for wiring in initializer**
- `TrackRelay::Subscribers::Test` — in-memory capture, synchronous, `events`/`find`/`clear!` API
- `TrackRelay::Subscribers::Logger` — Rails.logger + optional JSONL sink; synchronous
- `TrackRelay::Subscribers::Ga4MeasurementProtocol` — async HTTP, needs `ga4_measurement_id` + `ga4_api_secret`
- `TrackRelay::Subscribers::Ahoy` — synchronous, needs controller with ahoy present

**Testing surface** (`lib/track_relay/testing.rb`, `lib/track_relay/testing/helpers.rb`)
- `TrackRelay.test_mode!` / `TrackRelay.test_mode_off!`
- `TrackRelay::Testing::Helpers` — Minitest mixin; auto `setup`/`teardown` for test mode
- `assert_tracked :name, **params` / `refute_tracked :name`

**Rake tasks** (`lib/tasks/track_relay.rake`)
- `track_relay:lint` — audit untyped JSONL (requires `untyped_log_path`)
- `track_relay:lint:json` — same as JSON
- `track_relay:lint:ga4` — GA4-constraint audit; exits non-zero on violations
- `track_relay:manifest` — writes `public/track_relay_catalog.json`

**Gemspec** (`track_relay.gemspec`)
- Gem name: `track_relay`
- Current version: `0.3.0` (`lib/track_relay/version.rb:4`)
- Runtime dependency: `rails >= 7.1`
- Gem files include `lib/**/*` + `README.md CHANGELOG.md LICENSE.txt` — generators under `lib/generators/` will be auto-included

**Reserved constants**
- `TrackRelay::RESERVED_KEYS = %i[user visitor_token client_id request]`
- `TrackRelay::GA4_RESERVED_NAMES` — 37-item frozen Array of Strings

**Module path for the controller concern:**
```ruby
include TrackRelay::ControllerTracking
```
(The README uses `TrackRelay::ControllerTracking` at line 53. The module name in source is `module ControllerTracking` inside `module TrackRelay`. `lib/track_relay/controller_tracking.rb:42`.)

---

## Combustion harness inventory

### What is already booted

`test/test_helper.rb:25` boots Combustion with:
```ruby
Combustion.initialize!(:action_controller, :active_job) do
  config.active_job.queue_adapter = :test
  config.logger = ActiveSupport::Logger.new(IO::NULL)
end
```
- **ActiveController** and **ActiveJob** only — no ActiveRecord, no DB, no Solid Queue
- `queue_adapter = :test` — all DeliveryJob enqueues are captured in-process, never executed inline unless `force_synchronous = true`
- Dummy app root: `test/internal/`

### What exists in `test/internal/`

**`test/internal/app/controllers/application_controller.rb`**
```ruby
class ApplicationController < ActionController::Base
  include TrackRelay::ControllerTracking
end
```
The `ControllerTracking` concern is already wired in.

**`test/internal/app/controllers/articles_controller.rb`**
```ruby
class ArticlesController < ApplicationController
  def show
    track :article_viewed, article_id: params[:id].to_i, slug: "test-slug"
    head :ok
  end
end
```

**`test/internal/config/routes.rb`**
```ruby
Rails.application.routes.draw do
  get "/articles/:id", to: "articles#show", as: :article
end
```

**No `config/initializers/` directory** — confirmed absent. No `config/track_relay/` directory in `test/internal/` — catalog is defined inline in each test's `setup` block (see `test/integration/controller_tracking_test.rb:22`).

**No DB** — no `test/internal/db/schema.rb`, consistent with `:action_controller` + `:active_job` only boot.

### Existing integration test pattern

`test/integration/controller_tracking_test.rb` — the only existing integration test. Key characteristics:
- Inherits `ActionDispatch::IntegrationTest`
- Calls `TrackRelay.catalog do ... end` in `setup` to register the catalog entry needed by the test
- Subscribes directly to `ActiveSupport::Notifications` to capture events (`@subscription`)
- Does NOT use `TrackRelay.test_mode!` — instead uses raw AS::Notifications subscription
- Does NOT use `Rails::Generators::TestCase`
- Teardown: `ActiveSupport::Notifications.unsubscribe(@subscription)` + global `TrackRelay::Catalog.clear!` / `TrackRelay.reset_config!` (from `ActiveSupport::TestCase` base teardown in `test_helper.rb:43-49`)

### State mutation analysis for generator tests

Generator tests will need to:
1. Write `config/initializers/track_relay.rb` into `test/internal/`
2. Write `config/track_relay/sample.rb` into `test/internal/`
3. Possibly inject `include TrackRelay::ControllerTracking` into `test/internal/app/controllers/application_controller.rb` (though it already exists there)
4. Write a subscriber file somewhere in `test/internal/app/`

**The `ControllerTracking` include already exists in `test/internal/app/controllers/application_controller.rb`**, so the generator's inject step needs to be idempotent or skipped there.

**Recommended clean-state pattern:**
Use `Rails::Generators::TestCase` with a **tmpdir destination**, NOT `destination Rails.root` (which would mutate `test/internal/` permanently). Specifically:
```ruby
destination File.expand_path("../../tmp/generator_test", __dir__)
setup :prepare_destination
```
`prepare_destination` removes and recreates the tmpdir before each test. This gives a clean empty Rails-app skeleton per test without touching the live Combustion harness.

For the ONE E2E happy-path test, a different approach is needed (see "Test plan recommendations" section).

---

## README / CHANGELOG / doc state

### README (`README.md`) — inventory

**Present:**
- Status badge (stale — says "0.2.0 — adds…" but gem is now 0.3.0)
- Why section
- Installation section (with `gem "track_relay", "~> 0.2.0"` — stale version pin)
- Quick start (5-file example)
- Catalog DSL (types table, validators, GA4 constraints, reserved keys)
- `identify` section
- Subscribers section (`Base`, `Test`, `Logger`, async, direct AS::Notifications)
- Controller and Job helpers
- Test helpers (Minitest + RSpec, `test_mode!`, `assert_tracked`, `refute_tracked`)
- Untyped events + linter section
- GA4 + client-side tracking section (server-side subscriber, `client_id` resolver chain, JSON manifest, client-side JS)
- Compatibility matrix
- Roadmap (outdated — lists 0.3.0 and 0.4.0 as future, but 0.3.0 is already shipped)
- Contributing section
- License

**Missing for 1.0.0:**
- No mention of the Ahoy subscriber (`TrackRelay::Subscribers::Ahoy`)
- No mention of generators (`track_relay:install`, `track_relay:event`, `track_relay:subscriber`) — roadmap says "0.4.0" but Phase 4 ships them as 1.0.0
- Roadmap section needs complete rewrite for 1.0.0 state
- Status/badge section shows wrong version (0.2.0)
- Installation section references `"~> 0.2.0"` — must update to `"~> 1.0"`
- No link to a getting-started guide / `doc/usage.md`
- No public-API stability statement
- No migration notes reference

### CHANGELOG (`CHANGELOG.md`) — inventory

**Present and in Keep-a-Changelog format:**
- `[0.3.0] - 2026-05-06` — Added (Ahoy subscriber + AhoyJs), Changed BREAKING (`init({manifestUrl})` no longer requires `measurementId`)
- `[0.2.0] - 2026-05-06` — comprehensive Added list
- `[0.1.0] - 2026-05-06` — comprehensive Added list
- `[Unreleased]` section — currently empty

**Missing for 1.0.0:**
- `[1.0.0]` entry does not exist yet
- No public-API stability statement in any entry
- The `[Unreleased]` section needs to become `[1.0.0]` when the version bumps
- Version links at the bottom go to GitHub release tags; need a `[1.0.0]` link added

### Breaking change from 0.3.0 (migration notes needed)

The CHANGELOG `[0.3.0]` "Changed (BREAKING)" section (`CHANGELOG.md:19-20`) documents:
> `init({ manifestUrl })` no longer requires `measurementId`. Hosts that relied on the missing-`measurementId` throw to detect misconfiguration must migrate — assert their own `measurementId` before calling `init`.

This is a **JS-side breaking change** affecting `@track_relay/client` consumers.

### doc/ and USAGE.md state

- `doc/` directory does **not exist**
- `USAGE.md` does **not exist**
- A getting-started guide must be created from scratch
- The quick-start example in `README.md` is the closest existing content to extract from

---

## Generator conventions (Devise / ActiveAdmin / Spree)

### File layout under `lib/generators/`

Standard convention (Devise, ActiveAdmin, Spree, Rails itself):
```
lib/generators/
  <gem_name>/
    install/
      install_generator.rb
      templates/
        initializer.rb     # ERB template for config/initializers/<gem>.rb
        sample_catalog.rb  # (track_relay-specific)
    event/
      event_generator.rb
      templates/
        event.rb           # catalog DSL stub
    subscriber/
      subscriber_generator.rb
      templates/
        subscriber.rb      # subscriber class stub
```

Each generator file must be named `<name>_generator.rb` and define a class in the `TrackRelay::Generators` namespace.

### Base classes

- `Rails::Generators::Base` — for install-style generators that create files but don't require a name argument. Used by Devise's `InstallGenerator`.
- `Rails::Generators::NamedBase` — for generators that take a NAME argument (e.g. `rails g track_relay:event article_viewed`). Used by Devise's `DeviseGenerator` (model generation).

**For track_relay:**
- `track_relay:install` → `Rails::Generators::Base` (no NAME argument)
- `track_relay:event NAME` → `Rails::Generators::NamedBase` (NAME becomes the event name)
- `track_relay:subscriber NAME` → `Rails::Generators::NamedBase` (NAME becomes the subscriber class name)

### Template directory

```ruby
source_root File.expand_path("templates", __dir__)
```
ERB templates in the `templates/` subdirectory are rendered via `template "foo.rb", "config/initializers/foo.rb"`. Static copies use `copy_file`.

### Key generator action methods (from Rails `generators/actions.rb`)

- `template(source, destination)` — renders an ERB template from `source_root` and writes to `destination` in the app
- `initializer(filename, data)` — creates `config/initializers/<filename>`
- `inject_into_file(destination, code, before:, after:)` / `insert_into_file` — inserts a string into an existing file at a specified anchor
- `inject_into_class(file, class_name, code)` — injects code inside a named class body (Thor shorthand around `inject_into_file`)
- `route(routing_code)` — appends to `config/routes.rb`
- `create_file(path, content)` — creates a file with given content
- `directory(source, destination)` — copies a whole directory of templates

### ApplicationController injection pattern

Devise and ActiveAdmin-style gems use `inject_into_file` (or `inject_into_class`) to add an include to `ApplicationController`. The standard anchor pattern:
```ruby
inject_into_class "app/controllers/application_controller.rb",
  "ApplicationController",
  "  include TrackRelay::ControllerTracking\n"
```
This inserts the include at the top of the `ApplicationController` class body. It is **not idempotent** by default — must guard with a `gsub_file` check or accept the duplicate include. The preferred pattern for opinionated generators (Devise-style) is to include it unconditionally and document that hosts must remove duplicates manually.

### Non-interactive (no prompts) convention

Opinionated 1.0.0 generators (Devise `install`, ActiveAdmin `install`) do NOT use `ask` or `yes?` interactive prompts. All decisions are baked in. Any post-install instructions are emitted via `say` + `readme "INSTALL.md"` at the end of the generator.

### `desc` convention

```ruby
desc "Creates a TrackRelay initializer, sample catalog, and sample subscriber in your Rails app."
```
One sentence describing what the generator produces.

---

## What the install generator must emit

`rails g track_relay:install`

Generator class: `TrackRelay::Generators::InstallGenerator < Rails::Generators::Base`  
File: `lib/generators/track_relay/install/install_generator.rb`  
Source root: `lib/generators/track_relay/install/templates/`

**Files created:**

| Destination path | Template | Description |
|---|---|---|
| `config/initializers/track_relay.rb` | `initializer.rb.tt` | Richly commented initializer; see content shape below |
| `config/track_relay/sample.rb` | `sample_catalog.rb.tt` | Working sample catalog using typed DSL idiom |
| `app/track_relay/subscribers/application_subscriber.rb` | `application_subscriber.rb.tt` | Working ApplicationSubscriber subclassing Subscribers::Base |

**File modified:**

| File | Method | Injection |
|---|---|---|
| `app/controllers/application_controller.rb` | `inject_into_class` | `  include TrackRelay::ControllerTracking\n` |

**Note:** `test/internal/app/controllers/application_controller.rb` already has `include TrackRelay::ControllerTracking`. The generator must guard against double-inclusion. Recommended: wrap with `unless_in_source_root?(...)` check or use `gsub_file` with a content guard before injecting. Alternative: document it in a post-install message and skip the inject.

### `config/initializers/track_relay.rb` content shape

```ruby
# TrackRelay configuration
# See https://github.com/dchuk/track_relay for full documentation.

TrackRelay.configure do |config|
  # ----- Subscribers --------------------------------------------------------
  # Subscribe to the built-in Logger subscriber to log every event to
  # Rails.logger and capture untyped events to a JSONL file for audit.
  config.subscribe TrackRelay::Subscribers::Logger.new

  # Log untyped (non-catalog) events to a JSONL file so you can audit
  # them with `bundle exec rake track_relay:lint`.
  # config.untyped_log_path = Rails.root.join("tmp/track_relay_untyped.jsonl")

  # Subscribe to the Test subscriber in test environment (captures events
  # in memory; TrackRelay.test_mode! is the recommended approach in tests).
  # config.subscribe TrackRelay::Subscribers::Test.new if Rails.env.test?

  # ----- GA4 Measurement Protocol ------------------------------------------
  # config.ga4_measurement_id = ENV.fetch("GA4_MEASUREMENT_ID", nil)
  # config.ga4_api_secret     = ENV.fetch("GA4_API_SECRET", nil)
  # config.subscribe TrackRelay::Subscribers::Ga4MeasurementProtocol.new

  # ----- Ahoy (server-side) -------------------------------------------------
  # config.subscribe TrackRelay::Subscribers::Ahoy.new

  # ----- Catalog behavior ---------------------------------------------------
  # Raise on untyped events (not in the catalog). Default: allow them.
  # config.untyped_events_allowed = false

  # In production, subscriber errors are swallowed and logged (default).
  # In development/test, they are re-raised after fan-out (default).
  # Override:
  # config.swallow_subscriber_errors = false
end
```

### `config/track_relay/sample.rb` content shape

```ruby
# frozen_string_literal: true

# Sample catalog — define your events here.
# The Railtie autoloads all *.rb files under config/track_relay/ at boot
# and reloads them on every code reload in development.
#
# Run `rails g track_relay:event NAME` to scaffold a new event.

TrackRelay.catalog do
  # Example: a typed event with required and optional params.
  event :page_view_example do
    string  :path,       required: true  # e.g. request.path
    string  :referrer                    # optional
    integer :user_id                     # optional; use reserved :user key instead for GA4
  end
end
```

### `app/track_relay/subscribers/application_subscriber.rb` content shape

```ruby
# frozen_string_literal: true

# ApplicationSubscriber — base class for your custom subscribers.
#
# Subclass this to add your own destinations. Register via:
#
#   TrackRelay.configure do |config|
#     config.subscribe MySubscriber.new
#   end
#
# Or:
#   TrackRelay.subscribe(MySubscriber, only: %i[purchase sign_up])
#
# Run `rails g track_relay:subscriber NAME` to scaffold a subscriber.
class ApplicationSubscriber < TrackRelay::Subscribers::Base
  # synchronous!  # uncomment to run inline instead of via DeliveryJob

  def deliver(payload)
    # payload.name      => :event_name (Symbol)
    # payload.params    => { key: value, ... } (typed and coerced)
    # payload.context   => { controller:, action:, client_id:, user:, ... }
    # payload.timestamp => Time
    raise NotImplementedError, "#{self.class.name} must implement #deliver(payload)"
  end
end
```

**Subscriber file path convention:** `app/track_relay/subscribers/` — this is established by convention in the `test/internal/` dummy app's existing structure if any, and aligns with the Ahoy subscriber's directory. However since no convention currently exists in `test/internal/`, the Lead should decide. Two options:
- `app/track_relay/subscribers/` — gem-namespaced, clearly owned by track_relay
- `app/subscribers/` — shorter, Rails-conventional

Open question: see "Open questions" section.

---

## What the event/subscriber generators must emit

### `track_relay:event NAME`

Generator class: `TrackRelay::Generators::EventGenerator < Rails::Generators::NamedBase`  
File: `lib/generators/track_relay/event/event_generator.rb`  
Source root: `lib/generators/track_relay/event/templates/`

**Files created:**

| Destination | Template | Description |
|---|---|---|
| `config/track_relay/<file_name>.rb` | `event.rb.tt` | Catalog DSL stub for the named event |

`file_name` is the `NamedBase`-provided snake_case conversion of NAME (e.g. `ArticleViewed` → `article_viewed`).

**Template content shape:**
```ruby
# frozen_string_literal: true

TrackRelay.catalog do
  event :<%= file_name %> do
    # integer :id,    required: true
    # string  :label, required: true
    # string  :category
    # float   :value
    # boolean :active
  end
end
```

**Note:** each `config/track_relay/*.rb` file gets its own `TrackRelay.catalog do ... end` block. The Railtie's `Dir.glob` + `load` loads each file independently. Do NOT append to an existing file — create one file per event. The Railtie merges all files into the single `Catalog` singleton at boot.

### `track_relay:subscriber NAME`

Generator class: `TrackRelay::Generators::SubscriberGenerator < Rails::Generators::NamedBase`  
File: `lib/generators/track_relay/subscriber/subscriber_generator.rb`  
Source root: `lib/generators/track_relay/subscriber/templates/`

**Files created:**

| Destination | Template | Description |
|---|---|---|
| `app/track_relay/subscribers/<file_name>_subscriber.rb` | `subscriber.rb.tt` | Subscriber class stub |

**Template content shape:**
```ruby
# frozen_string_literal: true

# <%= class_name %>Subscriber — custom track_relay subscriber.
#
# Register in config/initializers/track_relay.rb:
#
#   TrackRelay.configure do |config|
#     config.subscribe <%= class_name %>Subscriber.new
#   end
#
class <%= class_name %>Subscriber < TrackRelay::Subscribers::Base
  # Uncomment to run inline instead of via DeliveryJob:
  # synchronous!

  # Filter to specific events only:
  # filter only: %i[<%= file_name %>]

  def deliver(payload)
    # payload.name      => :event_name (Symbol)
    # payload.params    => { key: value, ... }
    # payload.context   => { controller:, action:, client_id:, user:, ... }
    # payload.timestamp => Time
  end
end
```

**ERB variables provided by `NamedBase`:**
- `file_name` — snake_case name (e.g. `my_analytics`)
- `class_name` — CamelCase name (e.g. `MyAnalytics`)
- `singular_name`, `plural_name`, etc. — standard `NamedBase` helpers

---

## Test plan recommendations

### Structural assertions — one test class per generator

Use `Rails::Generators::TestCase` pattern for each generator. Place tests at:
- `test/generators/track_relay/install_generator_test.rb`
- `test/generators/track_relay/event_generator_test.rb`
- `test/generators/track_relay/subscriber_generator_test.rb`

Standard setup:
```ruby
require "test_helper"
require "rails/generators"
require "generators/track_relay/install/install_generator"

class TrackRelay::Generators::InstallGeneratorTest < Rails::Generators::TestCase
  tests TrackRelay::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generator_test", __dir__)
  setup :prepare_destination

  test "creates initializer" do
    run_generator
    assert_file "config/initializers/track_relay.rb" do |content|
      assert_match(/TrackRelay\.configure/, content)
      assert_match(/Subscribers::Logger/, content)
    end
  end

  test "creates sample catalog directory and file" do
    run_generator
    assert_file "config/track_relay/sample.rb" do |content|
      assert_match(/TrackRelay\.catalog/, content)
      assert_match(/event :page_view_example/, content)
    end
  end

  test "creates application subscriber" do
    run_generator
    assert_file "app/track_relay/subscribers/application_subscriber.rb" do |content|
      assert_match(/ApplicationSubscriber < TrackRelay::Subscribers::Base/, content)
    end
  end

  test "injects ControllerTracking into ApplicationController" do
    # Create a stub application_controller.rb in the destination first
    # (prepare_destination gives an empty tree — need the file to inject into)
    create_file "app/controllers/application_controller.rb",
      "class ApplicationController < ActionController::Base\nend\n"
    run_generator
    assert_file "app/controllers/application_controller.rb" do |content|
      assert_match(/include TrackRelay::ControllerTracking/, content)
    end
  end
end
```

For `event` and `subscriber` generators, `run_generator(["ArticleViewed"])` passes the NAME argument.

**`assert_file` / `assert_no_file`** are the primary assertion helpers. Use `assert_match` with regex or string patterns inside the content block. Avoid exact-string equality on full file content — patterns are more resilient to template changes.

### Clean-state concern for structural tests

`prepare_destination` removes and recreates the tmpdir destination. Because generator tests write to `File.expand_path("../../tmp/generator_test", __dir__)` (NOT to `test/internal/`), the Combustion harness is never mutated. The `test/internal/` app remains read-only to these tests. This is the cheapest pattern and the standard Rails::Generators::TestCase approach.

**No snapshot/restore needed** for structural tests because they use a fresh tmpdir per test via `setup :prepare_destination`.

### E2E happy-path test — recommended shape

The ONE E2E test exercises the full pipeline: install generator → catalog load → controller track call → Test subscriber capture. It belongs at `test/integration/generator_install_e2e_test.rb`.

**Key challenge:** the E2E test must run the generator against the LIVE Combustion harness (`test/internal/`) to prove that the Railtie actually picks up the generated files on `to_prepare`. A tmpdir won't work here because the Combustion app is already booted from `test/internal/`.

**Recommended approach — write + teardown, NOT Rails::Generators::TestCase:**

```ruby
class GeneratorInstallE2ETest < ActionDispatch::IntegrationTest
  GENERATED_FILES = [
    "test/internal/config/initializers/track_relay.rb",
    "test/internal/config/track_relay/sample.rb",
    "test/internal/app/track_relay/subscribers/application_subscriber.rb"
  ].freeze

  setup do
    # Write the generated files directly (mimics what the generator produces)
    # rather than running the generator binary inside a test — avoids
    # subprocess/Combustion boot ordering complexity.
    write_generated_initializer
    write_generated_catalog
    write_generated_subscriber

    # Force Railtie's to_prepare logic to reload the catalog
    TrackRelay::Catalog.clear!
    Dir.glob("test/internal/config/track_relay/**/*.rb").sort.each { |f| load f }

    # Wire Test subscriber for the E2E assertion
    TrackRelay.test_mode!
    TrackRelay::Dispatcher.start!
  end

  teardown do
    GENERATED_FILES.each { |f| File.delete(f) if File.exist?(f) }
    FileUtils.rmdir("test/internal/config/track_relay") rescue nil
    FileUtils.rmdir("test/internal/app/track_relay/subscribers") rescue nil
    FileUtils.rmdir("test/internal/app/track_relay") rescue nil
    TrackRelay.test_mode_off!
    TrackRelay::Dispatcher.stop!
    TrackRelay::Catalog.clear!
  end

  test "install generator output: controller track call captured by Test subscriber" do
    get article_path(42)
    assert_response :ok
    assert_tracked :article_viewed, article_id: 42, slug: "test-slug"
  end
end
```

**Note:** The E2E test writes the generated file content inline rather than actually invoking the generator binary. This avoids boot-ordering issues where the generator runner re-requires the Combustion app. The structural generator tests (using `Rails::Generators::TestCase`) already prove the generator produces the correct files. The E2E test's job is only to prove that the files the generator would produce are loadable and produce a working tracking call through the Railtie + controller concern pipeline.

**Alternative approach:** if the Lead prefers actually running the generator binary, use `run_generator` with `destination Rails.root.join("test/internal")` and restore files in `teardown`. The gist at stevepolitodesign.com (consulted above) shows this backup/restore pattern. It adds complexity (backup routes.rb, restore on teardown) but is more faithful to a true generator run. Given the existing `test/internal` already has `ApplicationController` with `ControllerTracking` included, the `inject_into_class` step would double-include — this makes the backup/restore approach slightly riskier. The write-inline approach is recommended.

**Reusable helpers from existing tests:**
- `TrackRelay::Testing::Helpers` mixin (`assert_tracked`, `refute_tracked`) — already required by `test_helper.rb`
- `test_helper.rb:43-49` global teardown resets `Catalog`, `Dispatcher`, and `config` — the E2E test can rely on this
- `article_path(id)` route helper — already defined in `test/internal/config/routes.rb`
- `TrackRelay::Dispatcher.start!` / `.stop!` — idempotent, safe to call manually

---

## Doc audit checklist

### README sections audit

| Section | Status | Notes |
|---|---|---|
| Status / version badge | STALE | References 0.2.0; must update to 1.0.0; replace with a gemversion badge |
| Why | PRESENT | Adequate; minor polish |
| Installation | STALE | `gem "track_relay", "~> 0.2.0"` → `"~> 1.0"` |
| Quick start | PRESENT | Good 5-file example; add generator-based path as "even faster" |
| Catalog DSL | PRESENT | Adequate |
| `identify` | PRESENT | Mark as "thin pass-through; per-adapter properties in future" |
| Subscribers — overview | PRESENT | Adequate |
| Built-in subscribers — Test | PRESENT | |
| Built-in subscribers — Logger | PRESENT | |
| Built-in subscribers — GA4 | PRESENT | |
| Built-in subscribers — **Ahoy** | MISSING | `TrackRelay::Subscribers::Ahoy` not mentioned |
| Controller and Job helpers | PRESENT | |
| Test helpers (Minitest + RSpec) | PRESENT | |
| Untyped events + linter | PRESENT | |
| GA4 + client-side section | PRESENT | |
| Generators | MISSING | `rails g track_relay:install`, `track_relay:event`, `track_relay:subscriber` |
| Compatibility matrix | PRESENT | Needs 1.0.0 update |
| Roadmap | STALE | Must rewrite — 0.3.0 and 0.4.0 are wrong predictions |
| Contributing | PRESENT | |
| License | PRESENT | |
| Link to `doc/usage.md` | MISSING | Getting-started guide not referenced |
| Public-API stability statement | MISSING | Required for 1.0.0 cut |
| Migration notes link | MISSING | Link to migration notes document |

### CHANGELOG entries needed for 1.0.0

The `[Unreleased]` section must become `[1.0.0]` with:

```markdown
## [1.0.0] - YYYY-MM-DD

### Added
- `rails g track_relay:install` — opinionated scaffold: richly commented initializer
  (`config/initializers/track_relay.rb`), sample catalog (`config/track_relay/sample.rb`),
  ApplicationSubscriber base class (`app/track_relay/subscribers/application_subscriber.rb`),
  and `include TrackRelay::ControllerTracking` injected into ApplicationController.
  `bundle exec rake test` passes cleanly immediately after running this generator.
- `rails g track_relay:event NAME` — scaffolds a typed catalog entry stub at
  `config/track_relay/<name>.rb`.
- `rails g track_relay:subscriber NAME` — scaffolds a subscriber class stub at
  `app/track_relay/subscribers/<name>_subscriber.rb`.
- Getting-started guide at `doc/usage.md` (also at USAGE.md).

### Changed
- Bumped to 1.0.0; public API is now stable. See UPGRADING.md for
  migration notes from 0.1.0 / 0.2.0 / 0.3.0.

### Notes
- Public API stability: `TrackRelay.track`, `TrackRelay.configure`,
  `TrackRelay.catalog`, `TrackRelay.subscribe`, `TrackRelay.test_mode!`,
  `TrackRelay::Subscribers::Base`, `TrackRelay::ControllerTracking`, and
  `TrackRelay::JobTracking` are stable as of 1.0.0. Internal classes
  (`EventPayload`, `Instrumenter`, `Dispatcher`, `Catalog`) are not part
  of the public API contract.
```

Also add `[1.0.0]` link at bottom:
```markdown
[1.0.0]: https://github.com/dchuk/track_relay/compare/v0.3.0...v1.0.0
```

### Migration notes content (`UPGRADING.md`)

The CONTEXT.md references migration notes for `0.1.0 → 0.2.0 → 0.3.0 → 1.0.0`. Create `UPGRADING.md` (or `doc/upgrading.md`) with these sections:

**0.1.0 → 0.2.0 (no breaking changes in Ruby surface)**
- `TrackRelay::Subscribers::Ga4MeasurementProtocol` added; wire with `config.ga4_measurement_id` + `config.ga4_api_secret`
- `config.client_id_resolvers` added; default chain preserves existing `_ga` cookie behavior
- Subscriber-side `only:` / `except:` filters added to `TrackRelay.subscribe`
- New rake task: `track_relay:lint:ga4`

**0.2.0 → 0.3.0 (one BREAKING change)**
- BREAKING (JS only): `init({ manifestUrl })` no longer requires `measurementId`. If your `@track_relay/client` usage relied on the missing-`measurementId` throw for configuration guard, add an explicit assertion before calling `init`. Ruby gem surface is unaffected.
- `TrackRelay::Subscribers::Ahoy` added; wire in initializer if you use ahoy_matey
- `AhoyJs` export added in `@track_relay/client`

**0.3.0 → 1.0.0 (no breaking changes)**
- Generators added — run `rails g track_relay:install` to scaffold configuration files
- Public API stability guarantee takes effect

### Getting-started guide (`doc/usage.md`)

Must be created from scratch. Recommended sections:
1. Installation (Gemfile + bundle install)
2. Quick scaffold (generator-first path: `rails g track_relay:install` → `rake test` passes)
3. Defining your first event (catalog DSL walkthrough)
4. Tracking from a controller (include concern, call `track`)
5. Adding subscribers (Logger, GA4, Ahoy, custom)
6. Testing your events (`test_mode!`, `assert_tracked`)
7. Untyped events and the linter
8. Adding more events (`rails g track_relay:event`)
9. Adding custom subscribers (`rails g track_relay:subscriber`)

The quick start from `README.md` (five-file manual path) is the source for sections 3–4; the generator path (sections 1–2) is new content.

---

## Open questions for the Lead

1. **Subscriber file path convention:** Should the install generator create `app/track_relay/subscribers/application_subscriber.rb` or `app/subscribers/application_subscriber.rb`? The gem uses `app/track_relay/subscribers/` nowhere in the current codebase (no convention yet). `app/subscribers/` is shorter and Rails-conventional (like `app/jobs/`, `app/mailers/`). Decision needed before writing the generator template.

2. **Inject-into-ApplicationController guard:** The `test/internal/app/controllers/application_controller.rb` already has `include TrackRelay::ControllerTracking`. If the install generator's `inject_into_class` step runs against a host app that already has the include, it will insert a duplicate. Should the generator use `gsub_file` with a presence check (`unless_in_source_root?`)? Or skip the inject and instead print a post-install instruction? Or accept the duplicate (Devise does not guard against duplicate includes)?

3. **E2E test: write-inline vs run-generator-binary approach:** The write-inline approach is recommended above because it avoids Combustion boot-ordering issues. However it means the E2E test does not actually exercise the generator binary against a live Rails app. If the Lead wants full generator-binary coverage, a backup/restore pattern against `test/internal/` is required (see `test/generators/` vs `test/integration/` decision). Confirm which approach is preferred.

4. **`config/track_relay/sample.rb` event name:** The sample event in the generated catalog should use an event name that is (a) not in `GA4_RESERVED_NAMES`, (b) not using `page_view` (reserved), and (c) illustrative. `page_view_example` is used above but is contrived. A more realistic example: `welcome_banner_viewed` or `onboarding_step_completed`. Lead should confirm the example event name.

5. **Gemspec `spec.files` for generators:** The gemspec currently uses `Dir.glob("lib/**/*")`. Generators at `lib/generators/track_relay/*/` will be automatically included. Confirm no additional `spec.files` entries are needed (e.g. for ERB templates in `lib/generators/track_relay/*/templates/`). Templates in subdirectories of `lib/` are included by `lib/**/*` — this is safe.

6. **`doc/usage.md` vs `USAGE.md`:** The CONTEXT.md says "`doc/usage.md` or `USAGE.md`". The Lead should decide which path: `USAGE.md` is visible at the GitHub repo root (like `CHANGELOG.md`); `doc/usage.md` keeps docs/ tidy but requires navigation. For a 1.0.0 first cut, `USAGE.md` at the repo root has higher discoverability.

7. **Ahoy subscriber registration in the generated initializer:** The install generator's initializer template comments out `config.subscribe TrackRelay::Subscribers::Ahoy.new`. Should it also add a note that Ahoy requires the `ahoy_matey` gem in the host app's Gemfile? This avoids a confusing `NameError`/`LoadError` if a user uncomments it without Ahoy installed.
