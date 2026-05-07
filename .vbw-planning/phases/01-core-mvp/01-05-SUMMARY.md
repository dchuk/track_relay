---
phase: 1
plan: "05"
title: Subscribers (Base, Test, Logger) + DeliveryJob
status: complete
completed: 2026-05-06
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - b520ea8
  - 9582495
  - 8c0c642
  - d9dd560
deviations: []
pre_existing_issues: []
ac_results:
  - criterion: "Subscribers::Base provides synchronous! macro, deliver/NotImplementedError, handle (sync vs async + per-subscriber rescue)"
    verdict: pass
    evidence: "lib/track_relay/subscribers/base.rb; test/integration/subscribers/base_test.rb (12 tests, all passing)"
  - criterion: "Per-subscriber rescue lives in Base#safe_deliver, ALWAYS logs via Rails.logger.error, returns exception (never re-raises inline). One bad subscriber does not abort peers."
    verdict: pass
    evidence: "base_test.rb 'safe_deliver does NOT re-raise even when swallow_subscriber_errors is false'; dispatcher_test.rb 'BOOM-BEFORE-TEST: peer captured event'"
  - criterion: "Dispatcher collects exceptions during fan-out and AFTER all subscribers have received the event, re-raises the FIRST one when swallow_subscriber_errors == false."
    verdict: pass
    evidence: "lib/track_relay/dispatcher.rb#dispatch (collect-then-reraise); test/integration/dispatcher_test.rb 'multiple boom subscribers: only the FIRST collected exception is re-raised' + BOOM-BEFORE-TEST/BOOM-AFTER-TEST loud/quiet matrix"
  - criterion: "Subscribers::Test opts into synchronous!, captures payloads per-instance via events Array, exposes clear! and find(name)"
    verdict: pass
    evidence: "lib/track_relay/subscribers/test.rb; test/integration/subscribers/test_subscriber_test.rb (7 tests including 'two instances are independent')"
  - criterion: "Subscribers::Logger opts into synchronous!, writes human-readable Rails.logger.info AND, when untyped_log_path is set AND payload is untyped, appends JSONL line {event, params, controller, action, timestamp} (param NAMES only)"
    verdict: pass
    evidence: "lib/track_relay/subscribers/logger.rb; test/integration/subscribers/logger_test.rb 'JSONL line keys are exactly [action, controller, event, params, timestamp]' + 'PRIVACY: param VALUES are NEVER written'"
  - criterion: "DeliveryJob < ActiveJob::Base performs subscriber.safe_deliver(EventPayload.from_h(payload_hash)); async loudness mirrors sync Dispatcher (re-raise iff !swallow_subscriber_errors)"
    verdict: pass
    evidence: "lib/track_relay/delivery_job.rb; test/integration/delivery_job_test.rb 'loud mode' + 'quiet mode' tests; queue_as :track_relay"
  - criterion: "Dispatcher is the single AS::Notifications subscription on track_relay.event; start! registers exactly one; stop! unsubscribes; both idempotent"
    verdict: pass
    evidence: "lib/track_relay/dispatcher.rb start!/stop!/started?; dispatcher_test.rb 'start! is idempotent', 'stop! is idempotent', 'started? reflects subscription state'"
  - criterion: "Async path: Base#handle calls DeliveryJob.perform_later(self.class.name, payload.to_h). Sync path: safe_deliver(payload) directly. Test and Logger always sync."
    verdict: pass
    evidence: "base_test.rb 'async subscriber: handle enqueues DeliveryJob with [class_name, to_h]'; Subscribers::Test and Subscribers::Logger both call synchronous!"
  - criterion: "EventPayload.from_h(hash) reconstructs from to_h form, with definition: nil"
    verdict: pass
    evidence: "lib/track_relay/event_payload.rb#from_h; delivery_job_test.rb 'round-trip' + 'round-trip survives ActiveJob string-key serialization'"
---

Implements the subscriber layer: Base sync/async dispatch + per-subscriber rescue, in-memory Test capture, human + JSONL Logger with the locked privacy contract, ActiveJob-backed DeliveryJob, and the Dispatcher fan-out implementing collect-then-reraise so peers always run before any loud re-raise.

## What Was Built

- `EventPayload.from_h` rehydrator that reconstructs an untyped payload from the `to_h` form, tolerant of ActiveJob's String-key argument round-trip and defensively coercing the name back to a Symbol.
- `Subscribers::Base` with `synchronous!` macro and the locked error contract: `safe_deliver` always logs and returns `nil` (success) or the StandardError (failure) — never re-raises inline. `handle` routes to sync (`safe_deliver` inline) or async (`DeliveryJob.perform_later`) based on `synchronous` and `force_synchronous`.
- `Subscribers::Test` synchronous! capture subscriber with per-instance state (no class-level globals), exposing `events`, `clear!`, and `find(name)` for consumer test suites.
- `Subscribers::Logger` synchronous! subscriber writing two outputs: `Rails.logger.info` always, and the JSONL untyped sidecar (only for untyped events when `untyped_log_path` is set) with the locked shape `{event, params, controller, action, timestamp}`. Privacy contract enforced: param NAMES only, never VALUES.
- `DeliveryJob < ActiveJob::Base` queued on `:track_relay`, mirroring the sync Dispatcher loudness contract: re-raises the StandardError returned by `safe_deliver` iff `!config.swallow_subscriber_errors`, so ActiveJob's normal retry/discard/failed-job path can surface failures.
- `Dispatcher` module with idempotent `start!`/`stop!`/`started?` and the collect-then-reraise dispatch loop. Defensive inline rescue covers non-Base subscribers that raise inline. Plan 06's Railtie will call `start!` once at boot.
- `test/test_helper.rb` teardown extended to call `Dispatcher.stop!` so any test that starts a subscription cannot leak it into the next test.

## Files Modified

- `lib/track_relay/event_payload.rb` -- modify: add `EventPayload.from_h` for ActiveJob round-trip rehydration.
- `lib/track_relay/subscribers/base.rb` -- create: Base subscriber with sync/async dispatch and per-subscriber rescue contract.
- `lib/track_relay/subscribers/test.rb` -- create: in-memory capture subscriber for consumer tests.
- `lib/track_relay/subscribers/logger.rb` -- create: human + JSONL untyped sidecar subscriber with locked privacy contract.
- `lib/track_relay/delivery_job.rb` -- create: ActiveJob-backed async delivery mirroring sync loudness contract.
- `lib/track_relay/dispatcher.rb` -- create: single AS::Notifications subscription with collect-then-reraise fan-out.
- `lib/track_relay.rb` -- modify: require the four new component files.
- `test/integration/subscribers/base_test.rb` -- create: Base sync/async dispatch + safe_deliver contract.
- `test/integration/subscribers/test_subscriber_test.rb` -- create: Test subscriber per-instance capture + clear/find.
- `test/integration/subscribers/logger_test.rb` -- create: Logger human + JSONL output + privacy regression.
- `test/integration/delivery_job_test.rb` -- create: DeliveryJob round-trip + loud/quiet mode + queue_as.
- `test/integration/dispatcher_test.rb` -- create: Dispatcher lifecycle + collect-then-reraise + first-error-wins ordering.
- `test/test_helper.rb` -- modify: teardown calls `Dispatcher.stop!` to prevent subscription leakage between tests.

## Deviations

None. All 4 tasks executed in sequence per plan; TDD red-green cycle followed for each task; full default rake task (standardrb + tests) green at every commit boundary. 182 tests / 371 assertions cumulative (up from 139 / 263 baseline).
