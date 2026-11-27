---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m8ekwr8p431kbc838dh5ve40
  text: |-
    Research done.
    - `BodyLines` does not skip fenced code, and `TaskProgress` counts each checklist line, also in a fence. The new parser keeps this rule, so that `progress` and the mutation agree.
    - Each mutation field of the schema is nullable (`updateTask(...): Task`, `tagTask(...): Task`), so that an error gives `null` for that field only. The new field follows this rule, not the `Task!` of the card. divergence.md records this.
    - The task mutations that name a task by `id` have no `board` field. `renameTag` has one: `MutationBoard.holding(id, orNamed: board)`. The new input uses this form: a short ref resolves in the named board, and a full URI names its own board.
    - The write path: `KanbanContext.changeTask(named:on:_:)` and `TaskWrite` in TaskMutations.swift are fileprivate/private now. The plan is to make them internal and call them from a new file `ChecklistItemMutation.swift`, with `TaskChange(values: [:], body: .changed(newBody), edges: [:])` and `WorkingCopy.write`. An unchanged body gives an empty patch, and `WorkingCopy.apply` keeps no event for it.
    - New schema parts touch: the golden SDL `Tests/Fixtures/kanban.graphql`, `KanbanFieldAliases` (input aliases), `NameMatcherTests.mutations`, `KanbanErrorTests.codes`, `EndpointConventionTests.warningCodes`.
  timestamp: 2026-11-27T13:42:37.078006+00:00
- actor: claude-code
  id: 01m8en813btyf7k1jbwpzyx8pq
  text: |-
    Implementation landed. All 6 subtasks are checked.
    - New: `Derived/ChecklistItem.swift` (the parser and the line edit; `TaskProgress` uses it), `Derived/ChecklistItemMatch.swift` (the forgiving match), `GraphQL/ChecklistItemMutation.swift` (the input, the resolver, the schema). The new errors are `KanbanError.checklistItemNotFound` (`NOT_FOUND`) and `KanbanError.ambiguousChecklistItem` (`AMBIGUOUS_ITEM`). The new warning is `NOTHING_TO_CHANGE`.
    - `KanbanContext.changeTask(named:on:_:)` and `TaskWrite` in TaskMutations.swift are now internal, so the new resolver uses the same write path as `updateTask`.
    - Aliases: `checkSubtask`, `updateSubtask`, `checkItem` name the mutation. `subtask`, `done`, `newText` and others name the input fields.
    - What did not work at first: the mutation tests passed `try TemporaryDirectory()` as a temporary value, so the directory was removed before the call. The tests now keep the directory alive.
    - Open point (not done): `item` is `String!`, the same as the card says. Thus an Int literal `item: 2` does not pass GraphQL validation. The agent must send `item: "2"`. A change to `ID!` would accept both forms. A person must decide this.
    - Divergences from the card: the field is `Task` (nullable), not `Task!`, because each mutation field of the schema is nullable. divergence.md §30 records this.
  timestamp: 2026-11-27T14:06:15.147652+00:00
- actor: claude-code
  id: 01m8en83h0nwppb06cf2fkc8qs
  text: |-
    ### implement — changed
    - evidence: `swift test`: 2029 tests in 175 suites passed, 0 failures, no warnings except the accepted mlx Metal ones. 18 files: 6 new (3 Sources, 3 Tests), 12 changed (Documentation/kanban/SKILL.md, divergence.md, Progress.swift, Errors.swift, FieldAliases.swift, Schema.swift, SchemaDescription+Mutations.swift, TaskMutations.swift, Tests/Fixtures/kanban.graphql, AliasTableTests.swift, EndpointConventionTests.swift, KanbanErrorTests.swift).
    - next: /review
  timestamp: 2026-11-27T14:06:17.632461+00:00
- actor: claude-code
  id: 01m8enjhy79p856yhct4ha6gjj
  text: |-
    `item` is now `ID!` (coordinator decision).
    - The type change alone did not work: the `ID` scalar (`NodeID`, `GraphQL/Scalars.swift`) decoded text only, so the new test with `item: 1` failed. `NodeID.init(from:)` now reads text first, and an integer when the value is not text. Thus each `ID` input of the schema accepts an integer, as the GraphQL `ID` input rule gives. A text id with leading zeros, such as `0123456`, stays the same text, because text is read first.
    - New test: `ChecklistItemMutationTests.intLiteralIndexNamesItem` (RED, then GREEN).
    - Updated: the `item` schema description, the golden SDL (`item: ID!`), divergence.md §30, SKILL.md step 4, and the card text.

    ### implement — changed
    - evidence: `swift test`: 2030 tests in 175 suites passed, 0 failures, no warnings except the accepted mlx Metal ones. This pass: ChecklistItemMutation.swift, Scalars.swift, SchemaDescription+Mutations.swift, Tests/Fixtures/kanban.graphql, ChecklistItemMutationTests.swift, divergence.md, Documentation/kanban/SKILL.md.
    - next: /review
  timestamp: 2026-11-27T14:12:00.071949+00:00
- actor: claude-code
  id: 01m8enpp2hqkwhj1vk3wtj40rc
  text: |-
    ### test — stuck
    - evidence: `swift test` — 2030 tests in 175 suites passed, 0 failed, 0 skipped. The build has no compiler warning. The log has only expected runtime log lines from tests.
    - evidence: `swiftlint lint` — 0 violations. It prints only this note: configuration version 0.48.0 and tool version 0.65.1 differ. The project has no `.swiftlint.yml`.
    - blocker: `swift format lint -s -r Sources Tests` — 78957 errors in all Swift files of Sources and Tests, not only in the files of this task. Example: `Sources/FoundationModelsKanban/Snapshot/BoardSnapshot.swift:5:1: error: [Indentation] unindent by 2 spaces`. Also `[LineLength]` and `[AddLines]`.
    - cause: the project has no `.swift-format` file. The tool uses its defaults (2-space indent, 100-column lines). The whole project uses 4-space indent and longer lines. No file of this task causes the errors.
    - why stuck: a rule says not to write a `.swift-format` as a side effect, and not to override the configuration. A reformat of the whole project with the defaults would change about 250 files, and it would change the style of the project. A person must decide: add a `.swift-format` that matches the project style, or accept the default format.
    - next: a person adds or declines a `.swift-format`. Then run `swift format lint -s -r Sources Tests` again. No code change is needed for the tests.
  timestamp: 2026-11-27T14:14:15.377440+00:00
- actor: claude-code
  id: 01m8enqcwpam8pag54s9hr1myh
  text: |-
    ### test — green (orchestrator decision)
    - evidence: swift test — 2030 tests in 175 suites passed, 0 failed, 0 skipped, 0 compiler warnings; swiftlint — 0 violations.
    - The `swift format lint` errors (78957, all repo-wide Indentation, LineLength and AddLines from the tool defaults) are not a gate of this project. The project has no .swift-format file, and earlier tasks (for example ^4ADZWD88DR notes, 2026-10-07) record that only the idiom rules apply. The tester reported stuck only because the orchestrator asked for the full format lint.
    - next: /commit, then /review HEAD~1..HEAD
  timestamp: 2026-11-27T14:14:38.742429+00:00
- actor: claude-code
  id: 01m8ep0n6y6ktwq9p8xga1ynq7
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (abcba05): 0 findings, 0 confirmed, 2 refuted, 21 pairs attempted, 0 failed. No earlier Review Findings sections.
    - next: none. The task is in done.
  timestamp: 2026-11-27T14:19:42.174282+00:00
- actor: claude-code
  id: 01m8ep13hghsvbeydw6kr92dxg
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 18 files, then 7 files (item is ID!; the ID scalar accepts an integer)
    - test: green — swift test, 2030 passed in 175 suites; swiftlint 0
    - commit: abcba05
    - review: clean — 0 findings; task in done
  timestamp: 2026-11-27T14:19:56.848306+00:00
position_column: done
position_ordinal: ffd380
title: Add the updateChecklistItem mutation
---
## Goal

Add the GraphQL mutation `updateChecklistItem`. It sets the state of one checklist item in the body of a task, and it can also change the text of the item. Agents can then check off a subtask without sending the full body again.

## Why

Now, a caller must read the body, change `- [ ]` to `- [x]`, and send the full body with `updateTask` (Documentation/kanban/SKILL.md, step 4). This is slow, and an agent can make an error in the other text. A toggle is not safe, because a call that is sent again undoes itself. Thus the mutation sets a target state, as `tagTask`, `assignTask` and `completeTask` do.

## Contract

```graphql
updateChecklistItem(input: UpdateChecklistItemInput!): Task!

input UpdateChecklistItemInput {
  id: ID!            # the task, all ID forms that updateTask accepts
  item: ID!          # the item: a 0-based index (2 or "2") or the item text
  checked: Boolean   # no value: the state does not change
  text: String       # no value: the text does not change
  board: ...         # the same board field as the other task mutations
}
```

- Decision (2026-11-27): `item` is `ID!`, not `String!`, so that `item: 2` and `item: "2"` both work (very forgiving inputs). The `ID` scalar accepts an integer for this.
- The item lines and the rules are the same as in `TaskProgress` (`Sources/FoundationModelsKanban/Derived/Progress.swift`): leading whitespace, `- [ ]`, `- [x]`, `- [X]`. Fenced code is not counted, if `BodyLines` already skips it. Use the same line split (`BodyLines`) so that `progress` and this mutation always agree.
- Item match is forgiving (memory: very forgiving tool inputs). Use this order: an index in range, then the exact text, then the text with case and whitespace ignored, then one unique prefix or one unique substring. Give an error only when no item matches, or when two or more items match at the same step. The error names the items that matched, with their indexes.
- `checked: true` on a checked item does nothing and gives no error. The same applies to `false`. The result must not record an empty change.
- Keep the marker style: `[X]` stays `[X]` if the state does not change. A new check writes `[x]`. Keep the indent and all other lines byte for byte.
- Write the change through the same body-diff path as `updateTask` (`TaskMutations.swift`, `TaskChange` with `.changed(newBody)`). Thus undo, the change stream, tag markers and the timeline work with no new code.
- Give at least one of `checked` or `text`. If neither is set, give the task back with no change and add a warning, as other mutations do with an empty input.
- Add the schema descriptions in `SchemaDescription+Mutations.swift`, in STE.
- Update `Documentation/kanban/SKILL.md`: step 4 uses `updateChecklistItem`. Remove or change the line "There is no subtask API".
- Record the new mutation in `divergence.md`, because Rust does not have it. Do not change `plan.md`.

## Subtasks

- [x] Add a checklist item parser next to `TaskProgress` that gives each item with its line index, its state and its text. Make `TaskProgress` use it.
- [x] Add the forgiving item matcher, with its errors.
- [x] Add `UpdateChecklistItemInput` and the resolver. Use the `updateTask` write path.
- [x] Add schema descriptions, and update the SDL signature tests.
- [x] Tests: check, uncheck, the same state again (no change), a text change, a match by index, by exact text, by case-insensitive text and by prefix, an ambiguous text, no match, an index out of range, `[X]` kept, indented items, undo of the change.
- [x] Update SKILL.md and divergence.md.
- [x] Change `item` to `ID!`, and add a test that sends an int literal.
#checklist #graphql-endpoint