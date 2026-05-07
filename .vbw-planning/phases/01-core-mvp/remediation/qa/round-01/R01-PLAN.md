---
phase: 01
round: 01
plan: R01
title: QA remediation round 01 — reconcile Phase 01 plan deviations
type: remediation
autonomous: true
effort_override: balanced
skills_used: [rails-architecture]
files_modified:
  - .vbw-planning/phases/01-core-mvp/01-01-PLAN.md
  - .vbw-planning/phases/01-core-mvp/01-06-PLAN.md
  - .vbw-planning/phases/01-core-mvp/01-07-PLAN.md
forbidden_commands: []
fail_classifications:
  - {id: "DEV-01", type: "plan-amendment", rationale: "Plan body explicitly says 'Either form is acceptable — pick one and stay consistent.' files_modified lists underscored gemfile filenames (rails_7_1.gemfile etc.); the dash-dot example in Appraisals contradicts that. Implementation chose the underscored slugs to match files_modified — a valid in-spirit choice. Update the plan to remove the dash-dot example and codify underscored slugs.", source_plan: "01-01-PLAN.md"}
  - {id: "DEV-02", type: "plan-amendment", rationale: "Modern Bundler/Ruby convention is that gem libraries SHOULD commit Gemfile.lock for development reproducibility. The pre-existing .gitignore already reflected this convention; the plan's instruction to add Gemfile.lock to .gitignore was incorrect. Update the plan's .gitignore list to remove Gemfile.lock.", source_plan: "01-01-PLAN.md"}
  - {id: "DEV-03", type: "plan-amendment", rationale: "Plan code snippet referenced ActiveSupport::CurrentAttributes::TestHelper without an explicit require. The constant is not autoloaded in this load path; the test harness fails to boot without `require 'active_support/current_attributes/test_helper'`. The implementation added the require correctly — codify it in the plan snippet.", source_plan: "01-01-PLAN.md"}
  - {id: "DEV-04", type: "process-exception", rationale: "Plan assumed a from-scratch git init, but the working tree had pre-existing .vbw-planning/, CLAUDE.md, track_relay_gem_plan.md from VBW bootstrap. Unwinding the chore commit (ac0587e) that absorbed those files would require rewriting history with a risky rebase. The chore commit does not affect runtime behavior or any must_have, and re-doing the phase from a clean tree is not possible retroactively. Accept as a one-time bootstrap artifact."}
  - {id: "DEV-05", type: "plan-amendment", rationale: "Real bug discovered during 01-06 testing: unit tests `require 'track_relay'` before Rails is loaded, causing `lib/track_relay.rb`'s `require 'track_relay/railtie' if defined?(Rails::Railtie)` guard to evaluate false; subsequent loads short-circuit and the Railtie never registers. The fix-up commit (fcf56d3) added an explicit `require 'track_relay/railtie'` in test_helper.rb after Combustion boots Rails — this is correct and necessary. Update plan 01-06 to mention this required test_helper.rb change as part of the Railtie task.", source_plan: "01-06-PLAN.md"}
  - {id: "DEV-06", type: "plan-amendment", rationale: "Plan snippet used `chain :with do |**params|` (keyword splat). RSpec 3.13 chain proxy delivers `.with(n: 7)` as a positional Hash on Ruby 3.4, so the keyword splat raises ArgumentError. The implementation correctly switched to a positional `params` Hash. Update the RSpec matcher snippet in plan 01-07 to use `chain(:with) { |params| @expected_params = params }`.", source_plan: "01-07-PLAN.md"}
known_issues_input: []
known_issue_resolutions: []
must_haves:
  truths:
    - "Each plan-amendment FAIL has the source PLAN.md updated to reflect the actually-shipped approach with rationale recorded as a 'Resolved by amendment (R01)' note."
    - "01-01-PLAN.md no longer instructs adding `Gemfile.lock` to .gitignore; lists underscored Appraisal slugs in the Appraisals snippet; includes `require 'active_support/current_attributes/test_helper'` in the test/test_helper.rb snippet."
    - "01-06-PLAN.md documents the required explicit `require 'track_relay/railtie'` in test/test_helper.rb (post-Combustion-boot) so unit tests that load `track_relay` before Rails still register the Railtie."
    - "01-07-PLAN.md's RSpec matcher snippet uses `chain(:with) { |params| ... }` (positional Hash) rather than `chain :with do |**params|` (keyword splat)."
    - "DEV-04 is recorded as an accepted process-exception with explicit rationale; no code or plan changes are made for it."
    - "No source code under lib/, test/, gemfiles/, .github/, or any production/test runtime file is modified by this remediation round — amendments are documentation-only."
  artifacts:
    - {path: ".vbw-planning/phases/01-core-mvp/01-01-PLAN.md", provides: "Amended plan reflecting actual scaffold approach", contains: "Resolved by amendment (R01)"}
    - {path: ".vbw-planning/phases/01-core-mvp/01-06-PLAN.md", provides: "Amended plan documenting Railtie load-order fix", contains: "Resolved by amendment (R01)"}
    - {path: ".vbw-planning/phases/01-core-mvp/01-07-PLAN.md", provides: "Amended plan with corrected RSpec chain matcher snippet", contains: "Resolved by amendment (R01)"}
  key_links:
    - {from: ".vbw-planning/phases/01-core-mvp/01-01-PLAN.md", to: "gemfiles/rails_7_1.gemfile", via: "files_modified now matches Appraisals snippet (underscored slugs)"}
    - {from: ".vbw-planning/phases/01-core-mvp/01-06-PLAN.md", to: "test/test_helper.rb", via: "explicit require 'track_relay/railtie' documented in Task 1"}
    - {from: ".vbw-planning/phases/01-core-mvp/01-07-PLAN.md", to: "lib/track_relay/testing/rspec_matchers.rb", via: "chain(:with) positional Hash signature"}
---
<objective>
Reconcile six FAIL checks (DEV-01..DEV-06) from 01-VERIFICATION.md by updating the original phase PLAN.md artifacts to reflect the actually-shipped, correct approach. Five FAILs are plan-amendments (the implementation was right; the plan text was wrong, ambiguous, or omitted required detail). One FAIL (DEV-04) is a non-fixable bootstrap artifact and is recorded as a process-exception. No production or test code is modified — the existing 241-test suite (0 failures) already verifies actual code behavior; this round only realigns the planning artifacts so future verification reads consistently.
</objective>
<context>
@.vbw-planning/phases/01-core-mvp/01-VERIFICATION.md
@.vbw-planning/phases/01-core-mvp/01-01-PLAN.md
@.vbw-planning/phases/01-core-mvp/01-06-PLAN.md
@.vbw-planning/phases/01-core-mvp/01-07-PLAN.md
@.vbw-planning/phases/01-core-mvp/01-01-SUMMARY.md
@.vbw-planning/phases/01-core-mvp/01-06-SUMMARY.md
@.vbw-planning/phases/01-core-mvp/01-07-SUMMARY.md
</context>
<tasks>
<task type="auto">
  <name>Amend 01-01-PLAN.md: Appraisal slugs, .gitignore Gemfile.lock, test_helper require (DEV-01, DEV-02, DEV-03)</name>
  <files>
    .vbw-planning/phases/01-core-mvp/01-01-PLAN.md
  </files>
  <action>
Edit `.vbw-planning/phases/01-core-mvp/01-01-PLAN.md` to apply three plan amendments. Do NOT modify any code, test, or config files outside `.vbw-planning/`. Use the Edit tool with exact-string replacements for each amendment so future verification reads the actually-shipped approach.

Amendment A (DEV-01 — Appraisal slugs):
1. In the `Appraisals` code block (under the "Appraisals + generated gemfiles for Rails 7.1/7.2/8.0" task), replace the dash-dot slugs with underscored slugs to match `files_modified`:
   ```ruby
   appraise "rails_7_1" do
     gem "rails", "~> 7.1.0"
   end
   appraise "rails_7_2" do
     gem "rails", "~> 7.2.0"
   end
   appraise "rails_8_0" do
     gem "rails", "~> 8.0.0"
   end
   ```
2. In the `must_haves.artifacts` entry for `Appraisals`, change `contains: "rails-8.0"` to `contains: "rails_8_0"`.
3. In the GitHub Actions matrix snippet (CI workflow task), update the matrix line and BUNDLE_GEMFILE expression to use the underscored form directly:
   - matrix entries: `appraisal: ["rails_7_1", "rails_7_2", "rails_8_0"]`
   - BUNDLE_GEMFILE: `${{ github.workspace }}/gemfiles/${{ matrix.appraisal }}.gemfile`
   - Remove the conditional ternary expression that mapped dash-dot to underscored.
4. Remove the paragraph that begins with "Note: Appraisal converts `rails-8.0` → `gemfiles/rails_8_0.gemfile`..." and ends with "Either form is acceptable — pick one and stay consistent." Replace with a single sentence: "Note: Appraisal slugs use underscores (`rails_7_1`, `rails_7_2`, `rails_8_0`) so they map 1:1 to `gemfiles/<slug>.gemfile` and to the matrix entries above. Resolved by amendment (R01) — see remediation/qa/round-01/."

Amendment B (DEV-02 — Gemfile.lock):
1. In the `.gitignore` instruction list (under Task 1), remove the `Gemfile.lock` entry. The remaining list should contain `*.gem`, `gemfiles/*.gemfile.lock`, `coverage/`, `pkg/`, `tmp/`, `tmp/track_relay_untyped.jsonl`, `.bundle/`, `vendor/bundle`, `.rspec_status`, `test/internal/log/*.log`, `test/internal/tmp/`.
2. Add a one-line note immediately after the `.gitignore` instruction: "Note: `Gemfile.lock` is intentionally committed for gem development reproducibility (modern Bundler convention for libraries). Resolved by amendment (R01)."

Amendment C (DEV-03 — test_helper require):
1. In the `test/test_helper.rb` code block under the "Combustion test harness with Current TestHelper" task, add an explicit require above the `class ActiveSupport::TestCase` line:
   ```ruby
   require "active_support/current_attributes/test_helper"
   ```
   Insert it on its own line between `require "minitest/autorun"` and the `class ActiveSupport::TestCase` open. The constant `ActiveSupport::CurrentAttributes::TestHelper` is not autoloaded in this load path, so the explicit require is required for the harness to boot.
2. Add a one-line note after the code block: "Note: `require 'active_support/current_attributes/test_helper'` is required because the constant is not autoloaded by the active_support entry. Resolved by amendment (R01)."

After all three amendments, append a single consolidated note at the bottom of the `<objective>` paragraph (or in a clearly-marked block at the end of the file just above `<output>`) reading:
"### R01 amendments\n- DEV-01 resolved by amendment: Appraisal slugs use underscores throughout.\n- DEV-02 resolved by amendment: Gemfile.lock is committed (gem-development convention); .gitignore list updated.\n- DEV-03 resolved by amendment: explicit `require 'active_support/current_attributes/test_helper'` documented in the test_helper snippet."
  </action>
  <verify>
- `grep -n 'rails-7.1\|rails-7.2\|rails-8.0' .vbw-planning/phases/01-core-mvp/01-01-PLAN.md` returns no matches inside the Appraisals/CI matrix code blocks (the `R01 amendments` note may legitimately reference the old slug for traceability).
- `grep -n 'rails_7_1\|rails_7_2\|rails_8_0' .vbw-planning/phases/01-core-mvp/01-01-PLAN.md` returns matches in the Appraisals snippet, the CI matrix snippet, and the must_haves artifact entry.
- `grep -n 'Gemfile.lock' .vbw-planning/phases/01-core-mvp/01-01-PLAN.md` shows only the new amendment note (gem-development convention) and not the .gitignore instruction list.
- `grep -n "active_support/current_attributes/test_helper" .vbw-planning/phases/01-core-mvp/01-01-PLAN.md` returns at least one match in the test_helper code block.
- `grep -c 'Resolved by amendment (R01)' .vbw-planning/phases/01-core-mvp/01-01-PLAN.md` returns >= 3.
  </verify>
  <done>
01-01-PLAN.md reflects the actually-shipped approach for Appraisal slugs, Gemfile.lock policy, and the test_helper require, with each change tagged "Resolved by amendment (R01)" so future readers understand the deviation rationale.
  </done>
</task>
<task type="auto">
  <name>Amend 01-06-PLAN.md: document Railtie load-order require in test_helper (DEV-05)</name>
  <files>
    .vbw-planning/phases/01-core-mvp/01-06-PLAN.md
  </files>
  <action>
Edit `.vbw-planning/phases/01-core-mvp/01-06-PLAN.md` to document the Railtie load-order fix that was discovered during execution. Do NOT modify `lib/track_relay.rb`, `test/test_helper.rb`, or any production/test code — the implementation already ships the fix and 241 tests pass.

Amendment (DEV-05):
1. Locate the `<files>` block for Task 1 ("TrackRelay::Railtie (catalog autoload + Dispatcher.start!)") and add `test/test_helper.rb` to the file list (between `lib/track_relay.rb` and `test/integration/railtie_test.rb`).
2. Locate the `files_modified` frontmatter list and add `test/test_helper.rb` if not already present (it was added by Plan 01; here we record the additional touch in 01-06 for traceability).
3. Inside Task 1's `<action>` block, immediately after the paragraph that begins "Update `lib/track_relay.rb`: add `require \"track_relay/railtie\" if defined?(Rails::Railtie)`...", insert a new paragraph:

   "Update `test/test_helper.rb`: add an explicit `require \"track_relay/railtie\"` line AFTER `Combustion.initialize!(...)` returns and AFTER `require \"track_relay\"`. Why: unit tests can `require \"track_relay\"` before Rails is loaded; in that load order the `if defined?(Rails::Railtie)` guard in `lib/track_relay.rb` evaluates false, so the Railtie file is skipped and the class is never registered. Once Combustion boots Rails, calling the explicit `require \"track_relay/railtie\"` is a no-op for the integration suite but ensures the Railtie is always defined for any unit test that touches Rails-dependent code paths. Discovered during execution as a load-order race; codified here so future readers understand why the require sits in test_helper."

4. Add a `must_haves.truths` bullet (insert into the existing list):
   "`test/test_helper.rb` performs an explicit `require \"track_relay/railtie\"` after Combustion boot so unit tests that loaded `track_relay` before Rails still see the Railtie registered."

5. Append a consolidated note at the end of the file just above `<output>`:
   "### R01 amendments\n- DEV-05 resolved by amendment: documented the explicit `require 'track_relay/railtie'` in `test/test_helper.rb` (post-Combustion-boot). The original plan's 3-task commit set assumed Rails was always loaded before `track_relay`; in unit-test load order that assumption fails. Fix-up commit fcf56d3 in the original execution applied the require correctly; this amendment records why it was necessary."
  </action>
  <verify>
- `grep -n "require .track_relay/railtie." .vbw-planning/phases/01-core-mvp/01-06-PLAN.md` returns at least one match in Task 1's action block (in addition to any existing reference inside `lib/track_relay.rb`).
- `grep -n "test_helper.rb" .vbw-planning/phases/01-core-mvp/01-06-PLAN.md` shows the file is referenced in Task 1's `<files>` list.
- `grep -n 'Resolved by amendment (R01)\|R01 amendments' .vbw-planning/phases/01-core-mvp/01-06-PLAN.md` returns at least one match.
- `grep -n 'load-order\|load order' .vbw-planning/phases/01-core-mvp/01-06-PLAN.md` returns at least one match in the new amendment paragraph.
  </verify>
  <done>
01-06-PLAN.md documents the test_helper.rb explicit Railtie require with the load-order rationale, so the fix-up commit fcf56d3 is no longer an undocumented deviation.
  </done>
</task>
<task type="auto">
  <name>Amend 01-07-PLAN.md: RSpec chain :with positional Hash signature (DEV-06)</name>
  <files>
    .vbw-planning/phases/01-core-mvp/01-07-PLAN.md
  </files>
  <action>
Edit `.vbw-planning/phases/01-core-mvp/01-07-PLAN.md` to correct the RSpec matcher snippet so it matches RSpec 3.13's chain proxy behavior on Ruby 3.4. Do NOT modify `lib/track_relay/testing/rspec_matchers.rb` — the implementation is already correct and the test suite passes.

Amendment (DEV-06):
1. Locate Task 3's `<action>` block ("RSpec matchers (have_tracked + .with chain) — guarded by defined?(RSpec)") and find the inner `RSpec::Matchers.define :have_tracked do |name|` code block.
2. Replace the lines:
   ```ruby
       chain :with do |**params|
         @expected_params = params
       end
   ```
   with the positional-Hash form:
   ```ruby
       chain(:with) do |params|
         @expected_params = params
       end
   ```
   (Note the parenthesized `chain(:with)` form for clarity; either `chain :with do |params|` or `chain(:with) do |params|` is acceptable — pick the parenthesized form to make the positional argument unambiguous.)

3. Insert an explanatory note immediately after the updated code block:
   "Note: RSpec 3.13's chain proxy delivers `.with(n: 7)` to the chain block as a positional Hash, NOT via keyword splat. On Ruby 3.4 the previously-shown `do |**params|` signature raises `ArgumentError: wrong number of arguments (given 1, expected 0)`. Use the positional `|params|` form. Resolved by amendment (R01)."

4. In the test snippet later in the same task, the `.with(n: 7)` and `.with(n: 999)` call sites are unchanged (caller-side syntax is the same). Confirm no caller-side changes are needed.

5. Append a consolidated note at the end of the file just above `<output>`:
   "### R01 amendments\n- DEV-06 resolved by amendment: corrected the `chain(:with)` block signature from keyword splat (`|**params|`) to positional Hash (`|params|`). The keyword-splat form raises ArgumentError on RSpec 3.13 + Ruby 3.4 because the chain proxy passes the Hash positionally. The shipped implementation already used the positional form; this amendment realigns the plan snippet."

6. Optional clarifying note (recommended): the original plan body also references that two happy-path tests append `pass` to satisfy Minitest's assertion counter (because RSpec's `expect(...).to ...` does not register a Minitest assertion when it succeeds). This is a known Minitest+RSpec interop pattern and was correctly applied in the implementation; no plan change is needed for it. The DEV-06 row in VERIFICATION calls this out only to surface the chain signature issue — the `pass` call sites are the correct fix and are already documented inline in the test file. No edit required.
  </action>
  <verify>
- `grep -n 'chain :with do |\*\*params|' .vbw-planning/phases/01-core-mvp/01-07-PLAN.md` returns no matches (the keyword-splat form is gone).
- `grep -n 'chain(:with)' .vbw-planning/phases/01-core-mvp/01-07-PLAN.md` returns at least one match (the positional form is present).
- `grep -n 'positional Hash\|positional argument' .vbw-planning/phases/01-core-mvp/01-07-PLAN.md` returns at least one match in the new note.
- `grep -n 'Resolved by amendment (R01)\|R01 amendments' .vbw-planning/phases/01-core-mvp/01-07-PLAN.md` returns at least one match.
  </verify>
  <done>
01-07-PLAN.md's RSpec matcher snippet uses `chain(:with) do |params|` and includes a note explaining why the keyword-splat form fails on RSpec 3.13 + Ruby 3.4, matching the actually-shipped implementation.
  </done>
</task>
<task type="auto">
  <name>Record DEV-04 process-exception decision in this remediation plan</name>
  <files>
    .vbw-planning/phases/01-core-mvp/remediation/qa/round-01/R01-PLAN.md
  </files>
  <action>
DEV-04 (extra chore commit ac0587e absorbing pre-existing VBW planning artifacts) is classified as a process-exception in this plan's frontmatter `fail_classifications`. No code, plan, or git-history changes are made:

- The chore commit is not retroactively unwindable without a risky `git rebase --root` that would rewrite shared history. The commit absorbed pre-existing files (`.vbw-planning/`, `CLAUDE.md`, `track_relay_gem_plan.md`) that were created by VBW bootstrap before Plan 01 began. Plan 01 assumed a from-scratch `git init`; that assumption was incorrect for this working tree.
- The commit does not alter runtime behavior, does not affect any must_have, and does not change the gem's published artifact (`gem build` reads files via the gemspec's `files` glob, which doesn't pick up planning artifacts).
- For future phases, planners should not assume a from-scratch git tree when VBW planning artifacts are already present. This is a one-time bootstrap artifact specific to Phase 01.

This task has no file edits. It exists so the remediation plan reads cleanly with one task per FAIL — Dev agents executing this task simply confirm the rationale is captured in `fail_classifications` and proceed.
  </action>
  <verify>
- `grep -n 'DEV-04' .vbw-planning/phases/01-core-mvp/remediation/qa/round-01/R01-PLAN.md` shows the FAIL is recorded as `type: "process-exception"` in `fail_classifications`.
- No code, test, or config files outside `.vbw-planning/` are modified by this task.
  </verify>
  <done>
DEV-04 is documented as an accepted process-exception with explicit reasoning; no remediation action is taken.
  </done>
</task>
</tasks>
<verification>
1. `grep -c 'Resolved by amendment (R01)\|R01 amendments' .vbw-planning/phases/01-core-mvp/01-01-PLAN.md` returns >= 3 (one per DEV-01/02/03).
2. `grep -c 'Resolved by amendment (R01)\|R01 amendments' .vbw-planning/phases/01-core-mvp/01-06-PLAN.md` returns >= 1 (DEV-05).
3. `grep -c 'Resolved by amendment (R01)\|R01 amendments' .vbw-planning/phases/01-core-mvp/01-07-PLAN.md` returns >= 1 (DEV-06).
4. `git diff --name-only` shows ONLY files under `.vbw-planning/phases/01-core-mvp/` were modified (no lib/, test/, gemfiles/, .github/, README/CHANGELOG/.gitignore/.standard.yml/Appraisals/Rakefile/track_relay.gemspec changes).
5. `bundle exec rake test` continues to pass (241 runs, 0 failures) — sanity check that the documentation-only amendments didn't accidentally alter runtime files.
6. `bundle exec standardrb` continues to pass (no Ruby files were touched).
7. `R01-PLAN.md` exists at `.vbw-planning/phases/01-core-mvp/remediation/qa/round-01/R01-PLAN.md` with all 6 FAIL IDs covered in `fail_classifications`.
</verification>
<success_criteria>
- All 5 plan-amendment FAILs (DEV-01, DEV-02, DEV-03, DEV-05, DEV-06) have their source PLAN.md updated with the actually-shipped approach and a "Resolved by amendment (R01)" tag.
- DEV-04 is recorded as a process-exception with explicit retroactive-non-fixable rationale.
- No production or test code is modified — the existing 241-test, 0-failure suite remains the source of truth for runtime behavior.
- Future verification runs of Phase 01 against the amended plans produce PASS for all 6 deviation checks (the plan text now matches the shipped implementation).
- This remediation plan's frontmatter `fail_classifications` covers all 6 IDs with `type` of either `plan-amendment` (with `source_plan`) or `process-exception` (with rationale).
</success_criteria>
<known_issue_workflow>
- Carried known-issues backlog status: missing (count=0). No prior round produced a known-issues file.
- `known_issues_input` is the empty array — there are no carried known issues to forward.
- `known_issue_resolutions` is the empty array — nothing to resolve, accept, or carry forward.
- If a future QA verification surfaces flaky tests or environment-dependent failures during this round, the next remediation round must populate both arrays per the canonical `{test,file,error}` shape.
</known_issue_workflow>
<output>
R01-SUMMARY.md
</output>
