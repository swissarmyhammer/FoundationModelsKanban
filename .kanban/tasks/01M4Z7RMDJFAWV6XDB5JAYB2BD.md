---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m51452p3xcmxfqhwv0fcjb21
  text: |-
    Research done.
    - `RefResolver.tag(named:includingTombstones:)` (S/GraphQL/TaskMutations.swift) is the one place that reads a tag text of a task tag list. `WorkingCopy.tagRefs` (addTask, updateTask, tagTask) and `WorkingCopy.untag` (untagTask) call it. Thus the change also applies to untagTask.
    - `RefResolver.RefText.localRefParts(of:)` (S/Identity/RefResolver.swift) already splits the stored local form `<type>/<id>` (type ignores case, white space trimmed). Plan: reuse it through a small internal static helper on RefResolver, so the tag list does not parse the form a second time.
    - `TagName(normalizing: "area/backend")` gives the name `area/backend` and the slug `area-backend`. This stays as it is.
    - `tag/` with no slug: report INVALID_TAG_NAME with the text as the caller wrote it.
    - Tests go in a new file Tests/FoundationModelsKanbanTests/Mutations/StoredTagRefTests.swift (temporary fixture repos only). It reuses `ReservedSlugTests.Refusal` cases `.addTaskTag`, `.updateTaskTag`, `.tagTask` for the three fields.
  timestamp: 2026-10-16T01:10:19.587948+00:00
- actor: claude-code
  id: 01m514jmhsegtx6q8r5jjxs965
  text: |-
    Implementation landed (TDD).
    - RED: new suite StoredTagRefTests failed for the expected reason: `tag/bug` gave the tag name `tag/bug` (slug `tag-bug`), `Tag/Bug` gave `Tag/Bug`, ` tag/ bug ` gave `tag/_bug`, untagTask with `tag/bug` did not remove `bug`, and `tag/` did not give INVALID_TAG_NAME. The `area/backend` case passed before and after (current behavior kept).
    - GREEN: `RefResolver.localID(inStoredLocalForm:ofType:)` (new, internal static, S/Identity/RefResolver.swift) reuses `RefText` to split `<type>/<id>`. `RefResolver.tag(named:includingTombstones:)` now calls the new private `tagName(of:)` (S/GraphQL/TaskMutations.swift): a `tag/<slug>` text gives `TagName(normalizing: slug)`; `tag/` with no slug gives INVALID_TAG_NAME with the text as written. Each other text is unchanged.
    - untagTask uses the same function, so it also accepts `tag/<slug>` (tested).
    - Doc comments of the tag inputs updated. divergence.md R18a records the decision.
    - Note: one pitfall in the test: a Swift raw string `#"...#\#(x)..."#` ends at `"#`; use `##"..."##` when the text holds `"#`.
  timestamp: 2026-10-16T01:17:43.865047+00:00
- actor: claude-code
  id: 01m514jpthnvpkvbxerxskbkxh
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/Identity/RefResolver.swift, Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift, Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift (doc only), divergence.md (R18a), Tests/FoundationModelsKanbanTests/Mutations/StoredTagRefTests.swift (new, 4 tests / 14 cases). `swift test --filter StoredTagRefTests`: 4 tests passed. `swift test`: 1548 tests in 123 suites passed, no new compiler warnings.
    - next: /review
  timestamp: 2026-10-16T01:17:46.193570+00:00
- actor: claude-code
  id: 01m514w6kn64bj6hhh3z92et0v
  text: |-
    ### test — green
    - evidence: swift build complete, 0 new warnings (only the allowed SwiftPM "missing creator" warning). swift test — 1548 tests in 123 suites passed, 0 failures, 0 skipped. IntegrationTests with the scratch path — 3 tests in 3 suites passed, 0 failures, 0 skipped. I ran each command one time. No time limit failed. No code change was needed.
    - next: review
  timestamp: 2026-10-16T01:22:57.269492+00:00
- actor: claude-code
  id: 01m514x08x7q2s5e1g88h2c5as
  text: |-
    ### commit — changed
    - evidence: one local commit, feat(tags): accept tag/<slug> in task tag lists (^jayb2bd). Files: Sources/FoundationModelsKanban/Identity/RefResolver.swift, Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift, Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift, divergence.md, Tests/FoundationModelsKanbanTests/Mutations/StoredTagRefTests.swift, and the changed .kanban/tasks files. I did not stage Package.resolved or .kanban/mcp.17281.log. I did not push. The sha is in the report of the caller.
    - next: none
  timestamp: 2026-10-16T01:23:23.549875+00:00
position_column: doing
position_ordinal: '80'
title: Accept the stored local form tag/<slug> in task tag lists
---
## What
Found during ^tjwb41h (divergence.md R18). `RefResolver` now accepts the stored local form `<type>/<id>`. But the tag list of `addTask`, `updateTask`, and `tagTask` does not use the resolver for a text that is not a URI: `TaskMutations.tag(named:includingTombstones:)` (S/GraphQL/TaskMutations.swift) sends each text that is not a `kanban://` URI to `TagName(normalizing:)`. Thus `tags: ["tag/bug"]` makes or names the tag `tag-bug`, not the tag `bug`.

Decide (very forgiving): treat a tag text that starts with `tag/` as the stored local form, so `tag/bug` names the tag `bug` (and makes it when the board has no such tag). A text such as `area/backend` stays a tag name. Record the decision in divergence.md.

## Acceptance Criteria
- [x] `addTask(input: {tags: ["tag/bug"]})` gives the task the tag `bug`.
- [x] `tagTask` and `updateTask` do the same.
- [x] A tag name with `/` that does not start with `tag/` keeps its current behavior.

## Tests
- [x] The cases above, each as a test, in temporary fixture folders (never the `.kanban/` of this repo).
- [x] `swift test` passes.