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
- actor: claude-code
  id: 01m4z3v94k14m9gy0jxjg8qdaz
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 3 files
    - test: green — swift test, 1364 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: c62db7f
    - review: findings — Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift:896, Tests/FoundationModelsKanbanTests/GraphQL/ListInStringTests.swift:115
  timestamp: 2026-10-15T06:26:29.651682+00:00
- actor: claude-code
  id: 01m4z423d3xeph6g57b93785xv
  text: |-
    Review findings fixed (2026-10-15 01:24 checklist, both items checked).
    - duplication (NameRewrite.swift): the rule "split the value when its type is a list" is now in one place, the private `JSONListText.splitting(_:isListPosition:)`. Two `splitting(_:ofType:)` overloads give it to the two type kinds: `(any GraphQLInputType)?` for an `input` key of a variable value, and `any GraphQL.Type` for the declared type of a variable. Each overload is a one-line forward. The two type kinds have no shared protocol, so one overload for each kind is necessary. The old `splitting(_:)` with no type is removed. Both sites in `RewriteWalk` (`rewritten(_:declaredIn:operationName:)` and `rewrittenFields`) now call `JSONListText.splitting(_:ofType:)`. `listEdit(of:ofType:)` is a different output (a text edit for the document text) and was already one helper.
    - reuse (ListInStringTests.swift): `stringLiteral(of:)` is deleted; both document-text call sites call `KanbanArgumentsTests.jsonLiteral(of:)`. `jsonArray(of:)` stays: it encodes a `[String]`, and no other test helper does that.
    - This is a refactor with no behavior change; the existing ListInStringTests cover it. Full `swift test`: 1364 tests in 108 suites pass; only the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-15T06:30:13.155419+00:00
- actor: claude-code
  id: 01m4z4256afdfkb2gv2jjwa6wb
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/GraphQL/JSONListText.swift, Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift, Tests/FoundationModelsKanbanTests/GraphQL/ListInStringTests.swift; `swift test` 1364 tests in 108 suites passed; 2/2 review findings checked
    - next: /review
  timestamp: 2026-10-15T06:30:14.986389+00:00
- actor: claude-code
  id: 01m4z49pv1fzjsw9y0xrswftwj
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 3 files (2 findings fixed)
    - test: green — swift test, 1364 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 485ce17
    - review: clean — none
  timestamp: 2026-10-15T06:34:22.433002+00:00
position_column: done
position_ordinal: f880
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

## Review Findings (2026-10-15 01:24)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift:896` `duplication/duplication` — The same two-step rule is written twice: a value is split when its type is a list, then the value is passed on. Line 896 repeats the logic of line 812 and differs only by the variable names. A later change to one copy can drift from the other. Add one helper, for example `JSONListText.splitting(_ value: Map, ofType type: (any GraphQLInputType)?) -> Map`, that returns `isList(type) ? splitting(value) : value`. Call it from both sites at lines 812 and 896.
- [x] `Tests/FoundationModelsKanbanTests/GraphQL/ListInStringTests.swift:115` `reuse/reuse` — The new helper `stringLiteral(of:)` reimplements an existing test helper. It JSON-encodes a string the same way, so the same capability now lives in two places. The existing helper is `static func jsonLiteral(of:)` in `KanbanArgumentsTests`, which is internal, not private, so this file can call it directly. Two copies can drift apart when one is fixed and the other is not. Delete `stringLiteral(of:)` from `ListInStringTests` and call `KanbanArgumentsTests.jsonLiteral(of:)` at the two call sites (lines 194 and 157 use it). If the two suites should not depend on each other, move the helper to a shared test support file and have both suites call it.
