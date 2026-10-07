---
depends_on:
- 01M4B3V22A3PCQRESESTYBQ2FH
- 01M4B4A8735GAP57Q8ZVDP5HY2
position_column: todo
position_ordinal: '8580'
title: Slugs, tag names, and auto color
---
## What
Name and slug rules. The basis is plan.md §3.2 (slug rule) and §6 (tag names, column and actor slugs).
- `Sources/FoundationModelsKanban/Tags/TagSlug.swift`: `normalizeSlug` (port of Rust `normalize_slug` in `../swissarmyhammer/crates/swissarmyhammer-kanban/src/tag_parser.rs`: ASCII alphanumeric kept, other runs become one `-`, no leading or trailing `-`), then lowercase.
- Tag name rule: trim, each run of spaces becomes `_`, remove NUL, refuse an empty name (`INVALID_TAG_NAME`).
- Column and actor slug: the same slug rule; an empty slug gives `INVALID_SLUG`.
- `Sources/FoundationModelsKanban/Tags/AutoColor.swift`: FNV-1a 32-bit hash of the slug, modulo the 16-color palette (copy the palette from Rust).

## Acceptance Criteria
- [ ] `Bug` and `bug` give the same slug.
- [ ] An empty name gives the correct error code for tags and for columns and actors.
- [ ] Auto color equals the Rust result for the same slugs.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Tags/TagSlugTests.swift` and `AutoColorTests.swift`, with cases ported from Rust.
- [ ] Run `swift test --filter TagSlugTests` and `--filter AutoColorTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.