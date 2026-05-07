---
phase: 03
round: "01"
plan: R01
title: "Plan amendments — formalize three pre-recorded deviations as resolved-by-amendment"
type: remediation
autonomous: true
effort_override: balanced
skills_used: []
files_modified:
  - .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md
  - .vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md
forbidden_commands:
  - git push
  - gem push
  - npm publish
  - scripts/bump-version.sh
fail_classifications:
  - {id: "MH-02", type: "plan-amendment", rationale: "Appraisal mechanics: dev-deps resolve transitively through generated lockfiles, not directly into .gemfile files. Update must_have to assert lockfile presence in all three appraisals.", source_plan: "03-01-PLAN.md"}
  - {id: "MH-06", type: "plan-amendment", rationale: "Ahoy::Visit#track does not exist as a public API. The implementation routes via controller.ahoy.track and uses the no-controller skip path as the substitute. Replace the self-deviation must_have with affirmative acceptance criteria.", source_plan: "03-01-PLAN.md"}
  - {id: "MH-21", type: "plan-amendment", rationale: "tsc rejects --allowImportingTsExtensions=false (TS5025). Default value is false; flag is omittable. Update Task 4 invocation.", source_plan: "03-02-PLAN.md"}
known_issues_input: []
known_issue_resolutions: []
must_haves:
  truths:
    - "Plan 03-01 MH-02 must_have wording asserts lockfile presence (not .gemfile presence) for ahoy_matey across all three Rails appraisals."
    - "Plan 03-01 MH-06 self-deviation must_have is replaced by two affirmative must_haves describing the implemented controller.ahoy.track-only routing AND the no-controller skip-path substitute for REQ-09's missing visit.track."
    - "Plan 03-02 Task 4 tsc invocation no longer contains --allowImportingTsExtensions=false."
    - "No source code, test, or release-artifact files are modified by this round — documentation amendments only."
    - "All three FAIL classifications in this round are plan-amendment with source_plan pointing at a real amended file."
  artifacts:
    - {path: ".vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md", provides: "Amended Plan 03-01 with reframed MH-02 and MH-06 must_haves", contains: "ahoy_matey resolves under all three Rails appraisal lockfiles"}
    - {path: ".vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md", provides: "Resolved Deviations section documenting the original ROADMAP wording vs. implemented contract", contains: "Resolved Deviations"}
    - {path: ".vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md", provides: "Amended Plan 03-02 Task 4 with corrected tsc invocation", contains: "--allowImportingTsExtensions=false is rejected by tsc with TS5025"}
    - {path: ".vbw-planning/phases/03-ahoy-subscribers/remediation/qa/round-01/R01-SUMMARY.md", provides: "Remediation round summary with commit_hashes, files_modified, and three resolved-by-amendment deviation entries", contains: "resolved-by-amendment"}
  key_links:
    - {from: "03-01-PLAN.md MH-06 amendment", to: "03-RESEARCH.md §2", via: "API analysis confirming Ahoy::Visit has no track(name, props) method"}
    - {from: "03-02-PLAN.md Task 4 note", to: "tsc TS5025 error", via: "documented rationale for omitting the malformed flag"}
    - {from: "R01-SUMMARY.md deviations[]", to: "MH-02, MH-06, MH-21", via: "each entry marked resolved-by-amendment"}
---
<objective>
Amend Plan 03-01 and Plan 03-02 to formalize three pre-recorded deviations (MH-02, MH-06, MH-21) as resolved-by-amendment. The underlying behaviors are already correct — the gem resolves transitively in all three appraisal lockfiles, the implementation routes via `controller.ahoy.track` only with a no-controller skip path that substitutes for the non-existent `visit.track`, and the `tsc` invocation works once the malformed flag is dropped. This round only updates plan must_haves and task wording so QA's contract record reflects the actual (correct) implementation. No source code, test, or release-artifact files change.
</objective>
<context>
@.vbw-planning/phases/03-ahoy-subscribers/03-VERIFICATION.md
@.vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md
@.vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md
@.vbw-planning/phases/03-ahoy-subscribers/03-01-SUMMARY.md
@.vbw-planning/phases/03-ahoy-subscribers/03-02-SUMMARY.md
@.vbw-planning/phases/03-ahoy-subscribers/03-RESEARCH.md
</context>
<tasks>
<!-- Tasks are executed sequentially. All three amendments are documentation-only
     edits to the same two plan files; they share a single commit. -->

<task type="auto">
  <name>Amend 03-01-PLAN.md MH-02 wording (lockfile-based assertion)</name>
  <files>
    .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md
  </files>
  <action>
Locate the must_have line in `03-01-PLAN.md` frontmatter that currently reads:

  "`ahoy_matey` appears in each generated gemfile under `gemfiles/` (rails_7_1.gemfile, rails_7_2.gemfile, rails_8_0.gemfile) — regenerate via `bundle exec appraisal generate` after gemspec change"

Replace it with:

  "`ahoy_matey` resolves under all three Rails appraisal lockfiles (`gemfiles/rails_7_1.gemfile.lock`, `gemfiles/rails_7_2.gemfile.lock`, `gemfiles/rails_8_0.gemfile.lock`) — verified via `grep \"ahoy_matey\" gemfiles/*.lock` showing presence in all three (note: Appraisal-generated `.gemfile` files only inline `gemspec path: \"../\"` and pull dev-deps transitively from the gemspec, so the dev-dep does not appear directly in the `.gemfile` files — the lockfiles are the authoritative resolution evidence)."

Keep all other must_haves and tasks intact. Do NOT touch the rest of the plan body.
  </action>
  <verify>
Run `grep -n "appears in each generated gemfile" .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` — MUST return zero matches (the old wording is gone).

Run `grep -n "resolves under all three Rails appraisal lockfiles" .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` — MUST return exactly one match in the must_haves block.

Run `grep -n "ahoy_matey" gemfiles/rails_7_1.gemfile.lock gemfiles/rails_7_2.gemfile.lock gemfiles/rails_8_0.gemfile.lock` — MUST show presence in all three (sanity-check that the new wording matches reality; this is read-only on the host repo).
  </verify>
  <done>
The MH-02 must_have line in `03-01-PLAN.md` reads with the new lockfile-based wording. The grep on the lockfiles confirms all three appraisals carry `ahoy_matey`. No other lines in the plan changed.
  </done>
</task>

<task type="auto">
  <name>Amend 03-01-PLAN.md MH-06 wording (replace self-deviation with affirmative must_haves + add Resolved Deviations section)</name>
  <files>
    .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md
  </files>
  <action>
1. Locate the must_have line in `03-01-PLAN.md` frontmatter that currently reads:

  "DEVIATION FROM SUCCESS CRITERIA — RECORDED: ROADMAP says \"routes via TrackRelay::Current.controller.ahoy.track or visit.track only\". Ahoy's public API has NO `Ahoy::Visit#track` method (confirmed by 03-RESEARCH.md §2). Implementation routes via `controller.ahoy.track` only and skip-logs when no controller is present. The job-context skip path is the substitute for `visit.track` in REQ-09."

   Replace this single must_have with TWO affirmative must_haves (in this order):

   First replacement must_have:
   "`#deliver` routes via `controller.ahoy.track(payload.name.to_s, payload.params)` only — `Ahoy::Tracker` is Ahoy's only public tracking surface (`Ahoy::Visit` has no `track(name, props)` method; confirmed by 03-RESEARCH.md §2)."

   Second replacement must_have:
   "In job/console contexts where `TrackRelay::Current.controller` is nil, the subscriber skip-logs (`Rails.logger.warn`) and returns. This skip path substitutes for REQ-09's reference to a `visit.track` fallback (which does not exist on `Ahoy::Visit` per Phase 03 research §2)."

2. Append a new section to the body of `03-01-PLAN.md` immediately before the existing `## Notes` section (or, if `## Notes` is the last section, immediately above it):

```
## Resolved Deviations

- **MH-06 (formerly self-recorded as DEVN-02):** ROADMAP REQ-09 originally specified routing via `TrackRelay::Current.controller.ahoy.track or visit.track only`. The phrase `visit.track` references an API that does not exist on `Ahoy::Visit` — `Ahoy::Tracker` is Ahoy's only public tracking surface (see `03-RESEARCH.md §2`). The implemented contract:
  - **Controller-present path:** dispatch via `controller.ahoy.track(payload.name.to_s, payload.params)`.
  - **No-controller path (job/console):** skip-log via `Rails.logger.warn` and return — this is the substitute for the missing `visit.track` fallback.
  Both paths are pinned by unit tests `test_dispatches_via_controller_ahoy_track` and `test_skips_when_no_current_controller` in `test/unit/subscribers/ahoy_test.rb`. Original self-deviation captured in `03-01-SUMMARY.md` deviations[] as DEVN-02.
```

Do NOT modify any other must_haves, tasks, or sections.
  </action>
  <verify>
Run `grep -n "DEVIATION FROM SUCCESS CRITERIA — RECORDED" .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` — MUST return zero matches (the self-deviation phrasing is gone from the must_haves).

Run `grep -n "Ahoy::Tracker is Ahoy's only public tracking surface" .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` — MUST return one match in the must_haves block.

Run `grep -n "skip path substitutes for REQ-09" .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` — MUST return one match in the must_haves block.

Run `grep -n "## Resolved Deviations" .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` — MUST return exactly one match.

Read the amended plan and confirm the two new must_haves replace the single old self-deviation must_have at the same position in the YAML list (no orphan blank lines, no broken YAML).
  </verify>
  <done>
The MH-06 self-deviation must_have is replaced by two affirmative must_haves describing the implemented controller.ahoy.track routing and the no-controller skip path. A `## Resolved Deviations` section is appended above `## Notes` documenting the original ROADMAP wording vs. the implemented contract with a reference to `03-RESEARCH.md §2`. YAML frontmatter parses cleanly.
  </done>
</task>

<task type="auto">
  <name>Amend 03-02-PLAN.md Task 4 tsc invocation (drop malformed flag)</name>
  <files>
    .vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md
  </files>
  <action>
1. Locate the heredoc block in `03-02-PLAN.md` Task 4 that currently reads:

```
   cd client
   cat > /tmp/track_relay_typecheck.ts <<'TS'
   import { AhoyJs, Ga4Gtag, init } from "./src/index.js"
   // measurementId is now optional (the 0.3.0 breaking change)
   init({ manifestUrl: "/m.json" })
   // Both forms still valid
   init({ measurementId: "G-X", manifestUrl: "/m.json" })
   // Both subscribers expose the same handle shape
   AhoyJs.handle("purchase", { value: 1 })
   Ga4Gtag.handle("purchase", { value: 1 })
   TS
   npx tsc --noEmit --strict --skipLibCheck --target ES2020 --module ESNext --moduleResolution Bundler --allowImportingTsExtensions=false /tmp/track_relay_typecheck.ts
```

2. Replace the heredoc block with the corrected form. Two changes:

   (a) Insert a one-line note immediately ABOVE the `npx tsc ...` line:

   `   # Note: --allowImportingTsExtensions=false is rejected by tsc with TS5025; the flag's default is false, so omitting it is correct.`

   (b) Drop `--allowImportingTsExtensions=false` from the `npx tsc` invocation, AND change the import path inside the heredoc from `"./src/index.js"` to an absolute path consistent with the Dev's working approach. Use the absolute repo-relative path so module resolution works when tsc runs against `/tmp/track_relay_typecheck.ts`:

   Replace `import { AhoyJs, Ga4Gtag, init } from "./src/index.js"` with:
   `import { AhoyJs, Ga4Gtag, init } from "/Users/darrindemchuk/code/side_projects/track_relay/client/src/index.js"`

   Replace the `npx tsc` line with:
   `   npx tsc --noEmit --strict --skipLibCheck --target ES2020 --module ESNext --moduleResolution Bundler /tmp/track_relay_typecheck.ts`

3. Also remove the trailing paragraph that begins `**Note:** if the `import` path needs adjustment because `src/index.d.ts` resolves differently...` (the paragraph that suggested adding `--allowImportingTsExtensions` as a remediation) — that note is now obsolete because the corrected invocation drops the flag entirely. Replace that paragraph with a single line:

   `**Note:** the absolute import path is required because `tsc` runs against a file in `/tmp/`, where relative resolution would not find `client/src/index.js`. The previously-suggested `--allowImportingTsExtensions=false` flag is omitted; it is rejected by tsc (TS5025) and its default value is `false` regardless.`

Do NOT modify any other tasks, must_haves, or verification steps in `03-02-PLAN.md`.
  </action>
  <verify>
Run `grep -n "allowImportingTsExtensions=false" .vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md` — MUST return zero matches (the malformed flag is gone from the prescribed command).

Run `grep -n "rejected by tsc with TS5025" .vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md` — MUST return one match (the new note documenting why the flag is omitted).

Run `grep -n "/Users/darrindemchuk/code/side_projects/track_relay/client/src/index.js" .vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md` — MUST return one match (the absolute import path inside the heredoc).

Read the amended Task 4 and confirm the heredoc block, the new note line, and the trailing paragraph all read cleanly with no broken markdown or stray flags.
  </verify>
  <done>
Plan 03-02 Task 4's `tsc` invocation no longer contains `--allowImportingTsExtensions=false`. A one-line note explains why the flag is omitted. The import path inside the heredoc uses the absolute path. The obsolete trailing paragraph about adding the flag is replaced by a single sentence about absolute-path resolution. No other content in `03-02-PLAN.md` is modified.
  </done>
</task>

<task type="auto">
  <name>Final verification + commit (one commit covers all three amendments)</name>
  <files>
    .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md
    .vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md
  </files>
  <action>
1. Read both amended plans end-to-end and confirm the three amendments are internally consistent:
   (a) Plan 03-01 MH-02 must_have wording asserts lockfile presence in all three appraisals; the parenthetical about Appraisal mechanics is present.
   (b) Plan 03-01 MH-06 is now two affirmative must_haves (controller.ahoy.track-only routing AND the no-controller skip substitute), and the new `## Resolved Deviations` section documents the change with a reference to `03-RESEARCH.md §2`.
   (c) Plan 03-02 Task 4's `tsc` invocation no longer contains `--allowImportingTsExtensions=false` and the absolute import path is in place.
   Confirm YAML frontmatter still parses cleanly in both plans (no orphan keys, no broken indentation).

2. Run the cross-evidence grep one final time as a sanity check:
   `grep -n "ahoy_matey" .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md gemfiles/rails_7_1.gemfile.lock gemfiles/rails_7_2.gemfile.lock gemfiles/rails_8_0.gemfile.lock`
   The plan reference must mention `ahoy_matey` in the new lockfile-based must_have, and the three lockfiles must each match.

3. Stage exactly the two amended plan files (no other files):
   `git add .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md .vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md`

4. Create a single commit with message:
   `docs(qa-remediation-r01): amend Plan 03-01 and Plan 03-02 for resolved-by-amendment deviations`

   Body should briefly enumerate the three amendments (MH-02 lockfile reframe, MH-06 affirmative replacement + Resolved Deviations section, MH-21 tsc flag removal).

5. Do NOT run `git push`, `gem push`, `npm publish`, or `scripts/bump-version.sh`. This is a documentation-only round; release artifacts are unchanged.
  </action>
  <verify>
Run `git status` after the commit — working tree clean, no untracked or modified files outside `.vbw-planning/`.

Run `git show --stat HEAD` — exactly two files changed: `.vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` and `.vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md`. No source code, test, or release-artifact files in the diff.

Run `git log -1 --format=%s` — commit subject matches `docs(qa-remediation-r01): amend Plan 03-01 and Plan 03-02 for resolved-by-amendment deviations`.

Capture the commit hash for `R01-SUMMARY.md` `commit_hashes`.
  </verify>
  <done>
A single commit on `main` records all three plan amendments. Working tree is clean. The diff touches only the two `.md` plan files. Commit hash captured for `R01-SUMMARY.md`. No release commands were run.
  </done>
</task>

</tasks>
<verification>
1. `grep -n "appears in each generated gemfile" .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` → zero matches.
2. `grep -n "resolves under all three Rails appraisal lockfiles" .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` → exactly one match.
3. `grep -n "DEVIATION FROM SUCCESS CRITERIA — RECORDED" .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` → zero matches.
4. `grep -n "Ahoy::Tracker is Ahoy's only public tracking surface" .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` → exactly one match.
5. `grep -n "skip path substitutes for REQ-09" .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` → exactly one match.
6. `grep -n "## Resolved Deviations" .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` → exactly one match.
7. `grep -n "allowImportingTsExtensions=false" .vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md` → zero matches.
8. `grep -n "rejected by tsc with TS5025" .vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md` → exactly one match.
9. `git show --stat HEAD` → exactly two files changed; both under `.vbw-planning/phases/03-ahoy-subscribers/`.
10. `git status` → working tree clean.
11. `bundle exec rake` is NOT required for this round (documentation-only); skip.
12. `cd client && npm test` is NOT required for this round (documentation-only); skip.
</verification>
<success_criteria>
- Plan 03-01 MH-02 must_have wording reflects lockfile reality: `ahoy_matey` resolves under all three Rails appraisal lockfiles, with a parenthetical explaining Appraisal mechanics (`gemspec path: "../"` pulls dev-deps transitively).
- Plan 03-01 MH-06 self-deviation must_have is replaced by two affirmative must_haves: one for the `controller.ahoy.track`-only dispatch path, one for the no-controller skip path that substitutes for the missing `visit.track`.
- Plan 03-01 has a new `## Resolved Deviations` section documenting the original ROADMAP wording vs. the implemented contract, with a reference to `03-RESEARCH.md §2`.
- Plan 03-02 Task 4's `tsc` invocation no longer contains `--allowImportingTsExtensions=false`; a one-line note documents the TS5025 error and the absolute-import-path resolution.
- A single commit on `main` records exactly the two amended plan files; no source code, test, or release-artifact files are changed.
- `R01-SUMMARY.md` is written using the REMEDIATION-SUMMARY template with `commit_hashes`, `files_modified` (the two plan files), and `deviations` (three entries — MH-02, MH-06, MH-21 — each marked `resolved-by-amendment`). `pre_existing_issues: []`. The deterministic gate's source-plan coverage check is satisfied: MH-02 → `03-01-PLAN.md`, MH-06 → `03-01-PLAN.md`, MH-21 → `03-02-PLAN.md`.
- No `git push`, `gem push`, `npm publish`, or `scripts/bump-version.sh` invocations occurred.
</success_criteria>
<known_issue_workflow>
- `known_issues_input` is empty (count=0 per orchestrator input). No carryover from prior rounds.
- `known_issue_resolutions` is empty for the same reason — there are no carried known issues to resolve, accept, or carry forward.
- The deterministic gate treats this as a clean known-issues ledger; no resolution entries are required.
</known_issue_workflow>
<output>
R01-SUMMARY.md
</output>
