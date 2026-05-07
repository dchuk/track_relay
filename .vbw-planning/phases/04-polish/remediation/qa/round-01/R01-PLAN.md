---
phase: 04
round: 01
plan: R01
title: Amend 04-05-PLAN to resolve DEV-01 and DEV-02 plan-amendment deviations
type: remediation
autonomous: true
effort_override: balanced
skills_used: []
files_modified:
  - .vbw-planning/phases/04-polish/04-05-PLAN.md
forbidden_commands: []
fail_classifications:
  - {id: "DEV-01", type: "plan-amendment", rationale: "Plan task 8 instructed editing a '0.x version cell' in README's Compatibility matrix that does not exist. The Compatibility section contains Ruby/Rails/test-framework rows only. The Installation section's ~> 1.0 pin must_have is independently met. Amend 04-05-PLAN.md task 1 acceptance to reflect the actual file structure.", source_plan: "04-05-PLAN.md"}
  - {id: "DEV-02", type: "plan-amendment", rationale: "Plan's task-2 verify step expected exactly 1 grep match for 'Public API stability' in CHANGELOG. The prescribed entry content produces 2 matches (Notes section bold + Added bullet). The must_have ('CHANGELOG [1.0.0] entry includes the public-API stability statement') is satisfied. Amend 04-05-PLAN.md task 2 verify count to match the prescribed content.", source_plan: "04-05-PLAN.md"}
known_issues_input: []
known_issue_resolutions: []
must_haves:
  truths:
    - "04-05-PLAN.md task 1 acceptance no longer references the non-existent Compatibility version cell in README"
    - "04-05-PLAN.md task 2 verify step is consistent with the prescribed CHANGELOG content (expects 2 matches for 'Public API stability', or removes the exact-count check)"
    - "Both DEV-01 and DEV-02 deviations have a Deviation resolution block in 04-05-PLAN.md documenting the rationale and blessing the original Dev approach as resolved-by-amendment"
    - "No code, README, CHANGELOG, USAGE.md, or UPGRADING.md content is modified — this round amends only the plan file"
  artifacts:
    - {path: ".vbw-planning/phases/04-polish/04-05-PLAN.md", provides: "amended task 1 acceptance and task 2 verify, plus two Deviation resolution blocks", contains: "Deviation resolution"}
  key_links:
    - {from: "04-05-PLAN.md task 1", to: "DEV-01 deviation", via: "resolved-by-amendment block"}
    - {from: "04-05-PLAN.md task 2", to: "DEV-02 deviation", via: "resolved-by-amendment block"}
---
<objective>
Resolve QA round-01 FAIL checks DEV-01 and DEV-02 by amending 04-05-PLAN.md. Both deviations are plan-amendment classifications: the plan's prescribed acceptance/verify steps did not match either the actual repository file structure (DEV-01) or the plan's own prescribed content (DEV-02). The Dev's delivery is correct in both cases and the underlying must_haves are independently satisfied. This round leaves the shipped docs untouched and only amends the plan to record the resolved-by-amendment dispositions.
</objective>
<context>
@.vbw-planning/phases/04-polish/04-VERIFICATION.md
@.vbw-planning/phases/04-polish/04-05-PLAN.md
@.vbw-planning/phases/04-polish/04-05-SUMMARY.md
</context>
<tasks>
<!-- Tasks are executed sequentially — task N+1 sees the results of task N.
     Order matters: place foundational fixes before dependent ones. -->
<task type="auto">
  <name>Amend 04-05-PLAN task 1 acceptance for DEV-01 (Compatibility matrix non-existent row)</name>
  <files>
    .vbw-planning/phases/04-polish/04-05-PLAN.md
  </files>
  <action>
Open .vbw-planning/phases/04-polish/04-05-PLAN.md and locate task 1 (the README 1.0.0 update task that originally referenced editing a "0.x version cell" in the Compatibility matrix).

Edit the task's `acceptance:` block to remove every reference to the non-existent Compatibility version cell/row. Replace it with acceptance criteria that match what actually exists in README.md and what was independently verified as PASS:
- Installation section pin updated to `~> 1.0` (this satisfies the original must_have).
- Roadmap section reflects 1.0.0 reality (post-1.0 framing rather than pre-1.0 milestones).
- Do NOT introduce or require any Compatibility-matrix version row, because the Compatibility section in README.md contains only Ruby / Rails / test-framework rows.

Append a `# Deviation resolution` block to that same task documenting:
- Deviation ID: DEV-01
- Classification: plan-amendment (resolved-by-amendment)
- What the original plan asked for: edit a 0.x version cell in the README Compatibility matrix.
- What actually exists: the Compatibility section has Ruby/Rails/test-framework rows only — no version row.
- What the Dev did: correctly skipped the non-existent edit and updated the Installation `~> 1.0` pin and Roadmap framing instead.
- Rationale: the Installation `~> 1.0` pin must_have is independently met (verified PASS in 04-VERIFICATION.md). The Dev's approach is hereby blessed as the correct delivery.

Do NOT modify README.md or any other file. The shipped README is correct as delivered.
  </action>
  <verify>
1. `grep -n "Compatibility" .vbw-planning/phases/04-polish/04-05-PLAN.md` shows that task 1's acceptance no longer instructs editing a Compatibility version cell/row (any remaining mentions are in the Deviation resolution block describing why the original instruction was wrong).
2. `grep -n "Deviation resolution" .vbw-planning/phases/04-polish/04-05-PLAN.md` returns at least one match associated with task 1, and the surrounding text references DEV-01 and "resolved-by-amendment".
3. `grep -n "~> 1.0" .vbw-planning/phases/04-polish/04-05-PLAN.md` confirms the Installation pin acceptance criterion remains in task 1.
4. `git status` shows only `.vbw-planning/phases/04-polish/04-05-PLAN.md` as modified — no README/CHANGELOG/USAGE/UPGRADING changes.
  </verify>
  <done>
04-05-PLAN.md task 1 acceptance no longer references the non-existent Compatibility version cell, the Installation `~> 1.0` pin and Roadmap-reality criteria remain, and a `# Deviation resolution` block records DEV-01 as resolved-by-amendment with the rationale and the Dev's approach blessed. One commit produced: `docs(qa-remediation-r01): amend Plan 04-05 task 1 acceptance for DEV-01 resolved-by-amendment`.
  </done>
</task>
<task type="auto">
  <name>Amend 04-05-PLAN task 2 verify for DEV-02 (CHANGELOG 'Public API stability' grep count)</name>
  <files>
    .vbw-planning/phases/04-polish/04-05-PLAN.md
  </files>
  <action>
Open .vbw-planning/phases/04-polish/04-05-PLAN.md and locate task 2 (the CHANGELOG [1.0.0] entry task whose verify step expected exactly 1 grep match for "Public API stability").

Edit the task's `verify:` block to be consistent with the plan's own prescribed CHANGELOG content. The prescribed entry contains both `**Public API stability:**` (Notes section bold label) and `Generators, Ahoy subscriber, Public API stability.` (Added bullet), which together yield 2 matches under `grep -c 'Public API stability' CHANGELOG.md`. Choose the cleaner of these two amendments and apply it:
- Preferred: replace the exact-count assertion with a semantic check — e.g., `grep -E 'Public API stability' CHANGELOG.md` returns at least 1 match AND the [1.0.0] section contains a public-API stability statement. This matches the underlying must_have ("CHANGELOG [1.0.0] entry includes the public-API stability statement") without re-introducing a brittle count.
- Acceptable alternative: keep the count check but set the expected count to 2 to match the prescribed content.

Append a `# Deviation resolution` block to that same task documenting:
- Deviation ID: DEV-02
- Classification: plan-amendment (resolved-by-amendment)
- What the original plan asked for: `grep -E 'Public API stability' CHANGELOG.md` returns exactly 1 match.
- What actually happens with the prescribed content: the entry contains both the Notes-section bold label and the Added bullet, producing 2 matches — the original verify expectation was internally inconsistent with the plan's own prescribed text.
- What the Dev did: produced CHANGELOG.md content that follows the prescribed entry verbatim, satisfying the must_have semantic.
- Rationale: the must_have ("CHANGELOG [1.0.0] entry includes the public-API stability statement") is independently met (verified PASS in 04-VERIFICATION.md MH-17). The Dev's approach is hereby blessed as the correct delivery; the verify expectation has been amended to match the prescribed content.

Do NOT modify CHANGELOG.md or any other file. The shipped CHANGELOG is correct as delivered.
  </action>
  <verify>
1. `grep -n "Public API stability" .vbw-planning/phases/04-polish/04-05-PLAN.md` shows task 2's verify is now either count-free (semantic-only assertion) or expects exactly 2 matches — never 1.
2. `grep -n "Deviation resolution" .vbw-planning/phases/04-polish/04-05-PLAN.md` returns at least two matches in total (task 1 from the previous step plus task 2 from this step), and the task-2 block references DEV-02 and "resolved-by-amendment".
3. `git status` shows only `.vbw-planning/phases/04-polish/04-05-PLAN.md` as modified — no CHANGELOG/README/USAGE/UPGRADING changes.
4. `git diff --stat HEAD~1 .vbw-planning/phases/04-polish/04-05-PLAN.md` (after this commit) shows only edits to the plan file.
  </verify>
  <done>
04-05-PLAN.md task 2 verify is consistent with the prescribed CHANGELOG content (semantic check or count = 2; never 1), and a `# Deviation resolution` block records DEV-02 as resolved-by-amendment with the rationale and the Dev's approach blessed. One commit produced: `docs(qa-remediation-r01): amend Plan 04-05 task 2 verify for DEV-02 resolved-by-amendment`.
  </done>
</task>
</tasks>
<verification>
1. `grep -c "Deviation resolution" .vbw-planning/phases/04-polish/04-05-PLAN.md` returns at least 2 (one block per amended task).
2. `grep -E "DEV-01|DEV-02" .vbw-planning/phases/04-polish/04-05-PLAN.md` finds both deviation IDs in the amended plan, each within a resolved-by-amendment block.
3. Task 1 acceptance no longer requires editing a Compatibility version cell; Installation `~> 1.0` pin and Roadmap-reality criteria remain.
4. Task 2 verify expects either no exact count or exactly 2 matches for "Public API stability" — never 1.
5. `git log --oneline -2` shows two new commits with `docs(qa-remediation-r01):` prefix, each modifying only `.vbw-planning/phases/04-polish/04-05-PLAN.md`.
6. `git status` is clean against README.md, CHANGELOG.md, USAGE.md, UPGRADING.md, and all source files — only the plan file changed in this round.
</verification>
<success_criteria>
- 04-05-PLAN.md task 1 acceptance no longer references the non-existent README Compatibility version cell, while preserving the Installation `~> 1.0` pin and Roadmap-reality criteria.
- 04-05-PLAN.md task 2 verify is consistent with its own prescribed CHANGELOG content (2 matches expected, or the exact-count check is replaced with a semantic check on the public-API stability statement).
- Both DEV-01 and DEV-02 carry a `# Deviation resolution` block in 04-05-PLAN.md that names the deviation ID, classifies it as plan-amendment / resolved-by-amendment, records the original Dev approach as correct, and gives the rationale grounded in the independent PASS evidence from 04-VERIFICATION.md.
- No source, README.md, CHANGELOG.md, USAGE.md, or UPGRADING.md content is modified in this remediation round.
- Two atomic commits are produced, each scoped to `.vbw-planning/phases/04-polish/04-05-PLAN.md` and using the `docs(qa-remediation-r01):` prefix.
</success_criteria>
<known_issue_workflow>
- Always include `known_issues_input` and `known_issue_resolutions` in frontmatter. If there are no carried known issues, set both to empty arrays: `known_issues_input: []` and `known_issue_resolutions: []`.
- Copy every carried known issue from the remediation input backlog into `known_issues_input` using the canonical `{test,file,error}` shape.
- Add a matching `known_issue_resolutions` entry for every carried known issue. Use `resolved` when this round fixes it, `accepted-process-exception` when QA should treat it as a verified non-blocking carryover for this phase, and `unresolved` only when the issue is intentionally carried into the next round.
- Do not omit a carried known issue from these arrays. The deterministic gate treats missing coverage as a failed remediation round.
</known_issue_workflow>
<output>
R01-SUMMARY.md
</output>
