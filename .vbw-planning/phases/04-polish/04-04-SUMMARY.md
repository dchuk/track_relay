---
phase: 4
plan: "04"
title: "E2E happy-path test (install generator → tracked controller call → Test subscriber capture)"
status: complete
completed: 2026-05-07
tasks_completed: 3
tasks_total: 3
commit_hashes:
  - 199ef99
  - 6dd752a
deviations:
  - "Task 3 (Run full test suite — no regressions) is verification-only with no files modified, so no commit was produced. Both `bundle exec rake test` runs (back-to-back) returned 405 runs, 0 failures, confirming no regressions and a leak-free teardown."
pre_existing_issues: []
ac_results:
  - criterion: "E2E test invokes the install generator programmatically (Rails::Generators.invoke) into a tmpdir, then copies the catalog + subscriber files into the live Combustion app. The generator binary is the source of truth — the copy is a deliberate isolation choice (initializer is excluded; the inject step skips because the tmpdir has no ApplicationController, hitting the `say_status :skip, ... not found` branch from plan 04-01)."
    verdict: pass
    evidence: "test/integration/generator_install_e2e_test.rb setup block calls Rails::Generators.invoke into TMPDIR, then FileUtils.cp the catalog + subscriber only. Test output for commit 6dd752a shows `skip  app/controllers/application_controller.rb not found` confirming the inject branch from plan 04-01 fires."
  - criterion: "Test cleans up loaded artifacts in teardown so test/internal/config/track_relay/ is empty between test runs"
    verdict: pass
    evidence: "Teardown in generator_install_e2e_test.rb deletes GENERATED_FILES, removes empty dirs (CATALOG_DIR, SUBSCRIBERS_DIR, app/track_relay), and rm_rf TMPDIR. Two consecutive `bundle exec rake test` runs both pass with `git status test/internal/` clean."
  - criterion: "Test asserts a tracked event from a real controller action is captured by the Test subscriber via assert_tracked"
    verdict: pass
    evidence: "test/integration/generator_install_e2e_test.rb test body: `get hello_path(message: \"hi from e2e\"); assert_response :ok; assert_tracked :hello_world, message: \"hi from e2e\"` — passes with 3 assertions."
  - criterion: "Test does NOT depend on the inject_into_class behavior — the generator runs against a tmpdir with no ApplicationController, so the inject step hits the controller-missing skip branch from plan 04-01. Independently, `test/internal/app/controllers/application_controller.rb` already has `include TrackRelay::ControllerTracking` so HelloController inherits the `track` method — this is fixture state, not generator output."
    verdict: pass
    evidence: "Generator run output shows `skip  app/controllers/application_controller.rb not found`. test/internal/app/controllers/application_controller.rb (untouched fixture) carries the include; HelloController inherits `track` via `< ApplicationController`."
  - criterion: "Sample event :hello_world matches the install generator's sample_catalog.rb.tt — the test exercises the same event the generator scaffolds"
    verdict: pass
    evidence: "lib/generators/track_relay/install/templates/sample_catalog.rb.tt declares `event :hello_world do; string :message, required: true; end`. Test asserts `:hello_world` with `message: \"hi from e2e\"`."
  - criterion: "test/integration/generator_install_e2e_test.rb provides E2E happy-path test class containing assert_tracked :hello_world"
    verdict: pass
    evidence: "File created in commit 6dd752a; class GeneratorInstallE2ETest < ActionDispatch::IntegrationTest; body contains `assert_tracked :hello_world, message: \"hi from e2e\"`."
  - criterion: "test/internal/app/controllers/hello_controller.rb provides controller that calls track :hello_world"
    verdict: pass
    evidence: "File created in commit 199ef99 with `track :hello_world, message: params.fetch(:message, \"hello\")`."
  - criterion: "test/internal/config/routes.rb provides route for /hello"
    verdict: pass
    evidence: "Edit in commit 199ef99 added `get \"/hello\", to: \"hello#show\", as: :hello`."
  - criterion: "generator_install_e2e_test.rb links to lib/generators/track_relay/install/install_generator.rb via Rails::Generators.invoke"
    verdict: pass
    evidence: "Setup block calls `Rails::Generators.invoke(\"track_relay:install\", [], destination_root: TMPDIR, shell: Thor::Shell::Basic.new)` and requires `generators/track_relay/install/install_generator`."
  - criterion: "generator_install_e2e_test.rb links to test/internal/config/track_relay/sample.rb via load (after invoke)"
    verdict: pass
    evidence: "Setup block: `Dir.glob(File.join(CATALOG_DIR, \"**/*.rb\")).sort.each { |f| load f }` runs after the generator output is copied to CATALOG_DIR."
  - criterion: "hello_controller.rb links to config/routes.rb via route entry"
    verdict: pass
    evidence: "test/internal/config/routes.rb line 4: `get \"/hello\", to: \"hello#show\", as: :hello` resolves to HelloController#show."
---

E2E happy-path test wires the install generator's binary output through the live Combustion harness — invoke into tmpdir, copy catalog + subscriber into test/internal, reload, assert a real controller action's `track :hello_world` is captured by the Test subscriber.

## What Was Built

- `GeneratorInstallE2ETest` integration test invoking `Rails::Generators.invoke("track_relay:install", ...)` into a tmpdir, copying catalog + subscriber output into `test/internal`, reloading the catalog, and asserting `assert_tracked :hello_world, message: "hi from e2e"` after a `get hello_path(...)` request.
- `HelloController` fixture under `test/internal` that calls `track :hello_world, message: params.fetch(:message, "hello")` from a real Rails controller action.
- New `/hello` route in `test/internal/config/routes.rb` named `:hello` so the integration test can use `hello_path(message: ...)`.
- Setup explicitly (re)starts `TrackRelay::Dispatcher` because the global teardown in `test_helper.rb` stops it after every test and `test_mode!` only swaps the subscriber list. Teardown deletes generated files, removes empty directories, and `rm_rf` the tmpdir; the global teardown handles `Catalog.clear!`, `Dispatcher.stop!`, and `reset_config!`.

## Files Modified

- `test/internal/app/controllers/hello_controller.rb` -- create: new controller fixture calling `track :hello_world` to exercise the install generator's sample event end-to-end.
- `test/internal/config/routes.rb` -- edit: add `get "/hello", to: "hello#show", as: :hello` so the E2E test can hit a tracked controller action.
- `test/integration/generator_install_e2e_test.rb` -- create: E2E happy-path test class invoking install generator into tmpdir, copying catalog + subscriber into test/internal, asserting captured event.

## Deviations

Task 3 (Run full test suite — no regressions) is verification-only with no files modified, so no commit was produced. Both `bundle exec rake test` runs (back-to-back) returned 405 runs, 0 failures, confirming no regressions and a leak-free teardown.
