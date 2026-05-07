---
phase: 1
plan: "06"
title: Railtie + ControllerTracking + JobTracking concerns
status: complete
completed: 2026-05-06
tasks_completed: 3
tasks_total: 3
commit_hashes:
  - 7d5524acde81a856b3048d02903f9a45e4c1e326
  - 813c8f9bea7ea26db594e09c80f356ce1adbb3d7
  - 5bb0bcecf58bceef714fdeb4d507060d0ef85fdc
  - fcf56d3d2d398970272f18450531c6a8ab14b1c3
deviations:
  - "DEVN-02: Added a fix-up commit (fcf56d3) on top of the three task commits to repair a Railtie load-order race exposed by the unit tests' early `require \"track_relay\"`. The fix is one line in test/test_helper.rb (explicit `require \"track_relay/railtie\"`); rake test went from ~50% flakiness to 20/20 passing."
pre_existing_issues: []
ac_results:
  - criterion: "TrackRelay::Railtie (1) calls Rails.autoloaders.main.ignore(catalog_dir) if catalog_dir.exist?, (2) sets up config.to_prepare { Dir[catalog_dir/**/*.rb].sort.each { |f| load f } }, (3) calls TrackRelay::Dispatcher.start! once on after_initialize."
    verdict: pass
    evidence: "lib/track_relay/railtie.rb (commit 7d5524a); covered by RailtieTest#test_to_prepare_loads_catalog_files_dropped_under_config/track_relay/ and #test_Dispatcher_is_started_after_Combustion_boot"
  - criterion: "Catalog directory is Rails.root.join('config', 'track_relay') resolved from the app argument inside the initializer block."
    verdict: pass
    evidence: "lib/track_relay/railtie.rb line 36: catalog_dir = app.root.join(\"config\", \"track_relay\")"
  - criterion: "Railtie loads catalog files even when config/track_relay/ doesn't exist yet (no error; Dir.glob returns []) — the ignore call is conditional on directory existence to avoid Zeitwerk warning."
    verdict: pass
    evidence: "Test RailtieTest#test_to_prepare_does_not_raise_when_config/track_relay_is_empty + lines 39-41 of lib/track_relay/railtie.rb (`if catalog_dir.exist?`)"
  - criterion: "TrackRelay::ControllerTracking is an ActiveSupport::Concern that adds before_action setting Current.controller/request/client_id (from _ga cookie) and an instance method track(name, **params) delegating to TrackRelay.track."
    verdict: pass
    evidence: "lib/track_relay/controller_tracking.rb (commit 813c8f9); five-test suite test/integration/controller_tracking_test.rb pinning track delegate, Current population, and _ga cookie parsing (happy + nil + malformed)"
  - criterion: "TrackRelay::JobTracking is an ActiveSupport::Concern that adds an instance method track(name, **params) delegating to TrackRelay.track. Job authors are responsible for Current.set(...) block usage."
    verdict: pass
    evidence: "lib/track_relay/job_tracking.rb (commit 5bb0bce); test/integration/job_tracking_test.rb pins both halves of the contract — happy path with Current.set block AND Executor-reset gotcha for jobs that omit Current.set"
  - criterion: "Railtie does NOT auto-include the concerns into ApplicationController or ApplicationJob. Host apps include them explicitly per the planning doc."
    verdict: pass
    evidence: "Concerns are require-only in lib/track_relay.rb; explicit `include TrackRelay::ControllerTracking` is in test/internal/app/controllers/application_controller.rb and `include TrackRelay::JobTracking` in test/internal/app/jobs/welcome_email_job.rb"
  - criterion: "Catalog hot-reload works: editing a file in config/track_relay/ triggers to_prepare on next request in dev."
    verdict: pass
    evidence: "RailtieTest#test_to_prepare_clears_Catalog_before_reloading_(hot-reload_safety) — invokes Rails.application.reloader.prepare! twice; both succeed thanks to Catalog.clear! before reload"
---

Wired the gem into Rails: a Railtie that auto-loads catalog files from `config/track_relay/**/*.rb` via the canonical Zeitwerk-ignore + `to_prepare` + `Dir.glob/load` pattern (with `Catalog.clear!` before reload for hot-reload safety) and starts the Dispatcher once at `after_initialize`, plus the two opt-in concerns (ControllerTracking, JobTracking) host apps include explicitly. Suite went from 182 → 193 runs, 396 assertions, 0 failures.

## What Was Built

- TrackRelay::Railtie with two initializers: `track_relay.catalog_autoload` (Zeitwerk ignore + `to_prepare` clear-then-load) and `track_relay.start_dispatcher` (idempotent `Dispatcher.start!` on `config.after_initialize`).
- TrackRelay::ControllerTracking concern: `included { before_action :_track_relay_set_current }` populates `Current.controller`/`Current.request`/`Current.client_id` (parsed from GA `_ga` cookie's last two dot-separated segments; tolerates nil/empty/malformed cookies); instance method `track(name, **params)` delegates to `TrackRelay.track`.
- TrackRelay::JobTracking concern: minimal `track(name, **params)` delegate. Documents the user contract that authors wrap calls in `Current.set(user: ...) { ... }` to defeat the Rails Executor pre-job CurrentAttributes reset.
- Test internal app gains `ApplicationController` (includes ControllerTracking), `ArticlesController#show`, `WelcomeEmailJob`, and the `articles#show` route — exercising the full request → instrument → context flow end-to-end.
- Three integration test files (railtie_test, controller_tracking_test, job_tracking_test) covering autoload, hot-reload safety, empty-directory tolerance, Dispatcher boot, controller before_action / track delegate / cookie parsing, job track delegate, Current.set block context propagation, and the Executor-reset contract.
- test_helper hardening: load `track_relay` and explicitly `track_relay/railtie` before `Combustion.initialize!` so the Railtie is registered regardless of which test file Minitest::TestTask requires first.

## Files Modified

- `lib/track_relay/railtie.rb` -- create: Rails integration boundary (catalog autoload + Dispatcher boot)
- `lib/track_relay/controller_tracking.rb` -- create: controller-side `track` delegate + before_action populating Current
- `lib/track_relay/job_tracking.rb` -- create: minimal job-side `track` delegate (documents Current.set block contract)
- `lib/track_relay.rb` -- update: require the three new files; conditionally require Railtie when `Rails::Railtie` is defined
- `test/test_helper.rb` -- update: require track_relay (and explicitly track_relay/railtie) BEFORE `Combustion.initialize!` to fix Railtie load-order race
- `test/internal/config/routes.rb` -- update: declare `articles#show` route for controller test
- `test/internal/app/controllers/application_controller.rb` -- create: includes ControllerTracking concern
- `test/internal/app/controllers/articles_controller.rb` -- create: `show` action that calls `track :article_viewed`
- `test/internal/app/jobs/welcome_email_job.rb` -- create: demonstrates `Current.set(user: ...) { track ... }` pattern with reserved-key `:visitor_token`
- `test/integration/railtie_test.rb` -- create: 4 tests covering autoload, hot-reload, empty-dir, dispatcher.started
- `test/integration/controller_tracking_test.rb` -- create: 5 tests covering track delegate, Current population, `_ga` cookie parsing
- `test/integration/job_tracking_test.rb` -- create: 2 tests covering Current.set block path + Executor-reset contract

## Deviations

- DEVN-02: Discovered during task 3 that the rake test suite was ~50% flaky (RailtieTest's `to_prepare` tests failed when unit tests requiring `track_relay` early in load order ran before the integration tests' test_helper). Root cause: `lib/track_relay.rb`'s conditional `require "track_relay/railtie" if defined?(Rails::Railtie)` evaluated false on the first load (before Rails was required) and Ruby's `$LOADED_FEATURES` then short-circuited subsequent `require "track_relay"` calls, leaving the Railtie silently missing. Fix landed as a separate fix-up commit (fcf56d3) adding an explicit `require "track_relay/railtie"` in test_helper after combustion has loaded Rails. Verified stable across 20/20 consecutive `bundle exec rake test` runs.
