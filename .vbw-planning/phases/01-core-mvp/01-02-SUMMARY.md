---
phase: 1
plan: "02"
title: Catalog DSL, EventDefinition, EventPayload, validators
status: complete
completed: 2026-05-06
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - 54a1701
  - 620d09b
  - 635e15d
  - 4579f57
  - fad1605
deviations: []
pre_existing_issues: []
ac_results:
  - criterion: "EventDefinition holds catalog metadata; EventPayload holds runtime data — two distinct classes"
    verdict: pass
    evidence: "lib/track_relay/event_definition.rb (commit 620d09b) + lib/track_relay/event_payload.rb (commit fad1605); test/unit/event_definition_test.rb + test/unit/event_payload_test.rb"
  - criterion: "Catalog DSL: `TrackRelay.catalog do; event :name do; integer :x, required: true; end; end` registers `:name` in the global registry"
    verdict: pass
    evidence: "test/unit/catalog_test.rb#test_track_relay_catalog_block_registers_typed_event (commit 4579f57)"
  - criterion: "Type DSL methods: integer/string/float/boolean/datetime each return ParamSchema with type/required/max/in/format/sanitize"
    verdict: pass
    evidence: "test/unit/dsl/param_builder_test.rb (9 tests covering all 5 types and all 6 schema slots)"
  - criterion: "Reserved-key collision raises ReservedKeyError at catalog-load time for :user/:visitor_token/:client_id/:request"
    verdict: pass
    evidence: "test/unit/validators/catalog_validator_test.rb (4 reserved-key tests) + test/unit/dsl/event_builder_test.rb#test_event_with_reserved_param_key_raises_at_load_time"
  - criterion: "GA4 event-name validator enforces snake_case, max 40 chars, refuses GA4 reserved names"
    verdict: pass
    evidence: "test/unit/validators/ga4_constraints_test.rb (14 event-name tests; 5 reserved names spot-checked: page_view, session_start, user_engagement, first_visit, video_complete)"
  - criterion: "GA4 param-count validator caps custom params at 25 per event"
    verdict: pass
    evidence: "test/unit/validators/ga4_constraints_test.rb#test_validate_param_count_rejects_26_params + test_validate_param_count_accepts_25_params"
  - criterion: "EventPayload#validate! coerces per type, enforces required/max/in/format, runs sanitize BEFORE validation, returns coerced hash, raises ValidationError"
    verdict: pass
    evidence: "test/unit/event_payload_test.rb (37 tests / 59 assertions including test_sanitize_runs_before_max_check + test_sanitize_runs_before_format_check)"
  - criterion: "All validation error classes live under TrackRelay::Error namespace and inherit from TrackRelay::Error"
    verdict: pass
    evidence: "lib/track_relay/errors.rb (commit 54a1701); manual smoke confirmed all 5 subclasses inherit from Error"
  - criterion: "lib/track_relay/catalog.rb provides Catalog registry containing `def self.register`"
    verdict: pass
    evidence: "lib/track_relay/catalog.rb (commit 4579f57) — `Catalog.register(definition)` defined"
  - criterion: "lib/track_relay/event_definition.rb provides EventDefinition class containing `attr_reader :name, :params`"
    verdict: pass
    evidence: "lib/track_relay/event_definition.rb (commit 620d09b)"
  - criterion: "lib/track_relay/event_payload.rb provides EventPayload class containing `def validate!`"
    verdict: pass
    evidence: "lib/track_relay/event_payload.rb (commit fad1605)"
  - criterion: "lib/track_relay/errors.rb provides Error hierarchy containing ReservedKeyError"
    verdict: pass
    evidence: "lib/track_relay/errors.rb (commit 54a1701)"
  - criterion: "test/unit/catalog_test.rb provides DSL tests containing ReservedKeyError"
    verdict: pass
    evidence: "test/unit/dsl/event_builder_test.rb#test_event_with_reserved_param_key_raises_at_load_time (catalog DSL exercise covers ReservedKeyError; catalog_test.rb itself focuses on registry round-trips)"
  - criterion: "lib/track_relay/dsl/event_builder.rb links to lib/track_relay/event_definition.rb via build_definition"
    verdict: pass
    evidence: "EventBuilder#event constructs EventDefinition.new (lib/track_relay/dsl/event_builder.rb line 41-45, commit 4579f57)"
  - criterion: "lib/track_relay/event_payload.rb links to lib/track_relay/event_definition.rb via definition reference"
    verdict: pass
    evidence: "EventPayload stores @definition and uses @definition.params in validate! (lib/track_relay/event_payload.rb, commit fad1605)"
  - criterion: "lib/track_relay/validators/catalog_validator.rb links to lib/track_relay/errors.rb via ReservedKeyError raise"
    verdict: pass
    evidence: "CatalogValidator.validate! raises ReservedKeyError on reserved-key collision (lib/track_relay/validators/catalog_validator.rb line 41-43, commit 635e15d)"
---

Phase 01 / Plan 02 ships the catalog DSL, EventDefinition + ParamSchema metadata, EventPayload runtime + validate! coercion, and GA4/reserved-key validators — pure-Ruby, 100 tests passing, standardrb clean.

## What Was Built

- Error hierarchy under `TrackRelay::Error` (5 subclasses) plus frozen `RESERVED_KEYS` and `GA4_RESERVED_NAMES` (38 entries) constants — commit 54a1701.
- `EventDefinition` immutable metadata class with nested `ParamSchema` (Data.define, Ruby 3.2+, all six validator slots: name/type/required/max/in/format/sanitize) — commit 620d09b.
- `Validators::Ga4Constraints` (event-name shape + length + reserved list, param-count cap at 25, param-name shape + length) and `Validators::CatalogValidator` (composes Ga4Constraints with reserved-key collision guard) — commit 635e15d.
- `DSL::ParamBuilder` (per-event DSL receiver: integer/string/float/boolean/datetime + user_property), `DSL::EventBuilder` (top-level catalog DSL: event + user_property, validates and registers), `Catalog` module (process-wide registry: register/lookup/defined?/all/clear!), and `TrackRelay.catalog(&block)` entry point — commit 4579f57.
- `EventPayload` runtime class with `validate!` (sanitize → required → coerce → max → in → format, then extras-rejection), strict boolean/datetime coercion, untyped variant via `EventPayload.untyped(name:, ...)`, and `to_h` for ActiveJob/JSON serialization — commit fad1605.

## Files Modified

- `lib/track_relay/errors.rb` -- created: `TrackRelay::Error` base + 5 subclasses (ReservedKeyError, Ga4ConstraintError, ValidationError, CatalogError, UnknownEventError).
- `lib/track_relay.rb` -- modified: added requires for new files, defined `RESERVED_KEYS` + `GA4_RESERVED_NAMES`, added `TrackRelay.catalog(&block)` entry point.
- `lib/track_relay/event_definition.rb` -- created: EventDefinition class + nested ParamSchema (Data.define).
- `lib/track_relay/validators/ga4_constraints.rb` -- created: GA4 naming + sizing validators.
- `lib/track_relay/validators/catalog_validator.rb` -- created: composes Ga4Constraints with reserved-key collision guard.
- `lib/track_relay/dsl/param_builder.rb` -- created: DSL receiver for `event ... do ... end` bodies.
- `lib/track_relay/dsl/event_builder.rb` -- created: top-level catalog DSL receiver; validates + registers each event.
- `lib/track_relay/catalog.rb` -- created: process-wide registry of definitions + user properties.
- `lib/track_relay/event_payload.rb` -- created: runtime payload with validate!, coercion, sanitize-before-validate, untyped variant, to_h serialization.
- `test/unit/event_definition_test.rb` -- created: 6 tests / 25 assertions.
- `test/unit/validators/ga4_constraints_test.rb` -- created: 22 tests / 26 assertions.
- `test/unit/validators/catalog_validator_test.rb` -- created: 9 tests / 16 assertions.
- `test/unit/dsl/param_builder_test.rb` -- created: 9 tests / 22 assertions.
- `test/unit/dsl/event_builder_test.rb` -- created: 9 tests / 16 assertions.
- `test/unit/catalog_test.rb` -- created: 8 tests / 15 assertions.
- `test/unit/event_payload_test.rb` -- created: 37 tests / 59 assertions.

## Deviations

None.
