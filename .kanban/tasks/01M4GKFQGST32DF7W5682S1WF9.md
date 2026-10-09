---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gqvnrekm32yxeyhfy4m1gq
  text: 'The `board` slug part of this task (item 2: a column, an actor, or a tag with the slug `board` gives an id that parses as a board URI) is done in ^5nrzsqh. The rule: no mutation makes a column, an actor, or a tag with the slug `board` (`INVALID_SLUG` / `INVALID_TAG_NAME`); replay still loads an old log with such a node; plan.md §3.2 has the bullet "The slug `board` is reserved". I removed that part from the description, its acceptance criterion ("Each id that the tool returns parses back to the same node"), and its test item. The title changed to match. The bare board key part stays here.'
  timestamp: 2026-10-09T16:27:37.614253+00:00
- actor: claude-code
  id: 01m4h3qkvry3b6cqgmqwhqh4f6
  text: |-
    Research done.
    - `BoardIndex.resolution(of:currentRoot:currentKey:)` compares the text from `boardKey(in:)` with `key.description` and with `copy.key.description`. A bare key goes through with no change. A URI key is already normalized by `NodeURI(parsing:)`.
    - `RefResolver.candidateRef(forKey:in:)`, case `.board`, compares the key with `boardKey`. `storedRef(for:ofType:.board)` and `anyLocalRef(for:)` (short form, `shortFormTypes`) both reach it. So one fix there covers the two paths.
    - `BoardKey.normalizedText(ofSegments:)` takes segments. A bare key is a text, so the fix adds `BoardKey.normalizedText(of:)`: it splits the text at `LocalRef.separator` and calls `normalizedText(ofSegments:)`. The case rule stays in one place.
    - Test fixtures: `NodeURITests.mixedCaseKey` is `DependencyMarkersTests.boardKey` with the host in mixed case. `BoardLocatorTests` uses `TwoCopies` and `resolve(_:in:index:)`.
  timestamp: 2026-10-09T19:55:07.512508+00:00
- actor: claude-code
  id: 01m4h3v5tz1nrfa0nd8wqb660w
  text: |-
    Implementation landed (TDD: the 4 new test cases failed first, then passed).
    - `BoardKey.normalizedText(of:)` (new): splits a bare key at `LocalRef.separator` and calls `normalizedText(ofSegments:)`. It adds no second case rule.
    - `BoardIndex.boardKey(in:)` gives the normalized key for a bare key. Both compares in `resolution(of:currentRoot:currentKey:)` (current key and copy keys) use it.
    - `RefResolver.candidateRef(forKey:in:)`, case `.board`, normalizes the key before it compares with `boardKey`. This covers `storedRef(... ofType: .board)` and `anyLocalRef(for:)`.
    - Choice: only the host segment ignores case. The owner and repo segments keep their case (plan.md §3.2: "The path keeps its case").
    - A repo directory name (`copy(named:)`) and a path ref still use the text as the caller wrote it.
    - Tests: `BoardLocatorTests.mixedCaseHostKeyResolves` (2 cases: current key and related key). `RefResolverTests.boardResolves` has a new argument `NodeURITests.mixedCaseKey`. `RefResolverTests.mixedCaseBoardKeyResolvesWithNoType` is new. The new helper `RefResolverTests.resolver(of:)` is now also used by `resolve`.
  timestamp: 2026-10-09T19:57:04.223625+00:00
- actor: claude-code
  id: 01m4h3v7xkd8syxp14gbq73z9b
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/Identity/BoardKey.swift, Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift, Sources/FoundationModelsKanban/Identity/RefResolver.swift, Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift, Tests/FoundationModelsKanbanTests/Identity/RefResolverTests.swift. `swift test`: 1100 tests in 80 suites passed, 0 failed. The only build warning is the accepted SwiftPM "missing creator for mutated node" warning.
    - next: /review
  timestamp: 2026-10-09T19:57:06.355999+00:00
position_column: doing
position_ordinal: '80'
title: Bare board key ignores host case
---
## What
A gap that ^5nrzsqh found. It is out of the scope of that task.

A bare board key that is not a URI is still compared with case. `CrossRepo/BoardLocator.swift` (`resolution(of:currentRoot:currentKey:)`, `boardKey(in:)`) compares the `board:` input text with `key.description`, and `Identity/RefResolver.swift` (`candidateRef(forKey:in:)`, case `.board`) compares a board short form with `boardKey`. Thus `board: "GitHub.com/o/r"` does not find the board `github.com/o/r`. plan.md §3.2 now says that the host part of a key ignores case. Fix: normalize the text with `BoardKey.normalizedText(ofSegments:)` before each compare.

## Acceptance Criteria
- [x] `board: "GitHub.com/<owner>/<repo>"` resolves to the board `github.com/<owner>/<repo>`.
- [x] The board short form with a mixed-case host resolves in `RefResolver`.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift`: a bare key with a mixed-case host.
- [x] `Tests/FoundationModelsKanbanTests/Identity/RefResolverTests.swift`: board short form with a mixed-case host.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.