---
phase: 3
plan: "01"
title: Ahoy server subscriber + dev-dep wiring
status: complete
completed: 2026-05-06
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - 29e3167e2fa252b93af62c1eff56635fb9d27701
  - 4f2ff9d44f5f24a2ed455954caef387c10c27aa7
  - b837ac1a468cd5fc74c588a93783ae8b42b5b9ce
  - c9ce847a9c4f88f16d9d6fcf67710e0bd91d4e75
deviations: []
resolved_by_amendment:
  - "DEVN-02 visit.track absent: ROADMAP success criteria mention `Ahoy::Visit#track` as a fallback dispatch path; no such method exists on `Ahoy::Visit` (per 03-RESEARCH.md §2). Plan 03-01 MH-06 was amended in QA Remediation Round 01 (commit `323e183`, MH-06 plan-amendment) to replace the self-deviation must_have with two affirmative must_haves describing the implemented `controller.ahoy.track`-only routing and the no-controller skip-path substitute. R01-VERIFICATION confirms the amendment."
  - "DEVN-01 verification grep mismatch: Plan verification step said `grep -n ahoy_matey gemfiles/rails_*.gemfile` should match. Appraisal-generated `.gemfile` files only contain `gemspec path: \"../\"`, so `ahoy_matey` resolves transitively through the gemspec dev-dep block; lockfile evidence confirms resolution under all three appraisals (5.4.2/5.5.0/5.5.0). Plan 03-01 MH-02 was amended in QA Remediation Round 01 (commit `323e183`, MH-02 plan-amendment) to assert lockfile presence instead. R01-VERIFICATION confirms the amendment."
pre_existing_issues: []
ac_results:
  - criterion: "ahoy_matey is a development dependency in track_relay.gemspec (no version pin needed initially)"
    verdict: pass
    evidence: "track_relay.gemspec:33 (commit 29e3167)"
  - criterion: "ahoy_matey appears in each generated gemfile under gemfiles/ (regenerate via bundle exec appraisal generate)"
    verdict: partial
    evidence: "Appraisal-generated .gemfile files only inline `gemspec path: \"../\"` — ahoy_matey resolves transitively through the gemspec; lockfiles confirm: gemfiles/rails_7_1.gemfile.lock:91 (5.4.2), gemfiles/rails_7_2.gemfile.lock:85 (5.5.0), gemfiles/rails_8_0.gemfile.lock:83 (5.5.0). All three appraisals pass `bundle exec appraisal rails_X_Y rake`. See DEVN-01 in deviations."
  - criterion: "lib/track_relay/subscribers/ahoy.rb exists, defines class TrackRelay::Subscribers::Ahoy < TrackRelay::Subscribers::Base, calls synchronous! at the class body, and does NOT require \"ahoy\" or \"ahoy_matey\""
    verdict: pass
    evidence: "lib/track_relay/subscribers/ahoy.rb:62-64 (commit b837ac1); negative grep on `require \"ahoy\"` clean in code lines"
  - criterion: "require \"track_relay/subscribers/ahoy\" added to lib/track_relay.rb directly after the GA4 require"
    verdict: pass
    evidence: "lib/track_relay.rb:21 (commit b837ac1)"
  - criterion: "#deliver(payload) reads TrackRelay::Current.controller directly, checks controller&.respond_to?(:ahoy, true), dispatches via controller.ahoy.track(payload.name.to_s, payload.params) only — never via Ahoy::Event.create! or any internal API"
    verdict: pass
    evidence: "lib/track_relay/subscribers/ahoy.rb:71-87 (commit b837ac1); test_dispatches_via_controller.ahoy.track_when_controller_is_present passes"
  - criterion: "DEVIATION RECORDED: routes via controller.ahoy.track only, not visit.track (which does not exist on Ahoy::Visit)"
    verdict: pass
    evidence: "Recorded in deviations array above (DEVN-02); also noted in 03-RESEARCH.md §2"
  - criterion: "Skip-not-raise: nil controller / no :ahoy / nil tracker → log warn via Rails.logger.warn (guarded) and return; no raise, no enqueue, no Ahoy API call"
    verdict: pass
    evidence: "lib/track_relay/subscribers/ahoy.rb:74-86, log_skip helper at lines 96-99 (commit b837ac1); three skip tests in test/unit/subscribers/ahoy_test.rb pass (commit 4f2ff9d, 4)"
  - criterion: "Synchronous dispatch: assert TrackRelay::Subscribers::Ahoy.synchronous returns true"
    verdict: pass
    evidence: "lib/track_relay/subscribers/ahoy.rb:64 (synchronous!); test_synchronous_flag_is_set passes"
  - criterion: "Unit tests in test/unit/subscribers/ahoy_test.rb cover seven cases (a–g)"
    verdict: pass
    evidence: "test/unit/subscribers/ahoy_test.rb (commit 4f2ff9d) — all seven tests pass under `bundle exec rake test TEST=test/unit/subscribers/ahoy_test.rb`"
  - criterion: "Unit tests use a stubbed tracker (Minitest::Mock or define_singleton_method(:ahoy)) — no real Ahoy::Tracker"
    verdict: pass
    evidence: "test/unit/subscribers/ahoy_test.rb:62-66 (build_controller_with_tracker helper) uses Object.new + define_singleton_method; mock_tracker is Minitest::Mock"
  - criterion: "Integration tests in test/integration/ahoy_delivery_test.rb cover (1) full pipeline with assert_no_enqueued_jobs only: TrackRelay::DeliveryJob; (2) job-context skip with no enqueue, no exception, warn line matched"
    verdict: pass
    evidence: "test/integration/ahoy_delivery_test.rb (commit c9ce847) — both tests pass under `bundle exec rake test TEST=test/integration/ahoy_delivery_test.rb`"
  - criterion: "All three Rails appraisals pass after this plan: rails_7_1, rails_7_2, rails_8_0"
    verdict: pass
    evidence: "bundle exec appraisal rails_7_1 rake → 392 runs, 0 failures; rails_7_2 → 392 runs, 0 failures; rails_8_0 → 392 runs, 0 failures"
  - criterion: "DUMMY-APP WIRING IS OUT OF SCOPE: no Combustion-app changes; all tests use stubbed trackers"
    verdict: pass
    evidence: "test/internal/app/controllers/application_controller.rb and test/internal/db/ untouched; both new test files use Minitest::Mock + define_singleton_method"
---

Server-side `TrackRelay::Subscribers::Ahoy` shipped: synchronous, duck-typed wrapper that routes catalog events through `controller.ahoy.track` (Ahoy's only public tracking surface) and skip-logs when no controller is in scope. All 392 tests pass on all three Rails appraisals (7.1, 7.2, 8.0).

## What Was Built

- `TrackRelay::Subscribers::Ahoy` subscriber class — inherits `Subscribers::Base`, calls `synchronous!`, implements `#deliver(payload)` per the research-§3 sketch with three skip-not-raise paths and a private `#log_skip(reason)` helper mirroring `Ga4MeasurementProtocol#warn_missing_credentials`.
- Duck-typed integration: no `require "ahoy"`, no `Ahoy::Event.create!`, no `Ahoy::Tracker.new` — graceful absence in non-Ahoy host apps via `respond_to?(:ahoy, true)` (precedent: `ClientId::AhoyVisitor`).
- `ahoy_matey` added as a development dependency in `track_relay.gemspec`; resolves to 5.4.2 (rails_7_1) / 5.5.0 (rails_7_2 + rails_8_0) in the appraisal lockfiles.
- Seven Minitest unit cases (`test/unit/subscribers/ahoy_test.rb`) using stubbed trackers, plus two integration cases (`test/integration/ahoy_delivery_test.rb`) pinning the full Dispatcher → subscriber → tracker pipeline AND the job-context skip path.

## Files Modified

- `track_relay.gemspec` -- modify: append `spec.add_development_dependency "ahoy_matey"` to dev-deps block (commit 29e3167)
- `Gemfile.lock` -- modify: bundler regenerated to include ahoy_matey 5.5.0 (commit 29e3167)
- `lib/track_relay/subscribers/ahoy.rb` -- create: server-side Ahoy subscriber (commit b837ac1)
- `lib/track_relay.rb` -- modify: insert `require "track_relay/subscribers/ahoy"` after the GA4 subscriber require (commit b837ac1)
- `test/unit/subscribers/ahoy_test.rb` -- create: seven unit cases pinning the subscriber contract (commits 4f2ff9d + b837ac1 minor assertion-warning fix)
- `test/integration/ahoy_delivery_test.rb` -- create: two integration cases for full pipeline + job-context skip (commit c9ce847)

## Deviations

**None remaining as contract deviations.** Both originally-recorded items below were resolved by plan amendment in QA Remediation Round 01 (commit `323e183`):

- ~~DEVN-02 visit.track absent~~ → Plan 03-01 MH-06 amended (resolved-by-amendment). See R01-VERIFICATION.md.
- ~~DEVN-01 verification grep mismatch~~ → Plan 03-01 MH-02 amended (resolved-by-amendment). See R01-VERIFICATION.md.
