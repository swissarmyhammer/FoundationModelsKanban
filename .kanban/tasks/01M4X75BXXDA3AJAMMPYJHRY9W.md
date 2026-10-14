---
assignees:
- claude-code
position_column: todo
position_ordinal: 9b80
title: Split a JSON array sent as a string for list fields
---
## What
divergence.md Q13 (DECIDED: yes, as Rust does), N6, and §11 "Q13". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem (N6): Rust accepts `"[\"a\",\"b\"]"` for `tags`, `depends_on`, and `assignees`. In Swift, this text becomes one bad value: one bad tag name for `tags`, one ref that does not resolve for `dependsOn`, and one actor that does not exist for `assignees`.

Change: for each input field whose type is a list (at least `tags`, `dependsOn`, `assignees`, and the list arguments of `tagTask`/`untagTask`/`assignTask`), when the value is a single string that parses as a JSON array of strings, use the array. Apply this in the document text and in `variables`. A string that is not a JSON array keeps the current behavior (a single string for a list field becomes a list of one item, if that is the current rule).

## Acceptance Criteria
- [ ] `addTask(input: {title: "x", tags: "[\"bug\",\"ui\"]"})` gives the tags `bug` and `ui`.
- [ ] The same for `dependsOn` and `assignees`.
- [ ] The same in `variables`.
- [ ] `tags: "bug"` keeps the current behavior.

## Tests
- [ ] One test for each list field above, in the document text and in `variables`.
- [ ] A test for a string that is not JSON.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.