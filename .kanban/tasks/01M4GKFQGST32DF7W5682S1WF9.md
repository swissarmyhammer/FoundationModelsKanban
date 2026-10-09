---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gqvnrekm32yxeyhfy4m1gq
  text: 'The `board` slug part of this task (item 2: a column, an actor, or a tag with the slug `board` gives an id that parses as a board URI) is done in ^5nrzsqh. The rule: no mutation makes a column, an actor, or a tag with the slug `board` (`INVALID_SLUG` / `INVALID_TAG_NAME`); replay still loads an old log with such a node; plan.md §3.2 has the bullet "The slug `board` is reserved". I removed that part from the description, its acceptance criterion ("Each id that the tool returns parses back to the same node"), and its test item. The title changed to match. The bare board key part stays here.'
  timestamp: 2026-10-09T16:27:37.614253+00:00
position_column: todo
position_ordinal: '9880'
title: Bare board key ignores host case
---
## What
A gap that ^5nrzsqh found. It is out of the scope of that task.

A bare board key that is not a URI is still compared with case. `CrossRepo/BoardLocator.swift` (`resolution(of:currentRoot:currentKey:)`, `boardKey(in:)`) compares the `board:` input text with `key.description`, and `Identity/RefResolver.swift` (`candidateRef(forKey:in:)`, case `.board`) compares a board short form with `boardKey`. Thus `board: "GitHub.com/o/r"` does not find the board `github.com/o/r`. plan.md §3.2 now says that the host part of a key ignores case. Fix: normalize the text with `BoardKey.normalizedText(ofSegments:)` before each compare.

## Acceptance Criteria
- [ ] `board: "GitHub.com/<owner>/<repo>"` resolves to the board `github.com/<owner>/<repo>`.
- [ ] The board short form with a mixed-case host resolves in `RefResolver`.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift`: a bare key with a mixed-case host.
- [ ] `Tests/FoundationModelsKanbanTests/Identity/RefResolverTests.swift`: board short form with a mixed-case host.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.