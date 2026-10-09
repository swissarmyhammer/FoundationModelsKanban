---
assignees:
- claude-code
position_column: todo
position_ordinal: '9880'
title: Bare board key ignores host case; a slug `board` gives a URI that parses as a board
---
## What
Two gaps that ^5nrzsqh found. They are out of the scope of that task.

1. A bare board key that is not a URI is still compared with case. `CrossRepo/BoardLocator.swift` (`resolution(of:currentRoot:currentKey:)`, `boardKey(in:)`) compares the `board:` input text with `key.description`, and `Identity/RefResolver.swift` (`candidateRef(forKey:in:)`, case `.board`) compares a board short form with `boardKey`. Thus `board: "GitHub.com/o/r"` does not find the board `github.com/o/r`. plan.md §3.2 now says that the host part of a key ignores case. Fix: normalize the text with `BoardKey.normalizedText(ofSegments:)` before each compare.
2. `NodeURI.init(parsing:)` now reads each URI whose last segment is `board` as the board URI (plan.md §3.2, "Board URI parse"). A column, an actor, or a tag with the slug `board` has the output id `kanban://<key>/column/board`, and that id parses as the board of the key `<key>/column`. Decide one rule and record it in plan.md §3.2: refuse the slug `board` for a column, an actor, and a tag (`INVALID_SLUG` / `INVALID_TAG_NAME`), or another rule.

## Acceptance Criteria
- [ ] `board: "GitHub.com/<owner>/<repo>"` resolves to the board `github.com/<owner>/<repo>`.
- [ ] The board short form with a mixed-case host resolves in `RefResolver`.
- [ ] Each id that the tool returns parses back to the same node.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift`: a bare key with a mixed-case host.
- [ ] `Tests/FoundationModelsKanbanTests/Identity/RefResolverTests.swift`: board short form with a mixed-case host.
- [ ] A test for the rule of the slug `board`.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.