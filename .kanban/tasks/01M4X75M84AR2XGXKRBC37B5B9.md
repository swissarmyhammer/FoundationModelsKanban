---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4z4k2ceq3t68ej48tqk284c
  text: |-
    Research done.
    - No code reads `priority` now. The name rewrite gives a "no match" error for `priority` on AddTaskInput and UpdateTaskInput. The Q15 error was never built.
    - Plan: add one input field `priority` to AddTaskInput and UpdateTaskInput, with the aliases `prio` and `urgent` (FieldAliases byType). The field type is a new scalar `Priority`. Its parseLiteral and parseValue change each value (string, unquoted enum word, Bool, number) to its text. Reason: Graphiti decodes each input through MapDecoder, and MapDecoder can read a number as a Bool. Text avoids that risk.
    - A fixed table (case does not matter) gives the move: top, end, or no move. `true` is in the top row, so `urgent: true` moves to the top.
    - addTask: the move gives the ordinal of the new task (before the first task of the column, or the end). updateTask: the move gives the ordinal in the new column (when `column` is given) or in the column where the task shows now. The move is in the same patch as the add or the update.
    - Each priority value gives one warning (code PRIORITY_IS_POSITION) in extensions.warnings through TaskWrite.warnings.
    - Tests: new suite Tests/FoundationModelsKanbanTests/Mutations/PriorityInputTests.swift on temporary fixture repos (ColumnActorTests.makeFixtureGraph), with the .watcherBudget trait.
  timestamp: 2026-10-15T06:39:29.166050+00:00
- actor: claude-code
  id: 01m4z4xkfmabmxxz8pstq2ee0j
  text: |-
    Implementation landed (TDD: the new suite failed first with "Field \"priority\" is not defined by type \"AddTaskInput\"", then passed).
    - New S/GraphQL/PriorityInput.swift: scalar `Priority` (PriorityValue keeps the text of a string, an unquoted word, a Bool, or a number), PriorityMove with the fixed table (lowercase lookup, so the case does not matter), the warning (code PRIORITY_IS_POSITION), Graph.ordinal(for:inColumn:excluding:) and Graph.displayColumn(of:).
    - TaskMutations.swift: `priority` input field on AddTaskInput and UpdateTaskInput. addTask: a top/end move gives the ordinal of the new task in the same patch (it wins over an explicit `ordinal`). updateTask: place(of:movingTo:by:...) puts the task at the top or end of the new column, or of the column where it shows now (ordinal only). The warning goes into TaskWrite.warnings after the dependency warnings.
    - FieldAliases.swift: `prio` and `urgent` are aliases of `priority` on both inputs. Scalars.swift registers the scalar. SchemaDescription.taskPriority describes the field.
    - Discovery: `urgent: true` works through the alias, because `true` is a row of the top move.
    - Tests: Tests/FoundationModelsKanbanTests/Mutations/PriorityInputTests.swift (16 table rows x updateTask and addTask, one-patch checks, column+priority, variable values Bool and number). Full `swift test`: 1371 tests in 109 suites passed; only the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-15T06:45:14.356163+00:00
- actor: claude-code
  id: 01m4z4xnx361hza7r2s38mwd9g
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsKanban/GraphQL/PriorityInput.swift (new), Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift, Sources/FoundationModelsKanban/GraphQL/Scalars.swift, Sources/FoundationModelsKanban/GraphQL/FieldAliases.swift, Sources/FoundationModelsKanban/GraphQL/SchemaDescription.swift, Tests/FoundationModelsKanbanTests/Mutations/PriorityInputTests.swift (new); `swift test` 1371 tests passed, 0 failures
    - next: /review
  timestamp: 2026-10-15T06:45:16.835549+00:00
- actor: claude-code
  id: 01m4z69e5hj6jxfeg8y39tpp40
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 6 files
    - test: green — swift test, 1371 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 2f695eb
    - review: findings — Sources/FoundationModelsKanban/GraphQL/PriorityInput.swift:62, Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift:133
  timestamp: 2026-10-15T07:09:10.705611+00:00
- actor: claude-code
  id: 01m4z6q2nzzq3g7pn5877hacja
  text: |-
    Review findings fixed (2 of 2).
    - Finding 1 (no_direct_standard_out_logs at PriorityInput.swift): the call was `print(ast:)`, the GraphQL AST printer. The swiftlint regex reads the identifier `print`, so a module prefix does not help. Now parseLiteral (it can throw now) gives a list, an object, or a null literal through `valueFromASTUntyped` and the compact JSON form of `Map.description`, for example `["high"]`. No `print`, `debugPrint`, `dump`, or `_printChanges` stays in PriorityInput.swift or TaskMutations.swift.
    - What did not work: the slice of `literal.loc` from the source body. The parse gives a list a location whose end is before its start (NameRewrite.Token.valueEnd says the same), and `prefix` with a negative length crashed the test process. Do not use `loc.end` for a list or an object.
    - Finding 2 (public-output-contract at TaskMutations.swift addTask): the user wants the call to be forgiving, so the call is not refused. The priority move still wins. `PriorityValue.warnings(of:overriding:)` adds a second warning, code ORDINAL_IGNORED: "The ordinal `X` was ignored: the priority value `high` moved the task to the top of its column. Give a priority value or an ordinal, not both." A value that makes no move (for example medium) keeps the ordinal and gives no second warning.
    - Tests (PriorityInputTests): addTaskHighWithOrdinalWarnsOrdinalIgnored (RED first: only one warning came back), addTaskMediumWithOrdinalKeepsOrdinal, and listLiteralMakesNoMove. The last two are guard tests for the behavior that did not change, so they passed before and after the change.
  timestamp: 2026-10-15T07:16:37.695953+00:00
- actor: claude-code
  id: 01m4z6q4s490v60nd8v4e4gays
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/GraphQL/PriorityInput.swift, Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift, Tests/FoundationModelsKanbanTests/Mutations/PriorityInputTests.swift; `swift test` 1374 tests in 109 suites passed, 0 failures; only the accepted SwiftPM "missing creator" warning; both Review Findings checked
    - next: /review
  timestamp: 2026-10-15T07:16:39.844879+00:00
- actor: claude-code
  id: 01m4z6ya6tnd1dde7rnn30fhny
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 3 files (2 findings fixed)
    - test: green — swift test, 1374 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 497599c
    - review: findings — Sources/FoundationModelsKanban/GraphQL/PriorityInput.swift:172
  timestamp: 2026-10-15T07:20:34.778302+00:00
- actor: claude-code
  id: 01m4z7336y00nc1ka2fqpj3y93
  text: |-
    Review finding fixed (reuse/reuse at PriorityInput.swift ordinalWarning).
    - New private builder `PriorityMove.warning(opening:for:advice:code:)` makes the one sentence shape "<opening> priority value `<text>` <effect> <advice>" and the ResponseWarning. `warning(for:)` and `ordinalWarning(ignoring:for:)` are now thin calls to it.
    - The tail of the ordinal warning is now the named constant `ordinalIgnoredAdvice`, the same as `warningAdvice`. No other ResponseWarning construction stays in PriorityInput.swift.
    - The message texts did not change. This is a refactor: the existing PriorityInputTests check both exact messages and both codes, and they pass.
  timestamp: 2026-10-15T07:23:11.454394+00:00
- actor: claude-code
  id: 01m4z734hh4z9hqa0ssvsvf2v6
  text: |-
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsKanban/GraphQL/PriorityInput.swift; `swift test --filter PriorityInputTests` 10 tests passed; full `swift test` 1374 tests in 109 suites passed, 0 failures; only the accepted SwiftPM "missing creator" warning; all Review Findings checked
    - next: /review
  timestamp: 2026-10-15T07:23:12.817261+00:00
- actor: claude-code
  id: 01m4z78e074tp189731h5pbh2y
  text: |-
    ### finish iteration 3 — clean
    - implement: changed — 1 file (1 finding fixed)
    - test: green — swift test, 1374 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 4977efa
    - review: clean — none
  timestamp: 2026-10-15T07:26:06.343325+00:00
depends_on:
- 01M4X6X6PS5P524DW45RBSSWN2
position_column: done
position_ordinal: f980
title: Move the task in its column for a priority input, with a warning
---
## What
divergence.md P2 and K15 (DECIDED; they replace Q15), and §11 "Q15 (replaced by P2 and K15)". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Priority comes from the task order in the column. There is no priority field. An agent can send `priority`, `prio`, or `urgent` in a task input (for example on `addTask` or `updateTask`).

Decided behavior: accept `priority`, `prio`, and `urgent` on task inputs. Use this fixed value table (case does not matter):
- `urgent`, `critical`, `high`, `P0`, `P1`, and `urgent: true` → move the task to the top of its column.
- `low`, `P3`, `P4` → move the task to the end of its column.
- `medium`, `normal`, `P2` → no move.
- A bare number (for example `1` or `5`), or any other value → no move.
- Each case gives a warning in `extensions.warnings` that says that the position in the column is the priority (use `moveTask` with `before`/`after`, or filter with `#HIGH`/`#MEDIUM`/`#LOW`).
- On `addTask`, the move applies to the new task in its column. The move is in the same transaction as the add or update.

## Acceptance Criteria
- [x] `addTask(input: {title: "x", priority: "high"})` puts the task at the top of its column, with a warning.
- [x] `updateTask(input: {id: ..., prio: "low"})` moves the task to the end, with a warning.
- [x] `priority: "medium"`, `"normal"`, `"P2"`, a bare number, and an unknown value make no move, with a warning.
- [x] `urgent: true` moves the task to the top.

## Tests
- [x] A test for each row of the table: `urgent`, `critical`, `high`, `P0`, `P1`, `urgent: true`, `low`, `P3`, `P4`, `medium`, `normal`, `P2`, a bare number (`1` and a large number), and an unknown value.
- [x] A test that each case gives a warning.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-15 01:48)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 6 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/PriorityInput.swift:62` `code-hygiene/disallowed-constructs-swift` — no_direct_standard_out_logs: Do not commit print(…), debugPrint(…), dump(…) or _printChanges(), which write to standard out in release. Log to a dedicated logging system, or silence one debug-only line with // swiftlint:disable:next no_direct_standard_out_logs and the reason after it.
- [x] `Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift:133` `completeness/public-output-contract` — In addTask, when the input has a priority that moves the task (for example high, which goes to the top) and also an explicit ordinal, the move wins and the explicit ordinal is dropped without any warning. The priority warning only describes the move, so the caller never learns that its ordinal was ignored. Either add a warning when both an explicit ordinal and a moving priority value are present, saying which one was used, or reject the combination as ambiguous. Add a test that sends priority high together with ordinal and asserts the chosen behaviour.

## Review Findings (2026-10-15 02:18)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/PriorityInput.swift:172` `reuse/reuse` — ordinalWarning builds a ResponseWarning from the same sentence shape as warning(for:) at line 158, with its own copy of the effect text and code wiring. A parameterized warning builder would keep one canonical message format, so a later wording change does not need two edits. Extend warning(for:) with an optional ordinal parameter, or add one private builder that takes the message tail and the code. Keep the two public entry points as thin calls to it.
