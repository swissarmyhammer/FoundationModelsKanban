---
depends_on:
- 01M4B3WBH8MREZBK6W0GRHP82E
- 01M4B3Y4M87387J50EQCD36VB0
- 01M4B3YC73VSKE9VEP29E3CZNQ
position_column: todo
position_ordinal: '9580'
title: Filter evaluator
---
## What
Evaluate a parsed filter against one task. The basis is plan.md §6.3. The connection to the queries is in a separate task.
- `Sources/FoundationModelsKanban/Filter/FilterEvaluator.swift`: `#tag` (edges, markers, rename redirect, virtual tags), `@user` (actor slug or slug of the actor name), `^id` (the task itself or a `dependsOn` target, from edges and markers, by any short form or full URI), `%column` (column slug or slug of the column name). All matches ignore case.
- URL atoms resolve by key: the current key resolves in this board; a tag, actor, or column URL of a different board matches nothing; a `^` URL of a different board matches tasks that depend on that task. A URL of the wrong type, a board URL, or a comment URL gives `INVALID_FILTER`.
- A value that names nothing matches nothing (no error).
- A helper that reports whether a filter names a column (a `%` atom or a column URL); the `excludeDone` rule uses it.

## Acceptance Criteria
- [ ] The evaluator tests of `../swissarmyhammer/crates/swissarmyhammer-filter-expr/src/lib.rs` pass (with `$project` removed).
- [ ] Each URL form matches the same tasks as its short form.
- [ ] A URL of the wrong type gives `INVALID_FILTER` with the correct form in the message.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Filter/FilterEvaluatorTests.swift`, against fixture graphs.
- [ ] Run `swift test --filter FilterEvaluatorTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.