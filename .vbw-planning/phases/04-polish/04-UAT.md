---
phase: 04
title: Polish — UAT (1.0.0 Generator + Doc Audit)
status: complete
started: 2026-05-07
completed: 2026-05-07
total_tests: 6
passed: 6
failed: 0
skipped: 0
issues_count: 0
---

# Phase 04 UAT: Polish for 1.0.0

This phase ships the three Rails generators (`track_relay:install`, `track_relay:event`, `track_relay:subscriber`), their structural tests, an E2E happy-path test, and the 1.0.0 documentation rewrite (README + CHANGELOG `[1.0.0]` + `USAGE.md` + `UPGRADING.md`). Work is library-internal — no live app to click through — so UAT focuses on subjective quality of the user-facing surfaces (generator output ergonomics + docs).

## Tests

### P1-T1 — Install generator scaffolding feels right for first 30 seconds

Read the four files in `lib/generators/track_relay/install/`:
- `install_generator.rb` (the 5 action methods — initializer, sample catalog, ApplicationSubscriber, guarded inject, post-install message)
- `templates/initializer.rb.tt` (richly commented; Logger active; Test/GA4/Ahoy/untyped-events scaffolds commented)
- `templates/sample_catalog.rb.tt` (working `event :hello_world` with one required `string :message`)
- `templates/application_subscriber.rb.tt` (`ApplicationSubscriber < TrackRelay::Subscribers::Base`)

**Expected:** A Rails developer running `bin/rails g track_relay:install` for the first time gets a working configuration that explains itself. The initializer comments cover GA4/Ahoy/test-mode without overwhelming. The sample catalog is tutorial-clear (`:hello_world`, not `page_view`). The ApplicationSubscriber is a reasonable empty starting point.

Result: pass

### P2-T1 — Event + subscriber generators emit useful stubs (not skeletons)

Read the four files added by plan 04-02:
- `lib/generators/track_relay/event/event_generator.rb`
- `lib/generators/track_relay/event/templates/event.rb.tt` (5 type stubs: integer/string/float/boolean/datetime)
- `lib/generators/track_relay/subscriber/subscriber_generator.rb`
- `lib/generators/track_relay/subscriber/templates/subscriber.rb.tt` (NamedBase ERB; commented `synchronous!`/`filter only:`/registration block)

**Expected:** Running `rails g track_relay:event ArticleViewed` and `rails g track_relay:subscriber Mixpanel` produces files that point the developer at real next steps — type stubs they can keep or trim, filter examples they can copy. The subscriber template subclasses `TrackRelay::Subscribers::Base` (NOT `ApplicationSubscriber`) so it works pre-install. Event files are self-contained `TrackRelay.catalog do ... end` blocks so the Railtie can glob and merge them.

Result: pass

### P3-T1 — Generator structural tests are sound (light checkpoint, internal)

Plan 04-03 adds `Rails::Generators::TestCase` tests for all three generators. They use a tmpdir destination (`File.expand_path("../../../tmp/generator_test", __dir__)`) so `test/internal/` stays untouched. The install generator test exercises **all three branches** of the inject guard: clean inject, idempotent no-op when `TrackRelay::ControllerTracking` is already included, and skip when ApplicationController doesn't exist.

**Expected:** The test approach (tmpdir + `setup :prepare_destination` + `assert_match` content checks) feels like the right tradeoff — durable, isolated, no `test/internal/` pollution. No concerns about tmpdir collisions or branch coverage.

Result: pass

### P4-T1 — E2E happy-path test approach is sufficient (light checkpoint, internal)

Plan 04-04 adds `test/integration/generator_install_e2e_test.rb`. Flow: invoke `Rails::Generators.invoke("track_relay:install", ...)` into a tmpdir → copy catalog + subscriber outputs into the live `test/internal/` Combustion app → reload catalog → hit `/hello` route → assert `assert_tracked :hello_world, message: "..."`. Initializer is excluded from the copy; the inject step hits the "ApplicationController not found" skip branch.

**Expected:** The E2E proves the generator binary actually produces files that load and dispatch end-to-end. The deliberate isolation choices (skip initializer, hit skip branch on inject) are clearly the right call — the live `test/internal/app/controllers/application_controller.rb` already includes `TrackRelay::ControllerTracking` as fixture state, not generator output.

Result: pass

### P5-T1 — README and CHANGELOG read like a 1.0.0 release

Open `README.md` and scan: the version line ("1.0.0 (pending release)"), Installation pin (`~> 1.0`), Quick Start tip pointing at the install generator, Subscribers > Ahoy section (was missing pre-1.0.0), Generators section listing all three, Public API stability statement (Stable / Internal split), Roadmap reflecting 0.3.0 done + 1.0.0 pending.

Open `CHANGELOG.md` and scan the `## [1.0.0] - 2026-05-07` block: Added (generators, docs, Ahoy on README), Notes ("Public API stability:" with the stable surface enumerated), version-link table including `[1.0.0]` (forward-looking compare URL — resolves once the v1.0.0 git tag is cut post-UAT). `[Unreleased]` is NOT retargeted (correct — the v1.0.0 tag does not exist yet).

**Expected:** README and CHANGELOG together convey "1.0.0 is what's stable; here's how to install it; here's what the public API surface is." Wording and emphasis match what you want shipped.

Result: pass

### P5-T2 — USAGE.md and UPGRADING.md serve their distinct roles

Open `USAGE.md` (8 sections) — getting-started narrative for someone who just ran `rails g track_relay:install`. Open `UPGRADING.md` (3 migration sections: 0.1.0→0.2.0, 0.2.0→0.3.0, 0.3.0→1.0.0) — terse migration steps for existing users.

**Expected:** USAGE.md walks a newcomer from install to first tracked event; UPGRADING.md gives existing users a checklist for each major bump. They don't overlap — USAGE is forward-looking, UPGRADING is migration-focused. Files at repo root (NOT `doc/`), discoverable from the README.

Result: pass

## Summary

- Passed: 6
- Skipped: 0
- Issues: 0
- Total: 6
