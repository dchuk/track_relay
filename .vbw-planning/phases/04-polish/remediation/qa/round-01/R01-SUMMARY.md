---
phase: 04
round: 01
title: Amend 04-05-PLAN to resolve DEV-01 and DEV-02 plan-amendment deviations
type: remediation
status: complete
completed: 2026-05-07
tasks_completed: 2
tasks_total: 2
commit_hashes:
  - d2e444a
  - 28cf7d3
files_modified:
  - .vbw-planning/phases/04-polish/04-05-PLAN.md
deviations: []
known_issue_outcomes: []
---

Amend 04-05-PLAN.md to record DEV-01 (non-existent README Compatibility version cell) and DEV-02 (CHANGELOG grep-count inconsistency) as resolved-by-amendment. Shipped docs untouched. Full test suite re-ran clean: 405 runs, 0 failures.

## Task 1: Amend 04-05-PLAN task 1 acceptance for DEV-01 (Compatibility matrix non-existent row)

### What Was Built
- Original step-8 instruction in 04-05-PLAN task 1 (edit a "0.x version cell" in README's Compatibility matrix) replaced with an explicit "No edit required" note explaining the Compatibility section contains only Ruby/Rails/test-framework rows.
- Acceptance now leans on the Installation `~> 1.0` pin (step 2) and Roadmap rewrite (step 6) to satisfy the version-currency must_haves independently.
- Appended a `# Deviation resolution: DEV-01 (resolved-by-amendment)` block that names the deviation, classifies it, records what the Dev did, and gives the rationale grounded in the PASS evidence from 04-VERIFICATION.md.

### Files Modified
- `.vbw-planning/phases/04-polish/04-05-PLAN.md` -- amended: removed prescription targeting non-existent README content; added Deviation resolution block for DEV-01.

### Deviations
None.

## Task 2: Amend 04-05-PLAN task 2 verify for DEV-02 (CHANGELOG 'Public API stability' grep count)

### What Was Built
- Original task-2 verify step `grep -E 'Public API stability' CHANGELOG.md returns 1 line` replaced with a semantic check: `grep -q 'Public API stability' CHANGELOG.md` exits 0 AND the [1.0.0] section contains a public-API stability statement.
- Rationale captured inline: the prescribed [1.0.0] entry contains BOTH the Notes-section bold label `**Public API stability:**` AND the Added bullet, yielding 2 matches under any count-based grep — so the original exact-count expectation was internally inconsistent with the plan's own prescribed text.
- Appended a `# Deviation resolution: DEV-02 (resolved-by-amendment)` block recording the deviation, classifying it, blessing the Dev's delivery, and grounding the rationale in 04-VERIFICATION.md MH-17 (PASS).
- Full test suite re-ran post-amendment: 405 runs, 0 failures (no regressions; matches MH-20 PASS).

### Files Modified
- `.vbw-planning/phases/04-polish/04-05-PLAN.md` -- amended: replaced brittle exact-count verify check with semantic equivalent; added Deviation resolution block for DEV-02.

### Deviations
None.
