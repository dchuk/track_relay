---
phase: 4
plan: 3
title: "Generator structural tests (Rails::Generators::TestCase, tmpdir destination)"
status: complete
completed: 2026-05-07
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 6751809
  - 2433198
  - 74ac9da
deviations: []
pre_existing_issues: []
ac_results:
  - criterion: "All three generator tests use Rails::Generators::TestCase with tmpdir destination — NEVER mutate test/internal/"
    verdict: "pass"
    evidence: "grep -l 'Rails::Generators::TestCase' test/generators/track_relay/*_test.rb returns all 3 files; git status test/internal/ shows untouched after full suite run"
  - criterion: "Tmpdir destination is File.expand_path with prepare_destination per test"
    verdict: "pass"
    evidence: "destination File.expand_path(\"../../../tmp/generator_test\", __dir__) + setup :prepare_destination present in all 3 test files"
  - criterion: "Install generator test for inject_controller_tracking creates a stub ApplicationController in the destination first"
    verdict: "pass"
    evidence: "test/generators/track_relay/install_generator_test.rb: 'injects ControllerTracking into ApplicationController when not yet included' uses FileUtils.mkdir_p + File.write before run_generator"
  - criterion: "Install generator test exercises both branches of the inject guard: clean file (injects) AND already-included file (no-ops)"
    verdict: "pass"
    evidence: "Three branch tests in install_generator_test.rb: clean inject, idempotent no-op (scan size == 1), missing-file no-op (assert_no_file)"
  - criterion: "Event/subscriber generator tests pass NAME via run_generator([\"ArticleViewed\"]) and assert_file on the snake_cased path"
    verdict: "pass"
    evidence: "event_generator_test.rb tests ArticleViewed → article_viewed.rb; subscriber_generator_test.rb tests Slack → slack_subscriber.rb and MyAnalytics → my_analytics_subscriber.rb"
  - criterion: "Tests use assert_match (regex/string patterns) inside content blocks — never exact full-file equality"
    verdict: "pass"
    evidence: "All assert_file blocks in the 3 files use assert_match (or scan().size for the idempotency test); no assert_equal on full content"
  - criterion: "test/generators/track_relay/install_generator_test.rb provides InstallGenerator structural tests using Rails::Generators::TestCase"
    verdict: "pass"
    evidence: "commit 6751809 adds the file; class TrackRelay::Generators::InstallGeneratorTest < Rails::Generators::TestCase"
  - criterion: "test/generators/track_relay/event_generator_test.rb provides EventGenerator structural tests with tests TrackRelay::Generators::EventGenerator"
    verdict: "pass"
    evidence: "commit 2433198 adds the file with the tests directive"
  - criterion: "test/generators/track_relay/subscriber_generator_test.rb provides SubscriberGenerator structural tests with tests TrackRelay::Generators::SubscriberGenerator"
    verdict: "pass"
    evidence: "commit 74ac9da adds the file with the tests directive"
  - criterion: "install_generator_test.rb requires lib/generators/track_relay/install/install_generator.rb"
    verdict: "pass"
    evidence: "require \"generators/track_relay/install/install_generator\" present at top of file"
  - criterion: "event_generator_test.rb requires lib/generators/track_relay/event/event_generator.rb"
    verdict: "pass"
    evidence: "require \"generators/track_relay/event/event_generator\" present at top of file"
  - criterion: "subscriber_generator_test.rb requires lib/generators/track_relay/subscriber/subscriber_generator.rb"
    verdict: "pass"
    evidence: "require \"generators/track_relay/subscriber/subscriber_generator\" present at top of file"
---

Added 12 structural tests across 3 files for the install, event, and subscriber generators using `Rails::Generators::TestCase` with a tmpdir destination, taking `bundle exec rake test` from 392 to 404 runs (0 failures) without mutating `test/internal/`.

## What Was Built

- 6 tests for InstallGenerator covering the initializer, sample catalog, ApplicationSubscriber, and all 3 branches of `inject_controller_tracking` (clean inject, idempotent no-op when already included, no-op when ApplicationController is missing).
- 3 tests for EventGenerator covering CamelCase-to-snake_case NAME normalization, already-snake_case NAME, and presence of all 5 type stubs.
- 3 tests for SubscriberGenerator covering destination path correctness, `class_name` interpolation in the registration comment, and `synchronous!`/`filter only:` example lines.
- All tests use `destination File.expand_path("../../../tmp/generator_test", __dir__)` + `setup :prepare_destination`, so `test/internal/` is read-only during the run; `/tmp/` is already in `.gitignore`.

## Files Modified

- `test/generators/track_relay/install_generator_test.rb` -- added: 6 install generator structural tests with 3-branch inject coverage.
- `test/generators/track_relay/event_generator_test.rb` -- added: 3 event generator structural tests for NamedBase snake_casing and template stubs.
- `test/generators/track_relay/subscriber_generator_test.rb` -- added: 3 subscriber generator structural tests for path, class_name interpolation, and example lines.

## Deviations

None.
