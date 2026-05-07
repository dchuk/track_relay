---
phase: 2
plan: "02"
title: Configurable client_id resolver chain
status: complete
completed: 2026-05-06
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - 8ddc8b3
  - 64f2738
  - 8eca271
  - 1d51f4c
  - 4817baa
deviations:
  - "DEVN-02: two existing Phase-1 ControllerTrackingTest cases asserted `Current.client_id == nil` when the `_ga` cookie was absent or malformed. Plan 02-02's `must_haves` mandate Session-fallback UUID in those exact paths, so I updated those two tests (test/integration/controller_tracking_test.rb lines ~75-99) to assert a valid UUID instead. The `_ga`-cookie-present parity test was left untouched and still passes bit-for-bit. Task 4 lead notes (`the existing controller_tracking tests must still pass with no changes`) is at odds with the must_have spec; resolved in favor of the must_haves which are the binding acceptance criteria."
pre_existing_issues: []
ac_results:
  - criterion: "TrackRelay::Configuration exposes client_id_resolvers (Array, default = [ClientId::Ga.new, ClientId::AhoyVisitor.new, ClientId::Session.new]); attribute is reader+writer with sensible default and resettable in reset_config!"
    verdict: pass
    evidence: "lib/track_relay/configuration.rb (attr_accessor + default_client_id_resolvers); test/unit/configuration_test.rb 5 new tests including 'reset! restores client_id_resolvers' and 'TrackRelay.reset_config! restores fresh client_id_resolvers'"
  - criterion: "TrackRelay::ClientId::Ga#call(controller:, **) returns last-two-segments of _ga cookie or nil; behavior matches Phase 1 parser at controller_tracking.rb:62-71"
    verdict: pass
    evidence: "lib/track_relay/client_id/ga.rb; test/unit/client_id/ga_test.rb (9 tests covering standard format, prefix-segment robustness, missing/empty/<4-segments → nil, controller=nil, request=nil)"
  - criterion: "TrackRelay::ClientId::AhoyVisitor#call returns controller.ahoy.current_visit&.visitor_token when Ahoy is present; returns nil when controller.respond_to?(:ahoy, true) is false (no NameError, no require of ahoy)"
    verdict: pass
    evidence: "lib/track_relay/client_id/ahoy_visitor.rb (duck-typed via respond_to?); test/unit/client_id/ahoy_visitor_test.rb (6 tests including a regression assertion that the source contains no `require \"ahoy\"`)"
  - criterion: "TrackRelay::ClientId::Session#call returns session[:track_relay_client_id] ||= SecureRandom.uuid; nil when no session available"
    verdict: pass
    evidence: "lib/track_relay/client_id/session.rb; test/unit/client_id/session_test.rb (6 tests covering UUID minting, idempotent storage, pre-seeded session, controller=nil, session=nil)"
  - criterion: "ControllerTracking#_track_relay_set_current invokes _resolve_client_id (private) which iterates config.client_id_resolvers first-non-nil-wins and assigns to Current.client_id; the inline _track_relay_client_id_from_cookie is removed"
    verdict: pass
    evidence: "lib/track_relay/controller_tracking.rb (the previous _track_relay_client_id_from_cookie is gone — `grep -rn _track_relay_client_id_from_cookie lib/` returns only one comment-string reference in ga.rb's docstring); _resolve_client_id wraps each resolver call in `rescue` (StandardError)"
  - criterion: "Test: with _ga cookie present, Current.client_id matches Phase 1 output for the same cookie input"
    verdict: pass
    evidence: "test/integration/client_id_chain_test.rb '_ga cookie present yields the same client_id as Phase 1 parser' AND test/integration/controller_tracking_test.rb '_ga cookie populates Current.client_id' (untouched Phase-1 test still passes — bit-for-bit parity)"
  - criterion: "Test: with no _ga cookie + no Ahoy, Current.client_id is a session-stable UUID (asserted by setting it once and re-running the before_action — value is identical)"
    verdict: pass
    evidence: "test/integration/client_id_chain_test.rb 'Session-fallback UUID is stable across two before_action invocations' (two `get`s on different paths, asserts first == second)"
  - criterion: "Test: a custom resolver inserted at position 0 wins over defaults"
    verdict: pass
    evidence: "test/integration/client_id_chain_test.rb 'custom resolver inserted at position 0 wins over defaults' (uses unshift on the default chain with _ga cookie also set, custom value wins)"
  - criterion: "Test: an exception inside one resolver does NOT abort the chain — chain continues and the failing resolver returns nil (rescue StandardError)"
    verdict: pass
    evidence: "test/integration/client_id_chain_test.rb 'a resolver raising StandardError does NOT abort the chain' AND 'exception inside a resolver is rescued without re-raising'"
---

Replaces the hardcoded `_ga`-cookie-only client_id parser in `ControllerTracking` with a configurable, ordered first-non-nil-wins resolver chain (`Ga` → `AhoyVisitor` → `Session`) that runs once per request inside the existing `before_action`, with per-resolver `rescue` so a single buggy resolver cannot block the chain. Phase-1 cookie parsing parity preserved bit-for-bit via `ClientId::Ga`; new `Session` fallback mints a session-stable `SecureRandom.uuid` for visitors without a `_ga` cookie. Implements REQ-26.

## What Was Built

- `TrackRelay::ClientId::Ga` — extracts the last two dot-separated segments of `_ga`; nil on missing/empty/<4-segments. Robust against extra prefix segments via `parts[-2..]`.
- `TrackRelay::ClientId::AhoyVisitor` — duck-typed `controller.respond_to?(:ahoy, true)` probe → `controller.ahoy&.current_visit&.visitor_token`. Does NOT `require "ahoy"`; the gem stays loadable in non-Ahoy hosts.
- `TrackRelay::ClientId::Session` — `session[:track_relay_client_id] ||= SecureRandom.uuid` for session-stable fallback; nil when controller has no session (API-only mode).
- `TrackRelay::Configuration#client_id_resolvers` — new `attr_accessor`; default `[Ga.new, AhoyVisitor.new, Session.new]`; `reset!` and `TrackRelay.reset_config!` restore fresh defaults.
- `TrackRelay::ControllerTracking#_resolve_client_id` — private chain runner; iterates `config.client_id_resolvers`, wraps each `resolver.call(controller: self)` in `rescue` (StandardError) with a `Rails.logger.warn` breadcrumb, returns the first non-nil result (or nil when all resolvers yield nil/raise).
- Phase-1 inline `_track_relay_client_id_from_cookie` removed; `_track_relay_set_current` now calls `_resolve_client_id`.

## Files Modified

- `lib/track_relay/client_id/ga.rb` -- create: Ga4 `_ga` cookie resolver (last-two-segments parser, parity with Phase 1).
- `lib/track_relay/client_id/ahoy_visitor.rb` -- create: duck-typed Ahoy visitor_token resolver.
- `lib/track_relay/client_id/session.rb` -- create: session-stable UUID fallback resolver.
- `lib/track_relay/configuration.rb` -- modify: add `client_id_resolvers` attr_accessor + private `default_client_id_resolvers` factory; wire into `reset!`.
- `lib/track_relay/controller_tracking.rb` -- modify: remove `_track_relay_client_id_from_cookie`; add `_resolve_client_id` chain runner with per-resolver rescue; rewire `_track_relay_set_current`.
- `lib/track_relay.rb` -- modify: add three `require "track_relay/client_id/*"` lines between `current.rb` and `configuration.rb` so Configuration's default array can reference the resolver classes at boot.
- `test/unit/client_id/ga_test.rb` -- create: 9 unit tests for the parser (standard format, prefix-segment robustness, malformed/missing/empty cookies, controller=nil edge cases).
- `test/unit/client_id/ahoy_visitor_test.rb` -- create: 6 unit tests including the duck-typed-only regression check (source must NOT contain `require "ahoy"`).
- `test/unit/client_id/session_test.rb` -- create: 6 unit tests for UUID minting + idempotent storage + pre-seeded session + nil-controller / nil-session.
- `test/unit/configuration_test.rb` -- modify: 5 new tests covering default chain order, reader+writer, reset! resets the chain, and `TrackRelay.reset_config!` semantics.
- `test/integration/client_id_chain_test.rb` -- create: end-to-end coverage through the dummy app's `ArticlesController` for Phase-1 parity, first-non-nil short-circuit, custom-at-position-0 priority, exception isolation (raising resolver skipped), AhoyVisitor stub returning a token, and Session UUID stability across two requests.
- `test/integration/controller_tracking_test.rb` -- modify: update two `_ga`-absent / `_ga`-malformed assertions from `assert_nil` (Phase 1 behavior) to `refute_nil` + UUID format match (Phase 2 Session-fallback behavior). The `_ga`-cookie-present parity test untouched.
- `CHANGELOG.md` -- modify: `[Unreleased]` bullet describing the chain, default order, first-non-nil semantics, per-resolver rescue, and Phase-1 parity.

## Deviations

DEVN-02 (logged in frontmatter `deviations`): two Phase-1 controller_tracking tests asserted `Current.client_id == nil` when `_ga` was absent or malformed. The plan's `must_haves` explicitly require Session-fallback UUID in those exact paths, so the tests were updated to assert UUID format instead of nil. Lead's task-4 note ("existing controller_tracking tests must still pass with no changes") was reconciled in favor of the binding `must_haves` spec. The cookie-PRESENT parity test was untouched and still passes bit-for-bit.

Final: 305 runs / 677 assertions / 0 failures / 0 errors (up from 253-run Phase-1 baseline; +18 new client_id unit tests, +7 new chain integration tests, +5 new Configuration tests, +27 from dev-03's parallel Plan 02-03 work also landing on main during this team session).
