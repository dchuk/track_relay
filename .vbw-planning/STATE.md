# State

**Project:** track_relay
**Milestone:** Core (MVP)

## Current Phase
Phase: 1 of 4 (Core Mvp)
Plans: 0/9
Progress: 0%
Status: ready

## Phase Status
- **Phase 1 (Core Mvp):** Planned
- **Phase 2 (Ga4 Subscribers):** Pending
- **Phase 3 (Ahoy Subscribers):** Pending
- **Phase 4 (Polish):** Pending

## Key Decisions
| Decision | Date | Rationale |
|----------|------|-----------|
| Ruby >= 3.2 floor; CI matrix Rails 7.1 / 7.2 / 8.0 | 2026-05-05 | Aligns with current LTS landscape; lets us use Ruby-3.2-only features (Data.define, etc.); no Rails upper bound — let SemVer break point us |
| Minitest for the gem's own test suite | 2026-05-05 | Rails-core convention; Combustion-based dummy app; user has tdd-cycle skill calibrated for Minitest+fixtures. Gem still ships matchers for both RSpec and Minitest for consumers |

## Todos
_(No todos)_

## Blockers
_(No blockers)_

## Activity Log
- 2026-05-05: Created Core (MVP) milestone (4 phases)
- 2026-05-05: Phase 01 discussion captured (Ruby/Rails matrix, failsafe boundary, test framework, untyped detection) — see `phases/01-core-mvp/01-CONTEXT.md`
- 2026-05-06: Phase 01 planning complete — Scout research (489 lines) + Lead decomposition into 9 plans / 33 tasks / 9 waves (fully serialized due to shared `lib/track_relay.rb` module growth)
