---
depends_on:
- 01M4B3V22A3PCQRESESTYBQ2FH
position_column: todo
position_ordinal: '8480'
title: 'Identity: ULID minting and short ids'
---
## What
ULIDs and short ids. The basis is plan.md §3.2 (mint rule, short forms) and §11 (port `types/short_id.rs`).
- Add the ULID package that `../FoundationModelsMultitool` uses.
- `Sources/FoundationModelsKanban/Identity/ShortID.swift`: short id = last 7 characters of the ULID, in lowercase. Parse `^short`.
- `ULIDSource` protocol with a system source and a fixed test source (a fixed clock and sequence), so tests are deterministic.
- Mint rule: mint again until the short id is unique in a given set of existing short ids (same as Rust `mint_unique_short_id`).

## Acceptance Criteria
- [ ] Short id of a known ULID equals the Rust result for the same ULID.
- [ ] The mint rule never returns a short id that is in the given set.
- [ ] The test ULID source gives the same sequence on each run.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Identity/ShortIDTests.swift`: port the cases of `../swissarmyhammer/crates/swissarmyhammer-kanban/src/types/short_id.rs`.
- [ ] Run `swift test --filter ShortIDTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.