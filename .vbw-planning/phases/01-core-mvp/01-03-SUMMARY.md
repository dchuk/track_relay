---
phase: 01
plan: "03"
title: TrackRelay::Current + Configuration + configure block
status: complete
completed: 2026-05-06
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 9f726c4
  - 9ec0aec
  - 0077d0b
  - 0455bd6
deviations: []
pre_existing_issues: []
ac_results:
  - criterion: "TrackRelay::Current inherits from ActiveSupport::CurrentAttributes with attributes :user, :request, :visit, :controller, :client_id"
    verdict: pass
    evidence: "lib/track_relay/current.rb (commit 9f726c4); test/unit/current_test.rb test_Current_is_a_subclass_of_ActiveSupport::CurrentAttributes + test_all_five_attributes_are_independently_settable"
  - criterion: "Configuration exposes accessors: subscribers (Array), swallow_subscriber_errors (Bool, default false in dev/test, true in prod), untyped_log_path (Pathname or nil, default nil), untyped_events_allowed (Bool, default true), force_synchronous (Bool, default false)"
    verdict: pass
    evidence: "lib/track_relay/configuration.rb (commit 9ec0aec); test/unit/configuration_test.rb default-block (subscribers/untyped_events_allowed/untyped_log_path/force_synchronous/swallow_subscriber_errors tests)"
  - criterion: "config.subscribe(subscriber_instance) appends to @subscribers and returns the instance (chainable)"
    verdict: pass
    evidence: "lib/track_relay/configuration.rb#subscribe (commit 9ec0aec); test/unit/configuration_test.rb test_subscribe(obj)_appends_and_returns_obj"
  - criterion: "TrackRelay.configure { |c| ... } yields the singleton Configuration. TrackRelay.config returns the same instance"
    verdict: pass
    evidence: "lib/track_relay.rb (commit 0077d0b); test/unit/configuration_test.rb test_TrackRelay.configure_yields_the_singleton_and_persists_mutations + test_TrackRelay.config_returns_the_same_instance_across_calls"
  - criterion: "Configuration#reset! clears subscribers and restores defaults — used by tests"
    verdict: pass
    evidence: "lib/track_relay/configuration.rb#reset! (commit 9ec0aec); test/unit/configuration_test.rb test_reset!_clears_subscribers_and_restores_defaults"
  - criterion: "Current attribute reset between tests is automatic via ActiveSupport::CurrentAttributes::TestHelper already mixed into ActiveSupport::TestCase in Plan 01"
    verdict: pass
    evidence: "test/test_helper.rb (Plan 01-01); test/unit/current_test.rb + test/integration/current_test.rb both contain a `Current.user is nil at start of next test` assertion that passes under --seed=1 and --seed=2"
  - criterion: "Artifact: lib/track_relay/current.rb provides Current class containing `attribute :user, :request, :visit, :controller, :client_id`"
    verdict: pass
    evidence: "commit 9f726c4 — file present with the exact attribute declaration"
  - criterion: "Artifact: lib/track_relay/configuration.rb provides Configuration class containing `def subscribe`"
    verdict: pass
    evidence: "commit 9ec0aec — file present with `def subscribe(subscriber)`"
  - criterion: "Artifact: test/integration/current_test.rb provides Current isolation test using TestHelper"
    verdict: pass
    evidence: "commit 0455bd6 — CurrentIntegrationTest covers persistence within a test, auto-reset between tests, Current.set restoration, and attribute independence"
  - criterion: "Key link: lib/track_relay.rb -> lib/track_relay/configuration.rb via TrackRelay.configure / TrackRelay.config"
    verdict: pass
    evidence: "commit 0077d0b — `require \"track_relay/configuration\"` plus singleton class << self with config/configure/reset_config!"
  - criterion: "Key link: lib/track_relay.rb -> lib/track_relay/current.rb via module-level require"
    verdict: pass
    evidence: "commit 9f726c4 — `require \"track_relay/current\"` added to lib/track_relay.rb"
---

Adds the per-request context layer (TrackRelay::Current) and the Configuration singleton (TrackRelay.configure / TrackRelay.config) that Plans 04-05 depend on, with TestHelper-backed isolation proven under --seed=1 and --seed=2.

## What Was Built

- `TrackRelay::Current` ActiveSupport::CurrentAttributes subclass with five attributes: `:user, :request, :visit, :controller, :client_id`. Auto-resets between requests, jobs, and (via TestHelper) tests.
- `TrackRelay::Configuration` with all Phase-01 knobs: `subscribers`, `swallow_subscriber_errors` (false in dev/test, true in prod), `untyped_log_path` (nil), `untyped_events_allowed` (true), `force_synchronous` (false), `raise_on_validation_error` (true in dev/test). `subscribe(obj)` appends and returns chainably; `replace_subscribers(list)` atomically swaps and returns the previous list (Plan 07 dependency); `reset!` restores defaults.
- `TrackRelay.config` lazy singleton, `TrackRelay.configure { |c| ... }` yields and returns it, `TrackRelay.reset_config!` swaps in a fresh Configuration for test isolation.
- Extended `test/test_helper.rb` teardown to clear both `TrackRelay::Catalog` and `TrackRelay.reset_config!` so per-test mutations cannot leak.
- Integration test under `test/integration/current_test.rb` proves the gem's contract with ActiveSupport's lifecycle hooks under a fully booted Combustion app, including order-independent auto-reset.

## Files Modified

- `lib/track_relay/current.rb` -- created: `Current < ActiveSupport::CurrentAttributes` with five attributes; explicitly `require "active_support"` so `AS::CodeGenerator` autoload is registered when running outside a host Rails boot.
- `lib/track_relay/configuration.rb` -- created: Configuration class with all Phase-01 settings, `subscribe`, `replace_subscribers`, `reset!`, and env-aware defaults (Rails.env preferred, RACK_ENV fallback).
- `lib/track_relay.rb` -- modified: added `require "track_relay/current"`, `require "track_relay/configuration"`, and `class << self` block with `config`, `configure`, `reset_config!` singleton methods.
- `test/test_helper.rb` -- modified: teardown hook now clears Catalog AND calls `TrackRelay.reset_config!` between tests.
- `test/unit/current_test.rb` -- created: 6 unit tests covering subclass identity, persistence within a test, auto-reset between tests, `Current.set` block restoration, attribute independence, and `respond_to?(:set, :reset)`.
- `test/unit/configuration_test.rb` -- created: 17 unit tests covering defaults, `subscribe`, `replace_subscribers` swap semantics, `reset!`, plus singleton wiring (`TrackRelay.config` identity, `configure` mutation, `reset_config!` freshness, teardown isolation pair).
- `test/integration/current_test.rb` -- created: 4 integration tests under Combustion proving Current persistence within a test, auto-reset between tests, `Current.set` restoration, and attribute independence.

## Deviations

None.
