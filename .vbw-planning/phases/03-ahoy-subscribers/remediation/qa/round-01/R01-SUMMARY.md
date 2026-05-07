---
phase: 03
round: "01"
title: Plan amendments — formalize three pre-recorded deviations as resolved-by-amendment
type: remediation
status: complete
completed: 2026-05-06
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 323e18369140b28fca2f3640bcbb5f5688cc782e
files_modified:
  - .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md
  - .vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md
deviations: []
fail_resolutions:
  - "MH-02 resolved-by-amendment: Plan 03-01 must_have updated to assert lockfile presence (not .gemfile presence). Source plan: 03-01-PLAN.md."
  - "MH-06 resolved-by-amendment: Plan 03-01 self-deviation replaced by two affirmative must_haves describing controller.ahoy.track routing and no-controller skip path. Resolved Deviations section appended to body. Source plan: 03-01-PLAN.md."
  - "MH-21 resolved-by-amendment: Plan 03-02 Task 4 tsc invocation corrected (dropped --allowImportingTsExtensions=false). Source plan: 03-02-PLAN.md."
known_issue_outcomes: []
pre_existing_issues: []
---

Documentation-only remediation round: amended Plan 03-01 and Plan 03-02 to formalize three pre-recorded deviations (MH-02 lockfile-resolution wording, MH-06 affirmative must_haves replacing the self-deviation, MH-21 corrected tsc invocation) as resolved-by-amendment. No source code, test, or release-artifact files changed.

## Task 1: Amend 03-01-PLAN.md MH-02 wording (lockfile-based assertion)

### What Was Built
- MH-02 must_have line in `03-01-PLAN.md` frontmatter rewritten to assert that `ahoy_matey` resolves under all three Rails appraisal lockfiles (`gemfiles/rails_7_1.gemfile.lock`, `gemfiles/rails_7_2.gemfile.lock`, `gemfiles/rails_8_0.gemfile.lock`), with a parenthetical explaining that Appraisal-generated `.gemfile` files only inline `gemspec path: "../"` and pull dev-deps transitively from the gemspec — the lockfiles are the authoritative resolution evidence.
- Cross-evidence verified: `grep "ahoy_matey" gemfiles/*.lock` returned 9 matches across all three lockfiles (rails_7_1: 5.4.2; rails_7_2: 5.5.0; rails_8_0: 5.5.0). The new must_have wording aligns with on-disk reality.

### Files Modified
- `.vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` -- amended: replaced the old `.gemfile`-presence wording at line 12 with the new lockfile-based wording.

### Deviations
None. Edit produced exactly the wording prescribed in R01-PLAN Task 1.

## Task 2: Amend 03-01-PLAN.md MH-06 wording (replace self-deviation with affirmative must_haves + add Resolved Deviations section)

### What Was Built
- The single MH-06 self-deviation must_have ("DEVIATION FROM SUCCESS CRITERIA — RECORDED: ...") was replaced by two affirmative must_haves: (a) `#deliver` routes via `controller.ahoy.track(payload.name.to_s, payload.params)` only — `Ahoy::Tracker` is Ahoy's only public tracking surface (`Ahoy::Visit` has no `track(name, props)` method per 03-RESEARCH.md §2); (b) in job/console contexts where `TrackRelay::Current.controller` is nil, the subscriber skip-logs (`Rails.logger.warn`) and returns, substituting for REQ-09's reference to a `visit.track` fallback.
- A `## Resolved Deviations` section was appended to the body of `03-01-PLAN.md` immediately above `## Notes`. It documents the original ROADMAP wording (`controller.ahoy.track or visit.track only`), explains why `visit.track` does not exist on `Ahoy::Visit`, enumerates the two implemented paths, and pins both to existing unit tests (`test_dispatches_via_controller_ahoy_track` and `test_skips_when_no_current_controller`). It cross-references `03-RESEARCH.md §2` and notes that the original self-deviation was captured in `03-01-SUMMARY.md` deviations[] as DEVN-02.
- Verification greps confirmed the old "DEVIATION FROM SUCCESS CRITERIA — RECORDED" phrase is gone (0 matches), the new "skip path substitutes for REQ-09" wording is present (1 match), and the `## Resolved Deviations` heading appears exactly once.

### Files Modified
- `.vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` -- amended: replaced the MH-06 self-deviation must_have at line 16 with two affirmative must_haves (lines 16-17) and appended the new `## Resolved Deviations` section above `## Notes`.

### Deviations
None. Edits produced exactly the wording and structure prescribed in R01-PLAN Task 2.

## Task 3: Amend 03-02-PLAN.md Task 4 tsc invocation (drop malformed flag)

### What Was Built
- The `npx tsc` invocation in `03-02-PLAN.md` Task 4's heredoc block no longer carries the malformed `--allowImportingTsExtensions=false` flag. The corrected command line reads: `npx tsc --noEmit --strict --skipLibCheck --target ES2020 --module ESNext --moduleResolution Bundler /tmp/track_relay_typecheck.ts`.
- A one-line note was inserted immediately above the corrected `npx tsc` line: `# Note: --allowImportingTsExtensions=false is rejected by tsc with TS5025; the flag's default is false, so omitting it is correct.`
- The heredoc's import path was switched from the relative `"./src/index.js"` to the absolute `"/Users/darrindemchuk/code/side_projects/track_relay/client/src/index.js"` so module resolution works when `tsc` runs against a file in `/tmp/`.
- The obsolete trailing paragraph that suggested adding `--allowImportingTsExtensions` as a remediation was replaced by a single sentence explaining why the absolute import path is required and why the malformed flag is omitted.
- Verification greps confirmed the prescribed `npx tsc` command no longer contains the flag, the new `rejected by tsc with TS5025` note appears, and the absolute import path appears once. Note: the literal string `--allowImportingTsExtensions=false` still appears in the two explanatory notes (R01-PLAN Task 3 action items required these literal phrases) — the *prescribed command* is clean, which matches the verify check's stated intent ("the malformed flag is gone from the prescribed command").

### Files Modified
- `.vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md` -- amended: rewrote the Task 4 heredoc block (absolute import path, new explanatory note line, corrected `npx tsc` invocation) and replaced the obsolete trailing paragraph.

### Deviations
None. Action items were followed verbatim and the verify check's stated intent (the malformed flag is gone from the prescribed `npx tsc` command) is satisfied — see body note in Plan 03-02 Task 4 explaining the TS5025 rationale, which legitimately mentions the malformed flag in the explanatory note.

## Task 4: Final verification + commit (one commit covers all three amendments)

### What Was Built
- Cross-evidence sanity grep confirmed the new MH-02 lockfile-based must_have aligns with reality: `ahoy_matey` is referenced in Plan 03-01 (multiple lines, including the new must_have at line 12) AND each of the three Rails appraisal lockfiles (rails_7_1.gemfile.lock at version 5.4.2; rails_7_2.gemfile.lock and rails_8_0.gemfile.lock at version 5.5.0).
- Both amended plans were read end-to-end and confirmed internally consistent: (a) Plan 03-01 MH-02 reflects lockfile reality; (b) Plan 03-01 MH-06 is now two affirmative must_haves and the new `## Resolved Deviations` section sits above `## Notes` with a reference to `03-RESEARCH.md §2`; (c) Plan 03-02 Task 4's prescribed `tsc` command no longer contains `--allowImportingTsExtensions=false` and the absolute import path is in place. YAML frontmatter parses cleanly in both plans.
- Exactly the two amended plan files were staged (`git add .vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md .vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md`); no other working-tree changes were included.
- Single commit created on `main` with subject `docs(qa-remediation-r01): amend Plan 03-01 and Plan 03-02 for resolved-by-amendment deviations`. Body enumerated the three amendments. Commit hash: `323e18369140b28fca2f3640bcbb5f5688cc782e`. `git show --stat HEAD` confirmed exactly two files changed (228 insertions, 0 deletions — both files were previously untracked in the working tree, so the diff shows them as added).
- No `git push`, `gem push`, `npm publish`, or `scripts/bump-version.sh` invocations occurred.

### Files Modified
- `.vbw-planning/phases/03-ahoy-subscribers/03-01-PLAN.md` -- staged and committed (amendments from Tasks 1 and 2).
- `.vbw-planning/phases/03-ahoy-subscribers/03-02-PLAN.md` -- staged and committed (amendment from Task 3).

### Deviations
None.
