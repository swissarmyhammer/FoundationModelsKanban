---
comments:
- actor: wballard
  id: 01m4b79qgs67882dsgf7510hv0
  text: |-
    Research done.
    - Multitool uses `https://github.com/yaslab/ULID.swift.git` from "1.3.1", product `ULID`. Added to Package.swift for the library target and the test target.
    - ULID.swift 1.3.1 has `ULID(timestamp:generator:)` with a `RandomNumberGenerator`. The fixed test source uses this init with a fixed date and a counter generator, so the sequence is deterministic and the last 35 bits (the short id) come from the counter.
    - Rust `short_id.rs` has 4 functions: `short_id`, `resolve_short_ref` (pure, over a list of ids), `find_short_id_collisions`, `mint_unique_short_id`. All 4 are ported, so that the RefResolver task (^cd36vb0) can use the pure resolve over a list of ULID strings.
    - The functions work over ULID text (`String`), as Rust works over `TaskId` text. Some Rust cases use 27-character and lowercase ids, which `ULID(ulidString:)` does not keep.
  timestamp: 2026-10-07T13:02:00.217279+00:00
- actor: wballard
  id: 01m4b7dd0dammmkkrg1jsv9k5v
  text: |-
    ### implement — changed
    - evidence: Package.swift (ULID.swift 1.3.1, product `ULID`, library and test targets), Package.resolved, Sources/FoundationModelsKanban/Identity/ShortID.swift, Sources/FoundationModelsKanban/Identity/ULIDSource.swift, Tests/FoundationModelsKanbanTests/Identity/ShortIDTests.swift. RED: `swift test --filter ShortIDTests` did not compile (no `ULIDSource`). GREEN: `swift test --filter ShortIDTests` 24 tests in 1 suite pass. Full `swift test`: 71 tests in 5 suites pass, 0 warnings.
    - API: `ShortID(ofULIDString:)`, `ShortID(of: ULID)`, `ShortID.searchKey(for:)` (parses `^short`), `ShortID.resolve(_:among:) -> ShortID.Resolution` (found / notFound / ambiguous), `ShortID.collisions(among:)`, `ULIDSource.makeULID(avoiding:)` (the mint rule), `SystemULIDSource`, `FixedULIDSource(at:)`, `SequenceNumberGenerator`.
    - Note for ^cd36vb0 (RefResolver): use `ShortID.resolve(_:among:)` for the ULID forms, so the resolve logic is not copied.
    - next: /review
  timestamp: 2026-10-07T13:04:00.525355+00:00
depends_on:
- 01M4B3V22A3PCQRESESTYBQ2FH
position_column: doing
position_ordinal: '80'
title: 'Identity: ULID minting and short ids'
---
## What
ULIDs and short ids. The basis is plan.md §3.2 (mint rule, short forms) and §11 (port `types/short_id.rs`).
- Add the ULID package that `../FoundationModelsMultitool` uses.
- `Sources/FoundationModelsKanban/Identity/ShortID.swift`: short id = last 7 characters of the ULID, in lowercase. Parse `^short`.
- `ULIDSource` protocol with a system source and a fixed test source (a fixed clock and sequence), so tests are deterministic.
- Mint rule: mint again until the short id is unique in a given set of existing short ids (same as Rust `mint_unique_short_id`).

## Acceptance Criteria
- [x] Short id of a known ULID equals the Rust result for the same ULID.
- [x] The mint rule never returns a short id that is in the given set.
- [x] The test ULID source gives the same sequence on each run.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Identity/ShortIDTests.swift`: port the cases of `../swissarmyhammer/crates/swissarmyhammer-kanban/src/types/short_id.rs`.
- [x] Run `swift test --filter ShortIDTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.