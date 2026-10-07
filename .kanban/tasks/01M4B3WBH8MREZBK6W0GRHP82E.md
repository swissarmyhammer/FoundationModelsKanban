---
comments:
- actor: wballard
  id: 01m4barp39vk4vpka33ga72csz
  text: |-
    Research (swift-parsing 0.15.2, resolved from `from: "0.15.2"`):
    - `ParsingError` is `@usableFromInline internal`. Our code cannot read the failure position from it. Thus each rule throws our own `FilterSyntaxError`, which holds the range. The rule types use typed throws, so only our error can escape.
    - `Many` and `OneOf` catch each error of an element or a branch, and `OneOf` wraps them in `ParsingError.manyFailed`. A committed error (for example `$auth` after `&&`) is lost inside them. Thus the chain loops of `OrExpr` and `AndExpr` are in their own `parse` methods. Library parsers (`OneOf`, `Optionally`, `Not`, `Peek`, `Prefix`, `Consumed`, string literals) give the tokens: operators with a word boundary, and the body.
    - `Lazy` is deprecated on macOS (`deprecated: 9999`, "Lazily evaluate a parser by specifying it in a computed 'Parser.body' property, instead"), so it gives a compiler warning. It is also a `final class` with an unsynchronized `var lazyParser`, so it is not `Sendable` (the Swift 6 strict concurrency problem). Correction in our code: the recursion `"(" expr ")"` calls `OrExpr()` from `Atom.parse` when the input reaches a `(`. The sub-parser is made only at that time, which is the lazy evaluation that the library recommends.
    - The `CasePaths` trait (default on) pulls swift-syntax. We do not use it.
    - `Prefix` keeps a non-Sendable closure, so no parser value is kept in a `static let`.
  timestamp: 2026-10-07T14:02:36.009269+00:00
- actor: wballard
  id: 01m4bb7y18r4q52564ge4cnh49
  text: |-
    Implementation landed (TDD: 45 tests written first, RED with a stub, then GREEN on the first run).
    - `Package.swift`: `swift-parsing` from 0.15.2 with `traits: []`. The default `CasePaths` trait is off, so `Package.resolved` adds only `swift-parsing` (no swift-case-paths, swift-syntax, or swift-issue-reporting).
    - `Filter/FilterExpr.swift`: the AST `FilterExpr` (`.atom(FilterAtomKind, FilterValue)`, `.and`, `.or`, `.not`), `FilterValue` (`.name` or `.uri(NodeURI)`), `FilterAtomKind` (one table: sigil, node type, body noun, example), and `FilterExpr(parsing:) throws(KanbanError)`.
    - `Filter/FilterParser.swift`: namespace `FilterParser` with the rules `Filter`, `OrExpr`, `AndExpr`, `NotExpr`, `Atom`, `Body`, and the tokens `Operator` and `Keyword`. The rule types must be qualified as `FilterParser.Body()` inside other rules, because the `Parser` protocol has its own `Body` typealias that shadows a bare `Body`.
    - `Filter/FilterSyntaxError.swift`: the typed parse error with a `String.Index` range, its detail and example, and `kanbanError(in:)` to `INVALID_FILTER` with character offsets.
    - Deviation from the card text, as the card allows for a concurrency problem: `Lazy` is not used. It is deprecated on macOS (a warning) and is a non-Sendable class with an unsynchronized cache. `Atom.parse` calls `OrExpr()` only when it reads a `(`, which is the lazy recursion that the library recommends.
    - The parser also rejects a URL of the wrong type for its sigil, a board URL, and a comment URL (with the correct form in the message). The evaluator card ^d2dfh0r lists that check; it now happens at parse time.
    - Not done here (other cards): evaluation, `excludeDone` column detection, connection to queries.
  timestamp: 2026-10-07T14:10:55.656861+00:00
- actor: wballard
  id: 01m4bb84varqjcpcy0sbhra1bf
  text: |-
    ### implement — changed
    - evidence: 6 files — Package.swift, Package.resolved, Sources/FoundationModelsKanban/Filter/FilterExpr.swift, Sources/FoundationModelsKanban/Filter/FilterParser.swift, Sources/FoundationModelsKanban/Filter/FilterSyntaxError.swift, Tests/FoundationModelsKanbanTests/Filter/FilterParserTests.swift. `swift test --filter FilterParserTests`: 45 tests pass. `swift test`: 218 tests in 13 suites pass. Clean `swift build --build-tests` (new scratch path): 0 warnings.
    - next: /review
  timestamp: 2026-10-07T14:11:02.634588+00:00
depends_on:
- 01M4B3V22A3PCQRESESTYBQ2FH
- 01M4B4A8735GAP57Q8ZVDP5HY2
position_column: doing
position_ordinal: '80'
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
- [x] All parser tests of `../swissarmyhammer/crates/swissarmyhammer-filter-expr/src/lib.rs` pass, except the `$project` tests, which now expect an error.
- [x] `nothing` is not parsed as `not`.
- [x] Each URL form parses to the correct atom kind.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Filter/FilterParserTests.swift`: the ported tests, the URL forms, the error messages and positions.
- [x] Run `swift test --filter FilterParserTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.