---
depends_on:
- 01M4B3V22A3PCQRESESTYBQ2FH
- 01M4B4A8735GAP57Q8ZVDP5HY2
position_column: todo
position_ordinal: '8880'
title: Filter DSL parser with swift-parsing
---
## What
Parse the filter language to an AST. The basis is plan.md §6.3 and §12 items 22 and 24.
- Add `pointfreeco/swift-parsing` to `Package.swift`. If it has a Swift 6 strict concurrency problem, correct it in our code.
- `Sources/FoundationModelsKanban/Filter/FilterParser.swift`: one `Parser` type for each rule: `OrExpr`, `AndExpr`, `NotExpr`, `Atom`, `Body`. `Lazy` for `"(" expr ")"`.
- Atoms: `#tag`, `@user`, `^id`, `%column`, and `kanban://…` (bare, or as the body of `#`, `@`, `^`, `%`). `body = [^ \t\n\r#@^%$()&|!]+`.
- Keywords `and`/`AND`/`or`/`OR`/`not`/`NOT` need a word boundary. AND binds tighter than OR. Two atoms next to each other = AND.
- Errors: empty input, `$x`, an atom with no body, an unclosed group. The tool's own message with a `start..end` position and a correction (for `$auth`: use `#auth` or `%auth`). Do not show the library error text.

## Acceptance Criteria
- [ ] All parser tests of `../swissarmyhammer/crates/swissarmyhammer-filter-expr/src/lib.rs` pass, except the `$project` tests, which now expect an error.
- [ ] `nothing` is not parsed as `not`.
- [ ] Each URL form parses to the correct atom kind.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Filter/FilterParserTests.swift`: the ported tests, the URL forms, the error messages and positions.
- [ ] Run `swift test --filter FilterParserTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.