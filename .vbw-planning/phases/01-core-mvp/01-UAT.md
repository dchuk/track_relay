---
phase: 1
plan: "01"
title: Phase 01 (Core MVP) — UAT
status: complete
started: 2026-05-06
completed: 2026-05-06
total_tests: 6
passed: 6
failed: 0
skipped: 0
issues_found: 0
---

# Phase 01 (Core MVP) — UAT Checkpoints

QA already verified 241 automated tests (catalog DSL, validation, dispatch, subscribers, Railtie, concerns, test mode, matchers, linter, end-to-end flow). UAT focuses on subjective quality that only the human user can judge: API ergonomics, doc clarity, and Quick Start experience.

## Tests

### P09-T01 — README clarity (plan 01-09)

**Scenario:** Open `README.md` in the repo root and skim it as if you were a Rails developer who just landed on this gem for the first time. Does it answer (a) what does this gem do?, (b) why should I use it?, (c) how do I start?, in under 60 seconds of reading?

**Expected:** README reads coherently; the value proposition is clear; you can identify the entry-point method (`TrackRelay.track`) without searching.

**Result:** pass
**Notes:**

---

### P09-T02 — Quick Start ergonomics (plan 01-09)

**Scenario:** Read the `## Quick start` section of `README.md`. Imagine you were following it in a fresh Rails 8 app. Are the steps in the right order? Does anything feel like it would trip up a developer who's never used the gem? (Don't actually run it — just judge whether the path looks viable.)

**Expected:** The Quick Start is a believable five-minute path: install → configure → write a catalog → fire your first event.

**Result:** pass
**Notes:**

---

### P02-T01 — Catalog DSL ergonomics (plan 01-02)

**Scenario:** Open `README.md` `## Catalog DSL` section (or read `lib/track_relay/dsl/event_builder.rb` and `lib/track_relay/dsl/param_builder.rb` directly). Look at the catalog declaration syntax:

```ruby
TrackRelay.catalog do
  event :article_viewed do
    integer :article_id, required: true
    string :slug, required: true
  end
end
```

Does this DSL feel right for the way you'd want to declare events in your own Rails app? Anything that would make you reach for a comment or a helper method on the third event you defined?

**Expected:** The DSL is declarative, reads naturally, and matches the spirit of "one catalog, many destinations" (the project's core value statement).

**Result:** pass
**Notes:**

---

### P07-T01 — Test helpers ergonomics (plan 01-07)

**Scenario:** Open `README.md` `## Test helpers` section. Look at the Minitest assertions and RSpec matchers:

```ruby
# Minitest
assert_tracked(:article_viewed, article_id: 7)

# RSpec
expect(track_relay).to have_tracked(:article_viewed).with(article_id: 7)
```

Would you actually want to write tests this way? Does the API feel coherent across both frameworks?

**Expected:** Both helpers feel idiomatic for their respective frameworks; the `track_relay` accessor / `track_relay_test` accessor names are intuitive.

**Result:** pass
**Notes:**

---

### P08-T01 — Linter output value (plan 01-08)

**Scenario:** Open `README.md` `## Untyped events + linter` section. Look at the example linter output (or imagine running `bundle exec rake track_relay:lint` after a week in production with several untyped events firing). Would the report's format help you decide which events to formalize first? Is the privacy contract (param NAMES only — never values) clearly communicated?

**Expected:** The linter output is actionable — sorted by occurrence count, dedupes by signature, makes it obvious which untyped events deserve catalog entries.

**Result:** pass
**Notes:**

---

### P00-T01 — Phase-wide coherence (all plans)

**Scenario:** Step back and look at the public API surface as a whole: `TrackRelay.configure`, `TrackRelay.catalog`, `TrackRelay.track`, `TrackRelay.identify`, `TrackRelay.test_mode!`, `TrackRelay::Subscribers::Base/Test/Logger`, `TrackRelay::ControllerTracking`, `TrackRelay::JobTracking`. Does the overall API feel like one gem written by one mind, or does it feel stitched together? Anything that surprised you in a bad way?

**Expected:** API surface feels coherent; naming is consistent; nothing reads as bolted on.

**Result:** pass
**Notes:**
