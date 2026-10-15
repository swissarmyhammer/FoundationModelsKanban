---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4z7dwkmghj9qjr053ct7wzp
  text: 'Research: `RefResolver.target(of:)` sorts a ref into `.shortForm`, `.sameBoard(key:type:)`, or `.otherBoard`. Plan: add a third `RefText` case for `<type>/<id>` when the text before the first `/` is a node type (`PatchNodeType(pathSegment:)`, case is ignored). It maps to `.sameBoard(key: <id>, type: <type>)`, so the existing `canName` check gives NOT_FOUND for a wrong type, and `candidateRef` applies each short form of the type to `<id>` (ULID, short id, `^short`, prefix, slug, name, tag rename redirect). `LocalRef(parsing:)` is not reused, because it needs a full ULID for a task. Board keys start with a host or `local`, so they never parse as a type. Bare `board` (no `/`) is NOT changed: `addColumn(id: "board")` must still give RESERVED_SLUG. `newNodeKey` also gets the form, so `addTag(id: "tag/bug")` gives `bug`.'
  timestamp: 2026-10-15T07:29:05.140999+00:00
- actor: claude-code
  id: 01m4z7s5kap9twzjpf661v5pet
  text: |-
    Implementation landed (TDD: RED seen for the expected reason, then GREEN).
    - `RefResolver.RefText` has a new case `localRef(type:key:)`. `localRefParts(of:)` splits at the first `/` when the text before it is a node type (case ignored). `target(of:)` maps it to `.sameBoard(key:type:)`, so `canName` gives NOT_FOUND for a wrong type, `candidateRef` gives each short form of the type, and `newNodeKey` gives the `<id>` part (`addTag(id: "tag/x")` makes tag `x`).
    - Not changed on purpose: bare `board` (no `/`) stays a short form, because `addColumn(id: "BOARD")` must still give RESERVED_SLUG (ReservedSlugTests). `board/<key>` works.
    - Tool description now names the stored form (`KanbanTool.storedLocalRefExample = "column/todo"`, and `task/^short`). The schema descriptions do not list ref forms (only "a short ref"), so they are not changed.
    - Discovery: task tag lists (`addTask`/`updateTask`/`tagTask` tags) do not use the resolver for non-URI text, so `tags: ["tag/bug"]` gives tag `tag-bug`. Recorded as new task ^jayb2bd (out of scope of this card).
    - `addTaskDependsOnLocalTask` is now parameterized over `LocalTaskRefForm` (URI, stored local ref) so the two forms share one body.
  timestamp: 2026-10-15T07:35:14.794866+00:00
- actor: claude-code
  id: 01m4z7s7tfhg1bzcgey7yad4cs
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsKanban/Identity/RefResolver.swift, Sources/FoundationModelsKanban/Tool/KanbanTool.swift, Tests/FoundationModelsKanbanTests/Identity/RefResolverTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/NodeQueryTests.swift, Tests/FoundationModelsKanbanTests/Mutations/AddUpdateTaskTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanToolTests.swift. `swift test`: 1382 tests in 109 suites passed, 0 failures; only the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-15T07:35:17.071772+00:00
position_column: doing
position_ordinal: '80'
title: Accept the stored local ref form type/id in the public resolver
---
## What
divergence.md R18 (§11 bugs). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem: the public resolver does not accept the stored local form `<type>/<id>` (for example `task/01K6Z3…`, `column/todo`, `tag/bug`). The logs store each ref in this form (`LocalRef`), and the design shows it in a `dependsOn` example. Only the internal `patch` mutation parses it (`LocalRef(parsing:)`, S/Identity/LocalRef.swift:85,190). `RefResolver` treats each text that is not a `kanban://` URI as a short form (S/Identity/RefResolver.swift:213-216). For a task, `task/01K6…` is not a ULID form, so `ulidRef` finds nothing (:347-348). For a column, an actor, or a tag, the slug rule makes `column/todo` into `column-todo` (:341-346), which names no node. The result is `NOT_FOUND`.

Fix ("very forgiving"): in `RefResolver.target(of:)`, accept `<type>/<id>` as a ref in the default board (or the board of `board:`), the same as a URI with the key of that board. The `<id>` part takes each short form of that type (a full ULID, a short id, `^short`, a ULID prefix, a slug, or a name). A type that is not the expected type gives `NOT_FOUND`, the same as a URI of the wrong type. A `<type>/<id>` ref never reaches a different board.

## Acceptance Criteria
- [x] `task/<ULID>`, `task/<short id>`, `column/todo`, `tag/bug`, and `actor/<slug>` resolve.
- [x] `column/todo` where a task is expected gives `NOT_FOUND`.
- [x] `node(id: "task/<ULID>")` gives the task.
- [x] `addTask(input: {dependsOn: ["task/<ULID>"]})` works.

## Tests
- [x] The cases above, each as a test.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.