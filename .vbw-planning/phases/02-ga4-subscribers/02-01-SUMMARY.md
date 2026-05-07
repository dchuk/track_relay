---
phase: 2
plan: "01"
title: Subscriber filter foundations + webmock dev dep
status: complete
completed: 2026-05-06
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - 56ecc16
  - 3dedc80
  - d62cd42
  - 3112e36
deviations: []
pre_existing_issues: []
ac_results:
  - criterion: "`webmock` is a development dependency in `track_relay.gemspec` (~> 3.23)"
    verdict: pass
    evidence: "track_relay.gemspec:41 (commit 56ecc16); `bundle exec ruby -e 'require \"webmock\"; puts WebMock::VERSION'` → 3.26.2"
  - criterion: "`require \"webmock/minitest\"` and `WebMock.disable_net_connect!` are present in `test/test_helper.rb`"
    verdict: pass
    evidence: "test/test_helper.rb:32, test/test_helper.rb:38 (commit 56ecc16)"
  - criterion: "`TrackRelay::Subscribers::Base` exposes `class_attribute :only_events, :except_events` (Set<Symbol> | nil) and a class-level `filter only:`/`except:` DSL setter"
    verdict: pass
    evidence: "lib/track_relay/subscribers/base.rb:42-43, :69-72 (commits 3dedc80, 3112e36); test/unit/subscribers/base_filter_test.rb only/except cases"
  - criterion: "`Base#handle` short-circuits with `return nil` when the payload's event name is filtered out, BEFORE the sync/async branch and BEFORE `safe_deliver`'s rescue boundary"
    verdict: pass
    evidence: "lib/track_relay/subscribers/base.rb:110 `return nil if filtered?(...)` placed before the synchronous/async branch (commit 3dedc80); test_filter_check_runs_BEFORE_safe_deliver in test/unit/subscribers/base_filter_test.rb"
  - criterion: "`TrackRelay.subscribe(klass_or_instance, only: nil, except: nil)` exists in `lib/track_relay.rb` and registers the subscriber with per-instance filter overrides"
    verdict: pass
    evidence: "lib/track_relay.rb:171 (commit d62cd42, refactored 3112e36); test/unit/track_relay_subscribe_test.rb 7 cases including class-vs-instance, override-no-bleed, override-replaces-class-default"
  - criterion: "Test: a filtered subscriber receives ONLY events in its `only:` set; an `except:` set blocks listed events; no filter = receives all events"
    verdict: pass
    evidence: "test_filter_only:_..._receives_:purchase_but_drops_:sign_up, test_filter_except:..., test_no_filter_set:_receives_every_event in test/unit/subscribers/base_filter_test.rb (commit 3dedc80)"
  - criterion: "Test: filter check happens before `safe_deliver` (a filtered event with a buggy `deliver` does NOT raise or log)"
    verdict: pass
    evidence: "test_filter_check_runs_BEFORE_safe_deliver:_filtered_event_with_raising_deliver_does_not_log + companion test_filter_does_not_block_matching_events (test/unit/subscribers/base_filter_test.rb, commit 3dedc80)"
  - criterion: "Existing Phase 1 test suite still passes — no behavior change for unfiltered subscribers"
    verdict: pass
    evidence: "`bundle exec rake` → 253 runs, 572 assertions, 0 failures (Phase 1 was 241 runs; +12 new from this plan, all passing)"
---

Wave-1 foundations for Phase 02: subscriber-side `only:`/`except:` event-name filters wired into `Subscribers::Base#handle` BEFORE the rescue boundary, a public `TrackRelay.subscribe(klass_or_instance, only:, except:)` registration helper that stores filters as per-instance overrides without mutating class defaults, and webmock as a dev dependency so plan 02-04 can stub the GA4 measurement-protocol endpoint.

## What Was Built

- `Subscribers::Base.filter(only:, except:)` class DSL — coerces inputs to `Set<Symbol>` via `coerce_event_set` and stores them in `class_attribute`s `only_events`/`except_events` (default `nil` = receive everything, Phase 1 behavior preserved).
- `Base#handle` now short-circuits with `return nil if filtered?(payload.name.to_sym)` BEFORE the sync/async branch and the `safe_deliver` rescue. A filtered event with a buggy `#deliver` neither runs nor logs — proven by a paired test (filtered event silent / matching event still logs).
- `Base#set_filter_overrides!(only:, except:)` — instance-level override path that stores per-instance filters on the singleton class so two instances of the same subscriber can carry different filters without cross-talk and the class-level defaults stay clean.
- `TrackRelay.subscribe(klass_or_instance, only: nil, except: nil)` — accepts either a class (instantiated via `.new`) or a pre-built instance, calls `set_filter_overrides!`, delegates registration to `config.subscribe`, returns the instance.
- `webmock ~> 3.23` added as a dev dependency. `test_helper.rb` requires `webmock/minitest` and calls `WebMock.disable_net_connect!(allow_localhost: true)`.
- 12 new tests (5 in `test/unit/subscribers/base_filter_test.rb`, 7 in `test/unit/track_relay_subscribe_test.rb`). Full suite: 253 runs / 572 assertions / 0 failures (was 241 / 550 / 0). `bundle exec rake` (standard + tests) green.

## Files Modified

- `track_relay.gemspec` -- added `spec.add_development_dependency "webmock", "~> 3.23"`
- `Gemfile.lock` -- regenerated to include webmock + transitive deps (addressable, crack, public_suffix, bigdecimal, rexml)
- `test/test_helper.rb` -- added `require "webmock/minitest"` and `WebMock.disable_net_connect!(allow_localhost: true)`
- `lib/track_relay/subscribers/base.rb` -- added `class_attribute :only_events, :except_events`, `.filter` DSL, `.coerce_event_set` helper, `#set_filter_overrides!`, `#only_events`/`#except_events` instance readers (with singleton-class override lookup), private `#filtered?`; wired filter gate at the top of `#handle`
- `lib/track_relay.rb` -- added public `TrackRelay.subscribe(subscriber_or_class, only:, except:)`
- `test/unit/subscribers/base_filter_test.rb` -- new: 5 minitest cases covering only-allows, except-drops, no-filter-receives-all, filter-before-safe_deliver ordering, and the matching-event-still-runs companion
- `test/unit/track_relay_subscribe_test.rb` -- new: 7 minitest cases covering class instantiation, instance pass-through, only/except per-instance overrides, no-bleed across siblings, override-replaces-class-default, and inherits-class-default fallback
- `CHANGELOG.md` -- added `[Unreleased]` section with bullets for the filter DSL/`TrackRelay.subscribe` and the new webmock dev dependency
