# Phase 4: Polish — Context

Gathered: 2026-05-06
Calibration: architect

## Phase Boundary

Generators (`track_relay:install`, `track_relay:event`, `track_relay:subscriber`) + documentation audit + real-world integration verification through the existing `test/internal` Combustion harness. Phase 4 closes out the "Core (MVP)" milestone by validating the gem is ready to cut 1.0.0 immediately after Phase 4 UAT passes.

Engine mount, performance benchmarks, custom Rubocop cop, and additional v2 subscribers (PostHog / Plausible / Webhook / Mixpanel / Segment — REQ-18, REQ-19) are NOT part of Phase 4. They defer to a follow-up post-1.0.0 milestone.

## Decisions Made

### Phase scope — single phase vs new milestone
- Decision: Trim Phase 4 to generators + doc audit + dummy-app integration test. 1.0.0 cut happens AFTER Phase 4 UAT passes, within this same "Core (MVP)" milestone.
- Rationale: Cramming v1 stabilization (engine mount, benchmarks, Rubocop cop, additional integrations) into the MVP-completion phase delays a shippable interim release and conflates "finish MVP" with "cut v1." A focused Phase 4 (generators + docs + smoke test) is sufficient to validate the gem is ready for a stable 1.0.0 cut, and deferred items represent post-1.0.0 enhancements that benefit from real-world feedback first.

### 1.0.0 release timing
- Decision: 1.0.0 cuts AFTER Phase 4 verification, as the post-verification step inside this milestone (not a separate follow-up milestone).
- Rationale: Phase 4 completion and 1.0.0 readiness are coupled — the doc audit and dummy-app integration test ARE the 1.0.0 readiness checks. Promoting 1.0.0 to its own milestone would add ceremony without changing the work.

### Dummy-app integration test target
- Decision: Use the existing `test/internal` Combustion harness for the real-world integration test. No separate `rails new` app outside the gem repo.
- Rationale: `test/internal` already exercises the full Rails lifecycle (Railtie boot, ApplicationController concern, ActiveJob via Solid Queue/inline, Combustion-managed DB). A separate Rails app adds setup/maintenance cost with no incremental signal that Combustion isn't already providing.

### Out-of-scope items (Phase 4)
- No additional v2 subscribers (PostHog, Plausible, Webhook, Mixpanel, Segment) — REQ-18 stays Future.
- No optional engine mount for ad-blocker resilience — REQ-19 stays Future.
- No performance benchmarks.
- No custom Rubocop cop for raw `gtag` / `ahoy.track` calls.

### Generator UX style
- Decision: Opinionated Devise/ActiveAdmin-style scaffolds. `track_relay:install` emits a richly commented initializer + a working sample catalog (`config/track_relay/sample.rb`) + a working sample subscriber. `track_relay:event` and `track_relay:subscriber` produce opinionated working stubs (typed catalog DSL idioms, ApplicationController concern wired up, Test subscriber active in dev). `bundle exec rake test` must pass cleanly immediately after `rails g track_relay:install`.
- Rationale: Standard convention for Rails-gem 1.0.0 generators (Devise, ActiveAdmin, Spree). The first-touch experience is one of the strongest 1.0.0 signals; commented-out config blocks encode Phase 1–3 decisions and let new users learn the API by reading the generated files.
- Implication for Plan mode: Lead must allocate plan tasks for crafting the sample files (catalog content, subscriber content, ApplicationController concern hookup) — these are not throwaway stubs.

### Doc audit scope
- Decision: Standard Ruby-gem 1.0.0 set: README expansion (installation, quick example, links to deeper docs) + CHANGELOG audit in Keep-a-Changelog format with a 1.0.0 entry that includes a public-API stability statement + getting-started guide (`doc/usage.md` or USAGE.md) + migration notes (0.1.0 → 0.2.0 → 0.3.0 → 1.0.0). YARD/RDoc generation and a published doc site are out of scope for this phase.
- Rationale: Standard set is the convention for Ruby-gem 1.0.0 cuts; comprehensive (YARD + published site) is post-1.0.0 territory; minimal would underwhelm given the gem's surface area.
- Implication for Plan mode: One or more plans devoted to docs; migration notes need to enumerate breaking changes between releases (0.3.0 already had the BREAKING `init({manifestUrl})`-now-optional change recorded in CHANGELOG).

### Integration test scope (test/internal)
- Decision: Layered — structural assertions per generator (file exists, content matches expected shape, frontmatter/keys correct) + ONE happy-path end-to-end test that runs `track_relay:install` against a clean Combustion harness, exercises a tracked call from a controller, and asserts the Test subscriber captured the event with the correct typed payload.
- Rationale: Rails-gem standard (Devise, ActiveAdmin, Spree). Cheap structural tests catch generator regressions on every change; one E2E test validates the install generator's "ready to go" claim end-to-end. Avoids the slow-iteration trap of full-E2E-only and the wiring-blindness trap of structural-only.
- Implication for Plan mode: Test scaffolding may need a fresh-Combustion-harness pattern (clean state per test) since generator runs mutate the dummy app's `config/`. Lead should research whether existing test helpers can be reused or if a new harness wrapper is needed.

## Deferred Ideas

- **Engine mount for ad-blocker resilience** (REQ-19) — mountable Rails engine with first-party `/track_relay/events` POST endpoint. Defer to follow-up milestone.
- **Performance benchmarks** — per-event dispatch overhead, subscriber throughput, manifest generation time, end-to-end Rails request impact. Defer.
- **Custom Rubocop cop for raw `gtag` / `ahoy.track` calls** — likely as `rubocop-track_relay` companion gem per RuboCop plugin convention. Defer.
- **Additional v2 subscribers** (REQ-18) — PostHog (OSS product analytics), Plausible (privacy web analytics), Webhook (generic HTTPS sink), Mixpanel, Segment. Defer; selection happens during follow-up milestone scoping.
