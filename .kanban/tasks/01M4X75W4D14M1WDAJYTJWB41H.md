---
assignees:
- claude-code
position_column: todo
position_ordinal: 9d80
title: Accept the stored local ref form type/id in the public resolver
---
## What
divergence.md R18 (§11 bugs). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem: the public resolver does not accept the stored local form `<type>/<id>` (for example `task/01K6Z3…`, `column/todo`, `tag/bug`). The logs store each ref in this form (`LocalRef`), and the design shows it in a `dependsOn` example. Only the internal `patch` mutation parses it (`LocalRef(parsing:)`, S/Identity/LocalRef.swift:85,190). `RefResolver` treats each text that is not a `kanban://` URI as a short form (S/Identity/RefResolver.swift:213-216). For a task, `task/01K6…` is not a ULID form, so `ulidRef` finds nothing (:347-348). For a column, an actor, or a tag, the slug rule makes `column/todo` into `column-todo` (:341-346), which names no node. The result is `NOT_FOUND`.

Fix ("very forgiving"): in `RefResolver.target(of:)`, accept `<type>/<id>` as a ref in the default board (or the board of `board:`), the same as a URI with the key of that board. The `<id>` part takes each short form of that type (a full ULID, a short id, `^short`, a ULID prefix, a slug, or a name). A type that is not the expected type gives `NOT_FOUND`, the same as a URI of the wrong type. A `<type>/<id>` ref never reaches a different board.

## Acceptance Criteria
- [ ] `task/<ULID>`, `task/<short id>`, `column/todo`, `tag/bug`, and `actor/<slug>` resolve.
- [ ] `column/todo` where a task is expected gives `NOT_FOUND`.
- [ ] `node(id: "task/<ULID>")` gives the task.
- [ ] `addTask(input: {dependsOn: ["task/<ULID>"]})` works.

## Tests
- [ ] The cases above, each as a test.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.