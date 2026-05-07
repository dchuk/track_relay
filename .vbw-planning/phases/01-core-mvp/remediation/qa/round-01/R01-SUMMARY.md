---
phase: 1
round: 01
plan: R01
title: QA remediation round 01 — reconcile Phase 01 plan deviations
type: remediation
status: complete
completed: 2026-05-06
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - c2884ca0a6c5d222b665e179a237dc5a4b22ba0c
  - c82175f36d2a4336e7360695740e9257ae02b943
  - 3372196de89f6b2ac20f03371f4ffbe08f6d9394
files_modified:
  - .vbw-planning/phases/01-core-mvp/01-01-PLAN.md
  - .vbw-planning/phases/01-core-mvp/01-06-PLAN.md
  - .vbw-planning/phases/01-core-mvp/01-07-PLAN.md
deviations: []
known_issue_outcomes: []
---

Reconciled five plan-text/implementation deviations (DEV-01, DEV-02, DEV-03, DEV-05, DEV-06) by amending the source PLAN.md artifacts to reflect the actually-shipped approach; recorded DEV-04 as an accepted process-exception with no file change. Documentation-only round — the 241-test suite remains 0 failures and standardrb is clean.

## Task 1: Amend 01-01-PLAN.md: Appraisal slugs, .gitignore Gemfile.lock, test_helper require (DEV-01, DEV-02, DEV-03)

### What Was Built
- DEV-01: Appraisal slugs codified as underscored (`rails_7_1`, `rails_7_2`, `rails_8_0`) throughout the Appraisals snippet, the `must_haves.artifacts` entry, the GitHub Actions matrix entries, and the `BUNDLE_GEMFILE` expression. Removed the dash-dot-vs-underscored ternary; the verify/done blocks for the Appraisals task and the CI workflow's `act` invocation example also use underscored slugs for internal consistency.
- DEV-02: Removed `Gemfile.lock` from the `.gitignore` instruction list and added a one-line note: "`Gemfile.lock` is intentionally committed for gem development reproducibility (modern Bundler convention for libraries). Resolved by amendment (R01)."
- DEV-03: Added explicit `require "active_support/current_attributes/test_helper"` to the `test/test_helper.rb` snippet (between `require "minitest/autorun"` and the `class ActiveSupport::TestCase` open) plus a note explaining the constant is not autoloaded by the activesupport entry.
- Appended a consolidated `### R01 amendments` block above `<output>` summarising all three amendments.

### Files Modified
- `.vbw-planning/phases/01-core-mvp/01-01-PLAN.md` -- amend: codify underscored Appraisal slugs, remove Gemfile.lock from .gitignore list, add explicit current_attributes/test_helper require, append R01 amendments block.

### Deviations
None.

## Task 2: Amend 01-06-PLAN.md: document Railtie load-order require in test_helper (DEV-05)

### What Was Built
- Added `test/test_helper.rb` to Task 1's `<files>` list (between `lib/track_relay.rb` and `test/integration/railtie_test.rb`) and to the frontmatter `files_modified` list.
- Inserted a new paragraph in Task 1's `<action>` block immediately after the `lib/track_relay.rb` paragraph documenting the explicit `require "track_relay/railtie"` in `test/test_helper.rb` (post-Combustion-boot) with the load-order rationale: unit tests can `require "track_relay"` before Rails is loaded, so the `if defined?(Rails::Railtie)` guard skips Railtie registration; the explicit require ensures the Railtie is always defined.
- Added a new `must_haves.truths` bullet codifying the explicit require requirement.
- Appended an `### R01 amendments` block above `<output>` with the rationale and reference to fix-up commit fcf56d3.

### Files Modified
- `.vbw-planning/phases/01-core-mvp/01-06-PLAN.md` -- amend: add test_helper.rb to files lists, document explicit Railtie require with load-order rationale, append R01 amendments block.

### Deviations
None.

## Task 3: Amend 01-07-PLAN.md: RSpec chain :with positional Hash signature (DEV-06)

### What Was Built
- Replaced the keyword-splat form `chain :with do |**params|` with the positional-Hash form `chain(:with) do |params|` in the `lib/track_relay/testing/rspec_matchers.rb` snippet (Task 3 action block).
- Inserted an explanatory note immediately after the rspec_matchers.rb code block documenting that RSpec 3.13's chain proxy delivers `.with(n: 7)` as a positional Hash on Ruby 3.4, so the keyword-splat form raises `ArgumentError: wrong number of arguments (given 1, expected 0)`.
- Appended an `### R01 amendments` block above `<output>` confirming the shipped implementation already uses the positional form; this amendment realigns the plan snippet.

### Files Modified
- `.vbw-planning/phases/01-core-mvp/01-07-PLAN.md` -- amend: switch chain :with block from keyword splat to positional Hash, add ArgumentError explanation, append R01 amendments block.

### Deviations
None.

## Task 4: Record DEV-04 process-exception decision in this remediation plan

### What Was Built
- Verified DEV-04 is recorded in `R01-PLAN.md` frontmatter `fail_classifications` as `type: "process-exception"` with explicit rationale: the chore commit (ac0587e) that absorbed pre-existing `.vbw-planning/`, `CLAUDE.md`, and `track_relay_gem_plan.md` files cannot be retroactively unwound without a risky `git rebase --root`; it does not alter runtime behavior or any must_have; and re-doing the phase from a clean tree is not possible retroactively.
- This task has no file edits (per R01-PLAN.md's task body); the documentation lives in `R01-PLAN.md`'s `fail_classifications` and is mirrored by this summary entry.

### Files Modified
- None (process-exception record only; no commit).

### Deviations
None.
