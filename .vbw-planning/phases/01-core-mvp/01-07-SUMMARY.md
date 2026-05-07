---
phase: 1
plan: "07"
title: TrackRelay.test_mode! + Minitest assertions + RSpec matchers
status: complete
completed: 2026-05-06
tasks_completed: 3
tasks_total: 3
commit_hashes:
  - eb60596895cc0720d294451d841eb0df89b9e32f
  - 581245ac76cfd65b1961ac6f7ad043d21cb09e3e
  - 13f8fdfa69907d385c98200e78b6e04eccd20ad3
deviations:
  - "DEVN-01: RSpec `chain :with` block parameter changed from `**params` (keyword splat per the plan's example) to `params` (positional Hash) because RSpec's chain proxy delivers `.with(n: 7)` as a positional hash on Ruby 3.4 / RSpec 3.13, raising `ArgumentError: wrong number of arguments (given 1, expected 0)` with the keyword form. Same subset semantics; behavior identical."
  - "DEVN-01: Two happy-path RSpec matcher tests append a redundant `pass` line to suppress Minitest 5.16+'s `Test is missing assertions` warning, since `expect(self).to have_tracked(...)` raises on failure but does not bump Minitest's `@assertions` counter. Tests still verify the matcher truthy-path correctly."
pre_existing_issues: []
ac_results:
  - criterion: "TrackRelay.test_mode! replaces config.subscribers with a fresh [Subscribers::Test.new] and stores the previous list in @previous_subscribers. Returns the new test subscriber so callers can hold a reference."
    verdict: pass
    evidence: "lib/track_relay/testing.rb (commit eb60596); covered by TestModeTest#test_test_mode!_replaces_subscribers_with_a_single_Subscribers::Test and #test_test_mode!_returns_the_new_test_subscriber_so_callers_can_hold_a_reference"
  - criterion: "TrackRelay.test_mode_off! restores the previously captured list. Calling test_mode! twice without restoring is safe — the second call does NOT clobber the originally-saved list."
    verdict: pass
    evidence: "TestModeTest#test_test_mode_off!_restores_the_previously_captured_subscriber_list and #test_test_mode!_twice_does_not_clobber_the_originally-captured_subscribers (idempotency guard via `return @test_subscriber if active?` at lib/track_relay/testing.rb:34)"
  - criterion: "TrackRelay::Testing::Helpers (Minitest module): exposes track_relay_test returning the active Subscribers::Test instance; assert_tracked(name, **expected_params) asserts at least one captured event matches; refute_tracked(name) asserts no matching event."
    verdict: pass
    evidence: "lib/track_relay/testing/minitest_assertions.rb + lib/track_relay/testing/helpers.rb (commit 581245a); ten-test suite test/integration/testing/minitest_assertions_test.rb covering both pass/fail paths, subset matching, and helpful error message when test_mode! was not called"
  - criterion: "TrackRelay::Testing RSpec matchers define have_tracked(name) matcher with .with(**params) chain for RSpec; usable via expect(track_relay).to have_tracked(:event).with(param: value)."
    verdict: pass
    evidence: "lib/track_relay/testing/rspec_matchers.rb (commit 13f8fdf); seven-test suite test/integration/testing/rspec_matchers_test.rb mixing RSpec::Matchers into Minitest test classes to verify match success, .with subset, failure messages, and the test_mode!-not-called error path. Note .with chain takes positional Hash (see deviation)."
  - criterion: "Loading track_relay/testing is OPT-IN: lib/track_relay.rb does NOT require it. Consumers add require 'track_relay/testing' themselves in their test_helper.rb / rails_helper.rb."
    verdict: pass
    evidence: "lib/track_relay.rb has no `require 'track_relay/testing'` line. Smoke-tested: `require 'track_relay'` alone leaves `TrackRelay.respond_to?(:test_mode!) => false` and `defined?(TrackRelay::Testing) => nil`; the require flips both to true. Gem's own test/test_helper.rb adds the explicit require (commit eb60596)."
  - criterion: "The gem's OWN Minitest suite requires track_relay/testing explicitly in test/test_helper.rb."
    verdict: pass
    evidence: "test/test_helper.rb line 22 (commit eb60596): `require 'track_relay/testing'` placed after `require 'track_relay'` and `require 'track_relay/railtie'`."
  - criterion: "TrackRelay.test_mode! and friends are defined in lib/track_relay/testing.rb (and only become available after the opt-in require)."
    verdict: pass
    evidence: "lib/track_relay/testing.rb defines TrackRelay::Testing module + adds class-level test_mode!/test_mode_off!/test_subscriber to TrackRelay singleton via `class << self` reopen. Smoke test confirms they're undefined without the require."
  - criterion: "RSpec matcher file uses if defined?(RSpec) guard so requiring track_relay/testing doesn't fail when RSpec is absent."
    verdict: pass
    evidence: "lib/track_relay/testing/rspec_matchers.rb wraps the entire RSpec::Matchers.define + RSpec.configure blocks in `if defined?(RSpec)`. lib/track_relay/testing.rb's auto-require of the matchers is also gated by `if defined?(RSpec)`."
  - criterion: "lib/track_relay/testing.rb provides Test mode entry containing test_mode!"
    verdict: pass
    evidence: "lib/track_relay/testing.rb (commit eb60596) — module TrackRelay::Testing with module_function test_mode!/test_mode_off!/active?/test_subscriber"
  - criterion: "lib/track_relay/testing/helpers.rb provides Minitest helpers containing assert_tracked"
    verdict: pass
    evidence: "lib/track_relay/testing/minitest_assertions.rb defines assert_tracked; lib/track_relay/testing/helpers.rb mixes it in via `base.include(MinitestAssertions)` on `included` callback (commit 581245a)"
  - criterion: "lib/track_relay/testing/rspec_matchers.rb provides RSpec matchers containing have_tracked"
    verdict: pass
    evidence: "lib/track_relay/testing/rspec_matchers.rb defines RSpec::Matchers.define :have_tracked (and :have_identified placeholder) (commit 13f8fdf)"
  - criterion: "lib/track_relay/testing.rb -> lib/track_relay/configuration.rb: replace_subscribers atomic swap"
    verdict: pass
    evidence: "lib/track_relay/testing.rb:36 calls `TrackRelay.config.replace_subscribers([test_subscriber])`; restore mirrors with `TrackRelay.config.replace_subscribers(@previous_subscribers)` at line 47. Verified by TestModeTest restoration tests."
  - criterion: "lib/track_relay/testing.rb -> lib/track_relay/subscribers/test.rb: Subscribers::Test.new on test_mode!"
    verdict: pass
    evidence: "lib/track_relay/testing.rb:35 instantiates `Subscribers::Test.new`; the require at the top of testing.rb pulls in subscribers/test.rb explicitly. TestModeTest assertions confirm `kind_of TrackRelay::Subscribers::Test`."
---

Shipped the testing surface: `TrackRelay.test_mode!` atomically swaps subscribers for a single in-memory Test instance (idempotent, restores on `test_mode_off!`); `TrackRelay::Testing::MinitestAssertions` provides `assert_tracked` / `refute_tracked` / `track_relay_test`; `TrackRelay::Testing::Helpers` is the Minitest mix-in that adds those assertions and per-test setup/teardown auto-wiring; `TrackRelay::Testing::RSpecMatchers` provides `have_tracked(name).with(params)` (+ `have_identified` Phase-02 stub) guarded by `defined?(RSpec)`. Loading is OPT-IN — `lib/track_relay.rb` does not require `track_relay/testing`. Suite went from 193 -> 219 runs, 396 -> 458 assertions, 0 failures.

## What Was Built

- TrackRelay::Testing module (lib/track_relay/testing.rb) with `test_mode!` / `test_mode_off!` / `active?` / `test_subscriber` module functions plus convenience delegates `TrackRelay.test_mode!` / `.test_mode_off!` / `.test_subscriber` on the umbrella module. `test_mode!` snapshots the current subscribers via `Configuration#replace_subscribers([Subscribers::Test.new])`, returns the new test subscriber, and is idempotent — a second call returns the same instance and does not overwrite the saved snapshot. `test_mode_off!` restores from the snapshot and clears state.
- TrackRelay::Testing::MinitestAssertions (lib/track_relay/testing/minitest_assertions.rb): `assert_tracked(name, **expected_params)` (subset semantics on params), `refute_tracked(name)`, `track_relay_test` (returns the active Test subscriber or raises a helpful "Call TrackRelay.test_mode!" message). All assertions use Minitest's standard `assert`/`refute` so failures bump the assertion counter and produce native Minitest::Assertion errors.
- TrackRelay::Testing::Helpers (lib/track_relay/testing/helpers.rb): Minitest mix-in. The `included` callback mixes `MinitestAssertions` and registers `setup { TrackRelay.test_mode! }` + `teardown { TrackRelay.test_mode_off! }` when the host class supports those hooks. Per-test isolation comes for free.
- TrackRelay::Testing RSpec matchers (lib/track_relay/testing/rspec_matchers.rb): `have_tracked(name)` with `.with(params)` chain (subset matching), `have_identified(user)` Phase-01 placeholder that always fails. Both are wrapped in `if defined?(RSpec)` so requiring the file outside RSpec is safe. Also registers a `track_relay` example-group helper on `RSpec.configure` so consumers can write `expect(track_relay).to have_tracked(:event)`.
- Auto-require in lib/track_relay/testing.rb: `require 'track_relay/testing/rspec_matchers' if defined?(RSpec)` at the bottom of the file so consumers who load RSpec before track_relay/testing get the matchers wired automatically.
- Three integration test files exercising the full surface: test/integration/test_mode_test.rb (9 tests), test/integration/testing/minitest_assertions_test.rb (10 tests), test/integration/testing/rspec_matchers_test.rb (7 tests). The RSpec matcher tests mix `RSpec::Matchers` into Minitest test classes and catch `RSpec::Expectations::ExpectationNotMetError` with `assert_raises`, keeping the gem's dev-dep surface small (no `rspec` runtime, no `spec/` tree).
- Gemspec dependency additions: `rspec-core ~> 3.13` and `rspec-expectations ~> 3.13` as `add_development_dependency` so the gem's own Minitest harness can self-test the RSpec matchers inline.
- test_helper.rb opts in to the testing surface via explicit `require 'track_relay/testing'` after `require 'track_relay'` / `require 'track_relay/railtie'`, modelling the consumer-side opt-in pattern documented in the success criteria.

## Files Modified

- `lib/track_relay/testing.rb` -- create: opt-in entry point defining TrackRelay::Testing module + class-level delegates on TrackRelay; auto-loads RSpec matchers when RSpec is defined
- `lib/track_relay/testing/minitest_assertions.rb` -- create: Minitest assertion module (assert_tracked / refute_tracked / track_relay_test)
- `lib/track_relay/testing/helpers.rb` -- create: Minitest mix-in combining MinitestAssertions with auto setup/teardown wiring
- `lib/track_relay/testing/rspec_matchers.rb` -- create: RSpec have_tracked + have_identified matchers (Phase-01 placeholder) guarded by `if defined?(RSpec)`
- `track_relay.gemspec` -- update: add `rspec-core ~> 3.13` and `rspec-expectations ~> 3.13` as development dependencies (Plan 01 omitted them)
- `Gemfile.lock` -- update: lock new rspec dependencies
- `test/test_helper.rb` -- update: add `require 'track_relay/testing'` after the existing requires (gem's own opt-in)
- `test/integration/test_mode_test.rb` -- create: 9 tests pinning subscriber swap, restore, idempotency, fresh-after-restore, captured events, real-subscriber isolation, no-op-when-inactive
- `test/integration/testing/minitest_assertions_test.rb` -- create: 10 tests pinning assert_tracked / refute_tracked happy + sad paths, subset matching, track_relay_test return value, Helpers auto-wire, per-test isolation, helpful error when test_mode! not called
- `test/integration/testing/rspec_matchers_test.rb` -- create: 7 tests using RSpec::Matchers mixed into Minitest classes, covering have_tracked match + .with subset, failure messages, missing-event path, wrong-params path, have_identified placeholder, test_mode!-not-called error

## Deviations

- DEVN-01: RSpec `chain :with` block parameter changed from `**params` (per the plan's example code) to `params` (positional Hash). RSpec 3.13's chain proxy passes the args to `.with(n: 7)` as a positional Hash on Ruby 3.4, so the keyword splat form raised `ArgumentError: wrong number of arguments (given 1, expected 0)`. Switched to a single positional Hash parameter — same subset semantics, identical behavior, callers still write `.with(n: 7)` exactly as planned.
- DEVN-01: Two happy-path RSpec matcher tests (`have_tracked matches a fired event`, `have_tracked.with(params) matches when subset is satisfied`) append a redundant `pass` line to satisfy Minitest 5.16+'s `Test is missing assertions` warning. `expect(self).to have_tracked(...)` raises on failure but does not bump Minitest's `@assertions` counter, so the warning fires even though the matcher succeeded. The `pass` is annotated inline explaining why.
