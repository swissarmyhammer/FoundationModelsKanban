# Divergences: Swift code, plan.md, and the Rust kanban

This file records the results of a review by many agents. The review compares three things:

- The Swift code in this repo.
- The design in `plan.md`.
- The Rust kanban feature in `../swissarmyhammer` (crate `swissarmyhammer-kanban` and the kanban MCP tool).

Status: all 7 reviews are complete.

## How to read this file

- **Kinds of divergence:**
  - **A** — the code does not agree with the plan.
  - **B** — the code does not agree with Rust, and the plan does not say that the change is intended.
  - **C** — the plan says that the change is intended. Section 9 lists these items briefly.
- **Path prefixes:**
  - `S/` = `Sources/FoundationModelsKanban/`
  - `T/` = `Tests/FoundationModelsKanbanTests/`
  - `R/` = `../swissarmyhammer/crates/swissarmyhammer-kanban/src/`
- **Questions:** Section 10 has the questions for you. Each question has a number (Q1, Q2, ...). Other sections point to these numbers.
- **Bugs:** Section 11 lists the bugs that need no decision.

---

## 1. Task dependencies

### 1.1 Dependencies between boards (the main new feature)

Rust has no dependencies between boards. In Rust, `depends_on` is a list of task ids in one board. `R/cross_board.rs::transfer_task` only moves or copies a task, and it copies `depends_on` with no change, so the ids then point to nothing.

The basic path in Swift works. A task can depend on a task in a different repo. The edge is stored as a full `kanban://` URI. The task stays blocked until the other task is done. A watcher on the other board keeps `ready` current. A cycle across two boards gives `DEPENDENCY_CYCLE`.

| # | Requirement in the plan | Status | Evidence |
|---|---|---|---|
| R1 | `dependsOn` can point to a task in any board (§3.1, §6.6) | Done. The input must be a full `kanban://` URI. There is no short form for a different board. | `S/GraphQL/TaskMutations.swift:198-200`, `S/Identity/RefResolver.swift:303-312` |
| R2 | An edge in the same board is a local ref. An edge to a different board is a full URI. | Done, tested | `T/CrossRepo/CrossRepoWriteTests.swift:443,453` |
| R3 | An unknown target counts as not done (§3.3 rule 4) | Done. In one board it is tested (`T/Derived/ReadinessTests.swift:89`). Across boards, only a board that is not found or not loaded is tested (`T/CrossRepo/CrossRepoReadTests.swift:156`). No test covers a missing task on a board that is found. | `S/Derived/Readiness.swift:148-149` |
| R4 | A tombstoned target is ignored (§3.3 rule 3) | Done. It is not tested across boards. | `S/Derived/Readiness.swift:207-213` |
| R5 | `blocks` is the reverse of `dependsOn`, and BLOCKING means "some live task depends on it" (§3.1, §6) | **Missing across boards.** Q1 removes this requirement. | `S/Derived/Readiness.swift:221-229` |
| R6 | `blockedBy` and `ready` across boards | Done, tested | `S/GraphQL/QueryResolvers.swift:512-536` |
| R7 | A cycle across boards gives `DEPENDENCY_CYCLE`. The commit locks each board that the check read. | Done, tested for 2 boards. A test for 3 or more boards is missing. | `S/Derived/DependencyWalk.swift`, `T/CrossRepo/CrossRepoCycleTests.swift` |
| R8 | A task URL in the body is a dependency, also across boards (§6.1) | Done. Only a unit test covers it. | `S/Derived/DependencyMarkers.swift:145-150` |
| R9 | Load a related board only when the call reaches it (§5.4) | **Different.** Each call loads all boards that the dependencies reach, through each step. This is also true for `{ board { name } }`. | `S/Tool/Commit.swift:409-410`, `S/Tool/KanbanGraph.swift:597-612` |
| R10 | Find boards by a scan: git repos, non-git folders, and path refs (§6.6) | Done, tested | `S/CrossRepo/BoardLocator.swift` |
| R11 | Each loaded board has a watcher (§5.6, §6.7) | Done, tested | `S/Tool/KanbanGraph.swift:761-775` |
| R12 | Undo of a transaction that changed many boards (§6.5) | Done, tested. See X5 and X6 below. | `S/GraphQL/UndoMutations.swift:192-201` |
| R13 | A later edge to a node that the undo would tombstone is a conflict (§6.5) | **Same board only** | `S/GraphQL/UndoMutations.swift:260-271` |
| R14 | The filter `^kanban://<other>/task/…` matches the dependents (§6.3) | Done, tested | `S/Filter/FilterEvaluator.swift:383-386` |
| R15 | `column`, `tags`, `assignees`, and `author` stay in one board | Done. Tested for `column` (`T/Mutations/ColumnActorTests.swift:345`) and in the resolver (`T/Identity/RefResolverTests.swift:275`, `otherURIGivesRemoteRef`). The resolver test uses a task URI. It tests the general rule `acceptingRemote: false`, not `tags`, `assignees`, or `author`. No test covers `tags`, `assignees`, or `author` with a URI of a different board. | `S/Identity/RefResolver.swift:59,308-310` |
| R16 | `node(id:)` reads a different repo | Done, tested | `T/CrossRepo/CrossRepoReadTests.swift:147` (`nodeReadsRelatedBoard`) |
| R17 | The agent can learn about the feature (§12 item 10) | **Missing.** §12 item 10 makes introspection the way to learn the schema, but the schema has no field descriptions. Thus introspection does not tell that `dependsOn` takes a full `kanban://` URI of a different board. The tool description agrees with item 10. | `S/GraphQL/Schema.swift:862` |

These are the problems that the review found. Each one was checked by reading the code.

- **X1. The other repo does not see the link (Q1 — DECIDED: remove `blocks` and BLOCKING, so this is not a problem).**
  - `dependents(from:)` looks only at slots in its own board.
  - Example: `app#Y` depends on `lib#X`. In `lib`, `X` has no BLOCKING tag, `blocks` is `[]`, and `#BLOCKING` does not find `X`.
- **X2. A dependency that cannot resolve is not shown (Q2).**
  - `dependsOn` and `blockedBy` drop each target that no loaded board has, but `ready` stays false.
  - Example: a typo in the URI, a missing repo, or an old key after a repo move. The task is BLOCKED with `blockedBy: []`, and the agent cannot see which URI to remove.
  - Rust keeps an id in `blocked_by` when the id goes missing after the write, for example after a merge (`R/task_helpers.rs:158-173`). Rust removes the id on a delete or an archive.
- **X3. A URI to a different board is not checked when it is written (Q3).**
  - In the same board, a URI to a missing task gives `NOT_FOUND`. A URI to a missing task on a different board is stored with no error. With X2, a typo blocks the task for good, and nothing shows why.
- **X4. A board that the call reached by a path never resolves by key.**
  - A board that the call reached only by a path to a folder outside the scan places (for example `board: "/x/notes"`) does not go into the scan index (`S/Tool/KanbanGraph.swift:703-721`). A path into a folder that the scan finds is in the index.
  - Example: a task on that board is done, but a task that depends on it stays BLOCKED. `node(id:)` gives null. Undo with no `board` field, of a transaction that also changed that board, gives `NOT_FOUND`. Undo with `board: "/x/notes"` works.
- **X5. Undo across boards can reverse part of a transaction, with no error.**
  - `boards(of:)` changes each key to the first copy in scan order (`S/GraphQL/UndoMutations.swift:192-201`). Then the undo field drops each board where the reverse wrote no events (`:119`).
  - Example: a write to a second worktree of `lib`. The undo looks at the first copy, finds nothing, and reverses only the current board.
  - **Second copy of the home board (closed by ^wwntbag):** the `boards` value of an event holds only the keys of the other boards, so a transaction that wrote two worktrees of one repo names the key of neither copy. The undo now also looks for each copy with the key of the board where it found the transaction (the scan, the host table, and the `boards` input), and it reverses the transaction in each copy that holds events of it.
- **X6. Undo has no conflict check across boards.**
  - Example: call 1 adds `lib#X`. Call 2 adds `app#Y`, which depends on `X`. `undo(call1)` gives no `UNDO_CONFLICT`. It tombstones `X`, and `Y` becomes READY with no warning.
- **X7. `undeleteTask` can bring back a cycle.**
  - The cycle check runs only when `dependsOn` or the body changes (`S/GraphQL/TaskMutations.swift:303-305`, `S/GraphQL/UndoMutations.swift:289-298`). `undeleteTask` calls `setDeleted` (`S/GraphQL/ColumnActorMutations.swift:443-453`), which does no cycle check.
  - Example: A→B→C, then delete B, then add C→A, then undelete B. The result is the cycle A→B→C→A, with no error. This can occur in one board or across boards.
- **X8. A cycle across boards that comes from a merge does not block.**
  - `hasDependencyPath` follows only edges in the same board (`S/Derived/Readiness.swift:144-151,175-181`).
  - Example: `a` depends on `B#b`, and `b` is done and depends on `A#a`. Then `a` is READY, and `nextTask` returns it. Plan §5.3 step 5 says that each task in a cycle is blocked.
- **X9. One related board that cannot be read makes every call fail (Q7).**
  - `EventLogError` is not a `KanbanError`, so `execute` throws. This occurs also for `{ board { name } }`.
- **X10. Each call scans again for a key that has no board.**
  - The "not found" result lasts for one call only (`S/Tool/Commit.swift:409`). Git runs again on each call for repos whose key read failed (`S/CrossRepo/BoardLocator.swift:174-193`).
- **X11. Two non-git folders with the same name cannot depend on each other.**
  - Both folders get the key `local/<name>`, so the URI resolves to the current board and gives `NOT_FOUND`. §12 item 26 accepts shared keys, but it does not name this result.
- **X12. The change feed stops when one related board cannot load (Q7).**
  - `publishLiveChanges` loads the dependency boards again. If one board fails, it logs the error, returns, and sends nothing (`S/Tool/KanbanGraph.swift:433-446`).
  - Subscribers then lose all changes of the current board, also changes that have no relation to the broken board. Plan §6.7 says that a `Change` goes out at once. No test covers this.
- **X13. The watcher of a related board can watch the whole repo directory.**
  - When the related repo has no `.kanban/`, the watcher watches the repo directory (`S/Tool/KanbanGraph.swift:785-787`).
  - Plan §6.6 "Trust of a path ref" (plan.md:809-813) says that the tool reads only `<folder>/.kanban/` and `git`. That rule is written for path refs, but X13 also applies to boards that the scan finds. The tool only reads, so the risk is low, but the plan does not say this.

Missing tests for dependencies between boards:

- A related board that cannot be read (X9, X12).
- A dependency on a tombstoned task of a related board.
- A body marker that closes a cycle through a related board.
- An end-to-end marker dependency on another board that changes `ready`.
- `updateTask(dependsOn:)` that drops a target on another board also removes its URL from the body.
- A `^<task on another board>` filter on `changes` and `history`.
- A cycle across three or more boards.
- A board that the call reached by a path (X4), undo on a second copy (X5), and the undo conflict across boards (X6).
- No test in `IntegrationTests/` uses two repos side by side.

### 1.2 Dependencies in one board

- **D1. A task URL in a code block is a dependency (Q5).**
  - Plan §6.1 names no exception for code, so the code agrees with the plan text. The two marker kinds do not have the same rules.
  - Tag markers skip fenced blocks and headings (`S/Tags/TagMarkers.swift:88-98`) and inline code (`:121-156`). Dependency markers do not skip them (`S/Derived/DependencyMarkers.swift:32-36,65-93`).
  - An example URL in a code block can block a task or cause `DEPENDENCY_CYCLE`.
- **D2 (B). A self-dependency.**
  - Rust accepts it on write. Swift refuses it.
  - A task that is not done and depends on itself is BLOCKED in both Rust and Swift (only after a merge in Swift). Today it is also BLOCKING in both; Q1 removes BLOCKING.
  - A done task that depends on itself is BLOCKED in Swift (the cycle rule, plan §5.3 step 5), but not in Rust (`R/task_helpers.rs:158-173`).
- **D3 (B). An unknown local ref in the `dependsOn` input gives `NOT_FOUND`.**
  - Rust gives `TaskNotFound` for a short form that matches no task (`R/dispatch.rs:121-132,291-310`).
  - For a full ULID that matches no task, Rust removes the id on write, with no error (`builtin/definitions/depends_on.yaml`, `swissarmyhammer-fields/src/validation.rs:124-150`). Swift refuses it.
- **D4 (C). Delete and undelete.**
  - Rust delete and archive remove the edge from each dependent for good (`R/task/delete.rs:41-55`, `R/task/archive.rs:56-68`). Swift keeps the edge, so `undeleteTask` makes the dependents blocked again.
  - Plan §3.3 rules 2 and 3 give this result.

This behavior agrees with the plan:

- `dependsOn` is the union of edges and markers.
- `updateTask(dependsOn:)` removes the edges and the URLs that the new list drops.
- A dependency on the task itself is refused.
- The done column is the column with the highest `order`. Two columns with the same order sort by slug.
- A tombstoned target is ignored.
- An unknown target blocks.
- A cycle in one board from a merge blocks each task in the cycle.

---

## 2. Next task

Path: `S/GraphQL/QueryResolvers.swift:329-332` → `S/GraphQL/TaskSelection.swift:46-54` → `S/Derived/Readiness.swift:258-272`.

| Step | Swift | Rust `R/task/next.rs` | Plan |
|---|---|---|---|
| Candidates | READY tasks: live, not in the terminal column, no blocking dependency. The filter also applies. | Not terminal, ready, filter (:52-70) | Same as Swift |
| Column sort | `(order, slug)`. A task with no live column shows in the first column. | Sort by `order` (:105-107). Two columns with the same `order` keep the list order, which can change from one load to the next. | `(order, slug)` |
| Order in a column | Ordinal, then ULID | Ordinal. A tie keeps the list order. | Ordinal. §7.3 names the ULID tie-break. |
| Priority tier | Not used. This is correct, because the tiers come from the same order. | none | Not asked for |
| Unknown dependency | Blocks | Blocks | Blocks |
| Tombstoned dependency | Ignored | Not blocked. Delete and archive remove the edge (`R/task/delete.rs:41-55`). An id that goes missing for a different reason blocks (`R/task_helpers.rs:142-151`, through `R/task/next.rs:117`). | Ignored |
| Dependency on another board | Done only when the target is in the terminal column of a loaded board | n/a | §6.6 |
| Cycle in one board | Each task blocked | Not handled | Each task blocked |
| Cycle across boards | **Not blocked (X8)** | n/a | Each task blocked |
| Nothing ready | `null` | `null` | `null` |

In one board, the review found no case where Swift returns a blocked task, skips a ready task, or uses an order that is different from the plan.

**Performance.** For each task, `isReady` walks the graph again for each done dependency (`S/Derived/Readiness.swift:147`), and nothing keeps the result. This can be slow on a large board.

**Missing tests for `nextTask`:**

- The only dependency is tombstoned.
- A cycle in one board, and a cycle across boards.
- A dependency on another board that is done, not done, or on a board that is not found. The current tests check `ready`, not `nextTask`.
- Two tasks with the same ordinal.
- Two columns with the same `order`.
- A task in a tombstoned column.
- All tasks are blocked.
- A board with one column.
- A task with CONFLICT.
- The filters `#READY`, `#BLOCKED`, and `^<blocked id>`.

---

## 3. Virtual tags

Swift: `S/Derived/VirtualTags.swift`. Rust: `R/virtual_tags.rs`.

| Tag | Plan | Swift | Rust | Divergence |
|---|---|---|---|---|
| READY | live, not done, all dependencies done | :87-88 | :197-250 | Rust has no tombstones. Delete and archive remove the edge, so the task is not blocked. Swift ignores the tombstone (intended). The result is the same, but undelete differs (D4). |
| BLOCKED | live, at least one dependency not done | :89-90 | :308-361 | The same as READY for a tombstoned dependency. A done task can be BLOCKED in both. |
| BLOCKING | live, not done, some live task depends on it | :91-92 | :252-306 | A done dependent counts in both (Q4). Swift does not count dependents on other boards (X1). |
| CONFLICT | body has a conflict block | :93-94 | none | New |
| DELETED | tombstone, hidden unless the filter names it | :95-96 | none (Rust has archive) | New |
| DONE | live, in the terminal column | :97-98 | none (Rust has `excludeDone`) | New |
| HIGH / MEDIUM / LOW | the third of the open tasks, in board order | `S/Derived/PriorityTier.swift:28-30` | none | New |

- **Reserved names.** A real tag cannot have a virtual tag name, in any case. In Rust, a real tag `ready` also matched `#READY`. In Swift, `#ready` matches only the virtual tag. This agrees with the plan.
- **Ready and done.** A done task is not READY as a tag, but the `ready` Boolean and `summary.ready` count it as ready. Rust does the same. Thus `summary.ready` is not equal to the count of `#READY`.
- **Column states.** There are no virtual tags for each column state (TODO or DOING) in Rust or in the plan. The `%column` filter atom does this job.
- **Metadata that Swift does not have (Q19).** Rust has a color, a description, and commands for each tag:
  - READY `0e8a16`
  - BLOCKING `d73a4a`, with `show_dependents` (not needed after Q1)
  - BLOCKED `e36209`, with `show_blockers`
- **Bug.** The doc comment `S/Derived/VirtualTags.swift:7-8` says "case-sensitive", but the match does not use case (:51-57). The test `slugIsCaseSensitive` tests only `rawValue`. The test `virtualTagCaseInsensitive` (`T/Filter/FilterEvaluatorTests.swift:285`) shows that the match ignores case, so the doc comment is wrong.
- **Missing tests:**
  - BLOCKING with a dependent on another board (not needed after Q1).
  - BLOCKING with only a done dependent: only implicit in `T/Filter/FilterEvaluatorTests.swift:274` (not needed after Q1).
  - A self-dependency on an open task: the virtual tag BLOCKED (D2). The BLOCKING part is not needed after Q1. `selfDependencyBlocks` (`T/Derived/ReadinessTests.swift:201`) checks only the blockers, on a done task.
  - A tombstone with CONFLICT.
  - The priority tags on a board with no live column.

---

## 4. Parameter names and synonyms

The goal: each argument and each input field has **one canonical name**, plus synonyms, so that an agent that is "close enough" gets a working call.

**Principle from the user: be VERY FORGIVING.** An agent that calls the tool must get the best chance of success. This applies to all inputs, not only to names: names, value shapes, refs, and the values that Rust accepts. When Swift can find one clear meaning, it does the work and does not give an error. Swift gives an error only when the input has two meanings, or no meaning, or when the work is not safe (for example, Q6). Section 14 lists the decisions to check against this principle.

**Rule from the user: be forgiving on synonyms.** The tables in 4.2 and 4.3 are the minimum, not the full list. When a name that an agent can send has only one possible meaning in that position, accept it. Refuse a name only when it can mean two different fields (`AMBIGUOUS_NAME`) or when it means no field.

- **Connection `nodes` (from the "very forgiving" principle).** Each connection type, for example `TaskConnection`, also has `nodes`: the list of the edge nodes. Agents often send `{ nodes { … } }` in place of `{ edges { node { … } } }`.

The matcher (`S/GraphQL/NameMatcher.swift`, `S/GraphQL/NameRewrite.swift`, and the alias table at `S/GraphQL/Schema.swift:1002-1013`) tries these steps in this order:

1. Exact match.
2. Case and style fold (camelCase, snake_case).
3. Singular or plural.
4. Word order and verb synonyms (mutations only).
5. Alias table.
6. One changed, added, or removed letter, for names of 4 or more letters (`S/GraphQL/NameMatcher.swift:132-134,299-311`).

When two or more names match at the same step, the matcher gives `AMBIGUOUS_NAME`. Most Rust keys work. In table 4.2, 11 different Rust MCP names fail. Some of them (`column`, `task`, `task_id`) fail in more than one position. N3, N4, and N5 add more names that fail. `task_id` goes to the wrong field on `updateComment` and `deleteComment`, or gives a duplicate `id`. `update tag {id, name}` runs but has a different effect.

### 4.1 Gaps in the mechanism

- **N1 (B, a gap in the plan). The names in `variables` are not changed (Q8).**
  - The rewrite changes only the document text (`S/GraphQL/NameRewrite.swift:450-498`). `variables` go to the engine with no change (`S/GraphQL/Schema.swift:1093-1101,1216-1221`).
  - When a script sends a whole `input` object as a variable (`addTask(input: $input)`), no alias and no fold applies to the names in it. Scalar variables in a literal `input` (the code-mode example, plan.md:1011-1014) are not affected.
- **N2 (A). The alias table is global, not for each field (Q9).**
  - Plan §4.5 says that the aliases are "next to each field".
  - The global entry `task_id → id` sends the task ref to the comment `id` on `updateComment` and `deleteComment`. The result is a duplicate `id` (the call fails) or a call on the wrong node. Rust has a rule that prevents this (`R/parse/mod.rs:186-219`).
- **N3 (A/B). There are no query verbs at the root (Q10).**
  - `getTask`, `listTasks`, `getBoard`, `listColumns`, `search`, and `next` all fail. Step 4 applies only to mutations.
- **N4 (C). `createBoard` and `newBoard` fail (Q11).** The plan names this rule (plan.md:365,372: "`create` never maps to `init`"). Q11 reverses the plan rule.
  - The never-list stops `create → init`, and the verb synonyms map `new` to `add` (`S/GraphQL/NameMatcher.swift:50,90`). So `newBoard` gives `addBoard`, which does not exist. Rust maps `create` and `new` to `init` (`R/types/operation.rs:58`).
- **N5 (B). The error message for a name that does not match is weak (Q12).**
  - The message suggests only names with a similar spelling. It does not list the fields of the type.
  - A removed Rust parameter gives a general validation error with no "use X" hint. This applies to `project`, `due`, `scheduled`, `exclude_done`, `page`, `detail`, `include_counts`, `model`, and `attachments` (`R/dispatch.rs:633`). (`avatar` is not a Rust MCP parameter: dispatch reads only `id`, `name`, and `ensure` for `add actor`, `R/dispatch.rs:908-916`.)
- **N6 (B). A list sent as a JSON string is not split (Q13).**
  - Rust accepts `"[\"a\",\"b\"]"` for `tags`, `depends_on`, and `assignees`. In Swift, this text becomes one bad value: one bad tag name for `tags`, one ref that does not resolve for `dependsOn`, and one actor that does not exist for `assignees`.
- **N7. Enum values.** The public schema has no input enum, so the enum code never runs for an agent call. It runs only for the internal `patch` mutation (`S/GraphQL/PatchSchema.swift:71-78,85`) and in tests.

### 4.2 Rust names that fail today

| Mutation or field | Swift name | Rust name that fails | Result |
|---|---|---|---|
| `assignTask`, `unassignTask` | `actor` | `assignee` | FAILS |
| `moveTask` | `before`, `after` | `before_id`, `after_id` | FAILS |
| task operations, `Board.task` | `id` | `task` | FAILS |
| `addTask`, `moveTask` | `column` | `col` | FAILS (3 letters, no alias) |
| column operations | `id` | `column` | FAILS |
| `addComment` | `task` | `task_id`, `taskId` | FAILS |
| `updateComment`, `deleteComment` | `id` | `task_id` | FAILS (duplicate `id`) when `id` is also sent, as Rust does (`R/dispatch.rs:1222`); **WRONG TARGET** when only `task_id` is sent |
| `updateComment`, `deleteComment` | – | `task` | FAILS (unknown field). Rust also accepts `task` here (`R/parse/mod.rs:206`). |
| `renameTag` | `from`, `to` | `update tag {id, name}` | **WRONG EFFECT.** `updateTag` runs and changes only the display name; the slug does not change. Rust renames the tag and the `#old` markers (`R/tag/update.rs:76-98`). Rust keeps the ULID id and changes `tag_name`. See C4. |
| `tasks`, `searchTasks` | `first` | `page_size`, `top_k` | FAILS |
| mutation | `unassignTask` | `remove_assignee` | FAILS (no synonym) |
| `updateTask` | – | `column` | FAILS. Rust ignores this key. Swift refuses the whole call. |

### 4.3 Proposed synonyms for names that agents often send (Q9)

| Agent sends | Where | Map to |
|---|---|---|
| `name`, `subject`, `summary` | task inputs | `title` |
| `notes`, `details`, `message`, `comment`, `text`, `description` | all inputs | `body` |
| `state`, `status`, `lane`, `col`, `columnId`, `column_id`, `to`, `toColumn` | `addTask`, `moveTask` | `column` |
| `before_id`, `beforeId`, `beforeTask` / `after_id`, `afterId`, `afterTask` | `moveTask` | `before` / `after` |
| `assignee`, `actorId`, `actor_id`, `user`, `who` | `assignTask`, `unassignTask` | `actor` |
| `assignTo`, `owner`, `owners` | task inputs | `assignees` |
| `author`, `user` | `addComment` | `actor` |
| `task_id`, `taskId` | `addComment` | `task` (an alias for this type only) |
| `task`, `ref`, `uri`, `key`, `<type>Id`, `<type>_id` | inputs for that node type | `id` |
| `dependencies`, `dependency`, `depends`, `deps`, `blockers`, `prerequisites`, `blockedBy` (Q14) | task inputs | `dependsOn` |
| `labels`, `label` | task inputs | `tags` |
| `tag`, `old`, `oldName` / `name`, `new`, `newName` | `renameTag` | `from` / `to` |
| `top_k`, `topK`, `limit`, `page_size`, `count`, `size` | `tasks`, `searchTasks`, `history` | `first` |
| `cursor` | `tasks` | `after` |
| `transaction`, `txnId`, `txn_id`, `id` | `undo`, `redo` | `txn` |
| `path`, `board`, `key`, `repo` | `board(id:)` | `id` |
| `getX`, `showX`, `readX`, `fetchX` / `listX`, `findX`, `queryX` / `search` / `next` | root query | singular field / plural field / `searchTasks` / `nextTask` |
| `createBoard`, `newBoard` | mutation | `initBoard` |
| `removeAssignee` | mutation | `unassignTask` |
| `created_at`, `updated_at`, `count`, `total` | selection | `created`, `updated`, `totalCount` |
| `priority`, `prio`, `urgent` | inputs | a move in the column, with a warning (P2) |

### 4.4 Gaps in plan §4.5

The plan:

- does not say that the rewrite applies to `variables`;
- gives its alias examples with no field scope (`task_id → id`, plan.md:366), although it says that the aliases are next to each field (plan.md:373);
- has a never-list rule that blocks `createBoard`;
- has no rule for query verbs at the root;
- does not have `remove_assignee` in its verb list;
- does not list the Rust names that Swift renamed;
- accepts the default "did you mean" message;
- does not say what `blockedBy` does as an input name.

---

## 5. Behavior of GraphQL operations

The schema agrees with the §4.1 sketch and the §4.2 table. Each of the 21 error codes in §4.4 exists and is used.

These are the differences from Rust that the plan does not name (Q16):

- **O1. `addActor(ensure: true)`.**
  - Rust updates the name, the color, and the avatar when they are different. Swift writes nothing (`S/GraphQL/ColumnActorMutations.swift:242-244`).
  - Swift also returns a tombstoned actor as it is, and does not make it live.
  - `AddActor` in Rust updates the name, the color, and the avatar (`R/actor/add.rs:80-101`), but through the MCP tool only the name can change (`R/dispatch.rs:908-916`).
- **O2. `tagTask` and `untagTask` with an empty list.** Rust gives an error. Swift writes nothing. A test records this, but the plan does not.
- **O3. A `before` or `after` ref that names no task.** Rust puts the task at the end of the column. Swift gives `NOT_FOUND`.
- **O4. `null` on a required field.** `null` clears `title` and the column `name`, and they then read as `""`. The same path also clears the actor `name` (`S/GraphQL/ColumnActorMutations.swift:114`) and the tag `name` (`S/GraphQL/TagMutations.swift:53,130-132`). Rust ignores `null` for these fields (Q17).

---

## 6. Graph and identity

- **G1 (A). The resolver accepts a column or actor name, not only the slug.** For example, `In Progress` resolves to `in-progress` (`S/Identity/RefResolver.swift:341-344`). The plan says "the slug" (Q18).
- **G2 (A). `node(id:)` accepts short forms in a fixed type order.** The order is task-or-comment (one step), board, column, actor, tag (`S/Identity/RefResolver.swift:29,33,140-148`). When a column and a tag have the same slug, the column wins. The plan gives no order.
- **G3 (B). A short id that two nodes share.**
  - Rust returns the first task. Swift gives `AMBIGUOUS_ID` (`S/Identity/ShortID.swift:109-112`, `S/Identity/RefResolver.swift:411-424`).
  - Swift checks tasks and comments, live and tombstoned (`S/Identity/RefResolver.swift:399-424`), so a tombstone can make the short id of a live task ambiguous. This also applies to the filter `^id` (Q20).
- **G4 (A). A git failure that is not "no repo" stops the board from opening.**
  - `S/Identity/BoardKey.swift:198-201,242-245` throws `gitFailed`. The plan says that a board always opens, with the `local/` fallback.
- **G5 (B). The actor `avatar` and the board `model` are removed.** §2.2 does not name them (Q19).
- **G6 (B). No terminal column on a board with no live column.** Rust falls back to `"done"`. Swift then treats no task as done. The impact is low.
- **G7 (B). An ordinal text with an odd number of characters gives `INVALID_ORDINAL`.** Rust ignores the last digit. There is no effect at replay.
- **G8 (B). Rust `transfer_task` (move or copy a task to a different board) has no Swift equivalent.** The plan does not remove it (Q21).

The six node types, the edges, the URI and local-ref forms, the slug rules, the mint rule, and the ordinal algorithm agree with the plan. The ordinal code gives the same bytes as the Rust crate `fractional_index` 2.0.2.

---

## 7. Storage and undo

- **S1 (A/B). Swift log files use the same paths as the Rust changelog files (Q6).**
  - Rust keeps a `.jsonl` changelog next to each entity (`swissarmyhammer-entity/src/io.rs:193-199`). Examples: `.kanban/columns/todo.jsonl` and `.kanban/tasks/<ULID>.jsonl`. These are the Swift log paths of §5.2.
  - Plan §12 item 11 says that the old Rust files are `.yaml` or `.md` and are ignored. This is not correct.
  - On a Rust board, these things occur:
    - Swift reads each Rust line, fails, and logs a warning for each line.
    - The auto-init of Swift appends its events into Rust files.
    - A Rust tool that runs at the same time appends to the same files, and it does not take the lock.
  - This repo has a Rust `.kanban`.
  - The board log is different: `boards/board.jsonl` in Rust, `board.jsonl` in Swift. Thus the locator (plan §12 item 13) does not see a Rust board as enabled, and Swift auto-inits on it.
  - Plan §2.2 ("Diff-patch changelog") already shows that Rust has a changelog. Thus §12 item 11 also disagrees with §2.2.
- **S2 (A). The `.gitattributes` and `.gitignore` rules are not added to existing boards (Q22).**
  - `S/Events/EventLog.swift:137-150` writes these files only when they do not exist.
  - A Rust board can have `**/*.jsonl merge=kanban-jsonl` (the `swissarmyhammer/.kanban` board has it), and its `.gitignore` has no `.lock` line (both repos). Thus git does not use the `union` merge for the Swift logs, and git does not ignore `.lock`.
- **S3 (A). Event ids are in order inside one call, but not from one call to the next.**
  - Each call starts from a new random ULID (`S/Tool/Commit.swift:31-37,62-66`).
  - Two calls in the same millisecond, or a clock that moves back, can put a later `set` before an earlier one. They can also put an undo before its target.
- **S4 (A). One bad property makes replay drop the whole line.**
  - A value with the wrong kind makes the decode throw, and `S/Events/Replay.swift:143-150` drops the full line.
  - The plan says that replay never refuses a log, and that a schema change needs no upgrade step.
- **S5 (A). "All or nothing" covers only errors that the code catches, not a crash (Q23).**
  - The code appends in place, with no fsync. A crash between two files keeps part of a transaction.
- **S6 (B). The lock waits with no time limit (Q24).**
  - `S/Events/BoardLock.swift:99-106` calls `flock(LOCK_EX)` in a loop. A process that holds the lock and stops responding makes each Swift mutation stop responding too.
  - Rust defines `lock()` with `try_lock` and `LockBusy` on the same `.kanban/.lock` file (`R/context.rs:690-708`). But only tests call it, so the Rust mutations take no lock.
- **S7 (A). The watcher can miss files when a tool moves a whole directory.** FSEvents can report only the directory.
- **S8 (A). The `boards` list cannot name a second copy of the same repo.** An undo reverses only one copy. See also X5.

---

## 8. Tags, filter, and search

- **F1 (A/B). The `^` filter does not match by the slug of the task title (Q25).**
  - Rust matches `^fix-login-bug` (`R/task_helpers.rs:871-883`). Swift accepts only ULID forms.
  - Rust keeps only one task for each title slug (`build_slug_index`, `R/task_helpers.rs:750-761`). When two tasks have the same title slug, the last task wins.
  - Plan §6.3 says that "a filter that works on the Rust tool must give the same result". The plan is not consistent here.
- **F2 (A). The plan allows `^^short` in a filter, but the grammar refuses it (Q25).** Rust also refuses it.
- **F3 (A). A shared short id in `^id` gives `AMBIGUOUS_ID` (Q20).** The plan says that a value that names nothing gives an empty result. Rust matches each task whose ULID has that short id, and the tasks that depend on one of them (`R/task_helpers.rs:818-824`).
- **F4 (A). The parser does not use the structure that the plan gives.**
  - The code uses hand loops, not `Many`, because `Many` and `OneOf` catch the errors of their parts. An error after an operator then loses its position (`S/Filter/FilterParser.swift:19-23`).
  - The code does not use `Lazy`, because `Lazy` is deprecated and not `Sendable` (`:152-154`).
  - A parse that succeeds gives the same result. The error positions are better than with `Many`. Update the plan.
- **F5 (B). A tag marker continues through `_` (Q26).**
  - In Swift, `#needs_review` gives the tag `needs-review`. Rust stops at `_` and gives `needs`.
- **F6 (B). A tag that a marker creates gets a lowercase name (Q26).**
  - In Swift, `#Bug` gives the name `bug`. Rust keeps the case.
- **F7 (B). A tag slug joins runs of `-` and removes a `-` at the end.**
  - `#a--b` gives `a-b`. Rust keeps `a--b`.
- **F8 (B). The `#`, `@`, and `%` values become slugs before the match.** Thus `@claude_code` matches `claude-code`. Swift finds more matches than Rust.
- **F9 (B). Tag order.** Rust sorts the tags. Swift gives the edges first, then the markers in text order.
- **F10 (B). Line breaks.** Swift also breaks lines at a lone `\r`, U+2028, U+2029, and U+0085. Rust breaks only at `\n`.
- **F11 (B). The `INVALID_FILTER` position counts characters. Rust counts bytes.**
- **F12 (B). Removed fields (Q19).**
  - The board summary does not have `total_actors`, or `task_count` and `ready_count` for each column.
  - `Progress` has `fraction`, not `percent`.

These items agree with Rust: the auto color (the same FNV-1a hash and palette), the checklist count, the fence, heading, and inline-code rules for tag markers, and the precedence of the filter grammar.

---

## 8a. The tool, the public API, the package layout, and the tests (§7–§11)

- **The public API agrees with §7.2.** It has `KanbanGraph.init(root:actor:locator:embedder:)`, `execute`, `subscribe`, `close`, `schemaSDL`, and `KanbanTool.init(graph:)`.
- **The tests that §7, §9, §10, and §11 ask for are present.** These include:
  - the `anyOf` schema;
  - code mode with an object and with `JSON.stringify`;
  - the Qwen integration test;
  - the serial gate;
  - the shuffle and replay property test;
  - 2000 files with the peak worker count;
  - the subscription union rewrite;
  - `SUBSCRIPTION_NOT_IN_TOOL`;
  - moving a repo;
  - two copies of one repo;
  - the undo scope;
  - unknown and new properties.

  The other missing tests are the tests that sections 1–3 list.
- **§8 layout (A).** The code has more files than the plan lists. None of them conflicts with the plan. The plan does not list:
  - `CrossRepo/RelatedBoards.swift`
  - five `Observe/Change*.swift` files
  - `Tool/Commit.swift`
  - `Log.swift`
  - other helper files in `Identity/`, `Derived/`, `Events/`, `Filter/`, `Undo/`, and `GraphQL/`
  - `Model/Node.swift` and `Body/BodyLines.swift`
  - the `IntegrationTests/` package

  Update §8 to list them.
- **§5.4 step 2 (A).** Related boards load on each call, also when the call does not read them. See R9 and X9.
- **Board location agrees with Rust.** Both use `<working dir>/.kanban`. For the current board, neither searches the parent directories. (The Swift locator does scan the parent directory of the repo for related boards, plan §12 item 13.)

---

## 9. Intended differences that the plan names (C)

For completeness only. These need no decision.

- **Interface:** GraphQL replaces the `verb noun` parser. `create` and `new` map to `add`, but `createBoard` and `newBoard` map to `initBoard` (Q11). Cursor paging replaces page numbers.
- **Removed:** projects, perspectives, attachments, archive (now `delete`/`undelete`), `due`, `scheduled`, and the `tag`, `assignee`, `column`, and `excludeDone` list parameters.
- **Identity:** tag ids are slugs, and all slugs are lowercase. Comments are full nodes. The URI form is `kanban://<board-key>/<type>/<id>`. `board` is a reserved slug.
- **Tombstones:** a delete makes a tombstone, with no cascade. A dependency on a tombstone is ignored.
- **Tags:** a rename makes a redirect. Tags come from edges plus markers. A task URL in the body is a dependency.
- **Readiness:** a cycle is refused when written. In a merged cycle, each task is blocked.
- **New items:** the virtual tags CONFLICT, DELETED, DONE, HIGH, MEDIUM, and LOW, and the `INVALID_ORDINAL` and `CONFLICTING_PLACEMENT` errors.
- **Filter:** `$project` is removed. `%column`, `~type`, and URL atoms are added.
- **Search:** it uses `MetadataSearcher`. Done tasks are hits.
- **Storage:** an event log with union merge, unified diffs for body edits, and an undo from `undoes` with no stored stack. GraphQL subscriptions replace the Rust watcher and change events, and an FSEvents watcher with signatures keeps the graph live. Locks for each board, `BOARD_BUSY`, and rollback by truncate are new.

---

## 10. Questions for you

All 26 questions have a decision. Section 11 lists the changes to the code and to the plan that the decisions cause.

### Dependencies between boards

**Q1. How does a board find the tasks on other boards that depend on its tasks (BLOCKING and `blocks`)?** (X1)

**DECIDED:** We do not need dependencies in two directions. Keep only `dependsOn` and `blockedBy`. Remove the `blocks` field and the BLOCKING virtual tag from the plan and the code, in one board and across boards.

- Reason: BLOCKING is for a human who wants to make less work. An agent does the blockers until they are done. It does not need the reverse view.
- Result: X1 is no longer a problem. The "BLOCKING" rows and tests in sections 1–3 do not apply. The change is in section 11.

**Q2. How do we show a dependency that cannot resolve?** (X2)

**DECIDED:** Add the field `Task.unresolvedDependsOn: [ID!]!`. It lists each `dependsOn` target that no loaded board has, as a URI. `blockedBy` stays `[Task!]!`. A target that cannot resolve still blocks the task (§3.3 rule 4).

**Q3. Do we check a URI to a different board when it is written?** (X3)

**DECIDED:**

- The board is found and the task is missing: give `NOT_FOUND`. **REPLACED by P3:** accept the URI, show it in `unresolvedDependsOn`, and give a warning.
- The board is not found: accept the URI, because the repo can be absent on this machine. `unresolvedDependsOn` (Q2) then shows it.

**Q4. Does a done dependent keep a task BLOCKING?** **NOT NEEDED:** Q1 removes BLOCKING.

**Q5. Is a task URL in a code block, inline code, or a heading a dependency?** (D1) **DECIDED:** No. Use the same rule as for tag markers: skip task URLs in fenced code blocks, inline code, and headings.

**Q6. How does Swift live next to an existing Rust `.kanban` board?** (S1) This is a large risk.

**DECIDED (final, replaces the first decision and C2, E2, E3):** Swift does not delete, import, or change a Rust board. The user must remove the Rust board (or ask Claude to delete it). Swift only finds it and reports it.

- When a `.kanban/` contains Rust files, Swift does not open it and does not write to it. The error says: "There is an incompatible board at `<path>/.kanban`. Remove it, then try again."
- Swift stops early: the check runs before any read or write. Swift does not try to continue around the board.
- This applies to every `.kanban/` that Swift opens: the current board and each related board. Swift never makes a new board in a `.kanban/` that has Rust files. (This is an exception to Q7: an incompatible related board stops the call, and does not give only a warning.)
- How Swift finds a Rust board: `.kanban/` contains a Rust-only path, for example `boards/`, `*.yaml` or `*.md` entity files, `perspectives/`, `views/`, `projects/`, `.gitconfig`, `search-cache.sqlite3`, `undo_stack.yaml`, or `mcp*.log`.
- There is no git check and no check for a running Rust server.
- The plan must change §12 item 11. It says now that Rust files are ignored.

**Q7. When a related board cannot be read, do the call and the change feed continue?** (X9, X12)

**DECIDED:** Yes.

- The call continues. Each dependency on that board counts as not done and shows in `unresolvedDependsOn` (Q2).
- The response has a warning that names the board.
- The change feed keeps sending the changes of the boards that load.

### Parameter names

**Q8. Does the name rewrite also apply to the names in `variables`?** This includes nested objects and arrays. **DECIDED (default, the user has no preference):** Yes, at all depths. This follows the goal "close enough just works". The input type of each variable gives the target type.

**Q9. Do we use aliases for each input type, and do we accept the synonym table in 4.3?** **DECIDED:** Yes. Use a global table for names that are safe everywhere, and a table for each input type for names like `task_id`. Use the synonym table in 4.3.

**Q10. Do we add query verbs at the root?** These are `get`, `show`, `read`, and `fetch` (singular field), `list`, `find`, and `query` (plural field), `search` (`searchTasks`), and `next` (`nextTask`). **DECIDED:** Yes.

**Q11. Do `createBoard` and `newBoard` map to `initBoard`?** There is no `addBoard`, so there is no conflict. **DECIDED:** Yes.

**Q12. When no name matches, does the error list the canonical field names of the type, and does each removed Rust parameter get a "removed, use X" message?** **DECIDED:** Yes.

**Q13. Do we split a JSON array that is sent as a string for the list fields?** **DECIDED:** Yes, as Rust does.

**Q14. Is `blockedBy` as an input name a synonym for `dependsOn`, or is it an error?** **DECIDED:** It is a synonym for `dependsOn`, because the agent means a dependency.

**Q15. What do we do with `priority` in an input?** Priority comes from the task order. **DECIDED:** Give an error that says "use `moveTask` with `before`/`after`, or filter with `#HIGH`".

### Operation behavior

**Q16. Which Rust behaviors do we keep?** (O1–O3)

**DECIDED:**

- `addActor(ensure: true)` updates the name, the color, and the `avatar` (Q19) when they are different, and makes a deleted actor live again. Rust also updates the avatar (`R/actor/add.rs:80-101`).
- `tagTask` and `untagTask` with an empty list write nothing and return the task. There is no error.
- An unknown `before` or `after` ref gives `NOT_FOUND`. **REPLACED by P1:** the task goes to the end of the column, with a warning.

**Q17. What does `null` on `title` or a column `name` do?** **DECIDED:** Ignore it, as Rust does. `null` on a required text field means "no change". The call works, and the field keeps its value.

**Q18. Can a column or actor ref be the display name, not only the slug?** (G1) **DECIDED:** Yes. Keep the current code, and write the rule in plan §3.2.

**Q19. Do we add back these Rust fields?**

- The actor `avatar`.
- The board `model`.
- The summary values `total_actors`, `task_count`, and `ready_count`.
- `percent` in `Progress`.
- The color and the description of each virtual tag.

**DECIDED:** Add all of them back.

- The actor `avatar` and the board `model`.
- `total_actors` in the board summary, and `task_count` and `ready_count` for each column.
- `percent` in `Progress`, next to `fraction`.
- A color and a description for each virtual tag (BLOCKING is removed by Q1).

**Q20. What does a short id that two nodes share give?** (G3, F3)

**DECIDED:** Use the first match, as Rust does. There is no `AMBIGUOUS_ID` for a 7-character short id.

- To make "first" the same each time (Rust uses list order, which can change): a live node comes before a tombstone, then the lowest ULID. (Proposal, accepted in section 11.)
- This applies to mutations and queries. In a filter, `^short` matches each task with that short id, as Rust does.
- A ULID prefix that matches more than one ULID still gives `AMBIGUOUS_ID`. Rust finds the ambiguity (`R/types/short_id.rs:123-127`), but the mutation path changes it to `TaskNotFound` (`R/dispatch.rs:126-130`). Rust has no error code for an ambiguous id.

**Q21. Do we need a move or copy of a task to a different board (Rust `transfer_task`)?** (G8) **DECIDED:** Add it now.

- Add `moveTask(board:)` to move a task to a different board, and a `copyTask` mutation to copy a task to a different board.
- In the new task, a local ref becomes a full URI, so that the dependencies on the old board still resolve.
- Tags that the target board does not have are dropped, as in Rust (`R/cross_board.rs:212-230`). Rust keeps the assignees with no check (`:196-210`). E6 decided: Swift keeps all tags and makes each missing tag on the target board.
- A move tombstones the old task. E6 decided: the old task body gets a line that points to the new URI, so that dependents on the old board can find it.

### Storage and safety

**Q22. Do we add the missing `.gitattributes` and `.gitignore` lines to an existing board?** (S2) **NOT DONE (K10, section 15).** First decision, history only: Fix the lines. Add each missing Swift line. Replace a line that gives `*.jsonl` a different merge driver (for example the Rust `**/*.jsonl merge=kanban-jsonl`). Keep all other lines.

**Q23. Do we need crash safety (fsync, or a check at load) for transactions on many files?** (S5) **DECIDED:** Fix now.

- Call fsync on each log file after the appends of a transaction.
- At load, find each transaction (`txn`) that is not complete in all its files, and do not apply its events. Proposal, accepted in section 11: each event line of a transaction records the count of files that the transaction wrote in this board, so the load can see when a file is missing its part. The field is optional; an old line with no count counts as complete.

**Q24. Does the lock have a time limit that gives `BOARD_BUSY`?** (S6) **DECIDED:** No. Keep the current behavior: the lock waits with no time limit.

### Filter and tags

**Q25. Do we support `^<title-slug>` (as Rust does) and `^^short` in a filter?** (F1, F2) **DECIDED:** Support both. Accept `^<title-slug>`, as Rust does, and `^^short`.

**Q26. Do we keep these tag rules?**

- A marker continues through `_` (F5).
- A tag that a marker creates gets a lowercase name (F6).

**DECIDED:** Keep both Swift rules, and write them in the plan. A marker continues through `_`, and a tag that a marker creates gets a lowercase name.

---

## 11. Bugs that need no decision, and changes from decisions

**Note from the user: `plan.md` will not be updated.** Each "Change the plan" line in this section is for information only. It shows where the plan and the code now differ. This file, not `plan.md`, records the decided behavior.

Changes from decisions:

- Q1: remove the `blocks` field and the BLOCKING virtual tag.
  - Change the code: `S/Derived/Readiness.swift:36,65,129,221-229` (the stored `dependents`), `S/Derived/VirtualTags.swift:17,91-92`, `S/GraphQL/QueryResolvers.swift:539-541`, `S/Observe/ChangeBuilder.swift:419` (`("blocks", ...)`), and `S/GraphQL/Schema.swift`. Fix the doc comments at `S/Derived/Readiness.swift:3,125` and `S/Derived/VirtualTags.swift:73`.
  - Change the tests: the BLOCKING and `blocks` tests, and also `T/Observe/ChangeBuilderTests.swift`, `T/GraphQL/NodeQueryTests.swift`, and `T/CrossRepo/CrossRepoReadTests.swift`, which use these fields.
  - Change the plan: §3.1, §4.1, §5.3 step 4, §6, §6.3, and §10 item 8. (Information only: `plan.md` will not be updated.)
  - Then BLOCKING is not a reserved tag name (C1).
- C1: `#BLOCKING` is an ordinary tag filter.
  - No code change in Swift other than Q1.
  - Change the skills: remove `#BLOCKING` and the word BLOCKING from `../swissarmyhammer/builtin/skills/kanban/SKILL.md:81` and `../swissarmyhammer/builtin/skills/finish/SKILL.md:58`. Plan §12 item 29 says that the skills are in `../skills`, but that repo has no kanban or finish skill. Change plan item 29 to name the correct repo.
  - Change the plan: §6.3. It says that a Rust filter gives the same result in Swift. Add: except `#BLOCKING`.
- Q2: add `Task.unresolvedDependsOn: [ID!]!`.
  - Change the code: `S/GraphQL/QueryResolvers.swift:512-536` and `S/GraphQL/Schema.swift`. Add tests for a typo in a URI, a missing repo, and a missing task on a loaded board.
  - Change the plan: §3.1 and §4.1.
- Q3 (changed by P3): check a `dependsOn` URI to a different board when it is written. A missing task on a found board does not fail the call: store the URI, and give a warning.
  - Change the code: `S/Identity/RefResolver.swift:303-312` (`remoteRef`) and `S/GraphQL/TaskMutations.swift:198-200`. Also check the task URLs in a body (markers). Add tests for both cases.
  - Change the plan: §6.6.
- Q5: dependency markers skip fenced code blocks, inline code, and headings.
  - Change the code: `S/Derived/DependencyMarkers.swift:32-36,65-93`. Use the same skip logic as `S/Tags/TagMarkers.swift:88-98,121-156`. The removal of a URL by `updateTask(dependsOn:)` must use the same rule. Add tests.
  - Change the plan: §6.1.
- Q6: find a Rust board and report it. Do not delete or change it.
  - Change the code: add one Rust-board check (the path list in Q6) before the first read, in `loadSession` (`S/Tool/KanbanGraph.swift:562`), so that it covers the current board and related boards (`loadRelatedBoard`, `:761-775`). Also check before Swift makes a new board (plan.md:814, and `prepareDirectory` in `S/Events/EventLog.swift:137-150`).
  - Add a new error code, for example `INCOMPATIBLE_BOARD`. The message: "There is an incompatible board at `<path>/.kanban`. Remove it, then try again."
  - Any `.kanban/` with Rust files (the current board or a related board): give the error before any read or write, and change no file.
  - Add tests: a Rust board as the current board gives the error and changes no file; a related Rust board gives the error; Swift does not make a new board in a `.kanban/` with Rust files.
  - Change the plan: §2.2, §4.4 (the new error code; the list has 21 codes now), §5.2, and §12 item 11.
- Q7: a related board that cannot be read does not stop the call or the change feed.
  - Change the code: `S/Tool/KanbanGraph.swift:761-775` (`loadRelatedBoard`) and `:433-446` (`publishLiveChanges`), and `S/Tool/Commit.swift:409-410`. Catch the error for each board, mark the board as not loadable, and add a warning to the response.
  - Add tests: a related board with no read permission; a related board with a broken log; a subscriber that still gets changes of the current board.
  - Change the plan: §6.6 and §6.7.
- Q8–Q15: parameter names.
  - Change the code: `S/GraphQL/NameRewrite.swift`, `S/GraphQL/NameMatcher.swift`, and the alias table at `S/GraphQL/Schema.swift:1002-1013`.
    - Q8: rewrite the keys in `variables` at all depths, by the input type of each variable.
    - Q9: move the aliases to a table for each input type. Keep a global table only for names that are safe everywhere. Add the synonyms in 4.3. Remove the global `task_id → id`. Also move the global aliases `assignee → assignees` and `status` (`S/GraphQL/Schema.swift:1008-1009`) to the tables for each input type. On `assignTask` and `unassignTask`, `assignee` maps to `actor` (4.3), so a global alias gives `AMBIGUOUS_NAME` or a wrong target.
    - Q10: add the root query verbs.
    - Q11: map `createBoard` and `newBoard` to `initBoard`.
    - Q12 (changed by P4): when no name matches, list the canonical fields of the type. Ignore each removed Rust parameter, and give a "removed, use X" warning.
    - Q13: split a JSON array in a string for list fields.
    - Q14: add `blockedBy` as a synonym for `dependsOn` on input types.
    - Q15 (replaced by P2 and K15): `priority`, `prio`, and `urgent` move the task in its column by the fixed value table in K15 (section 15), with a warning. A bare number or an unknown value makes no move.
  - Add tests: each row of the tables in 4.2 and 4.3, in the document text and in `variables`.
  - Change the plan: §4.5.
- Q16: operation behavior.
  - Change the code: `S/GraphQL/ColumnActorMutations.swift:242-244`. With `ensure: true`, update the name, the color, and the `avatar`, and undelete the actor. Add tests.
  - Change the plan: §4.2. Write the three rules of Q16 there, with the third rule from P1 (an unknown `before`/`after` ref puts the task at the end of the column, with a warning).
- Q17: `null` on a required text field (`title`, column `name`) is ignored.
  - Change the code: the update mutations in `S/GraphQL/TaskMutations.swift`, `S/GraphQL/ColumnActorMutations.swift` (column and actor `name`), and `S/GraphQL/TagMutations.swift` (tag `name`). Change the tests `T/Mutations/AddUpdateTaskTests.swift:651-660` and `T/Mutations/ColumnActorTests.swift:382-390`.
  - Change the plan: §4.2, §6, and §11 (the rule "`null` clears a field").
- Q18: no code change. Write in plan §3.2 that a column or actor ref can be the display name.
- Q19: add back the Rust fields.
  - Change the code: `S/Model/ActorNode.swift` and the actor mutations (`avatar`); `S/Model/BoardNode.swift` and `BoardInput` (`model`); `S/Derived/Summary.swift` (`totalActors`, and `taskCount` and `readyCount` for each column); `S/Derived/Progress.swift` (`percent`); `S/Derived/VirtualTags.swift` (color and description); `S/GraphQL/Schema.swift`. Add tests.
  - Change the plan: §4.1 and §6.
- Q20: a short id that two nodes share resolves to the first match.
  - Change the code: the canonical short-id branch of `S/Identity/ShortID.swift:109-112` (keep the prefix branch), `S/Identity/RefResolver.swift:127-129,384-424` (`checkShortIDIsUnique`, `ulidRef`), `S/Filter/FilterEvaluator.swift:322-326` (match all), and `S/GraphQL/Errors.swift:24-26,124,162,264-270` (`sharedShortID`). Fix the doc comments at `S/Filter/FilterEvaluator.swift:7-8`, `S/Observe/ChangeFeed.swift:112`, `S/Observe/ChangeFilter.swift:63`, `S/Observe/ChangeSubscription.swift:44`, and `S/GraphQL/TaskSelection.swift:8,44`. Also fix the doc comments that name `sharedShortID` or `AMBIGUOUS_ID` at `S/Identity/RefResolver.swift:21,36,381-382,409` and `S/Filter/FilterEvaluator.swift:44,95,121,316,320`. Order: live before tombstone, then lowest ULID.
  - Change the tests: `T/Identity/SharedShortIDTests.swift`, `T/Identity/ShortIDTests.swift:134` (`sharedShortIDIsAmbiguous`), and `T/GraphQL/KanbanErrorTests.swift:135-156`.
  - Change the plan: §3.2 and §6.3. In §4.4, keep `AMBIGUOUS_ID` for ULID prefixes and names.
- Q21: add a move and a copy of a task to a different board.
  - Change the code: a `board` field on `moveTask`, and a new `copyTask` mutation in `S/GraphQL/TaskOperationMutations.swift`. Write events on both boards in one transaction, under the locks of both boards. Change local refs to full URIs. Make each missing tag on the target board (E6). A move adds a line to the old task body that points to the new URI (E6).
  - Add tests: move and copy across two repos; dependencies still resolve after a move; dependents on the old board; undo of a move across boards.
  - Change the plan: §4.2 and §6.6.
- Q22: **NOT DONE (K10).** Rust boards are refused (Q6), so no existing board has the bad git files. The text below is history only. Fix the git files of a board.
  - Change the code: `S/Events/EventLog.swift:137-150` (`prepareDirectory`). Change the test `T/Events/EventLogTests.swift:270-279`, which now checks that an existing file is not changed.
  - Change the plan: §5.2.
- Q23: crash safety for transactions on many files.
  - Change the code: `S/Events/EventLog.swift:158-167` (fsync after append), `S/Events/Event.swift:21-50` (an optional file count), `S/Events/Replay.swift` / `S/Events/Loader.swift` (skip a transaction that is not complete), and `S/Observe/LiveGraph.swift:165` (`reload`, which reloads one node and so must also check the transaction).
  - Add tests: a transaction with one file cut off is not applied; a complete transaction is applied; an old line with no count is applied.
  - Change the plan: §5.1, §5.3, §5.4, and §5.6.
- Q24: no code change. Write in plan §5.4 that the lock waits with no time limit.
- Q25: the filter accepts `^<title-slug>` and `^^short`.
  - Change the code: `S/Filter/FilterParser.swift:35-37,221-223` (allow `^` after `^`) and `S/Filter/FilterEvaluator.swift:397-408` (`isReferenced`: match the slug of the task title). In a filter, `^<title-slug>` matches all tasks with that slug (C3). Rust keeps only the last task (`R/task_helpers.rs:750-761`).
  - C3 also accepts a title slug as a task ref in a mutation or a query for one task (first match). Rust does not do this: `resolve_task_ref` accepts only a ULID or a short id (`R/dispatch.rs:121-132`). Change the code: `S/Identity/RefResolver.swift` (a new title-slug step, after the ULID and short-id steps). Open point: see E4 in section 13 (the resolve order).
  - Add tests for both forms, for a shared title slug in a filter, and for a title-slug ref in a mutation.
  - Change the plan: §3.2 (the title-slug ref), and §6.3 (the grammar, the list of id forms, and the note that "match all" is different from Rust).
- C4: `updateTag` with a `name` whose slug is different does a `renameTag`.
  - Change the code: `S/GraphQL/TagMutations.swift:113-128` (the resolver and the doc comment). Add tests: a new slug makes a redirect and changes the markers; the same slug changes only the display name.
  - Change the plan: §4.2 and §6. Plan.md:306 says "`updateTag` does not change the slug", and plan.md:576 says "A display name does not change a slug, so `updateTag` accepts the name `Done`". C4 changes both.
  - Open point: see E1 in section 13 (the edge cases).
- Q26: no code change. Write in plan §6 that a marker continues through `_`, and that a tag that a marker creates gets a lowercase name.

Bugs:

- X4: a board that was reached by a path does not go into the key index.
- X5: undo across boards reverses part of a transaction. It must write nothing when it cannot reach a board.
- X6: undo has no conflict check across boards.
- X7: `undeleteTask` and undo of a delete do not run the cycle check.
- X8: a cycle across boards does not block.
- X10: the scan runs again on each call for a key that has no board.
- X13: the watcher of a related board must watch only `.kanban/`, or the plan must say why it watches the repo directory.
- §8: list the files that the plan does not list.
- S3: event ids do not always increase from one call to the next. Start each call after the largest id in the log.
- S4: replay drops the whole line for one bad value. Skip only that value.
- The doc comment in `S/Derived/VirtualTags.swift:7-8` says "case-sensitive", but the match does not use case.
- R17: the tool description does not mention dependencies between repos. The schema has no field descriptions.
- R18 (new): the public resolver does not accept the stored local form `<type>/<id>` (for example `task/01K6Z3…`, `column/todo`, `tag/bug`).
  - The logs store each ref in this form (`LocalRef`), and plan.md:392 shows it in a `dependsOn` example. Only the internal `patch` mutation parses it (`LocalRef(parsing:)`, `S/Identity/LocalRef.swift:85,190`).
  - `RefResolver` treats each text that is not a `kanban://` URI as a short form (`S/Identity/RefResolver.swift:213-216`). For a task, `task/01K6…` is not a ULID form, so `ulidRef` finds nothing (`:347-348`). For a column, an actor, or a tag, the slug rule makes `column/todo` into `column-todo` (`:341-346`), which names no node. The result is `NOT_FOUND`. This was found by reading the code; no test was run.
  - Fix ("very forgiving"): in `RefResolver.target(of:)`, accept `<type>/<id>` as a ref in the default board (or the board of `board:`), the same as a URI with the key of that board. The `<id>` part takes each short form of that type (a full ULID, a short id, `^short`, a ULID prefix, a slug, or a name). A type that is not the expected type gives `NOT_FOUND`, the same as a URI of the wrong type.
  - Add tests: `task/<ULID>`, `task/<short id>`, `column/todo`, `tag/bug`, and `actor/<slug>` resolve; `column/todo` where a task is expected gives `NOT_FOUND`; `node(id: "task/<ULID>")` gives the task.
- R18a (new, DECIDED): the tag list of `addTask`, `updateTask`, `tagTask`, and `untagTask` does not use the resolver for a text that is not a URI. Each such text goes to the tag name rule (`TagName(normalizing:)`). Thus `tags: ["tag/bug"]` makes or names the tag `tag-bug`, not the tag `bug`. Found during R18.
  - Decision ("very forgiving"): a tag text that starts with `tag/` is the stored local form. The text after `tag/` is the tag name or the slug, so `tag/bug` names the tag `bug`, and makes it when the board has no such tag. The type segment ignores case (`Tag/Bug` gives the tag name `Bug`), and white space at the two ends of the text and of the slug is ignored, the same as R18.
  - A text with `/` that does not start with `tag/` stays a tag name, for example `area/backend` (tag name `area/backend`, slug `area-backend`). A text that starts with a different node type, for example `column/todo`, also stays a tag name.
  - `tag/` with no slug gives `INVALID_TAG_NAME` with the text as the caller wrote it.
  - The check uses the same split as R18 (`RefResolver.localID(inStoredLocalForm:ofType:)`), in `RefResolver.tag(named:includingTombstones:)` (`S/GraphQL/TaskMutations.swift`).
  - Tests: `Tests/FoundationModelsKanbanTests/Mutations/StoredTagRefTests.swift`.
- F9 (section 15): sort `Task.tags` by slug.
- S7 (section 15): a directory path inside `.kanban/` starts the full compare (`S/Tool/Commit.swift:346`).
- The missing tests listed in sections 1–3 (K14: keep all, as one test task). Leave out only "a related board that cannot be read", because the Q7 tests cover it. The fixes for X4, X5, and X6 each need their test from that list.

---

## 12. Open points from the double check

The double check found four points where the decisions conflict, or where a decision is not complete. The user decided all four points (see DECIDED in each point).

**C1. What does `#BLOCKING` give after Q1?**

- The Rust skills use `#BLOCKING` (`../swissarmyhammer/builtin/skills/kanban/SKILL.md:81`, `../swissarmyhammer/builtin/skills/finish/SKILL.md:58`).
- Plan §6.3 says that a Rust filter gives the same result in Swift.
- After Q1, BLOCKING is not a virtual tag and not a reserved name. Then `#BLOCKING` matches only a real tag named `blocking`, and that is usually nothing.
- Options: (a) `INVALID_FILTER` with a message that BLOCKING is removed; (b) `#BLOCKING` matches nothing, with no error; (c) keep BLOCKING as a reserved name only, so that no real tag can take it.
- **DECIDED:** none of the options. BLOCKING is not special in Swift. `#BLOCKING` is an ordinary tag filter, and a user can make a real tag named `blocking`. Do not add a special error or a reserved name. The user said that the skills never had to use BLOCKING. (The Rust tool has BLOCKING, `R/virtual_tags.rs:254-262`, so the skills work with Rust now.) When Swift replaces the Rust tool, remove BLOCKING from the skills, and use `#BLOCKED` or the dependencies. The change list is in section 11.

**C2. Q6 (delete an old Rust board) does not work on the real boards as written.** **REPLACED:** the final Q6 decision removes the delete. Swift only finds an incompatible board and stops with an error. The text below is history only.

- `FoundationModelsKanban/.kanban/search-cache.sqlite3` is git-ignored, so git never tracks it. `.kanban/mcp.17281.log` is untracked. With the rule "git tracks all of them", Swift always refuses this repo.
  - Proposal: the git check skips git-ignored files, and Swift deletes them with no check. Treat `mcp*.log` the same way.
- The detection list does not name `projects/`, `views/`, or `.gitconfig`. `.gitconfig` holds the Rust merge drivers.
  - Proposal: delete `.gitconfig`. Keep only `.gitattributes` and `.gitignore`, and fix them (Q22).
- A related board (another repo) can also be a Rust board. A write that reaches it through a dependency would then delete that repo's data.
  - Proposal: delete a Rust board only for the current board of the call. For a related board, do not delete; treat its dependencies as not found (Q7).
- **DECIDED:** accept all three proposals.
  - The git check skips git-ignored files and `mcp*.log` files. Swift deletes them with no check.
  - Swift also deletes `.gitconfig`, `projects/`, and `views/`. It keeps `.gitattributes` and `.gitignore`, and fixes them (Q22).
  - Swift deletes a Rust board only when it is the current board of the call. Swift does not change a related Rust board. Its dependencies are "not found", and the response gives a warning (Q7).

**C3. A title slug that two tasks share in the filter (Q25 and Q20).**

- Rust keeps only one task for each title slug, and the last task wins (`R/task_helpers.rs:750-761`).
- Q20 says "first match" for a short id in mutations, and "match all" in a filter.
- Options for `^<title-slug>`: (a) match all tasks with that slug, as for a short id in a filter; (b) use the first match (live before tombstone, then lowest ULID).
- **DECIDED:** use the Q20 rule for a short id. In a filter, `^<title-slug>` matches all tasks with that slug. In a mutation or a query for one task, it uses the first match (live before tombstone, then lowest ULID).

**C4. `updateTag {id, name}` with a new name.**

- In Rust, this call renames the tag: the slug changes, and the `#old` markers change (`R/tag/update.rs:76-98`).
- In Swift, the call runs, but it changes only the display name. The slug stays. An agent that uses the Rust form thinks that it renamed the tag, but it did not.
- Options: (a) when `updateTag` gets a `name` whose slug is different, do a `renameTag` (a redirect, plan §6.2); (b) keep the current behavior, and add a warning in the response that says to use `renameTag`; (c) keep the current behavior with no warning.
- **DECIDED:** (a). When `updateTag` gets a `name` whose slug is different from the current slug, it does a `renameTag` (a redirect, plan §6.2). When the slug is the same, `updateTag` changes only the display name.

---

## 13. Open points from the second check

The second check found these points. The decisions in sections 10 and 12 do not answer them. Each point has a proposal.

**E1. The edge cases of C4 (`updateTag` with a new slug).**

- The new slug already exists. `renameTag` then merges the old tag into that tag (`S/GraphQL/TagMutations.swift:250-253,267-268`).
- The new slug is reserved (`board`) or is a virtual tag name (for example `Done` gives `done`). `renameTag` then gives `INVALID_TAG_NAME` or the virtual-tag error.
- The same call also sets `color` or `body`.
- After C4, a display name whose slug is different from the tag slug cannot be set. Example: the tag `bug` cannot get the display name "Defect".
- Proposal: do the same as `renameTag` in all cases (merge, and the same errors). Apply `color` and `body` to the tag at the end of the rename. Accept that a display name must give the same slug.
- **DECIDED:** accept the proposal. `updateTag` with a new slug does the same as `renameTag`: a merge into an existing tag, and the same errors. `color` and `body` go to the tag at the end of the rename. Add tests for the merge, the reserved slug, the virtual tag name, and `color` in the same call.

**E2. A write to a related board that is a Rust board.** **REPLACED:** the final Q6 decision. Any incompatible `.kanban/`, also a related one, stops the call with an error. The text below is history only.

- C2 says that Swift does not change a related Rust board. But some writes name a board directly: a mutation with `board:` (for example `S/GraphQL/ColumnActorMutations.swift:238`), and Q21 `moveTask(board:)` and `copyTask`.
- Plan.md:814 makes a new board in a related repo that does not have one. A Rust board has `boards/board.jsonl`, not `board.jsonl`, so Swift does not see it as a board. Then the write adds Swift events into the Rust files.
- Q3 gives `NOT_FOUND` when the board is found and the task is missing. It is not clear if a dependency on a task in a related Rust board gives `NOT_FOUND` or is accepted.
- Proposal: a write that names a related Rust board gives the Q6 error (`RUST_BOARD_NOT_CLEAN`, or a new code), and changes nothing. Do not make a new board where Rust files are. A `dependsOn` URI to a related Rust board is accepted, as for a board that is not found (Q3), and shows in `unresolvedDependsOn`.
- **DECIDED:** accept the proposal. A write that names a related Rust board gives the Q6 error and changes nothing. Swift never makes a new board in a `.kanban/` that has Rust files (change plan.md:814). A `dependsOn` URI to that board is accepted and shows in `unresolvedDependsOn`. Add tests for a mutation with `board:`, for `moveTask(board:)`, for `copyTask`, and for a `dependsOn` URI.

**E3. A Rust MCP server that is running.** **REPLACED:** the final Q6 decision. Swift deletes nothing, so a running Rust server is not a risk. Its `mcp*.log` file is one of the signs of an incompatible board. The text below is history only.

- A file `mcp.<pid>.log` shows that a Rust kanban MCP server runs. One runs now in this repo (`.kanban/mcp.17281.log`). After Swift deletes the Rust board, that server can write Rust files again (S1).
- Proposal: refuse the delete when an `mcp.<pid>.log` file belongs to a live process. The error tells the user to stop the Rust server.

**E4. The resolve order for a title-slug ref (C3).**

- C3 accepts a title slug as a task ref in a mutation. A ref field that takes many types (G2) can then match a task title slug and a column or tag slug.
- Proposal: in a field that takes only tasks, try the ULID, then the short id, then the title slug. In a field that takes many types, a title slug comes last, after all other slugs.
- **DECIDED:** accept the proposal. Add tests: a title slug in a task field; a title slug that is the same as a column slug in `node(id:)` gives the column.

**E5. Three rows of table 4.2 have no fix in table 4.3.**

- `updateTask` with `column`: Rust ignores the key, and Swift refuses the whole call.
- Column operations with `column` in place of `id`: Rust accepts `column` for get, update, and delete column (`R/dispatch.rs:442,446,457`). Table 4.3 maps `<type>Id` and `task` to `id`, but not `column`.
- `updateComment` and `deleteComment` with `task_id` or `task`: Rust needs `task_id` for each comment operation (`R/dispatch.rs:1222`). After Q9 removes the global `task_id → id`, the Rust form fails on an unknown field.
- Proposal:
  - Map `column` to `id` on column operations (4.3).
  - On `updateTask`, give an error that says "use `moveTask` with `column`". Do not ignore it, because an agent that sends it wants a move.
  - On `updateComment` and `deleteComment`, accept `task_id` and `task` and ignore them, because the comment `id` alone finds the comment. (Option: check that the comment is on that task, and give `NOT_FOUND` if not.)
- Then add these rows to 4.3, so that the tests in section 11 (Q8–Q15) can pass.
- **DECIDED:** forgive all (not the proposal).
  - `updateTask` with `column` also moves the task to that column (at the end), in the same transaction. This is different from Rust, which ignores the key.
  - Column operations map `column` to `id`.
  - `updateComment` and `deleteComment` accept `task_id` and `task`. Swift checks that the comment is on that task, and gives `NOT_FOUND` if not.
  - Add these rows to 4.3. Add tests for each row, in the document text and in `variables`. Change plan §4.2 (`updateTask`) and §4.5.

**E6. The two proposals in Q21 (move and copy across boards).**

- A tag marker in the body makes the tag on the target board.
- A move adds a line to the old task body that points to the new URI.
- Proposal: accept both. Then add them to the Q21 change list in section 11.
- **DECIDED:** accept both.
  - A move or a copy keeps all tags. Swift makes each missing tag on the target board (this is different from Rust, which drops them).
  - A move adds a line to the old task body that points to the new URI.
  - Add tests for both. Change the Q21 change list in section 11.

---

## 14. Decisions to check against "be VERY FORGIVING"

These decisions give an error where a forgiving rule can do the work. Each point has a proposal. The user must decide each point.

**P1. An unknown `before` or `after` ref (Q16).**

- Now: `NOT_FOUND`. Rust puts the task at the end of the column (O3).
- Proposal: do as Rust does. Put the task at the end of the column, and give a warning that names the ref.
- **DECIDED:** accept the proposal. This replaces the third rule of Q16. Change the Q16 change list in section 11 and plan §4.2. Add a test.

**P2. `priority` in an input (Q15).**

- Now: an error that says "use `moveTask` with `before`/`after`".
- Proposal: do the work. `high`, `urgent`, or `1` moves the task to the top of its column. `low` or a large number moves it to the end. `medium` makes no move. The response gives a warning that says the position in the column is the priority.
- **DECIDED:** accept the proposal. This replaces Q15. Change the Q15 line in section 11 and the `priority` row in 4.3. Add tests for `high`, `urgent`, `1`, `low`, `medium`, and a large number.

**P3. A `dependsOn` URI to a missing task on a board that Swift found (Q3).**

- Now: `NOT_FOUND`.
- Proposal: accept the URI. It shows in `unresolvedDependsOn` (Q2) and blocks the task, and the response gives a warning. A typo then does not stop the agent, and the agent sees the problem.
- Risk: a typo blocks the task until someone fixes it.
- **DECIDED:** accept the proposal. This replaces the first rule of Q3. A URI to a missing task is stored, shows in `unresolvedDependsOn`, blocks the task, and gives a warning. The same applies to a task URL in the body. Change the Q3 change list in section 11 and plan §6.6.

**P4. An input field that matches no name, or a removed Rust parameter (Q12, N5).**

- Now: the whole call fails, with a list of the fields of the type, or a "removed, use X" message.
- Proposal: for a removed Rust parameter (`project`, `due`, `scheduled`, `exclude_done`, `page`, `detail`, `include_counts`, `attachments`), ignore it and do the call, with a warning. For a name that matches nothing, keep the error, because Swift cannot know what the agent wanted to set.
- **DECIDED:** accept the proposal. This changes Q12: a removed Rust parameter is ignored, and the response gives the "removed, use X" text as a warning. A name that matches nothing still fails, and the error lists the canonical fields of the type. Add a test for each removed parameter.
- **DECIDED (^164tehz):** when the value of a removed parameter is a variable, and the document reads that variable at no other place, the rewrite also takes out the definition of the variable. When no definition stays, the rewrite takes out the parentheses too. A read in an argument, in a directive, or in a fragment that the operation spreads keeps the definition. A variable that the caller defined and did not read keeps its definition, and validation still reports it. The value of the variable in `variables` stays; the engine ignores it.

**P5. A ULID prefix that matches more than one ULID (Q20).**

- Now: `AMBIGUOUS_ID`.
- Proposal: keep the error, because the input has two meanings. Add the matching ids to the error, so that the next call can succeed.
- **DECIDED:** accept the proposal. `AMBIGUOUS_ID` lists the matching ids and titles. Add a test.

**Warnings (DECIDED with P1–P4).** Use one list for all warnings in the response (for example, `extensions.warnings`). Q7, P1, P2, P3, and P4 write to it. Change plan §4.4. Add tests that each warning shows in the response.

---

## 15. Work that we can NOT DO

**DECIDED by the user:**

- 15.1: keep all features. K1, K2, K3, K4, and K5 stay as decided in sections 10–14.
- 15.2: cut only K10 (Q22 is not done). K6, K7, K8, K9, and K11 stay as work to do.
- 15.3 and 15.4: decided one item at a time:
  - G6: accept. No work.
  - G7: accept. No work.
  - F7: accept. No work.
  - F8: accept. No work.
  - F9: fix. Sort `Task.tags` by slug, as Rust does. Add a test.
  - F10: accept. No work.
  - F11: accept. No work.
  - S7: fix. In `S/Tool/Commit.swift:346`, a path that is a directory inside `.kanban/` starts the full compare, the same as `.kanban/` itself. Add a test that moves `.kanban/tasks/` and checks that the live graph changes.
  - X11: accept. No code work.
  - K13: not done. `plan.md` will not be updated (see the note at the start of section 11).
  - K14: keep all the missing tests of sections 1–3, as one test task in section 11.
  - K15: keep P2, with a fixed value table (case does not matter). `urgent`, `critical`, `high`, `P0`, `P1`, and `urgent: true` move the task to the top of its column. `low`, `P3`, and `P4` move it to the end. `medium`, `normal`, and `P2` make no move. A bare number, or any other value, makes no move. Each case gives a warning. Add a test for each row of the table.
  - K16: keep E5 as decided. `updateComment` and `deleteComment` accept `task_id` and `task`, check that the comment is on that task, and give `NOT_FOUND` if not. Rust also fails in this case (`R/comment/update.rs:44`, `R/comment/delete.rs:41`).

This section lists the work in sections 10–14 that we can drop. The reasons: the user is the only user of `.kanban`; an agent does the work and does not need extra views; git is the backup; and Swift now refuses an old Rust board (Q6). Each item has a recommendation. "Cut" means: do not do the work, and write no plan change for it.

### 15.1 Features to cut

- **K1. Q21 + E6: move and copy of a task to a different board.** This is a large feature: one transaction on two boards under two locks, a URI rewrite, tag creation, a pointer line, and undo across boards. An agent can do the same with `addTask` on the other board and `deleteTask` on the old board. **Recommendation: cut.** (G8 then stays as a known difference from Rust.)
- **K2. Q19: add back the Rust fields** (`avatar`, `model`, `totalActors`, `taskCount`, `readyCount`, `percent`, and the color and description of each virtual tag). An agent does not need them: it can count with a query, and colors are for a human UI. **Recommendation: cut.** Then Q16 does not update `avatar`.
- **K3. Q23: crash safety** (fsync, and a file count in each transaction line, with a check at load and in `LiveGraph.reload`). A crash in the middle of a transaction is rare, and git can restore. This change touches the event format and the loader. **Recommendation: cut.** S5 stays as a known limit.
- **K4. C3 + E4: a title slug as a task ref in a mutation.** Rust does not do this. It adds a new resolve step and an order rule. Agents get ids from each response. **Recommendation: cut.** Keep `^<title-slug>` in the filter only (Q25), because Rust has it.
- **K5. Q8: rewrite the names in `variables` at all depths.** The user had no preference. Agents send literal arguments in most calls. **Recommendation: keep**, because of the "very forgiving" principle. (Cut it if the work is large.)

### 15.2 Bugs and fixes to cut

- **K6. X5 and S8: undo on a second copy (worktree) of the same repo.** This needs two copies of one repo, both with boards, and a transaction across them. **Recommendation: cut.** Write it as a known limit.
- **K7. X6: undo conflict check across boards.** The undo in one board has the check. Across boards, the result is only that a dependent becomes READY. **Recommendation: cut.**
- **K8. X4: a board reached by a path outside the scan places does not go into the key index.** This needs a `board: "/some/path"` outside the scan. **Recommendation: cut.**
- **K9. Performance items: X10 (the scan runs again for a missing key), R9 (all related boards load on each call), and the `isReady` walk.** No one measured a problem. **Recommendation: cut until a measurement shows a problem.** Update nothing.
- **K10. Q22: fix the git files of an existing board.** The bad merge line comes from Rust boards, and Swift now refuses Rust boards (Q6). A Swift board already gets the correct files. **Recommendation: cut.**
- **K11. X13: the watcher of a related board that has no `.kanban/` watches the repo directory.** It only reads. **Recommendation: cut.**

### 15.3 Items that need no work (accept as they are)

- **K12. Small differences from Rust: G6, G7, F7, F8, F9, F10, F11, S7, X11.** These have a low impact, and no agent depends on them. **Recommendation: accept them, and do no work.**
- **K13. Plan updates for the layout (§8a) and for F4.** These are document changes only. The user said not to change the plan now. **Recommendation: cut.**
- **K14. The long lists of missing tests in sections 1–3.** Many tests cover items that the cuts above remove, or that Q1 removes. **Recommendation: keep only the tests for the work that we do. Each change in section 11 already lists its tests.** Cut the separate lists.

### 15.4 Simpler forms of decided work

- **K15. P2: `priority` moves the task.** Simpler: ignore `priority` and give a warning (the option "Ignore + warning" in P2). The move needs rules for many value forms. **Recommendation: keep P2 as decided only if the user wants it; the simple form is less work.**
- **K16. E5: the comment check.** Simpler: accept `task_id` and `task` on `updateComment` and `deleteComment`, and ignore them, with no check that the comment is on that task. **Recommendation: use the simple form.**

---

## 16. Many ACP agent sessions in one process

**The use:** one ACP agent process runs many sessions at the same time. Each session has its own working directory (`CatalogContext.workingDirectory`). Many sessions can use the same repo, a worktree of the same repo, or a subfolder of a repo. All sessions are in the same process.

**The design now:**

- Plan §9 item 4 makes one `KanbanGraph` in `ToolCatalog.makeRegistry(context:)`. That function runs once for each session. Thus N sessions make N engines.
- A `KanbanGraph` has one current board (`root`), and it loads the related boards itself (`relatedBoards`, `S/Tool/KanbanGraph.swift:84`). Each engine has its own live graph, file watchers, serial gate, change feed, and search index.
- The session actor is fixed when the engine starts. The default is the OS user (plan §6, plan.md:582).

**The problems that this gives.** Each one was checked against the code and the plan:

- **M1. The same board is loaded many times.** Two sessions in one repo give two live graphs of the same board, with two watchers, two search indexes (with embeddings), and two serial gates. Each related board is also loaded once for each session. The memory and the watcher count grow with the session count.
- **M2. A write in one session reaches another session late.** A write is safe, because the commit compares the file signatures under the board lock (`S/Tool/Commit.swift:512`). But session B sees the write of session A only after FSEvents reports it. Until then, B gives an old `nextTask`, old `ready` values, and an old change feed.
- **M3. Two agents can take the same task.** `nextTask` is a read. Two sessions that call it at the same time get the same task, and both start it. This is true also with one shared engine, because the read and the later `moveTask`/`assignTask` are two calls.
- **M4. `undo` crosses sessions.** `undo` with no argument reverses the newest transaction of the session actor (plan.md:762). When all sessions use the default actor (the OS user), an `undo` in session B can reverse the work of session A.
- **M5. A session in a subfolder makes a new board.** The board is always `<working dir>/.kanban/`, and the tool does not search up (plan §3.2). A session that starts in `repo/Sources/` sees an empty board. Its first write makes a new board in `repo/Sources/.kanban/`, apart from the board of the repo.
- **M6. Worktrees have separate boards with the same key.** A session in each worktree of one repo has its own `.kanban/`, with the same key. Their boards join only through git (union merge). Until a merge, each agent sees only its own copy. Related refs with that key go to the first copy in scan order (plan §12 item 26). This is the design of the plan, but with many agents in worktrees it decides what each agent can see.

**Proposal: one host object for the process, and one light view for each session.**

- **`KanbanHost`** (a new public actor), made one time when the agent process starts, and given to each session through `CatalogContext`:
  - It keeps one engine for each board, by the real path of its `.kanban/` directory. Each engine has one live graph, one watcher, one serial gate, one search index, and one change feed.
  - It keeps the board locator and the scan index, one time for the process.
    - It keeps a reference count for each board. ~~A board unloads when no session needs it, or at `close()`.~~ **Replaced by the cache rule below:** a loaded board stays in memory until the host closes.
- **`host.session(workingDirectory:actor:)`** gives a `KanbanGraph` view for one session:
  - The current board is the board of the working directory. The actor is the actor of the session.
  - The public API does not change: `execute`, `subscribe`, `close`, and `KanbanTool.init(graph:)`. `close()` of a view releases its references and does not stop a board that another session uses.
  - A write in one session goes to the shared engine, so each other session sees it at once (M1, M2).
- **Locks across boards:** a call that writes more than one board takes the gates of those boards in a fixed order (by path), so two sessions cannot deadlock.
- **Changes in FoundationModelsACPAgent** (a separate change in that repo): make the host one time at process start, add it to `CatalogContext`, and in `makeRegistry(context:)` call `host.session(workingDirectory: context.workingDirectory, actor: <session actor>)`.

**DECIDED (the user):** accept the host design. "We really don't want one process loading up the same board multiple times, and we really want each session to know and work on its default board from its cwd."

- One process loads each board one time only (M1, M2).
- **Hard rule from the user: "it's really important to me that each board, its file watchers — are only loaded once per process."** The design must make a second load impossible, not only unlikely:
  - **One host for each process.** `KanbanHost.shared` is the only way to get a host. There is no public `init`. Thus two hosts cannot exist in one process.
  - **One identity for each board.** The host keys each board by the file identity of the board folder (the device and inode of the folder that holds `.kanban/`), not by its path text. Thus a symlink, `/tmp` against `/private/tmp`, a `..` in the path, or a different letter case on APFS gives the same board.
  - **One engine for current and related boards.** A board that is the current board of one session and a related board of another session is the same engine. The host has one table of engines. The split today, between the current session (`loadState`) and `relatedBoards` in `S/Tool/KanbanGraph.swift:74,84`, goes away.
  - **One watcher for each board.** The engine owns the watcher, and the watcher starts and stops only with the engine. This includes the watcher on the repo folder before `.kanban/` exists (X13).
  - **Load once under concurrency.** Two sessions that open the same board at the same time wait for one load. The host keeps the load task in its table before the first `await`.
  - **Hard rule from the user: "it's also important to me that the boards are fully cached in memory."**
    - A loaded board stays in memory until the host closes. A board does not unload when its last session closes.
    - A read (a query, `nextTask`, a filter, search) reads no file and runs no `git`. It uses only memory.
    - The file watcher is the only way that changes from outside the process reach memory.
    - **What the code does now, checked against this rule:**
      - **Good:** the live graph, the events, and the bodies of a loaded board are in memory (`LiveGraph`). A loaded related board stays loaded (`relatedBoards`, `S/Tool/KanbanGraph.swift:84`).
      - **Gap 1, `git` on reads:** a board ref or a `dependsOn` URI that names no known board starts a new scan on each call (`S/Tool/KanbanGraph.swift:720`, X10). The scan runs `git` in each repo that it finds. With P3, a URI with a typo is stored, so each call that reaches that task runs the scan again. Fix: keep the "not found" result in memory, and scan again only when a watcher sees a new folder in a scan place.
      - **Gap 2, lazy first load:** the current board loads at the first call of a session, not when the session starts (`S/Tool/KanbanGraph.swift:543-551`). Thus the first call waits for the load.
        - **DECIDED: detect and load at session start, and wait.** `host.session(workingDirectory:actor:)` does these steps before it returns:
          1. `git rev-parse --show-toplevel` in the working directory gives the top folder of the worktree. Not in a git repo: no board, and each kanban call gives `NOT_A_REPO`.
          2. A repo with no commit gets the empty first commit (M8).
          3. The key: the `origin` remote, else `local/<root commit>` (M7).
          4. The host finds the engine of `<worktree top>/.kanban/` by file identity, or makes it (one watcher).
          5. The host loads the board content (the logs, the graph, and the search index) if it is not loaded yet, and waits for the load. A second session on the same board waits for the same load.
        - Then the board is in memory before the first kanban call. A board that cannot load (for example an incompatible Rust board, Q6) makes the session start fail with that error.
        - Related boards still load when a call first reaches them, and then stay in memory.
        - Add tests: the board is loaded when `host.session` returns; two sessions that start at the same time load the board one time; a Rust board makes `host.session` fail.
  - **Rule from the user: "I want the board to be in memory all the time with write through — and file watch detection to allow manual poking of files."**
    - Memory is the source for each read. A write goes to the log files and to memory in the same commit (write through). The code does this now: the commit appends under the lock, and then the working copy becomes the live graph (`S/Tool/Commit.swift:525-552`).
    - The file watcher brings each change from outside the process into memory: a manual edit, a `git pull`, a merge, or another process. S7 (a moved folder) is a fix for this path.
    - The commit also compares the file signatures of the board under the lock before it writes (`S/Tool/Commit.swift:537-540`). This is a safety net for a manual edit that the watcher has not reported yet. Keep it.
  - **Rule from the user: "we do need our board load to be as parallel as possible."** What the load does now, and what to change:
    - **L1. Git and the file load run one after the other.** The key read (and the first commit, M8) run before the load starts. The log does not store the key, so the load does not need it. Change: after `git rev-parse --show-toplevel` gives the folder, run the key read, the watcher start, and the file load at the same time.
    - **L2. Six stages with a barrier after each.** The loader reads the files of one node type at a time: board, actors, columns, tags, tasks, comments (`S/Events/Loader.swift:44,109-119`). Each stage waits for its slowest file before the next stage starts. But each file folds alone (`log.readLog(of:)`, `:171`). Only the join needs the stage order. Change: one worker pool reads and folds all files of all types; then the join runs in stage order, in memory. This removes five barriers.
    - **L3. The directory listings run one after the other** (`:151-156`, one for each node type). Change: list the six folders at the same time.
    - **L4. The search index runs after the load.** `loadSession` loads the graph, then calls `updateSearch()` and waits (`S/Tool/KanbanGraph.swift:567-577`). `MetadataSearcher.update(items:)` waits until the embeddings of all tasks are done. Change: start the search update as soon as the task nodes exist, at the same time as the event merge and the other work.
      - **DECIDED: the session is ready when the graph is loaded.** `host.session(...)` waits for the files, the graph, the event list, and the keyword index (BM25 and trigram). It does not wait for the embeddings. They finish in the background, and `searchTasks` uses the keyword scores until then (`MetadataSearcher+Search.swift:92-95`). Add a test: `host.session` returns before a slow embedder finishes, and `searchTasks` gives keyword hits at once.
    - **L5. Related boards load one at a time.** The loop answers one board request at a time (`S/Tool/KanbanGraph.swift:604-607`). Change: load all requested boards at the same time.
    - **L6. Sessions on different boards must load at the same time.** The host must not hold its actor during a load. It keeps a load task for each board in its table, and the load runs outside the actor.
    - Add tests: the worker observer shows that the files of all types are read in one pool; two boards load at the same time; the key read and the file load overlap.
      - **Gap 3, readiness is not cached (closed by ^zmyzzfw):** `ready` and `nextTask` walked the dependency graph again on each call (K9). Now `LiveGraph` keeps a `ReadinessCache` (`S/Derived/ReadinessCache.swift`). A read with no change uses the kept result. After a change, the cache computes again only the changed tasks and the tasks that depend on them, also across boards.
      - **Gap 4, one FSEvents stream for each watched folder (closed by ^swk9c8n):** the system gives a small number of FSEvents streams to all processes together (about 36 free streams on one test machine). Each board, scan place, folder of a path ref, and board that cannot load had its own stream, so a process with many sessions and related boards could run out of streams, and then a board did not see manual edits. Now the host keeps one stream for all its folders (`S/Observe/FolderStreams.swift`), and a router gives each event to the watcher of each folder that holds its path. When the set of folders changes, the new stream starts at the last event that the router got, so FSEvents gives it each later event from its history, also an event that the old stream did not give yet. Then the old stream stops. No event is lost, an event that the two streams both give goes to the watcher one time, and a new folder gets no event from before its add. No step of the change waits for FSEvents, so a change does not hold a thread. Change the plan (information only, plan.md stays frozen): plan §5.6 says that each loaded board starts its own FSEvents stream.
      - **Note, writes check the files:** each write compares the signature of every log file of each locked board under the lock (`S/Tool/Commit.swift:537-540`). This reads file metadata (one `stat` for each file), not file content. It is what keeps a write safe against another process or a `git pull`. It applies to writes only.
  - **Tests:** a test opens many sessions on the same repo, on a symlink to it, and on a sibling repo that the first repo also reaches as a related board. It then checks that the host has exactly one engine and one watcher for each board. A second test opens two sessions at the same time and checks that the board loads one time.
- Each session has its default board from its working directory. A call that names no board goes to that board.

**Open points (each needs a decision):**

- **M3 → a claim operation.** Proposal: add `claimNextTask(filter:, column:)`. Under the gate and the board lock, it finds the next ready task, assigns the session actor, and moves the task to the given column (default: the column after the first). It returns the task, or `null`. Two sessions then never get the same task. This also works across processes, because the commit checks the signatures under the board lock.
  - **DECIDED: do nothing.** No claim operation, and `nextTask` does not change. The agents coordinate themselves.
- **M4 → a distinct actor for each session.** Proposal: the ACP agent gives each session its own actor (for example `<agent name>-<session id>`, with the display name of the agent). Then `undo` with no argument stays in its session, and the board shows which session did each change. Option: keep one actor, and scope `undo` to the session instead.
  - **DECIDED: an actor for each session.** The ACP agent passes `<agent name>-<short session id>` (with a readable display name) to `host.session(workingDirectory:actor:)`. No change in this package. Known result: old session actors stay in `Board.actors`.
- **M5 → find the board of a subfolder.** Proposal: when `<working dir>/.kanban/` does not exist, search up to the top-level folder of the git repo, and use the first `.kanban/` that exists. When none exists, use the top-level folder of the repo for auto-init. A folder that is not in a git repo keeps the current rule. This changes plan §3.2 ("the tool does not search up").
  - **DECIDED (final, the user): a board exists only in a git repo, at the top folder of the repo.** "`.kanban` is always repo top — there is no such thing as a kanban without a repo — remove all the 'local kanban' complexity." This replaces the decision below where they differ.
    - The board of a session is `<repo top>/.kanban/`, for each working directory in the repo. In a worktree, the repo top is the top folder of that worktree (M6).
    - A working directory that is not in a git repo has no board. Each call gives a clear error, for example `NOT_A_REPO`: "The kanban needs a git repo. `<path>` is not in a git repo."
    - **Remove:**
      - boards in folders that are not git repos, and the locator code that finds them (commit `afca516`, task `^fv1dcq3`);
      - a `board:` path to any folder (commit `107ffed`, task `^8dy1xz2`): a path must be in a git repo, and it names the board of that repo;
      - the key `local/<folder-name>` for a folder outside git and for a subfolder of a repo;
      - a `.kanban/` in a subfolder.
    - **Results:** X11 does not apply to non-git folders any more. G4 (a git failure stops the board from opening) is now the correct behavior, because there is no `local/` fallback for a folder outside git.
    - **M7 DECIDED: the key of a git repo with no usable `origin` remote is its root commit.** The user: "we will need to be able to provide an identifier for a kanban in a repo with no remote."
      - The key is `local/<root commit>`, with the first 12 hex digits of the root commit of `HEAD` (`git rev-list --max-parents=0 HEAD`). When the history has more than one root commit, use the lowest SHA, so the key is the same each time.
      - The key is unique, and it does not change when the folder moves or is renamed. All clones and worktrees of the repo have the same key, as for a repo with a remote.
      - Known results: when the repo later gets an `origin` remote, the key changes to the remote key (as for any remote change, plan §12 item 4). A branch with a different history (an orphan branch) gives a different key.
      - **M8 DECIDED: a repo with no commit gets a first commit.** The user: "just make a first commit."
        - When the repo has no commit, Swift makes one empty first commit before it reads the key. Then the root commit exists, and the key is `local/<root commit>` from the start. The key does not change later (except when a remote is added).
        - The commit must not take the files that the user staged. Thus Swift does not use `git commit`. It makes the commit from the empty tree (`git commit-tree <empty tree> -m "Initial commit"`), and sets the current branch to it (`git update-ref HEAD <commit>`). The index and the working files do not change.
        - When git cannot make the commit (for example, no `user.name` or `user.email` is set), the call gives an error that says why.
        - There is no key that the user sets (no `kanban.key` in git config, and no key file).
        - Add tests: a new repo with no commit gets one empty commit and a `local/<root commit>` key; staged files stay staged and are not in the commit; a repo with commits gets no new commit.
  - **DECIDED: always the top folder of the repo.** In a git repo, the board of a session is always `<repo top>/.kanban/` (from `git rev-parse --show-toplevel`), for each working directory in the repo. A `.kanban/` in a subfolder is ignored. Outside a git repo, the board is `<working dir>/.kanban/`, with no search up. The key of the board is the key of the repo. Add tests: a session in a subfolder uses the repo board; a `.kanban/` in a subfolder is not used; a folder outside git keeps its own board.
- **M6 → worktrees.** Proposal: keep the plan rule (each worktree has its own board, joined by git). Option: all worktrees of one repo use the board of the main clone, so that all agents see one board at once. Then the board is not on the branch of the worktree.
  - **DECIDED (final, replaces the decision below): each worktree has its own board, on its own branch.** The user: "I want the kanban commits to travel with the code commits, so I actually want the kanban to be in the worktree, not the main checkout — and we'll merge up kanbans."
    - The board of a session is `<top folder of its worktree>/.kanban/` (from `git rev-parse --show-toplevel`). In the main clone, it is the top folder of the main clone.
    - Task changes are on the branch of the worktree, and they are committed with the code. Boards join when the branches merge (union merge of the log lines, plan §5.2).
    - The host loads each worktree board one time (its folder has its own file identity). Two sessions in the same worktree share one engine. Two worktrees are two engines, because they are two sets of files.
    - All worktrees have the same key. A URI with that key, in a session of that repo, names the current board of the session (plan §12 item 26: the current key resolves to the current directory). From a different repo, it names the first copy in scan order.
    - Known results: agents in different worktrees see the changes of each other only after a merge. Two agents can work on the same task (M3 is "do nothing").
    - The merge depends on S3 (event ids that increase from one call to the next), because the replay order after a union merge is the order of the event ids. S3 is in the bug list of section 11.
    - A bare repo works: each worktree has its own top folder.
    - Add tests: a session in a worktree uses the worktree board; two worktrees are two engines with the same key; a git merge of two worktree branches gives the union of both boards.
  - ~~**DECIDED: all worktrees use the board of the main clone.**~~ (Replaced.) A session in any worktree of a repo reads and writes `<main clone top>/.kanban/` (the folder above `git rev-parse --git-common-dir`). With the host, this is one engine for the whole repo, and each agent sees each change at once. This replaces "the top folder of the worktree" in the M5 decision. Known result: task changes are written in the working copy of the main clone, not on the branch of the worktree. Plan §12 item 26 ("a related key resolves to the first copy in scan order") then applies only to separate clones, not to worktrees. Add tests: two sessions in two worktrees share one engine and see each change at once; a write from a worktree goes to the main clone's `.kanban/`.
