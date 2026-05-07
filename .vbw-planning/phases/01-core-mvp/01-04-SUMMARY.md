---
phase: 1
plan: "04"
title: TrackRelay.track / .identify / Notifications wiring
status: complete
completed: 2026-05-06
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 6bb1678
  - 4225f84
  - 0e9f5a7
  - 829e8ae
deviations: []
pre_existing_issues: []
ac_results:
  - criterion: "TrackRelay.track(name, **params) extracts the four reserved keys, looks up Catalog.lookup(name), builds an EventPayload, calls payload.validate!, then instruments via ActiveSupport::Notifications.instrument(\"track_relay.event\", event: payload). Reserved keys never appear in payload.params."
    verdict: pass
    evidence: "lib/track_relay/instrumenter.rb#track + test/integration/track_test.rb 'track instruments track_relay.event with EventPayload' (commit 4225f84)"
  - criterion: "Reserved-key routing is split: :user/:request/:client_id via Current.set(...) block; :visitor_token written directly to payload.context[:visitor_token] (NOT a Current attribute)."
    verdict: pass
    evidence: "lib/track_relay/instrumenter.rb#partition_reserved + CURRENT_ATTR_KEYS / DIRECT_CONTEXT_KEYS; test 'visitor_token goes to context, never params, never Current' asserts refute_respond_to TrackRelay::Current, :visitor_token (commit 4225f84)"
  - criterion: "Untyped path: Catalog.lookup nil AND config.untyped_events_allowed → EventPayload.untyped + same notification name. When disallowed, raise TrackRelay::UnknownEventError."
    verdict: pass
    evidence: "lib/track_relay/instrumenter.rb#build_payload + test/integration/untyped_event_test.rb both branches (commit 0e9f5a7)"
  - criterion: "Validation errors gated by config.raise_on_validation_error — true: re-raise; false: log via Rails.logger.error and swallow (do NOT instrument)."
    verdict: pass
    evidence: "lib/track_relay/instrumenter.rb#validate + tests 'track raises ValidationError when raise_on_validation_error is true' and 'track does not instrument when validation fails AND swallow is enabled' (commit 4225f84)"
  - criterion: "TrackRelay.identify(user, **user_properties) instruments track_relay.identify with {user:, properties:} payload. No catalog validation in this phase (deferred)."
    verdict: pass
    evidence: "lib/track_relay/instrumenter.rb#identify with TODO(phase-02) comment + test/integration/identify_test.rb (commit 829e8ae)"
  - criterion: "Reserved-key extraction happens BEFORE catalog lookup."
    verdict: pass
    evidence: "lib/track_relay/instrumenter.rb#track first line is partition_reserved; Catalog.lookup is called inside the with_current_attrs block (commit 6bb1678)"
  - criterion: "Context capture at instrument time: user / controller (class name) / action / client_id / visit / request_id; :visitor_token merged in directly. Required by Plan 05's DeliveryJob contract."
    verdict: pass
    evidence: "lib/track_relay/instrumenter.rb#current_context returns all six keys; #build_payload merges extra_context (visitor_token) into the snapshot (commit 6bb1678)"
  - criterion: "Artifact lib/track_relay/instrumenter.rb provides track/identify implementation containing ActiveSupport::Notifications.instrument."
    verdict: pass
    evidence: "lib/track_relay/instrumenter.rb#track and #identify both call ActiveSupport::Notifications.instrument (commit 6bb1678)"
  - criterion: "Artifact test/integration/track_test.rb provides track flow tests containing track_relay.event."
    verdict: pass
    evidence: "test/integration/track_test.rb subscribes to 'track_relay.event' across 6 assertions (commit 4225f84)"
  - criterion: "Artifact test/integration/untyped_event_test.rb provides untyped path tests containing untyped_events_allowed."
    verdict: pass
    evidence: "test/integration/untyped_event_test.rb 'untyped event raises UnknownEventError when disallowed' flips config.untyped_events_allowed (commit 0e9f5a7)"
  - criterion: "Key link lib/track_relay/instrumenter.rb → lib/track_relay/event_payload.rb via EventPayload.new + validate!."
    verdict: pass
    evidence: "lib/track_relay/instrumenter.rb requires event_payload, uses EventPayload.new / EventPayload.untyped, calls #validate! (commit 6bb1678)"
  - criterion: "Key link lib/track_relay/instrumenter.rb → lib/track_relay/current.rb via Current.set + context snapshot."
    verdict: pass
    evidence: "lib/track_relay/instrumenter.rb requires current, calls Current.set in with_current_attrs, snapshots Current.user/controller/visit/client_id/request in #current_context (commit 6bb1678)"
  - criterion: "Key link lib/track_relay/instrumenter.rb → lib/track_relay/catalog.rb via Catalog.lookup."
    verdict: pass
    evidence: "lib/track_relay/instrumenter.rb requires catalog, calls Catalog.lookup(name) inside #track (commit 6bb1678)"
---

Wired TrackRelay.track / TrackRelay.identify on top of ActiveSupport::Notifications with split-routed reserved-key extraction (Current attrs vs payload.context), validation gating, untyped-event support, and a Current-snapshot contract for the future async DeliveryJob.

## What Was Built

- `TrackRelay::Instrumenter` module with `track` (typed + untyped), `identify` (Phase 01 pass-through), `partition_reserved` (3-bucket split: Current attrs / direct context / event params), `build_payload` (typed vs untyped + visitor_token merge), `current_context` (6-key snapshot), and `validate` (config-gated re-raise vs log+swallow).
- `TrackRelay.track` / `TrackRelay.identify` thin module-level delegates so consumers never reach into `Instrumenter` directly.
- `with_current_attrs` helper that no-ops when no reserved Current keys are present, sidestepping ActiveSupport 8.x's `Current.set(**{})` ArgumentError on zero-arg dispatch.
- 12 new integration tests (139 total, 263 assertions, 0 failures) across `test/integration/track_test.rb` (typed flow + reserved-key partitioning + validation gating), `test/integration/untyped_event_test.rb` (allow/disallow + reserved-key partitioning on untyped path), and `test/integration/identify_test.rb` (pass-through semantics + channel isolation between `track_relay.event` and `track_relay.identify`).
- All tests use `ActiveSupport::Notifications.subscribed { }` for capture; no manual unsubscribe and no global subscriber state to clean up.

## Files Modified

- `lib/track_relay/instrumenter.rb` -- created: central orchestrator for track/identify with reserved-key partitioning, context snapshot, AS::Notifications dispatch, and validation gating
- `lib/track_relay.rb` -- modified: require `track_relay/instrumenter` and add `TrackRelay.track` / `TrackRelay.identify` module-level delegates
- `test/integration/track_test.rb` -- created: 6 assertions over the typed (catalog-defined) path
- `test/integration/untyped_event_test.rb` -- created: 3 assertions over the no-catalog-match path (allow + disallow + reserved-key partitioning)
- `test/integration/identify_test.rb` -- created: 3 assertions over the identify pass-through (with + without properties + channel isolation from `track_relay.event`)

## Deviations

None. `Configuration#raise_on_validation_error` was already added in Plan 01-03 (the plan's prompt warned this attribute might be missing — it is not), so no scope expansion was required. The single shape change against the plan's reference snippet is `with_current_attrs`, an inlined guard that wraps `Current.set(**hash) { }` only when `hash` is non-empty; this prevents `ArgumentError: wrong number of arguments (given 0, expected 1)` from ActiveSupport 8.1.x's `CurrentAttributes#set` when no reserved Current keys are present in `params`. Documented in the implementation comments and verified by the smoke test (`ruby -Ilib -r track_relay -e 'TrackRelay.track(:_smoke, foo: 1)'`).
