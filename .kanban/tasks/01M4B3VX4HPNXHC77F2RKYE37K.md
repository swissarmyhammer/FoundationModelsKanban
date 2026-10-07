---
comments:
- actor: wballard
  id: 01m4b9jdppd6f9dp69w37cf115
  text: |-
    Research:
    - Rust `normalize_slug` (tag_parser.rs) keeps ASCII alphanumeric, changes each run of other characters to one `-`, and removes a leading and a trailing `-`. It keeps case. The Swift port adds lowercase (plan.md §3.2).
    - Rust `auto_color` (auto_color.rs): FNV-1a 32-bit (offset basis 0x811c9dc5, prime 0x01000193) over the UTF-8 bytes, modulo the 16-color palette. Expected colors in the Swift tests come from the FNV-1a definition (Python), and `fnv1a("a") == 0xe40c292c` agrees with the published FNV test vector.
    - The tag name rule (trim, spaces to `_`, remove NUL) is NOT in the Rust code. It comes only from plan.md §6. The Swift code removes NUL first, so that a NUL next to a space does not stop the collapse of a space run.
    - `KanbanError.invalidTagName(name:)` and `.invalidSlug(name:)` already exist in GraphQL/Errors.swift.
    - No `.swiftlint.yml` in the repo. The validators for Swift: no force unwrap in source, magic numbers (also in tests; only 0, 1, -1, 100 are free), docs, `let` in each bound case variable, labelled first arguments.
  timestamp: 2026-10-07T13:41:42.230357+00:00
- actor: wballard
  id: 01m4b9qc08r4qkfrcywfccz1f6
  text: |-
    Implementation landed (TDD: RED on missing types, then RED on two Rust-parity edge cases, then GREEN).
    - API: `Slug` (struct, `value`), `Slug.normalizedText(of:)` is the port of Rust `normalize_slug` plus lowercase. The card names it `normalizeSlug`; the Swift name follows the label rules and the type namespace. `Slug(columnOrActorName:) throws(KanbanError)` gives `INVALID_SLUG`. `TagName(normalizing:) throws(KanbanError)` gives `name` and `slug`, or `INVALID_TAG_NAME`. `Slug.autoColor`, `AutoColor.palette`, `AutoColor.fnv1aHash(of:)`.
    - Discovery: a first version iterated Swift `Character` values and lowercased before the ASCII check. That differs from Rust in two cases: `e` + combining accent (one Character, not ASCII, so Rust keeps `e` but Swift dropped it), and the Kelvin sign U+212A (lowercases to ASCII `k`; Rust drops it). The final code iterates Unicode scalars and checks ASCII before lowercase. Tests pin both cases.
    - Tag name: white space runs (Character.isWhitespace, so tabs and newlines too) become `_`. NUL is removed before the trim and the collapse.
    - The error carries the raw name as the caller wrote it.

    ### implement — changed
    - evidence: Sources/FoundationModelsKanban/Tags/TagSlug.swift, Sources/FoundationModelsKanban/Tags/AutoColor.swift, Tests/FoundationModelsKanbanTests/Tags/TagSlugTests.swift, Tests/FoundationModelsKanbanTests/Tags/AutoColorTests.swift; `swift test --filter "TagSlugTests|AutoColorTests"` 18 tests in 2 suites passed; `swift test` 153 tests in 11 suites passed, 0 warnings
    - next: review
  timestamp: 2026-10-07T13:44:24.328243+00:00
depends_on:
- 01M4B3V22A3PCQRESESTYBQ2FH
- 01M4B4A8735GAP57Q8ZVDP5HY2
position_column: doing
position_ordinal: '80'
title: Slugs, tag names, and auto color
---
## What
Name and slug rules. The basis is plan.md §3.2 (slug rule) and §6 (tag names, column and actor slugs).
- `Sources/FoundationModelsKanban/Tags/TagSlug.swift`: `normalizeSlug` (port of Rust `normalize_slug` in `../swissarmyhammer/crates/swissarmyhammer-kanban/src/tag_parser.rs`: ASCII alphanumeric kept, other runs become one `-`, no leading or trailing `-`), then lowercase.
- Tag name rule: trim, each run of spaces becomes `_`, remove NUL, refuse an empty name (`INVALID_TAG_NAME`).
- Column and actor slug: the same slug rule; an empty slug gives `INVALID_SLUG`.
- `Sources/FoundationModelsKanban/Tags/AutoColor.swift`: FNV-1a 32-bit hash of the slug, modulo the 16-color palette (copy the palette from Rust).

## Acceptance Criteria
- [x] `Bug` and `bug` give the same slug.
- [x] An empty name gives the correct error code for tags and for columns and actors.
- [x] Auto color equals the Rust result for the same slugs.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Tags/TagSlugTests.swift` and `AutoColorTests.swift`, with cases ported from Rust.
- [x] Run `swift test --filter TagSlugTests` and `--filter AutoColorTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.