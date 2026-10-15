---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4z36t5zeq625r756e54s107
  text: |-
    Picked up. Research:
    - The name rewrite in S/GraphQL/NameRewrite.swift is the correct place. `RewriteWalk.visitNamedValue` has the full input type of each argument and `input` field (list or not), and `RewriteWalk.rewrittenFields` has it for each key in the value of a variable. `RewriteWalk.rewritten(_:declaredIn:operationName:)` has the declared syntax type of each variable.
    - The list fields are `AddTaskInput`/`UpdateTaskInput` `tags` ([String]), `dependsOn` and `assignees` ([NodeID]), and `TagTaskInput.tags` (tagTask, untagTask). `AssignTaskInput.actor` is one value, not a list, so assignTask has no list argument.
    - A single string for a list field is a list of one item now: GraphQL input coercion does that. This stays for a string that is not a JSON array of strings.
    - Plan: a new helper `JSONListText` (S/GraphQL/JSONListText.swift) parses a text as a JSON array of strings. The walk replaces such a string literal at a list position with a GraphQL list literal (a text edit), and replaces such a `.string` value of a variable with `.array` (an `input` key of list type, or a variable whose declared type is a list).
    - GraphQL `getNullableType` is internal to the GraphQL module, so the helper unwraps `GraphQLNonNull` itself.
  timestamp: 2026-10-15T06:15:18.975029+00:00
- actor: claude-code
  id: 01m4z3j2emg5cq1am2x9gccwwk
  text: |-
    Implementation landed (TDD: RED run gave 23 issues for the missing split, GREEN run passes).
    - New S/GraphQL/JSONListText.swift: `items(of:)` (JSONDecoder into [String]), `splitting(_:)` for a `Map` value, `listLiteral(of:)` for a string literal, and `isList` for a schema input type and for a syntax type (both unwrap non-null).
    - S/GraphQL/NameRewrite.swift: `visitNamedValue` adds a text edit that replaces such a string literal at a list position with its GraphQL list literal (`RewriteWalk.listEdit(of:ofType:)`). `rewrittenFields` splits the value of an `input` key of list type. `rewritten(_:declaredIn:operationName:)` splits the value of a variable whose declared type is a list, also when the document does not read the variable.
    - The JSON text of the items is a valid GraphQL list literal (JSON string syntax is GraphQL string syntax), so no own escape code is necessary.
    - Discovery: tag names change a space to `_` (`"[bug, ui"` gives the tag name `[bug,_ui`), so the not-JSON test uses texts with no space (`[bug`, `[1,2]`).
    - assignTask has no list argument (`actor` is one value); the generic list-type check covers tagTask and untagTask `tags`, and each other list position.
    - Tests: Tests/FoundationModelsKanbanTests/GraphQL/ListInStringTests.swift (addTask tags/assignees/dependsOn x document text, input variable, list variable; one tag name; not-JSON text; tagTask and untagTask in each form). Full `swift test`: 1364 tests in 108 suites pass; only the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-15T06:21:27.892526+00:00
- actor: claude-code
  id: 01m4z3j3w3qmpr318ndvpyxzz0
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/GraphQL/JSONListText.swift (new), Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift, Tests/FoundationModelsKanbanTests/GraphQL/ListInStringTests.swift (new); `swift test` 1364 tests in 108 suites passed
    - next: /review
  timestamp: 2026-10-15T06:21:29.347720+00:00
position_column: doing
position_ordinal: '80'
title: Split a JSON array sent as a string for list fields
---
## What
divergence.md Q13 (DECIDED: yes, as Rust does), N6, and §11 "Q13". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem (N6): Rust accepts `"[\"a\",\"b\"]"` for `tags`, `depends_on`, and `assignees`. In Swift, this text becomes one bad value: one bad tag name for `tags`, one ref that does not resolve for `dependsOn`, and one actor that does not exist for `assignees`.

Change: for each input field whose type is a list (at least `tags`, `dependsOn`, `assignees`, and the list arguments of `tagTask`/`untagTask`/`assignTask`), when the value is a single string that parses as a JSON array of strings, use the array. Apply this in the document text and in `variables`. A string that is not a JSON array keeps the current behavior (a single string for a list field becomes a list of one item, if that is the current rule).

## Acceptance Criteria
- [x] `addTask(input: {title: "x", tags: "[\"bug\",\"ui\"]"})` gives the tags `bug` and `ui`.
- [x] The same for `dependsOn` and `assignees`.
- [x] The same in `variables`.
- [x] `tags: "bug"` keeps the current behavior.

## Tests
- [x] One test for each list field above, in the document text and in `variables`.
- [x] A test for a string that is not JSON.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.