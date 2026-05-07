---
phase: 02
tier: standard
result: PARTIAL
passed: 71
failed: 3
total: 74
date: 2026-05-07
verified_at_commit: 4dd8c4acf585f944af54780dcfc1c7ca4164efb8
writer: write-verification.sh
plans_verified:
  - 02-01
  - 02-02
  - 02-03
  - 02-04
  - 02-05
---

## Must-Have Checks

| # | ID | Truth/Condition | Status | Evidence |
|---|-----|-----------------|--------|----------|
| 1 | MH-01 | webmock ~> 3.23 added as development dependency in track_relay.gemspec | PASS | track_relay.gemspec:41 — spec.add_development_dependency "webmock", "~> 3.23" |
| 2 | MH-02 | require 'webmock/minitest' and WebMock.disable_net_connect! present in test/test_helper.rb | PASS | test/test_helper.rb:32 require 'webmock/minitest'; :38 WebMock.disable_net_connect!(allow_localhost: true) |
| 3 | MH-03 | Subscribers::Base exposes class_attribute :only_events, :except_events and class-level filter DSL | PASS | base.rb:42 class_attribute :only_events default nil; :43 except_events default nil; :69 def self.filter(only:, except:) |
| 4 | MH-04 | Base#handle short-circuits with return nil when event filtered, BEFORE sync/async branch and BEFORE safe_deliver rescue | PASS | base.rb:110 return nil if filtered?(payload.name.to_sym) — before safe_deliver at :113 |
| 5 | MH-05 | TrackRelay.subscribe(klass_or_instance, only: nil, except: nil) exists in lib/track_relay.rb | PASS | lib/track_relay.rb:175 def self.subscribe(subscriber_or_class, only: nil, except: nil) |
| 6 | MH-06 | Test: filtered subscriber receives only events in only: set; except: set blocks listed events; no filter = all events | PASS | test/unit/subscribers/base_filter_test.rb (4.3K) — only-allows, except-drops, no-filter-receives-all cases confirmed |
| 7 | MH-07 | Test: filter check happens before safe_deliver — filtered event with raising deliver does NOT raise or log | PASS | test/unit/subscribers/base_filter_test.rb test_filter_check_runs_BEFORE_safe_deliver confirmed by SUMMARY ac_results |
| 8 | MH-08 | Existing Phase 1 test suite still passes — no behavior change for unfiltered subscribers | PASS | bundle exec rake: 383 runs, 857 assertions, 0 failures, 0 errors, 0 skips |
| 9 | MH-09 | TrackRelay::Configuration exposes client_id_resolvers (Array, default [Ga, AhoyVisitor, Session]); resettable in reset_config! | PASS | configuration.rb:81 @client_id_resolvers = default_client_id_resolvers; :117 private default_client_id_resolvers; attr_accessor :58 |
| 10 | MH-10 | ClientId::Ga#call returns last-two-segments of _ga cookie or nil; matches Phase 1 parser | PASS | lib/track_relay/client_id/ga.rb (1.8K); test/unit/client_id/ga_test.rb covers standard format, <4 segments nil, extra segments |
| 11 | MH-11 | ClientId::AhoyVisitor#call duck-typed via respond_to?(:ahoy, true); returns nil without NameError when ahoy absent; no require of ahoy | PASS | ahoy_visitor.rb:28 controller.respond_to?(:ahoy, true); comment :14 confirms no require 'ahoy'; grep lib/ shows only comment |
| 12 | MH-12 | ClientId::Session#call returns session[:track_relay_client_id] &#124;&#124;= SecureRandom.uuid; nil when no session | PASS | session.rb:42 session[SESSION_KEY] &#124;&#124;= SecureRandom.uuid; test/unit/client_id/session_test.rb covers UUID stability |
| 13 | MH-13 | ControllerTracking#_track_relay_set_current calls _resolve_client_id; inline _track_relay_client_id_from_cookie removed | PASS | controller_tracking.rb:64 Current.client_id = _resolve_client_id; grep lib/ returns only a docstring comment in ga.rb for _track_relay_client_id_from_cookie |
| 14 | MH-14 | Test: _ga cookie present → Current.client_id matches Phase 1 output (parity) | PASS | controller_tracking_test.rb:62 '_ga cookie populates Current.client_id' asserts '123456789.1700000000' — untouched parity test passes |
| 15 | MH-15 | Test: no _ga cookie + no Ahoy → Current.client_id is a session-stable UUID | PASS | controller_tracking_test.rb:75 'missing _ga cookie falls through to Session UUID' — refute_nil + UUID format match; client_id_chain_test.rb:150 stable-across-two-requests |
| 16 | MH-16 | Test: custom resolver inserted at position 0 wins over defaults | PASS | test/integration/client_id_chain_test.rb:96 'custom resolver inserted at position 0 wins over defaults' |
| 17 | MH-17 | Test: exception inside one resolver does NOT abort the chain | PASS | test/integration/client_id_chain_test.rb:107 'a resolver raising StandardError does NOT abort the chain' |
| 18 | DEV-01 | DEVN-02 (declared deviation): two Phase-1 ControllerTrackingTest cases updated from assert_nil to UUID format — plan task note said existing tests must pass with no changes | FAIL | controller_tracking_test.rb:75,92 now use refute_nil + assert_match UUID regex (was assert_nil). Cookie-present parity test at :62 unchanged. Must_have MH-15 PASS. Deviation is plan violation — task 4 note explicitly said no changes to existing tests. |
| 19 | MH-18 | Manifest.generate returns Hash matching shape {version:, generated_at:, events: {name => {params:, required:}}} | PASS | manifest.rb:43-50 generate method with VERSION, iso8601 generated_at, events hash; manifest_test.rb covers all 5 types + required/optional |
| 20 | MH-19 | Manifest.write!(path:) writes pretty JSON; FileUtils.mkdir_p called before write; default path = Rails.root/public/track_relay_catalog.json | PASS | manifest.rb:69 FileUtils.mkdir_p(File.dirname(path)); :70 File.write + JSON.pretty_generate; default_path private method |
| 21 | MH-20 | Manifest.write! succeeds in fresh checkout with no public/ directory — test_creates_parent_directory | PASS | manifest_test.rb test_creates_parent_directory uses Dir.mktmpdir + brand_new_subdir/ — green in full suite |
| 22 | MH-21 | rake track_relay:manifest task exists; depends on :environment; aborts non-zero when Catalog.all.empty? | PASS | tasks/track_relay.rake: task manifest: :environment at :68; abort 'catalog is empty' at :73; manifest_rake_test.rb covers both paths |
| 23 | MH-22 | Railtie initializer track_relay.enhance_assets_precompile chains track_relay:manifest when assets:precompile is defined | PASS | railtie.rb:79-89 initializer with Rake guard; manifest_dev_reload_test.rb verifies prerequisite chaining |
| 24 | MH-23 | Railtie dev-mode regeneration: to_prepare calls Manifest.write! when Rails.env.development? after catalog reload | PASS | railtie.rb:60-62 if Rails.env.development? && Catalog.all.any? then Manifest.write! inside catalog_autoload to_prepare block |
| 25 | MH-24 | Test: Manifest.generate produces correct shape for mixed required/optional params and all 5 ParamSchema types | PASS | manifest_test.rb: test_generate_covers_all_5_ParamSchema_types + test_generate_emits_params_as_Hash_required[]_as_strings — both green |
| 26 | MH-25 | Test: rake track_relay:manifest exits non-zero when catalog is empty | PASS | manifest_rake_test.rb test_aborts_NONZERO_when_catalog_is_empty — SystemExit + refute_equal 0 status + /catalog is empty/i |
| 27 | MH-26 | Test: dev-mode reload regenerates file after to_prepare invocation | PASS | manifest_dev_reload_test.rb test_to_prepare_regenerates_when_Rails.env.development? stubs env + invokes reloader.prepare! — green |
| 28 | MH-27 | Manifest JSON is valid JSON.parse-able with version matching TrackRelay::VERSION | PASS | manifest_test.rb parses JSON.pretty_generate and asserts version equals TrackRelay::VERSION; also covered by manifest_rake_test |
| 29 | DEV-02 | DEVN-01A (declared deviation): tasks 1+2 combined into single commit 4f6aa3d instead of two separate commits | FAIL | 02-03-SUMMARY.md has 4 commits for 5 tasks — tasks 1+2 merged in commit 4f6aa3d. All must_haves MH-18 through MH-27 PASS. Recorded FAIL per protocol. |
| 30 | DEV-03 | DEVN-01B (declared deviation): defined?(Rake) && guard added to track_relay.enhance_assets_precompile — not in plan body spec | FAIL | railtie.rb:85 if defined?(Rake) && Rake::Task.task_defined?(...). Plan body showed bare Rake::Task.task_defined?. In-spirit fix for Combustion NameError. MH-22 PASS. |
| 31 | MH-28 | Ga4MeasurementProtocol < Subscribers::Base; async by default; synchronous! opt-in per REQ-11 | PASS | ga4_measurement_protocol.rb:70 class Ga4MeasurementProtocol < Base; no synchronous! in class body; ga4_synchronous_opt_in_test.rb covers opt-in |
| 32 | MH-29 | #deliver POSTs to mp/collect with correct JSON body shape (client_id, timestamp_micros, events[]) | PASS | ga4_measurement_protocol_test.rb webmock-stubbed URL/query/body assertions — SUMMARY verdict: pass |
| 33 | MH-30 | EU region toggle: config.ga4_use_eu_endpoint = true → POST to region1.google-analytics.com/mp/collect | PASS | ga4_measurement_protocol.rb:75 ENDPOINT_URL_EU = 'https://region1.google-analytics.com/mp/collect'; :110 uses ga4_use_eu_endpoint flag |
| 34 | MH-31 | Call-time payload validation: >25 params or reserved prefix raises Ga4ConstraintError or warns per raise_on_validation_error | PASS | ga4_payload_validation_test.rb 11 tests — SUMMARY verdict: pass |
| 35 | MH-32 | DeliveryRetriableError and DeliveryDiscardableError defined in errors.rb as direct StandardError subclasses | PASS | errors.rb:45 class DeliveryRetriableError < StandardError; :53 class DeliveryDiscardableError < StandardError |
| 36 | MH-33 | Subscribers::Base#safe_deliver carve-out re-raises DeliveryRetriableError and DeliveryDiscardableError regardless of swallow_subscriber_errors | PASS | base.rb:148 rescue DeliveryRetriableError, DeliveryDiscardableError then raise; base_retry_passthrough_test.rb 7 tests |
| 37 | MH-34 | DeliveryJob declares retry_on with :polynomially_longer and DEFAULT_GA4_DELIVERY_ATTEMPTS=5; discard_on DeliveryDiscardableError | PASS | delivery_job.rb:60 DEFAULT_GA4_DELIVERY_ATTEMPTS = 5; :62 retry_on...wait: :polynomially_longer; :66 discard_on |
| 38 | MH-35 | Configuration exposes ga4_measurement_id, ga4_api_secret, ga4_use_eu_endpoint; NO ga4_delivery_attempts accessor | PASS | configuration.rb:59-61 three accessors; grep ga4_delivery_attempts lib/ → 0 matches |
| 39 | MH-36 | Missing ga4_measurement_id or ga4_api_secret emits Rails.logger.warn and returns without raising | PASS | ga4_measurement_protocol.rb:104 warn_missing_credentials; :244 Rails.logger.warn — SUMMARY verdict: pass |
| 40 | MH-37 | Test: webmock asserts POST URL, query string, JSON body for purchase event with client_id | PASS | ga4_measurement_protocol_test.rb covers URL/query/body assertions — SUMMARY verdict: pass |
| 41 | MH-38 | Test: 5xx → DeliveryRetriableError; DeliveryJob re-enqueues via assert_enqueued_with | PASS | ga4_delivery_retry_test.rb test_5xx_response_triggers_retry_on — SUMMARY verdict: pass |
| 42 | MH-39 | Test: 26 dynamic params raises in dev/test; logs in prod | PASS | ga4_payload_validation_test.rb raise_on_validation_error true/false cases — SUMMARY verdict: pass |
| 43 | MH-40 | Test: synchronous! opt-in dispatches inline without enqueuing job | PASS | ga4_synchronous_opt_in_test.rb 2 tests — SUMMARY verdict: pass |
| 44 | MH-41 | client/package.json with name @track_relay/client, version 0.2.0, type module, dual ESM+CJS exports, files includes dist/ | PASS | package.json: name '@track_relay/client', version '0.2.0', type 'module', exports import→./dist/index.mjs require→./dist/index.cjs, files: ['dist','src/index.d.ts','README.md'] |
| 45 | MH-42 | tsup produces both dist/index.mjs AND dist/index.cjs; build smoke test asserts both exist and non-empty | PASS | npm run build: mjs 3862B, cjs 4985B; test/build_smoke.test.js 4 tests pass |
| 46 | MH-43 | index.js exports init/track/setClientId/Ga4Gtag; init() throws synchronously (not via rejected promise) when measurementId or manifestUrl is nullish | PASS | index.js:47 if (!measurementId &#124;&#124; !manifestUrl) throw new Error(...) — sync before _initAsync; 6 required-both tests pass |
| 47 | MH-44 | client/src/index.d.ts exists with full public type signatures | PASS | index.d.ts exists (2.6K) — InitOptions, TrackParams, init, track, setClientId, Ga4Gtag documented |
| 48 | MH-45 | init() fetches manifest URL, stores measurementId; subsequent track() dispatches via gtag('event'); first track() emits gtag('config') once | PASS | index.js:56-65 _initAsync; :113-119 lazy config flush; gtag config lifecycle tests pass |
| 49 | MH-46 | Validation mirrors REQ-05: env=development throws Error; env=production console.warns and drops | PASS | validator.js + index.js:75-89 dev/prod branching; 8 validation tests in index.test.js pass |
| 50 | MH-47 | track() calls window.gtag('event', name, params) after validation; missing window.gtag warns and drops | PASS | index.js:91-94 gtag dispatch; test 'missing window.gtag — warn + drop, never throw' passes |
| 51 | MH-48 | Ga4Gtag named export with handle(name, params); reads same module-private state as init | PASS | index.js:132 export const Ga4Gtag = Object.freeze({name:'Ga4Gtag', handle(...)}); ga4_gtag.test.js 4 tests pass |
| 52 | MH-49 | Vitest suite: init fetches manifest, throws on missing fields, track validates, dev throws/prod warns, unknown event passes through, missing gtag warns+drops, gtag(config) once | PASS | 31 tests across 3 files (build_smoke 4, index 23, ga4_gtag 4) all pass — confirmed by npm test output |
| 53 | MH-50 | .github/workflows/ci.yml adds js-test job on Node 22; build runs BEFORE test | PASS | .github/workflows/ci.yml:36-53 js-test job, node-version: '22', steps: npm ci → npm run build → npm test in sequence |
| 54 | MH-51 | lib/track_relay/version.rb bumped to 0.2.0 | PASS | grep VERSION lib/track_relay/version.rb → VERSION = "0.2.0" |
| 55 | MH-52 | CHANGELOG.md has ## [0.2.0] - <date> collecting all [Unreleased] bullets | PASS | CHANGELOG.md:10 ## [0.2.0] - 2026-05-06 |
| 56 | MH-53 | README.md has new section documenting GA4 subscriber, client_id_resolvers, manifest, @track_relay/client install + init with ERB snippet | PASS | README.md:28 npm install @track_relay/client; :313 import { init }; :324 import { track } — GA4 section present |

## Artifact Checks

| # | ID | Artifact | Exists | Contains | Status |
|---|-----|----------|--------|----------|--------|
| 1 | ART-01 | test/unit/subscribers/base_filter_test.rb and test/unit/track_relay_subscribe_test.rb | Yes | filter only/except/no-filter cases + TrackRelay.subscribe 7 cases | PASS |
| 2 | ART-02 | lib/track_relay/client_id/*.rb; test/unit/client_id/*_test.rb; test/integration/client_id_chain_test.rb | Yes | three resolver implementations + unit tests + chain integration test | PASS |
| 3 | ART-03 | lib/track_relay/manifest.rb; test/unit/manifest_test.rb; test/integration/manifest_rake_test.rb; test/integration/manifest_dev_reload_test.rb | Yes | generate/write! methods + rake task tests + dev-reload tests | PASS |
| 4 | ART-04 | lib/track_relay/subscribers/ga4_measurement_protocol.rb + 5 test files | Yes | 250-line subscriber + 78 new tests across unit and integration | PASS |
| 5 | ART-05 | client/ npm package: src/index.js, index.d.ts, validator.js, dist/index.mjs, dist/index.cjs | Yes | dual ESM+CJS build artifacts with real CommonJS exports | PASS |

## Key Link Checks

| # | ID | From | To | Via | Status |
|---|-----|------|-----|-----|--------|
| 1 | KL-01 | lib/track_relay/subscribers/base.rb#handle | filtered? | return nil if filtered?(payload.name.to_sym) | PASS |
| 2 | KL-02 | lib/track_relay.rb | lib/track_relay/client_id/*.rb | three require statements before configuration.rb | PASS |
| 3 | KL-03 | lib/tasks/track_relay.rake | lib/track_relay/manifest.rb | require_relative | PASS |
| 4 | KL-04 | lib/track_relay/subscribers/base.rb#safe_deliver | lib/track_relay/delivery_job.rb retry_on/discard_on | re-raise before existing rescue | PASS |
| 5 | KL-05 | .github/workflows/ci.yml | client/dist/ | build step before test step | PASS |

## Anti-Pattern Scan

| # | ID | Pattern | Status | Evidence |
|---|-----|---------|--------|----------|
| 1 | AP-01 | No require 'ahoy' in AhoyVisitor (would cause NameError in non-Ahoy hosts) | PASS | grep lib/ for require 'ahoy' returns only a comment confirming absence; duck-typed via respond_to? only |
| 2 | AP-02 | ga4_delivery_attempts NOT a Configuration accessor (avoids class-body load-order hazard) | PASS | grep ga4_delivery_attempts configuration.rb → 0 matches; class-local constant used instead |
| 3 | AP-03 | defined?(Rake) guard prevents NameError in API-only Rails apps that do not load Rake | PASS | railtie.rb:85 if defined?(Rake) && Rake::Task.task_defined?('assets:precompile') |
| 4 | AP-04 | init() throws synchronously (not via rejected promise) on missing measurementId or manifestUrl | PASS | index.js:47 sync throw before _initAsync delegation; 6 required-both tests including fetch-not-called assertion |

## Convention Compliance

| # | ID | Convention | File | Status | Detail |
|---|-----|------------|------|--------|--------|
| 1 | CONV-01 | bundle exec rake passes: 383 runs, 0 failures (standardrb + full minitest suite) | all phase 02 Ruby files | PASS | standardrb --fix applied across all modified Ruby files per plan convention |
| 2 | CONV-02 | JS suite: 31 tests pass; dist artifacts non-empty after npm run build | client/ | PASS | tsup dual-build + vitest run via required CI command |
| 3 | CONV-03 | CJS build is real CommonJS: node -e require index.cjs → typeof init = 'function' | client/dist/index.cjs | PASS | Honors 02-CONTEXT dual ESM+CJS commitment |
| 4 | CONV-04 | Release consistency: client version 0.2.0, Ruby VERSION 0.2.0, CHANGELOG [0.2.0], README @track_relay/client section | client/package.json, lib/track_relay/version.rb, CHANGELOG.md, README.md | PASS | All version-bearing files consistent at 0.2.0 |

## Pre-existing Issues

| Test | File | Error |
|------|------|-------|
| manual GA4 DebugView verification | test/integration/ga4_delivery_retry_test.rb | Requires real G-XXX measurement_id + api_secret — deferred to UAT; webmock-stubbed unit + integration tests cover the wire contract |
| manual GA4 Realtime browser smoke | client/test/index.test.js | Requires real measurement_id + browser session — deferred to UAT; happy-dom + vitest cover the contract |

## Summary

**Tier:** standard
**Result:** PARTIAL
**Passed:** 71/74
**Failed:** DEV-01, DEV-02, DEV-03
