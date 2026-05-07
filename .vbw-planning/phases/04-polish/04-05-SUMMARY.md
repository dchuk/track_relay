---
phase: 4
plan: "05"
title: "Doc audit for 1.0.0 — README expansion, CHANGELOG [1.0.0], USAGE.md, UPGRADING.md"
status: complete
completed: 2026-05-07
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - f2730149e0546f009f5153d04ad303652b52ad17
  - af6b1f23f047b79f5268c614249c750fa1cf8535
  - ef9c4a0ac8801ca9c7eb9a9b17e6842f0589e79c
  - 8bb5c29b4743dd0567fd94fe9b927dbcb060cc15
deviations:
  - "DEVN-01 (Task 1, Compatibility row): Plan called for editing a '0.x version cell' in the Compatibility matrix; no such cell exists — that section lists Ruby/Rails/test-framework rows only, no version row. Left unchanged. Out of scope and minor."
  - "DEVN-01 (Task 2, verify exact-count): Task 2 verify says `grep -E 'Public API stability' CHANGELOG.md` returns 1, but the prescribed entry content includes both '**Public API stability:**' and a 'Generators, Ahoy subscriber, Public API stability.' bullet, producing 2 matches. Followed prescribed content verbatim — must_have truth ('CHANGELOG [1.0.0] entry includes the public-API stability statement') is satisfied."
  - "Task 5 produced no commit because it is verification-only (`<files>(no files modified — verification only)</files>`). All cross-doc links verified to resolve; results captured in this SUMMARY."
pre_existing_issues: []
ac_results:
  - criterion: "README references the three generators (track_relay:install, track_relay:event, track_relay:subscriber)"
    verdict: pass
    evidence: "f273014 — README.md Generators section + Installation + USAGE link"
  - criterion: "README has a public-API stability statement listing the stable surface"
    verdict: pass
    evidence: "f273014 — README.md `## Public API stability` heading at line 411"
  - criterion: "README has a link to USAGE.md and UPGRADING.md"
    verdict: pass
    evidence: "f273014 — both linked from Status, Installation, Generators, Public API stability sections (>= 2 references each)"
  - criterion: "README's Ahoy subscriber documentation exists (was missing pre-1.0.0)"
    verdict: pass
    evidence: "f273014 — `### Ahoy subscriber (server-side)` subsection added"
  - criterion: "README's Roadmap section reflects 1.0.0 reality (0.3.0 done; 1.0.0 cuts after Phase 4 UAT)"
    verdict: pass
    evidence: "f273014 — Roadmap rewritten with Shipped (0.1.0/0.2.0/0.3.0) / Pending release (1.0.0) / Future"
  - criterion: "Installation section uses ~> 1.0 (not ~> 0.2.0)"
    verdict: pass
    evidence: "f273014 — `gem \"track_relay\", \"~> 1.0\"`; 0 occurrences of `~> 0.2.0` remain"
  - criterion: "CHANGELOG has a [1.0.0] entry in Keep-a-Changelog format with Added/Changed/Notes sections"
    verdict: pass
    evidence: "af6b1f2 — CHANGELOG.md `## [1.0.0] - 2026-05-07` with Added/Changed/Notes subsections"
  - criterion: "CHANGELOG [1.0.0] entry includes the public-API stability statement"
    verdict: pass
    evidence: "af6b1f2 — CHANGELOG.md Notes section bold label `**Public API stability:**` enumerates stable surface and internal exclusions"
  - criterion: "CHANGELOG version-link table includes [1.0.0] entry (forward-looking compare URL)"
    verdict: pass
    evidence: "af6b1f2 — `[1.0.0]: https://github.com/dchuk/track_relay/compare/v0.3.0...v1.0.0`"
  - criterion: "Roadmap and CHANGELOG describe 1.0.0 as 'pending release' (NOT 'shipped')"
    verdict: pass
    evidence: "f273014 README Roadmap 'Pending release' subhead; af6b1f2 CHANGELOG Changed section says 'Targeting 1.0.0 (pending release)'"
  - criterion: "[Unreleased] link target is NOT retargeted in this plan"
    verdict: pass
    evidence: "af6b1f2 — Bottom of CHANGELOG.md retains existing tags-style link entries; no [Unreleased] retarget added"
  - criterion: "USAGE.md exists at repo root (NOT doc/usage.md)"
    verdict: pass
    evidence: "ef9c4a0 — USAGE.md created at /Users/darrindemchuk/code/side_projects/track_relay/USAGE.md"
  - criterion: "UPGRADING.md exists at repo root, covers 0.1.0 → 0.2.0 → 0.3.0 → 1.0.0 migration paths"
    verdict: pass
    evidence: "8bb5c29 — UPGRADING.md created with three `## ` migration sections (0.1→0.2, 0.2→0.3, 0.3→1.0)"
  - criterion: "README.md provides expanded for 1.0.0; contains 'rails g track_relay:install'"
    verdict: pass
    evidence: "f273014 — README has Quick Start tip + Generators section both referencing `bin/rails g track_relay:install`"
  - criterion: "CHANGELOG.md provides [1.0.0] entry; contains '## [1.0.0]'"
    verdict: pass
    evidence: "af6b1f2 — `^## \\[1\\.0\\.0\\] - 2026-05-07` matches once"
  - criterion: "USAGE.md provides getting-started guide; contains 'rails g track_relay:install'"
    verdict: pass
    evidence: "ef9c4a0 — section 1 'Install' begins `bin/rails generate track_relay:install`"
  - criterion: "UPGRADING.md provides migration notes; contains '0.3.0 → 1.0.0'"
    verdict: pass
    evidence: "8bb5c29 — `## 0.3.0 → 1.0.0` heading at line 59"
  - criterion: "README.md links to USAGE.md (markdown link)"
    verdict: pass
    evidence: "Task 5 verification: README.md -> USAGE.md resolves"
  - criterion: "README.md links to UPGRADING.md (markdown link)"
    verdict: pass
    evidence: "Task 5 verification: README.md -> UPGRADING.md resolves"
  - criterion: "README.md links to CHANGELOG.md (markdown link)"
    verdict: pass
    evidence: "Task 5 verification: README.md -> CHANGELOG.md resolves"
  - criterion: "CHANGELOG.md [1.0.0] links to UPGRADING.md (markdown link)"
    verdict: pass
    evidence: "af6b1f2 — Two markdown links to UPGRADING.md inside the [1.0.0] entry (Added list + Changed section)"
---

Doc audit for 1.0.0 readiness — README expansion, CHANGELOG [1.0.0], USAGE.md, UPGRADING.md — all four documents now form a coherent reference graph with the 1.0.0 surface fully described.

## What Was Built

- README expanded for 1.0.0: status line bumped to "1.0.0 (pending release)", Gemfile pin updated to `~> 1.0`, generator-first install path added (Quick Start tip + Installation block), new Ahoy subscriber subsection, new Generators section covering all three generators, Roadmap rewritten (Shipped / Pending release / Future), new Public API stability section enumerating stable surface and internal exclusions, plus cross-links to USAGE.md / UPGRADING.md / CHANGELOG.md
- CHANGELOG [1.0.0] entry added in Keep-a-Changelog format with Added (three generators, USAGE.md/UPGRADING.md, E2E test, README sections), Changed (1.0.0 stability target), and Notes (full public-API stability statement) sections; forward-looking `[1.0.0]: …compare/v0.3.0...v1.0.0` link added; `[Unreleased]` link target intentionally left as-is (release-cut concern)
- USAGE.md created at repo root with 7+1 numbered sections: Install, Define event, Track from controller, Add subscribers (with built-in catalog), Test events, Untyped + linter, GA4 + client-side, plus a Next footer
- UPGRADING.md created at repo root with 3 migration sections: 0.1.0→0.2.0 (no breaking, GA4 features), 0.2.0→0.3.0 (one JS BREAKING change with code example), 0.3.0→1.0.0 (no breaking, generators + stability + 4-step upgrade procedure)
- All cross-document markdown links verified to resolve (README/CHANGELOG/USAGE/UPGRADING form a connected reference graph; UPGRADING's `README.md#public-api-stability` anchor matches the rendered heading anchor)

## Files Modified

- `README.md` -- modified: Status, Installation, Quick start tip, Subscribers (Ahoy added), Generators section, Roadmap, Public API stability section
- `CHANGELOG.md` -- modified: [1.0.0] - 2026-05-07 entry inserted between [Unreleased] and [0.3.0]; [1.0.0] compare link added to version-link table
- `USAGE.md` -- created: getting-started guide at repo root (8 `## ` headings)
- `UPGRADING.md` -- created: migration notes at repo root (3 `## ` migration sections)

## Deviations

- DEVN-01 (Task 1, Compatibility row): Plan called for editing a "0.x version cell" in the Compatibility matrix; no such cell exists in the current README. The Compatibility section is a simple bulleted list of Ruby/Rails/test-framework rows. Nothing to update — left unchanged.
- DEVN-01 (Task 2, verify exact-count): Plan's verify check `grep -E "Public API stability" CHANGELOG.md` expected 1 line; the prescribed entry content (followed verbatim) produces 2 matches because the entry contains both `**Public API stability:**` (Notes label) and a "Generators, Ahoy subscriber, Public API stability." bullet in the Added list. Content is correct and matches the must_have truth; verify-count expectation in the plan is internally inconsistent with the prescribed content.
- Task 5 (link integrity verification) produced no git commit because it is a verification-only task per the plan (`<files>(no files modified — verification only)</files>`). All four task verify outputs are recorded above in `ac_results`.
