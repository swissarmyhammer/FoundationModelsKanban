---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5r3w51d26175mtd6qhp4rak
  text: |-
    Research done.
    - Extras: `GraphQLError.coded(as:)` (CodedError.swift) is the path of each resolver error (`codedAsResultError`, via NameRewrite). `CodedErrorJSON` is the path of a call that fails as a whole: `KanbanGraph.respond` and `startSubscription` give `failure.responseJSON(...)`. So both paths must carry the new keys.
    - `Map` (GraphQL) is Codable, Equatable and Hashable. It encodes a number as its Double value. `Number` equality compares NSNumber values, so an Int and a Double of the same value are equal.
    - Kanban: only `.filterModelMissing(filterError:)` holds a filter error. Its filter error is always an `.invalidFilter` (the parse error, or the first name that names nothing). `ChangeFilter` (subscriptions) also gives `.invalidFilter`, so it gets the span with no more change.
    - Plan: `CodedError.extensionFields: [String: Map]` with a default of `[:]`; a shared `extensionsObject` merges the fields and `code`, and `code` wins. `CodedErrorJSON.Extensions` gets `fields` with a custom Codable that writes the fields beside `code`.
  timestamp: 2026-10-24T23:27:59.021712+00:00
- actor: claude-code
  id: 01m5r44bzeqbvzqjme265wt520
  text: |-
    Extras part landed and pushed: 59b1dc974bb464ae55cedb52f8108ff98a541d3e on origin/main (feat(graphql): let a CodedError put more keys into extensions beside code). `CodedError.extensionFields` (default `[:]`), merged by `coded(as:)`; `CodedErrorJSON.Extensions` has `fields` with a custom Codable; `code` always wins. 4 new Extras tests; full Extras `swift test`: 1565 tests passed, only the "missing creator" warning.
    Note: the first push was rejected because origin/main had 6 new commits (one is `refactor(pool)!`, a breaking change of the model pool). I rebased on them and ran the full suite again before the push. The new pin brings these pool changes into FoundationModelsKanban too.
  timestamp: 2026-10-24T23:32:28.270902+00:00
- actor: claude-code
  id: 01m5r4mfg31xht567np0sbt1mv
  text: |-
    Implementation landed in FoundationModelsKanban (not committed, as asked).
    - Pin: `swift package update foundationmodelsextras` failed again on swift-case-paths ("exhausted attempts to resolve"). I changed the pin in Package.resolved by hand to 59b1dc974bb464ae55cedb52f8108ff98a541d3e. `swift package resolve` then passed, and the checkout is at that commit. The new pin also brings the `refactor(pool)!` commits of Extras; FoundationModelsKanban builds and passes with them.
    - `KanbanError.extensionFields` (Errors.swift): `.invalidFilter` gives `start`/`end` (`spanStartKey`, `spanEndKey`); `.filterModelMissing` gives the fields of its filter error; each other case gives `[:]` in an exhaustive switch. No other case holds a filter error. Subscriptions also get the keys, because their errors go through `codedAsResultError` → `coded(as:)`.
    - Discovery: `translateFilter` is non-null, so a `FILTER_MODEL_MISSING` response has no `data` key at all: `{"errors":[...]}`.
    - Discovery: `KanbanArgumentsTests.jsonLiteral(of:)` escapes `/`, but the responses do not escape it. So the full-response tests use filters whose messages have no `/` (`#bug &&`, `#🐛 &&`, `%todoo`); the English text detail holds `kanban://`.
    - No schema description of `INVALID_FILTER` exists, so the schema text did not change. divergence.md §24 records the keys, the unit, and the exclusive end. plan.md is not changed.

    ### implement — changed
    - evidence: Extras 59b1dc974bb464ae55cedb52f8108ff98a541d3e pushed to origin/main; Extras `swift test` 1565 passed; Kanban `swift test` 1879 tests in 163 suites passed, only the "missing creator" warning. Files: Package.resolved, Sources/FoundationModelsKanban/GraphQL/Errors.swift, Tests/FoundationModelsKanbanTests/GraphQL/KanbanErrorTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/ErrorCoverageTests.swift, Tests/FoundationModelsKanbanTests/Filter/TranslateFilterTests.swift, divergence.md
    - next: /review
  timestamp: 2026-10-24T23:41:16.163499+00:00
- actor: claude-code
  id: 01m5r4wq4asb40qrbr1jd533em
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (1d9174f). 0 findings, 0 confirmed, 0 refuted. 7 pairs attempted, 0 failed. No validator matched Package.resolved, IntegrationTests/Package.resolved, and divergence.md. The .reviewignore rule excluded the .kanban files.
    - next: none. The task moved to done.
  timestamp: 2026-10-24T23:45:46.122730+00:00
- actor: claude-code
  id: 01m5r4x5p44veh4cr0tv23xwb9
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — FoundationModelsExtras 59b1dc9 (pushed); Errors.swift, 3 test files, divergence.md §24, both Package.resolved pins
    - test: green — swift test, 1879 passed in 163 suites, 0 failed, 0 skipped; IntegrationTests build complete
    - commit: 1d9174f
    - review: clean — 0 findings
  timestamp: 2026-10-24T23:46:01.028562+00:00
position_column: done
position_ordinal: ffc380
title: Put the span of an INVALID_FILTER error in extensions
---
## Request

KanbanViewKit asks for this. Now, a `tasks(filter:)` call with a bad filter gives `INVALID_FILTER`, and the place of the error is only in the message text (`at N..M: …`). The kit filter field parses that text to underline the error. The error must also carry the span as numbers in `extensions`, so that the kit can stop parsing the message.

Expected `extensions`: `{ "code": "INVALID_FILTER", "start": N, "end": M }`. The message text does not change.

## Unit of the span

- `start` and `end` count Swift `Character`s (extended grapheme clusters) from the start of the filter text. This is the unit of `KanbanError.invalidFilter(position: Range<Int>)` and of the message now (`FilterSyntaxError.kanbanError(in:)`, `Filter/FilterSyntaxError.swift:99`).
- `end` is exclusive. The span is the half-open range `start..<end`.
- Write the unit and the exclusive end in the doc comments, in the schema description of the error if one exists, and in divergence.md.

## Design

The engine cannot do this alone. `CodedError` (FoundationModelsExtras, `Sources/FoundationModelsExtras/GraphQL/CodedError.swift`) has only `code` and `message`, and `GraphQLError.coded(as:)` puts only `code` into `extensions`.

- [x] FoundationModelsExtras (`../FoundationModelsExtras`): add a requirement to `CodedError` for more `extensions` keys of an error (for example `var extensionFields: [String: Map] { get }`). Give it a default implementation that returns no key, so that each current error does not change. Merge the keys in `coded(as:)`. `code` must always win over a key with the same name. Make `CodedErrorJSON` carry the same keys, or record why it does not need them. Add tests in FoundationModelsExtras. Commit and push FoundationModelsExtras to its main.
- [x] Update the FoundationModelsExtras pin in `Package.resolved` to the new commit. If `swift package update` fails (it failed on swift-case-paths before), change the pin by hand, as for ^5yygn91.
- [x] FoundationModelsKanban: in `KanbanError` (`GraphQL/Errors.swift`), give `start` and `end` for `.invalidFilter`. Name the keys with constants. `FILTER_MODEL_MISSING` holds an `INVALID_FILTER` error of the text (`filterModelMissing(filterError:)`), so give it the same span keys. Look at each other case that holds a filter error, and do the same where it applies.
- [x] Tests in FoundationModelsKanban: a `tasks(filter:)` call with a bad filter gives the full error JSON with `code`, `start`, and `end`. Add a filter with a character that is more than one UTF-16 unit (for example an emoji before the error), to show that the unit is characters. Add a test for the `FILTER_MODEL_MISSING` span. Compare full responses.
- [x] divergence.md: record the new `extensions` keys, the unit, and the exclusive end. Do not edit plan.md.

## Acceptance

- `INVALID_FILTER` errors have `extensions.start` and `extensions.end` as numbers. The message text is the same as before.
- Errors with no span do not change.
- The full test suites of both packages are green, with no new warnings.
#kanbanviewkit