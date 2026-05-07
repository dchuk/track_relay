---
phase: 4
plan: "01"
title: "Install generator (track_relay:install) — opinionated 1.0.0 scaffold"
status: complete
completed: 2026-05-07
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - 44a5da0
  - 46a3e50
  - 301a442
  - 6fa8d45
deviations: []
pre_existing_issues: []
ac_results:
  - criterion: "Generator class is TrackRelay::Generators::InstallGenerator < Rails::Generators::Base"
    verdict: pass
    evidence: "lib/generators/track_relay/install/install_generator.rb (commit 44a5da0)"
  - criterion: "Generator is non-interactive (no ask/yes? prompts) per Devise/ActiveAdmin convention"
    verdict: pass
    evidence: "no ask/yes? calls in install_generator.rb (commit 44a5da0)"
  - criterion: "ApplicationController inject is idempotent: no-op when TrackRelay::ControllerTracking is already included"
    verdict: pass
    evidence: "inject_controller_tracking uses File.read + String#include? guard (commit 44a5da0)"
  - criterion: "Subscriber path convention is app/track_relay/subscribers/ (gem-namespaced)"
    verdict: pass
    evidence: "create_application_subscriber writes to app/track_relay/subscribers/application_subscriber.rb (commit 44a5da0)"
  - criterion: "Sample event name is :hello_world (tutorial-clear, not in GA4_RESERVED_NAMES, not page_view)"
    verdict: pass
    evidence: "lib/generators/track_relay/install/templates/sample_catalog.rb.tt (commit 301a442)"
  - criterion: "Generated initializer is syntactically valid Ruby and references only stable, top-level public TrackRelay APIs"
    verdict: pass
    evidence: "TrackRelay.configure + TrackRelay::Subscribers::Logger.new only (commit 46a3e50); E2E verification deferred to plan 04-04"
  - criterion: "lib/generators/track_relay/install/install_generator.rb provides InstallGenerator class containing 'class InstallGenerator < Rails::Generators::Base'"
    verdict: pass
    evidence: "ruby -c passed; grep confirmed (commit 44a5da0)"
  - criterion: "lib/generators/track_relay/install/templates/initializer.rb.tt provides richly commented initializer template containing 'TrackRelay.configure'"
    verdict: pass
    evidence: "grep confirmed TrackRelay.configure block (commit 46a3e50)"
  - criterion: "lib/generators/track_relay/install/templates/sample_catalog.rb.tt provides working sample catalog containing 'event :hello_world'"
    verdict: pass
    evidence: "grep confirmed event :hello_world block (commit 301a442)"
  - criterion: "lib/generators/track_relay/install/templates/application_subscriber.rb.tt provides ApplicationSubscriber base class containing 'ApplicationSubscriber < TrackRelay::Subscribers::Base'"
    verdict: pass
    evidence: "grep confirmed class declaration (commit 6fa8d45)"
  - criterion: "install_generator.rb -> templates/initializer.rb.tt via template"
    verdict: pass
    evidence: "create_initializer method calls template (commit 44a5da0)"
  - criterion: "install_generator.rb -> templates/sample_catalog.rb.tt via template"
    verdict: pass
    evidence: "create_sample_catalog method calls template (commit 44a5da0)"
  - criterion: "install_generator.rb -> templates/application_subscriber.rb.tt via template"
    verdict: pass
    evidence: "create_application_subscriber method calls template (commit 44a5da0)"
  - criterion: "install_generator.rb -> app/controllers/application_controller.rb via inject_into_class (guarded)"
    verdict: pass
    evidence: "inject_controller_tracking uses inject_into_class with idempotency guard (commit 44a5da0)"
---

Shipped the opinionated `rails g track_relay:install` generator and its three templates, locking in conventions (subscriber path `app/track_relay/subscribers/`, sample event `:hello_world`, idempotent inject via `File.read` + `String#include?`) for downstream plans 04-02, 04-03, 04-04, 04-05.

## What Was Built

- `TrackRelay::Generators::InstallGenerator` (subclass of `Rails::Generators::Base`, non-interactive) with five action methods: initializer, sample catalog, ApplicationSubscriber, guarded ControllerTracking inject, post-install message.
- Richly commented `initializer.rb.tt` with one active `Subscribers::Logger.new` registration and commented-out scaffolds for Test, GA4, Ahoy (with `ahoy_matey` requirement note), untyped-events, and validation behavior.
- `sample_catalog.rb.tt` with a working `event :hello_world` declaration (single required `string :message` param) and tutorial comments showing controller-action and `assert_tracked` usage.
- `application_subscriber.rb.tt` defining `ApplicationSubscriber < TrackRelay::Subscribers::Base` with abstract `#deliver(payload)` raising `NotImplementedError` and payload-shape documentation.
- Smoke-test probe confirms generator class loads, `source_root` resolves correctly, and all three templates are present. Existing test suite remains green (392 runs, 0 failures).

## Files Modified

- `lib/generators/track_relay/install/install_generator.rb` -- create: install generator class with 5 action methods and idempotent inject guard.
- `lib/generators/track_relay/install/templates/initializer.rb.tt` -- create: richly commented initializer template referencing only stable public APIs.
- `lib/generators/track_relay/install/templates/sample_catalog.rb.tt` -- create: working `event :hello_world` sample catalog template.
- `lib/generators/track_relay/install/templates/application_subscriber.rb.tt` -- create: ApplicationSubscriber base class scaffold with abstract `#deliver`.

## Deviations

None.
