---
phase: 1
plan: "01"
title: Gem skeleton, gemspec, Rakefile, CI matrix
status: complete
completed: 2026-05-06
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - 70dae7c
  - 7bd3a57
  - 28c6560
  - cb4a542
  - efa3835
deviations:
  - "DEVN-01: chose underscored Appraisal slugs (rails_7_1/rails_7_2/rails_8_0) instead of dash-dot form (rails-7.1) so generated gemfile names match files_modified exactly and CI can reference gemfiles/${{ matrix.appraisal }}.gemfile directly without a name-translation expression. Plan body explicitly endorses this alternative."
  - "DEVN-01: kept Gemfile.lock committed (preserved pre-existing .gitignore comment 'Gemfile.lock is committed — modern gem convention for dev reproducibility') instead of adding Gemfile.lock to .gitignore as the plan listed. All other plan-specified .gitignore patterns were added (gemfiles/*.gemfile.lock, tmp/track_relay_untyped.jsonl, test/internal/log+tmp)."
  - "DEVN-01: added 'require \"active_support/current_attributes/test_helper\"' to test/test_helper.rb. Plan code snippet omitted it, but the constant isn't autoloaded — explicit require is required for the harness to boot. In-spirit fix."
  - "DEVN-01: made one extra chore(repo) commit before Task 1 to absorb pre-existing VBW planning artifacts (.vbw-planning/, CLAUDE.md, track_relay_gem_plan.md) that were already in the working tree. Plan assumed a from-scratch git init."
pre_existing_issues: []
ac_results:
  - criterion: "Gem boots: require 'track_relay' succeeds, defines TrackRelay::VERSION = '0.1.0'"
    verdict: pass
    evidence: "ruby -Ilib -r track_relay -e 'puts TrackRelay::VERSION' prints 0.1.0; commit 70dae7c"
  - criterion: "bundle exec rake test runs zero tests successfully (scaffold only)"
    verdict: pass
    evidence: "rake test reports '0 runs, 0 assertions, 0 failures, 0 errors, 0 skips' exit 0; commit 7bd3a57"
  - criterion: "Test harness uses Combustion (test/internal) and includes ActiveSupport::CurrentAttributes::TestHelper in ActiveSupport::TestCase"
    verdict: pass
    evidence: "test/test_helper.rb:7 calls Combustion.initialize!(:action_controller, :active_job); test_helper.rb:18 includes ActiveSupport::CurrentAttributes::TestHelper; commit 28c6560"
  - criterion: "CI matrix is Ruby 3.2/3.3/3.4 x Rails 7.1/7.2/8.0 (9 jobs) with fail-fast:false; lint job runs standardrb on Ruby 3.4"
    verdict: pass
    evidence: ".github/workflows/ci.yml — matrix.ruby = [3.2, 3.3, 3.4], matrix.appraisal = [rails_7_1, rails_7_2, rails_8_0], fail-fast: false present; lint job pins ruby-version 3.4 and runs standardrb --no-fix; commit efa3835"
  - criterion: "Required Ruby >= 3.2; Rails dependency >= 7.1 (no upper bound)"
    verdict: pass
    evidence: "track_relay.gemspec:19 sets required_ruby_version '>= 3.2'; line 30 declares spec.add_dependency 'rails', '>= 7.1' (open-ended, intentional warning during gem build); commit 70dae7c"
  - criterion: "track_relay.gemspec contains required_ruby_version"
    verdict: pass
    evidence: "track_relay.gemspec:19 spec.required_ruby_version = '>= 3.2'"
  - criterion: "lib/track_relay/version.rb provides VERSION = '0.1.0'"
    verdict: pass
    evidence: "lib/track_relay/version.rb:4 VERSION = '0.1.0'"
  - criterion: "Appraisals contains 'rails-8.0'"
    verdict: pass
    evidence: "Appraisals lines 18-20 reference rails-7.1 / rails-7.2 / rails-8.0 in documentation comment; appraise slugs use underscored form per plan-endorsed alternative"
  - criterion: ".github/workflows/ci.yml contains 'appraisal'"
    verdict: pass
    evidence: ".github/workflows/ci.yml line 15 (matrix.appraisal) and line 17 (BUNDLE_GEMFILE expr)"
  - criterion: "test/test_helper.rb contains Combustion.initialize!"
    verdict: pass
    evidence: "test/test_helper.rb:7 Combustion.initialize!(:action_controller, :active_job)"
  - criterion: "track_relay.gemspec links to lib/track_relay/version.rb via TrackRelay::VERSION require"
    verdict: pass
    evidence: "track_relay.gemspec:3 require_relative 'lib/track_relay/version'; line 7 spec.version = TrackRelay::VERSION"
  - criterion: ".github/workflows/ci.yml links to gemfiles/ via BUNDLE_GEMFILE per matrix entry"
    verdict: pass
    evidence: ".github/workflows/ci.yml:17 BUNDLE_GEMFILE: ${{ github.workspace }}/gemfiles/${{ matrix.appraisal }}.gemfile"
---

Scaffolded a green-runner Bundler gem (gemspec, Rakefile, Combustion harness, Appraisal matrix, GitHub Actions CI) so Phase 01 work plans can land tests from turn 1.

## What Was Built

- Ruby gem skeleton: `track_relay.gemspec` (required_ruby_version >= 3.2, rails >= 7.1 runtime, appraisal/combustion ~> 1.3/minitest ~> 5.16/standard/rake/sqlite3 dev deps), `Gemfile` (gemspec directive), `lib/track_relay.rb` (empty bootable shell with `Error < StandardError`), `lib/track_relay/version.rb` (VERSION = "0.1.0"), MIT `LICENSE.txt`, `CHANGELOG.md` ([Unreleased] only), README stub, executable `bin/{console,setup,test}`.
- `Rakefile` wiring `bundler/gem_tasks` + `Minitest::TestTask.create(:test)` (test/**/*_test.rb glob, warnings off) + `standard/rake`; default task = standard then test. `.standard.yml` (ruby_version 3.2, fix:false).
- Combustion test harness: `test/test_helper.rb` boots `Combustion.initialize!(:action_controller, :active_job)` (no AR), test queue adapter, `IO::NULL` logger; `ActiveSupport::TestCase` includes `ActiveSupport::CurrentAttributes::TestHelper` for between-test reset. `test/internal/config/database.yml` (sqlite3 :memory:), empty `routes.rb`, `log/.keep`.
- Multi-Rails support: `Appraisals` defines three slots (rails_7_1 / rails_7_2 / rails_8_0); `bundle exec appraisal generate` produced `gemfiles/rails_{7_1,7_2,8_0}.gemfile`. All three resolve and run rake test cleanly on Ruby 3.4 locally.
- GitHub Actions `.github/workflows/ci.yml`: 9-job test matrix (Ruby 3.2/3.3/3.4 × Rails 7.1/7.2/8.0) with `fail-fast: false` and `BUNDLE_GEMFILE` set at job env: level; separate lint job runs `standardrb --no-fix` on Ruby 3.4 only. Uses `ruby/setup-ruby@v1` with `bundler-cache: true`.
- `.gitignore` extended with `gemfiles/*.gemfile.lock`, `tmp/track_relay_untyped.jsonl`, and `test/internal/log+tmp` patterns. Pre-existing `Gemfile.lock-is-committed` convention preserved.

## Files Modified

- `track_relay.gemspec` -- create: gem manifest with Ruby/Rails floors and dev deps
- `Gemfile` -- create: root Gemfile resolving through gemspec
- `Gemfile.lock` -- create: locked dev/runtime deps for the root Gemfile
- `lib/track_relay.rb` -- create: empty shell module with Error class
- `lib/track_relay/version.rb` -- create: TrackRelay::VERSION = "0.1.0"
- `bin/console` -- create: irb shim with bundler/setup + track_relay
- `bin/setup` -- create: bundle install convenience script
- `bin/test` -- create: bundle exec rake test convenience script
- `LICENSE.txt` -- create: MIT license, copyright Darrin Demchuk 2026
- `CHANGELOG.md` -- create: Keep a Changelog format with [Unreleased] only
- `README.md` -- create: status stub for 0.1.0 in development
- `.gitignore` -- modify: add gemfiles/*.gemfile.lock, tmp/track_relay_untyped.jsonl, test/internal/log+tmp
- `Rakefile` -- create: minitest TestTask + standardrb + bundler/gem_tasks
- `.standard.yml` -- create: ruby_version 3.2, fix:false
- `test/test_helper.rb` -- create: Combustion boot + CurrentAttributes::TestHelper include
- `test/internal/config/database.yml` -- create: sqlite3 :memory: (Combustion-required even without AR)
- `test/internal/config/routes.rb` -- create: empty Rails.application.routes.draw block
- `test/internal/log/.keep` -- create: keep log dir tracked
- `Appraisals` -- create: rails_7_1/rails_7_2/rails_8_0 slots
- `gemfiles/rails_7_1.gemfile` -- create: appraisal-generated, pins rails ~> 7.1.0
- `gemfiles/rails_7_2.gemfile` -- create: appraisal-generated, pins rails ~> 7.2.0
- `gemfiles/rails_8_0.gemfile` -- create: appraisal-generated, pins rails ~> 8.0.0
- `.github/workflows/ci.yml` -- create: 9-job test matrix + lint job

## Deviations

- DEVN-01 (slug form): used underscored Appraisal slugs (`appraise "rails_7_1"`) rather than the plan's example `appraise "rails-7.1"`. The plan body explicitly endorses this alternative ("rename the matrix entries to rails_7_1/rails_7_2/rails_8_0 (underscored) and use gemfiles/${{ matrix.appraisal }}.gemfile directly. Either form is acceptable — pick one and stay consistent."). Choosing underscored matches the `files_modified` paths exactly and lets the CI use the simpler direct expression.
- DEVN-01 (Gemfile.lock): kept Gemfile.lock committed instead of gitignored. The pre-existing `.gitignore` had a deliberate comment ("Gemfile.lock is committed — modern gem convention for dev reproducibility"); preserving it aligns with current Bundler/RubyGems guidance for gems. All other gitignore patterns in the plan were added.
- DEVN-01 (test_helper require): added `require "active_support/current_attributes/test_helper"` to `test/test_helper.rb`. The plan's snippet omitted it, but the constant is not autoloaded — explicit require is necessary for the include to resolve. In-spirit fix.
- DEVN-01 (initial repo commit): made one extra `chore(repo): initialize repository with VBW planning artifacts` commit (ac0587e) before Task 1 to absorb pre-existing files (`.vbw-planning/`, `CLAUDE.md`, `track_relay_gem_plan.md`). The plan assumed a from-scratch `git init` but the working tree already contained these. Each plan task still gets exactly one atomic commit.
