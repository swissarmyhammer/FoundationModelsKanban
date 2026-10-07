---
comments:
- actor: wballard
  id: 01m4bnqbjxeha22s036hp30j6n
  text: |-
    Research done.
    - `PublicSchema` + `API.respond` (GraphQL/Schema.swift) run a document against a `KanbanContext(store: BoardStore, clock:)`. `respond` keeps the selection key order and does not catch the `GraphQLError` that `parse` throws for a syntax error (GraphQLSwift `graphql()` rethrows it). `execute` must catch it, so that a GraphQL error never throws.
    - `GraphQLJSONEncoder.OutputFormatting` has `.sortedKeys`.
    - `BoardLoader(reading: EventLog(repositoryAt:)).load()` gives an empty `Graph` for a repo with no `.kanban/`. `BoardObject(in:)` throws NOT_FOUND when the graph has no board node, so the empty-repo case needs an in-memory board node with the repo directory name.
    - `BoardKey.read(fromRepoAt:)` runs git; the tests inject a fake key reader.
    - Plan: `KanbanGraph` actor in Tool/KanbanGraph.swift with a `SerialGate` actor (waiter queue of continuations). The concurrency test uses an observer hook (same pattern as `LoaderWorkerObserver`) whose async start suspends the first call, so that without the gate the second call would start before the first ends.
    - The `actor:` init parameter has no reader in this task (the session-actor task uses it), so the init names it `_`.
  timestamp: 2026-10-07T17:14:06.813329+00:00
- actor: wballard
  id: 01m4bnyypcn2mq80c7y9qrnjmy
  text: |-
    Implementation landed.
    - New `Sources/FoundationModelsKanban/Tool/KanbanGraph.swift`: `public actor KanbanGraph` (`init(root:actor:) throws`, `execute(query:variables:operationName:)`, `static var schemaSDL`), an internal init with `readingKeyWith:timedBy:reportingTo:` for tests, the internal `SerialGate` actor (a FIFO queue of continuations), and the internal `KanbanCallObserver` hook (same pattern as `LoaderWorkerObserver`).
    - `API.respond` (GraphQL/Schema.swift) now takes `operationName:` and `formattedWith:` (the engine passes `.sortedKeys`), and it catches the `GraphQLError` that a parse error throws, so a GraphQL error never throws. Existing callers keep the defaults.
    - The first call reads the key with the key reader and loads the board with `BoardLoader`. A graph with no board node gets an in-memory board with the repo directory name and the clock time (`Graph.withBoard(named:at:)`). Nothing is written. A failed load is not cached, so the next call tries again.
    - Discovery: `init(root:actor:)` throws because `PublicSchema()` throws. `schemaSDL` uses `preconditionFailure` when the Graphiti types are not valid (programmer error).
    - Proof that the gate test can fail: with the gate removed, the recorded order was [start, start, finish, finish]; with the gate it is [start, finish, start, finish].
  timestamp: 2026-10-07T17:18:15.756112+00:00
- actor: wballard
  id: 01m4bnz0kk430tpthcn2h1zykn
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsKanban/Tool/KanbanGraph.swift (new), Sources/FoundationModelsKanban/GraphQL/Schema.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift (new). `swift test --filter KanbanGraphTests`: 8 tests passed. `swift test`: 459 tests in 30 suites passed. periphery (`--retain-public`, tests built, native build system): no unused code.
    - next: /review
  timestamp: 2026-10-07T17:18:17.715076+00:00
depends_on:
- 01M4B3YQSXZCGCB08FVP8QCSF3
- 01M4B3XHRVFA2YDCJC76MAFQR5
- 01M4B3VKJ8W42AXVFVMH6WN5VQ
- 01M4B4A8735GAP57Q8ZVDP5HY2
position_column: doing
position_ordinal: '8180'
title: 'KanbanGraph: execute, serial gate, board load'
---
## What
The engine actor and the query path. The basis is plan.md §5.4 steps 1 to 3 and §7.2.
- `Sources/FoundationModelsKanban/Tool/KanbanGraph.swift`: `public actor KanbanGraph` with `init(root:actor:)`, `execute(query:variables:operationName:) async throws -> String` (response JSON with sorted keys), and `schemaSDL`. The `locator:` and `embedder:` parameters of plan.md §7.2 are added by the cross-repo and search tasks, with default values, so this init stays valid.
- Serial gate: an async queue so that calls in one process run one at a time (an actor alone does not do this).
- Load the current board with the parallel loader the first time that a call needs it, then keep the `Graph` in memory (the watcher comes in a later task). The board key is read from git with `BoardKey`.
- A query on a repo with no `.kanban/` returns an empty board with the repo directory name and writes nothing.
- The tool does not throw for a GraphQL error; it throws only for an I/O fault.

## Acceptance Criteria
- [x] A query on fixture logs returns the expected JSON through `execute`.
- [x] Two concurrent `execute` calls on one `KanbanGraph` run one at a time (a test records that the second starts after the first ends).
- [x] A query on an empty repo writes no file.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift`: temporary repo directory, fixed clock and ULID source, fake `BoardKey`.
- [x] Run `swift test --filter KanbanGraphTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.