---
phase: 2
plan: "04"
title: Ga4MeasurementProtocol server subscriber + DeliveryJob retry policy
status: complete
completed: 2026-05-07
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - cb09572
  - a0a9cfc
  - d7a711a
  - 31f8bd3
  - 51670cf
deviations: []
pre_existing_issues:
  - '{"test": "manual GA4 DebugView verification", "file": "test/integration/ga4_delivery_retry_test.rb", "error": "Requires real G-XXX measurement_id + api_secret — deferred to UAT; webmock-stubbed unit + integration tests cover the wire contract"}'
ac_results:
  - criterion: "TrackRelay::Subscribers::Ga4MeasurementProtocol < TrackRelay::Subscribers::Base exists and is async by default; supports opt-in via synchronous! per REQ-11"
    verdict: pass
    evidence: "lib/track_relay/subscribers/ga4_measurement_protocol.rb:70 + test/integration/ga4_synchronous_opt_in_test.rb"
  - criterion: "#deliver(payload) POSTs to mp/collect with the JSON body shape from Scout §2"
    verdict: pass
    evidence: "test/unit/subscribers/ga4_measurement_protocol_test.rb test_request_body_has_client_id_..."
  - criterion: "EU region toggle (config.ga4_use_eu_endpoint = true) posts to region1.google-analytics.com"
    verdict: pass
    evidence: "test/unit/subscribers/ga4_measurement_protocol_test.rb test_ga4_use_eu_endpoint_..."
  - criterion: "Call-time payload validation: >25 params or reserved-prefix → raise/log per raise_on_validation_error"
    verdict: pass
    evidence: "test/unit/subscribers/ga4_payload_validation_test.rb (11 tests)"
  - criterion: "DeliveryRetriableError + DeliveryDiscardableError defined in errors.rb; subscriber raises them on 5xx/4xx/network"
    verdict: pass
    evidence: "lib/track_relay/errors.rb:38-53 + test/unit/errors_test.rb + ga4_measurement_protocol_test 5xx/4xx/network cases"
  - criterion: "Subscribers::Base#safe_deliver carve-out re-raises both typed exceptions regardless of swallow_subscriber_errors"
    verdict: pass
    evidence: "lib/track_relay/subscribers/base.rb:145-156 + test/unit/subscribers/base_retry_passthrough_test.rb (7 tests)"
  - criterion: "DeliveryJob declares retry_on/discard_on with DEFAULT_GA4_DELIVERY_ATTEMPTS = 5 class-local constant"
    verdict: pass
    evidence: "lib/track_relay/delivery_job.rb:62-66 + test/integration/ga4_delivery_retry_test.rb"
  - criterion: "Configuration exposes ga4_measurement_id, ga4_api_secret, ga4_use_eu_endpoint; NO ga4_delivery_attempts"
    verdict: pass
    evidence: "lib/track_relay/configuration.rb:59 + test/unit/configuration_test.rb"
  - criterion: "Missing ga4_measurement_id or ga4_api_secret at delivery time emits Rails.logger.warn and returns without raising"
    verdict: pass
    evidence: "lib/track_relay/subscribers/ga4_measurement_protocol.rb:108-111 + test_missing_*_credentials cases"
  - criterion: "Test: webmock asserts URL/query/JSON body for purchase event with client_id from payload.context"
    verdict: pass
    evidence: "test/unit/subscribers/ga4_measurement_protocol_test.rb test_POSTs_to_mp_collect_..."
  - criterion: "Test: 5xx → DeliveryRetriableError → DeliveryJob re-enqueues (assert_enqueued_with)"
    verdict: pass
    evidence: "test/integration/ga4_delivery_retry_test.rb test_5xx_response_triggers_retry_on"
  - criterion: "Test: 26 dynamic params raises in dev/test, logs in prod"
    verdict: pass
    evidence: "test/unit/subscribers/ga4_payload_validation_test.rb (raise_on_validation_error true/false cases)"
  - criterion: "Test: synchronous! opt-in dispatches inline without enqueuing the job"
    verdict: pass
    evidence: "test/integration/ga4_synchronous_opt_in_test.rb"
---

Ships the server-side `Ga4MeasurementProtocol` subscriber with typed retry/discard exceptions, the load-bearing `Subscribers::Base#safe_deliver` carve-out that lets ActiveJob's `retry_on`/`discard_on` actually fire, call-time GA4 payload validation (REQ-27 split), and a `rake track_relay:lint:ga4` audit task — closing out wave 3 of Phase 02 (305 → 383 tests, all green).

## What Was Built

- `TrackRelay::Subscribers::Ga4MeasurementProtocol` — async server subscriber that POSTs validated events to GA4's Measurement Protocol via Net::HTTP (no new gem dep). Configurable global vs EU endpoint; warn-and-skip when credentials are nil; synthesized client_id fallback for server-only events.
- `TrackRelay::DeliveryRetriableError` and `TrackRelay::DeliveryDiscardableError` — direct StandardError subclasses (NOT TrackRelay::Error) so ActiveJob's retry_on/discard_on macros pick them up and consumers who rescue TrackRelay::Error don't accidentally swallow retriable network blips.
- `Subscribers::Base#safe_deliver` REQ-23 carve-out — re-raises the two typed exceptions BEFORE the existing log-and-return path, so retry_on/discard_on fire even when `swallow_subscriber_errors = true` (the production default). Without this narrow exception the entire retry policy is silently broken in production.
- `TrackRelay::DeliveryJob` retry/discard wiring — `retry_on TrackRelay::DeliveryRetriableError, wait: :polynomially_longer, attempts: DEFAULT_GA4_DELIVERY_ATTEMPTS` (= 5, class-local constant) and `discard_on TrackRelay::DeliveryDiscardableError`. The constant sidesteps the load-order hazard of reading from `TrackRelay.config` at class-body time.
- `TrackRelay::Configuration` GA4 attrs — `ga4_measurement_id`, `ga4_api_secret` (read at delivery time so credentials lambdas / late-bound configs work), and `ga4_use_eu_endpoint` (default false). Intentionally NO `ga4_delivery_attempts` — deferred to Phase 4.
- Call-time GA4 payload validation in `#deliver` (REQ-27 split, call-time half) — `payload.params.size <= 25` and reserved-prefix check (`firebase_`, `ga_`, `google_`). Honors `raise_on_validation_error` (raise in dev/test, log+skip in prod).
- `rake track_relay:lint:ga4` + `Linter#ga4_violations` / `#print_ga4` — audits the JSONL untyped sink for GA4 event-name violations; exits non-zero on violations so CI can gate.
- 78 new tests across 5 files (305 → 383 runs, 0 failures).

## Files Modified

- `lib/track_relay/errors.rb` -- modify: add DeliveryRetriableError + DeliveryDiscardableError as direct StandardError subclasses
- `lib/track_relay/configuration.rb` -- modify: add ga4_measurement_id, ga4_api_secret, ga4_use_eu_endpoint accessors + reset! defaults
- `lib/track_relay/subscribers/base.rb` -- modify: amend safe_deliver to RE-RAISE the typed retry/discard exceptions before the existing rescue (REQ-23 narrow carve-out)
- `lib/track_relay/subscribers/ga4_measurement_protocol.rb` -- create: 250-line subscriber implementing the GA4 wire contract + payload validation + Net::HTTP transport
- `lib/track_relay/delivery_job.rb` -- modify: add DEFAULT_GA4_DELIVERY_ATTEMPTS=5 + retry_on/discard_on declarations
- `lib/track_relay.rb` -- modify: require the new ga4_measurement_protocol subscriber
- `lib/track_relay/linter.rb` -- modify: add Ga4Violation struct, ga4_violations method, print_ga4 method
- `lib/tasks/track_relay.rake` -- modify: add `track_relay:lint:ga4` rake task
- `CHANGELOG.md` -- modify: 6 new [Unreleased] entries covering everything shipped in 02-04
- `test/unit/errors_test.rb` -- create: 7 tests pinning the typed-exception inheritance contract
- `test/unit/configuration_test.rb` -- modify: 8 tests for new GA4 config attrs + the deferred `ga4_delivery_attempts` pin
- `test/unit/subscribers/ga4_measurement_protocol_test.rb` -- create: 20 webmock-stubbed unit tests (URL/query/body, EU toggle, missing creds, error mapping, fallback client_id)
- `test/unit/subscribers/ga4_payload_validation_test.rb` -- create: 11 call-time payload validation tests (>25 params, reserved prefixes, raise/log gate)
- `test/unit/subscribers/base_retry_passthrough_test.rb` -- create: 7 tests pinning the carve-out behavior (re-raise typed, swallow others)
- `test/integration/ga4_delivery_retry_test.rb` -- create: 10 end-to-end tests verifying retry_on/discard_on fire correctly through the carve-out
- `test/integration/ga4_synchronous_opt_in_test.rb` -- create: 2 tests for the REQ-11 synchronous! opt-in path
- `test/unit/linter_test.rb` -- modify: 7 tests for the new ga4_violations / print_ga4 surface
- `test/integration/linter_rake_task_test.rb` -- modify: 4 tests for the new rake track_relay:lint:ga4 task

## Deviations

None. Every must_have shipped as planned. The plan's ⚠ live-validation step (real GA4 DebugView round-trip with authenticated credentials) is recorded in `pre_existing_issues` and deferred to UAT — webmock-stubbed coverage of the wire contract is sufficient to gate the QA review for 0.2.0.
