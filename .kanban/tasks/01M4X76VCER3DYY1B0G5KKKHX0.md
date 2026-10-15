---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4z90m5rk0mn7k1e3egpqqpd
  text: |-
    Research done.
    - Resolver: `KanbanResolver.updateTag` in Sources/FoundationModelsKanban/GraphQL/TagMutations.swift. It resolves the ref (the ref follows the rename redirect), then calls `work.updateNode` with name and color.
    - `WorkingCopy.renameTag(_:to:at:)` already does the merge, the redirect, and the cycle check. It returns the source when the new slug is the same. The reserved and virtual tag checks come from `addNode` (LocalRef.checkSlugIsNotReserved) when renameTag makes the new tag.
    - Swift renameTag changes no task body (plan.md 6.2): a `#bug` marker shows `defect` at read time through the redirect. So "the markers change" means: the task shows the new tag, and `#defect` matches. Tests check that.
    - Plan: in updateTag, when the new name gives a different slug, call `work.renameTag`, then apply color and body to the returned target. When the slug is the same, set the display name as now. On a merge, the target keeps its own name (same as renameTag).
    - The existing test `updateTagChangesFields` sets the name "Bug Fix" (slug bug-fix) on `bug`. After C4 that is a rename, so the test changes to a same-slug name.
  timestamp: 2026-10-15T07:56:47.672326+00:00
- actor: claude-code
  id: 01m4zb9yzqqq0e9jt8a4dc1n2r
  text: |-
    Implementation landed (TDD: RED showed only the updateTag cases fail; GREEN after the change).
    - Sources/FoundationModelsKanban/GraphQL/TagMutations.swift: the resolver now calls a new `WorkingCopy.updateTag(_:naming:color:body:at:)`. A name of a new slug calls `renameTag(_:to:at:)` (redirect, merge, reserved and virtual-tag errors, cycle check), then the color and the body go to the tag at the end of the rename. A name of the same slug sets only the display name. On a merge the target keeps its own name, the same as renameTag. Doc comments of MutationName.updateTag, UpdateTagInput.name, and the resolver are changed.
    - Tests: TagMutationTests runs the rename tests (new slug, merge, edge and marker on a task) on renameTag and on updateTag, with the GraphQL alias `rename:` so one response key fits both. New tests: same slug changes only the name; a new slug with color and body sets them on the target. `updateTagChangesFields` now uses the name "Bug", because "Bug Fix" is a rename after C4. ReservedSlugTests has a new Refusal case `.updateTagName`; VirtualTagNameTests has a row `(.updateTagName, "Done", .done)`.
    - Note: plan.md still says "updateTag does not change the slug" and "updateTag accepts the name Done/Board". plan.md is frozen; divergence.md C4/E1 is the decided behavior.

    ### implement — changed
    - evidence: `swift test` 1387 tests in 109 suites passed; only the accepted SwiftPM "missing creator" warning. Files: Sources/FoundationModelsKanban/GraphQL/TagMutations.swift, Tests/FoundationModelsKanbanTests/Mutations/TagMutationTests.swift, Tests/FoundationModelsKanbanTests/Mutations/ReservedSlugTests.swift, Tests/FoundationModelsKanbanTests/Mutations/VirtualTagNameTests.swift
    - next: /review
  timestamp: 2026-10-15T08:36:50.807271+00:00
- actor: claude-code
  id: 01m4zcnk6vjjdvn12c1hg0yrbc
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 4 files
    - test: green — swift test, 1387 passed, 0 failed, 0 skipped (first run had 60s time-limit starvation under load 70-97; rerun green); IntegrationTests 2 passed
    - commit: 0d9814d
    - review: clean — none
  timestamp: 2026-10-15T09:00:40.539118+00:00
position_column: done
position_ordinal: fc80
title: Make updateTag with a new slug do a renameTag
---
## What
divergence.md C4 (DECIDED: option a) and E1 (DECIDED), and §11 "C4". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem: `updateTag {id, name}` with a new name runs, but it changes only the display name. The slug stays. An agent that uses the Rust form thinks that it renamed the tag, but it did not.

Decided behavior:
- When `updateTag` gets a `name` whose slug is different from the current slug, it does the same as `renameTag` (a redirect from the old slug, and the `#old` markers change).
- When the slug is the same, `updateTag` changes only the display name (as now).
- E1 edge cases (do the same as `renameTag` in all cases):
  - The new slug already exists: merge the old tag into that tag (S/GraphQL/TagMutations.swift:250-253,267-268).
  - The new slug is reserved (`board`) or is a virtual tag name (for example `Done` gives `done`): give the same error as `renameTag` (`INVALID_TAG_NAME` or the virtual-tag error).
  - The same call also sets `color` or `body`: apply them to the tag at the end of the rename (the target tag).
  - Accepted result: a display name must give the same slug as the tag. For example, the tag `bug` cannot get the display name "Defect" without a rename.
- Change S/GraphQL/TagMutations.swift:113-128 (the resolver and its doc comment).

## Acceptance Criteria
- [x] `updateTag(input: {id: "bug", name: "defect"})` renames the tag to `defect`, makes a redirect from `bug`, and changes `#bug` markers to `#defect`.
- [x] `updateTag(input: {id: "bug", name: "Bug"})` changes only the display name.
- [x] A new slug that exists merges into that tag.
- [x] A reserved slug or a virtual tag name gives the same error as `renameTag`.
- [x] `color` in the same call goes to the target tag.

## Tests
- [x] A new slug makes a redirect and changes the markers.
- [x] The same slug changes only the display name.
- [x] The merge case, the reserved slug, the virtual tag name, and `color` in the same call.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.