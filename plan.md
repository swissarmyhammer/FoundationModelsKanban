# Plan: FoundationModelsKanban — a task graph that you talk to with GraphQL

This package moves the kanban function of `../swissarmyhammer` (Rust) to Swift.

The tasks are a graph. GraphQL is the protocol to read and change the graph.
The package gives one `FoundationModels.Tool`, named `kanban`. Each call runs to completion. The tool does no work in the background.
The input of the tool is a GraphQL document and its variables. The output is a GraphQL response.
There is no HTTP server. GraphQL is only the language and the protocol.

An agent links the tool through FoundationModelsMultitool, so that code mode can use it.

**Target: macOS 27, on-device, Swift 6 strict concurrency.**

This plan does not copy the Rust design one-to-one. It keeps the behavior that agents use.
It changes four items:

1. The data is a graph of nodes and edges.
2. A GraphQL schema defines the graph.
3. The tool takes GraphQL as input. The nouns and verbs are still there, but GraphQL gives them:
   - **Nouns** are the types of the GraphQL schema: `Board`, `Column`, `Task`, `Comment`, `Actor` (assignee), `Tag`.
   - **Verbs** are the two GraphQL operation types: `query` (read) and `mutation` (change).
4. The only stored data is an append-only event log. Each event is a GraphQL `patch` mutation that sets or removes properties on one node.

---

## 1. Principles

1. **GraphQL in, GraphQL out.** The tool takes `{query, variables, operationName}` and returns `{data, errors}`, the same as a GraphQL server. There is no transport layer.
2. **Swift types first.** Swift types are the one source of truth for nodes, edges, queries, and mutations. Graphiti builds the GraphQL schema from these types. The SDL is generated from the schema. No hand-written `.graphql` file exists.
3. **No background work.** Each call runs to completion before it returns. The API is `async`, but the tool has no background task, no watcher, and no event bus.
4. **Event sourcing.** The event log is the only stored data. The current state is the result of the replay of the log. The tool does not write a YAML or Markdown file for an entity.
5. **Graph.** Each entity is a node with a global URI. Each relation is an edge that stores the URI of the target node.
6. **Cross-repo.** A task in one repo can depend on a task in a different repo. The tool can also read and change the boards of other repos that it finds on the disk (§6.6).
7. **Forgiving input, strict log.** The resolvers accept loose input (short ids, slugs, tag names). The log stores only canonical, fully resolved values.
8. **Code mode.** In Multitool, a script calls `tools.kanban({ query, variables })` and gets the graph back as a structured value.

## 2. Scope

### 2.1 Node types

| Node | Meaning |
|---|---|
| `Board` | The kanban board of one repo. One repo has one board, and one board has one repo. The `Board` is the root of the graph. |
| `Task` | A unit of work. |
| `Column` | A workflow state (for example `todo`, `doing`, `review`, `done`). |
| `Actor` | A person or an agent. Tasks are assigned to actors. Comments have an actor as author. |
| `Tag` | A label on a task. Tags do the grouping job that the Rust `project` noun did before. |
| `Comment` | A text note on one task. |

### 2.2 Removed from the Rust design

- **Attachments.** We did not use them. All attachment ops, fields, and files are removed.
- **The Rust `project` noun** (many projects in one board). Tags are sufficient for grouping.
- **The `verb noun` op parser** (op string, verb and noun aliases, inference from the data). GraphQL field names replace it.
- **Perspectives.** These are a GUI concept. A saved view is a saved GraphQL query document. See §12, item 2.
- **Entity YAML and Markdown files.** The event log replaces them.
- **Diff-patch changelog.** The GraphQL mutation log replaces it.
- **Watcher, entity cache events, broadcast channels, GUI views and commands, merge-driver install.** (The Rust undo stack is replaced by undo from the event log, §6.5.)
- **The `_plan` ACP plan data** that the Rust MCP wrapper adds to task mutation results. A caller can get this data with a query.

## 3. The graph

### 3.1 Nodes and edges

The graph is a containment tree, plus cross edges:

```
Board                           (one per repo)
└── Column                      (sorted by order)
    └── Task                    (sorted by ordinal)
        ├── Comment             ──author──▶ Actor
        ├── assignees ──▶ Actor
        ├── tags      ──▶ Tag
        └── dependsOn ──▶ Task  (this repo or a different repo)
```

- **Containment:** `Board → Column → Task → Comment`. A query normally starts at `board` and goes down the tree.
- **Shared nodes:** `Actor` and `Tag` belong to the board. Many tasks point to the same actor or tag. `Board.actors` and `Board.tags` list them.
- **Cross edge:** `dependsOn` goes from a task to any task, in this repo or in a different repo.

These edges are stored:

| Edge | From | To | Cardinality | Cross-repo |
|---|---|---|---|---|
| `column` | Task | Column | 1 | No |
| `assignees` | Task | Actor | many | No |
| `tags` | Task | Tag | many | No |
| `dependsOn` | Task | Task | many | **Yes** |
| `task` | Comment | Task | 1 | No |
| `author` | Comment | Actor | 1 | No |

These edges are derived at read time. They are not stored:

- `blocks` (the reverse of `dependsOn`)
- `blockedBy` (the `dependsOn` targets that are not done)
- `comments` (the reverse of `Comment.task`)
- `tasks` on Column, Actor, and Tag.

### 3.2 Identifiers

Each node has one global URI. This URI is the GraphQL `ID`. The `Board` is the one exception to the pattern below: its URI is `kanban://<board-key>/board`, with no local id, because a repo has one board.

```
kanban://<board-key>/<type>/<local-id>

kanban://github.com/swissarmyhammer/FoundationModelsKanban/task/01K6Z3...ABCDEFG
kanban://github.com/swissarmyhammer/FoundationModelsKanban/column/doing
kanban://github.com/swissarmyhammer/FoundationModelsKanban/actor/claude-code
```

- **`board-key`** comes from the initial git remote `origin`, normalized to `host/owner/repo`. If there is no remote, the key is `local/<directory-name>`. The first board patch records the key, and the tool always reads it from the log. Thus, the key does not change later. See §12, item 4.
- **Each node has an identifier.** All queries and mutations find a node by its identifier, so each node can be read, updated, and deleted by itself:

  | Node | `local-id` | Example URI | Short forms |
  |---|---|---|---|
  | `Board` | none | `kanban://<board-key>/board` | board key, unique repo directory name, or path (§6.6) |
  | `Column` | slug | `kanban://<board-key>/column/doing` | the slug |
  | `Actor` | slug | `kanban://<board-key>/actor/claude-code` | the slug |
  | `Task` | ULID | `kanban://<board-key>/task/01K6Z3…` | ULID, short id, `^short`, prefix |
  | `Tag` | slug | `kanban://<board-key>/tag/bug` | the slug, or the tag name (normalized to the slug) |
  | `Comment` | ULID | `kanban://<board-key>/comment/01K6Z5…` | ULID, short id, `^short`, prefix |

- **A comment is a full node, with its own identifier.** `updateComment(id:)` and `deleteComment(id:)` need only the comment id. The caller does not also give the task id, as the Rust code required. The comment stores its task as the `task` edge.
- **Target board.** A short form resolves in the target board. For a mutation on an existing node, the target board is the board of that node. For other mutations, it is the board that the `board` input field names, or the current repo (§6.6).
- **Short forms.** An `ID` argument also accepts these forms:
  - Full ULID.
  - Short id: the last 7 characters of the ULID, in lowercase.
  - `^short`, and a unique ULID prefix (git style).
  - A slug, for a column, an actor, or a tag. A tag name is normalized to its slug first.
- **Slug rule.** A slug is lowercase. This is different from the Rust `normalize_slug`, which keeps case. Two names that differ only in case give the same slug, so `Bug` and `bug` are one tag and one file on a case-insensitive disk. A name that gives an empty slug is refused (`INVALID_TAG_NAME` for a tag, `INVALID_SLUG` for a column or an actor).
- **Mint rule.** A new ULID must have a short id that is unique in the board (same as `mint_unique_short_id` in Rust).
- **Output.** `id` is always the full URI. `Task` and `Comment` also have `shortId`.
- **Tag rename.** A tag slug is its identifier, so a rename changes the identifier. See §6.2 and §12, item 15.

### 3.3 Graph rules

1. Each stored edge holds the full URI of its target.
2. A delete makes a **tombstone**. It does not change other nodes.
3. At read time, the projection ignores an edge to a tombstoned node. Thus, delete does not need cascade writes.
4. A `dependsOn` edge to a node that is **not known** (for example, the other repo is not available) counts as **not done**. The task is then blocked. This is the same as the Rust rule "missing dependency = blocked".
5. A column that has live tasks cannot be deleted (`COLUMN_NOT_EMPTY`).
6. A `dependsOn` edge that makes a cycle is refused (`DEPENDENCY_CYCLE`). The check reads all boards on the cycle path, and the commit check of §5.4 covers these boards. The Rust code defined this error but did not use it.
7. **Rules 5 and 6 (and the rename-cycle rule in §6.2) apply only when a mutation writes patches.** Replay never refuses a log. A `union` merge of two branches can make a state that breaks a rule. §5.3 tells how the projection shows such a state.

## 4. The GraphQL API

The schema is defined in Swift (`GraphQL/Schema.swift`) with Graphiti, from the Swift node types. The SDL below is a sketch of the generated output. It is not a file in the package.

### 4.1 Types and queries (sketch)

```graphql
scalar Date
scalar DateTime

interface Node { id: ID! }

type Board implements Node {
  id: ID!
  key: String!
  name: String!
  description: String
  columns: [Column!]!                 # the tree: Board > Column > Task > Comment
  actors: [Actor!]!                   # shared nodes
  tags: [Tag!]!                       # shared nodes
  task(id: ID!): Task
  tasks(filter: String, column: ID, tag: ID, assignee: ID,
        excludeDone: Boolean = true, archived: Boolean = false,
        first: Int = 10, after: String): TaskConnection!
  nextTask(filter: String): Task
  searchTasks(query: String!, filter: String, first: Int = 10): [TaskHit!]!   # §6.4
  summary: BoardSummary!              # counts: total, ready, blocked, done, percent
  history(node: ID, actor: ID, first: Int = 20): [Change!]!   # §6.5, newest first
}

type Change { txn: ID!  at: DateTime!  actor: Actor!  ops: [String!]!  boards: [String!]!  nodes: [Node!]!  undone: Boolean!  undoes: ID }
# Change.boards has one key when the transaction changed one board.

type Column implements Node { id: ID!  name: String!  order: Int!  tasks(filter: String): [Task!]! }
type Actor  implements Node { id: ID!  name: String!  color: String  tasks(filter: String): [Task!]! }
type Tag    implements Node { id: ID!  name: String!  color: String!  description: String  tasks(filter: String): [Task!]! }

type Task implements Node {
  id: ID!
  shortId: String!
  title: String!
  description: String
  column: Column!
  ordinal: String!
  assignees: [Actor!]!
  tags: [Tag!]!
  dependsOn: [Task!]!                 # can resolve across repos
  blockedBy: [Task!]!                 # derived
  blocks: [Task!]!                    # derived
  ready: Boolean!                     # derived
  virtualTags: [String!]!             # READY | BLOCKED | BLOCKING
  progress: Progress!                 # derived from Markdown checklists
  comments: [Comment!]!
  due: Date
  scheduled: Date
  archived: Boolean!
  created: DateTime!                  # derived from the event log
  updated: DateTime!
  started: DateTime
  completed: DateTime
}

type Comment implements Node { id: ID!  shortId: String!  task: Task!  author: Actor!  text: String!  created: DateTime!  updated: DateTime! }

type Query {
  board(id: String): Board            # no id = this repo, never null. With an id: a board key, repo directory name,
                                      # or path (§6.6); null only together with a NOT_FOUND error
  boards(enabled: Boolean): [Board!]! # related boards that the scan found; filter by enabled state (§6.6)
  node(id: ID!): Node                 # direct access by URI, also in a different repo
  nodes(ids: [ID!]!): [Node]!
}
```

The root has only four fields. All other reads go down the tree from `board`. For example:

```graphql
{ board { columns { name tasks(filter: "#kanban") { shortId title
    comments { text author { name } } assignees { name } tags { name } } } } }
```

`TaskConnection` uses cursor paging (`edges`, `pageInfo`, `totalCount`). This replaces the Rust `page` and `page_size` params.

### 4.2 Mutations

Each Rust write op becomes one mutation field. The names use the `verbNoun` form. Each public mutation writes one or more property patches to the log (§5.1).

Each mutation takes one `input` object. The table lists the fields of that object. `input` is optional when it has no required field (for example `undo`, `redo`, `initBoard`).

**Notation.** In this plan, `f(x: v)` means `f(input: { x: v })`.

These mutations also have an optional `board` field in `input`, because they name a node by a short form or by no id, not by a node URI: `initBoard`, `updateBoard`, `addTask`, `addColumn`, `addActor`, `addTag`, and `renameTag`. A mutation on an existing node (including `addComment`, which names its task) finds its board from that node. See §6.6.

| Mutation | Fields of `input` | Patches in the log |
|---|---|---|
| `initBoard` | `name`, `description` | board: `set name, description, key`; 4 columns: `set name, order` (default columns). On a board that exists: only `set` the given fields that differ; no columns are added. |
| `updateBoard` | `name`, `description` | board: `set` the given properties |
| `addTask` | `title!`, `description`, `column`, `ordinal`, `assignees`, `tags`, `dependsOn`, `due`, `scheduled` | task: `set` the scalars, `add` the edges; one `set` patch for each unknown tag |
| `updateTask` | `id!`, and any field of `addTask` except `column` and `ordinal`. A list value replaces the list. `null` clears a field. | task: `set` / `unset` the scalars; `add` / `remove` the list difference |
| `moveTask` | `id!`, `column!`, `ordinal`, `before`, `after` | task: `set column, ordinal` (plus a column `set` patch if the column is new) |
| `completeTask` | `id!` | task: `set column, ordinal` (terminal column) |
| `assignTask` / `unassignTask` | `id!`, `actor!` | task: `add` / `remove` on `assignees` |
| `tagTask` / `untagTask` | `id!`, `tags!` | task: `add` / `remove` on `tags` (plus a tag `set` patch for each unknown tag) |
| `deleteTask` | `id!` | task: `delete` |
| `archiveTask` / `unarchiveTask` | `id!` | task: `set archived` true / false |
| `undo` | `txn` (optional), `force` | the inverse patches of the transaction (§6.5) |
| `redo` | `txn` (optional), `force` | the inverse patches of an `undo` transaction (§6.5) |
| `addColumn` / `updateColumn` / `deleteColumn` | `id`, `name`, `order` | column: `set` / `delete` |
| `addActor` / `updateActor` / `deleteActor` | `id`, `name`, `color`, `ensure` | actor: `set` / `delete` |
| `addTag` / `updateTag` / `deleteTag` | `id` (slug), `name`, `color`, `description` | tag: `set` / `delete` (`addTag` is idempotent on slug). `updateTag` does not change the slug. |
| `renameTag` | `from!`, `to!` | new tag: `set` (only if `to` does not exist); old tag: `set renamedTo` (§6.2) |
| `addComment` / `updateComment` / `deleteComment` | `task`, `id`, `text`, `actor` | comment: `set task, author, text` / `set text` / `delete` (plus an actor `set` patch if the author is new) |

Each mutation field returns the changed node. Thus, the caller selects the fields that it needs. For example:

```graphql
mutation {
  addTask(input: { title: "Port the filter DSL", tags: ["kanban"], dependsOn: ["^a1b2c3d"] }) {
    id shortId ready blockedBy { title }
  }
}
```

### 4.3 Rules for the schema

- **The public mutations are not logged.** Only property patches go into the log. Thus, the public mutations (and the sugar mutations such as `completeTask`) can change at any time, and old logs still replay.
- **Each patch changes exactly one node.** A public mutation can make more than one patch (see the table). Each patch goes into the log of its node (§5.2).
- **Patches hold canonical values:** full URIs, minted ids, computed ordinals, and resolved actors. A patch does not generate an id or read the clock. Thus, replay is deterministic.
- **Many mutations in one document** run in sequence, as the GraphQL specification requires. This replaces the Rust batch input.
- **Schema changes need no upgrade step.** See §5.3 and §12, item 3.

### 4.4 Errors

The response follows the GraphQL specification: `{ "data": …, "errors": [ … ] }`.

- Each error has `message`, `path`, and `extensions.code`.
- The codes are: `INVALID_VARIABLES`, `NOT_FOUND`, `AMBIGUOUS_ID`, `ACTOR_NOT_FOUND`, `DUPLICATE_ID`, `COLUMN_NOT_EMPTY`, `DEPENDENCY_CYCLE`, `TAG_RENAME_CYCLE`, `NOTHING_TO_UNDO`, `UNDO_CONFLICT`, `INVALID_FILTER`, `INVALID_DATE`, `INVALID_TAG_NAME`, `INVALID_SLUG`, `INVALID_ORDINAL`, `BOARD_BUSY`.
- The message must tell the model how to correct the call. For example, an `AMBIGUOUS_ID` error gives the matching ids.
- A syntax or validation error gives the GraphQL "did you mean" suggestion. This is after the field-name rewrite in §4.5.
- If a mutation field fails, no patch of that field is written. The patches of the other fields of the call are written (§5.4). The tool validates all patches of a field before it keeps them.
- The tool does not throw for a GraphQL error. It returns the response JSON. The tool throws only for a fault that the caller cannot correct, for example an I/O failure.

### 4.5 Forgiving field names

The agent can write a mutation name in the verbNoun order (`addTask`) or in the nounVerb order (`taskAdd`). Both orders work.

- **The schema has one name for each field.** The canonical form is verbNoun (`addTask`, `moveTask`, `initBoard`). Thus, the schema that introspection shows stays small.
- **A rewrite step runs before validation.** It looks at each top-level field of a mutation. If the schema does not have that name, the step tries the other word order. If it finds a match, it changes the field to the canonical name.
- **The response key does not change.** The rewrite adds a GraphQL alias. For example, `taskAdd(...)` becomes `taskAdd: addTask(...)`. Thus, the caller finds the result under the name that it wrote.
- **The same step accepts verb synonyms.** `create`/`new`/`insert` → `add`, `remove`/`rm`/`del` → `delete`, `edit`/`modify`/`set`/`patch` → `update`, `mv` → `move`, `done`/`finish`/`close` → `complete`, `label` → `tag`, `unlabel` → `untag`, `restore` → `unarchive`. Plural nouns change to the singular. These are the Rust verb aliases. **`create` never maps to `init`.**
- **A caller alias is kept.** If the caller already wrote an alias (`x: taskAdd(...)`), the step keeps `x`.
- If no rewrite matches, normal validation runs and gives the "did you mean" error.
- The rewrite does not change the log. The log holds only property patches (§5.1).

## 5. Storage: the event log

### 5.1 Event format

Each line of a log is one **property patch** on one node. The patch is a GraphQL request to one generic internal mutation, `patch`, plus an envelope:

```json
{"id":"01K6Z4...","txn":"01K6Z4...","ops":["addTask"],"at":"2026-10-06T14:49:10.690Z","actor":"kanban://github.com/o/r/actor/claude-code",
 "query":"mutation($p: PatchInput!) { patch(input: $p) }",
 "variables":{"p":{"node":"kanban://github.com/o/r/task/01K6Z3...","type":"Task",
   "set":{"title":"Port the filter DSL","column":"kanban://github.com/o/r/column/todo","ordinal":"80"},
   "add":{"tags":["kanban://github.com/o/r/tag/kanban"]}}}}
```

| Field | Meaning |
|---|---|
| `id` | The event ULID. The replay order is the sort order of this field. |
| `at` | The time of the event (UTC, RFC 3339). This is the only clock value in the event. |
| `actor` | The URI of the actor that made the change. |
| `txn` | The transaction ULID. All patches of one tool call have the same `txn` (§6.5). |
| `ops` | The names of the public mutations in the tool call, for example `["moveTask"]`. Only for `history`. Replay does not use it. |
| `boards` | Only when the transaction changes more than one board: the keys of all boards that it changes. `undo` uses it (§6.5). |
| `undoes` | Only on the patches of `undo` and `redo`: the `txn` that this transaction reverses. |
| `query`, `variables` | A GraphQL request to the internal `patch` mutation. |

The `PatchInput` has these parts. Each part is optional, except `node` and `type`:

| Part | Meaning |
|---|---|
| `node` | The URI of the one node that the patch changes. |
| `type` | The node type (`Board`, `Column`, `Task`, `Actor`, `Tag`, `Comment`). |
| `set` | Properties to write. A value replaces the old value. |
| `unset` | Property names to clear. |
| `add` | Values to add to a set-valued property (for example `tags`, `assignees`, `dependsOn`). |
| `remove` | Values to remove from a set-valued property. |
| `delete` | `true` makes a tombstone (§3.3). `false` removes the tombstone (used by `undo`). |

- **Create, read, update, and delete are all patches.** A node exists after its first patch. There is no separate "create" event.
- **Set-valued properties use `add` and `remove`, not a full list.** Thus, when two branches add different tags to the same task, the merge keeps both tags.
- **The `patch` mutation is internal.** It is not in the public schema, so the model cannot write a patch directly.

### 5.2 Layout on disk

```
.kanban/
  board.jsonl                    # events for the board node
  columns/<slug>.jsonl           # one log per node
  actors/<slug>.jsonl
  tags/<slug>.jsonl
  tasks/<ULID>.jsonl
  comments/<ULID>.jsonl
  .gitattributes                 # *.jsonl merge=union
  .gitignore                     # cache/, .lock
  .lock                          # the write lock
  cache/                         # optional derived snapshot (not tracked in git)
```

Decision: **one log file for each node.**

- Two branches that change different tasks change different files. Thus, git merges have fewer conflicts.
- When two branches change the same task, the git `union` merge driver keeps the lines from both sides. This is a built-in driver, so we do not install a custom one.
- Replay sorts the events by event ULID, not by line position. Thus, the order of lines after a merge is not important.

See §12, item 5.

### 5.3 Replay and projection

1. Read each `*.jsonl` file. Parse each line. Sort all events by event `id`.
2. Apply each patch to an empty in-memory `Graph` store. The state of a node is the accumulated result of its patches:
   - `set` writes a value. A later `set` of the same property wins (the order is the event ULID).
   - `unset` clears a value.
   - `add` and `remove` change the members of a set-valued property.
   - `delete: true` makes a tombstone. `delete: false` removes it.
3. While the patches apply, record the time values for each node: `created`, `updated`, `started`, `completed`.
   - `created`: the time of the first patch. `updated`: the time of the last patch.
   - `started`: the first `set column` to a column that is not the first column.
   - `completed`: set only if the last `set column` went to the terminal column.
4. Calculate the derived fields at read time: `blockedBy`, `blocks`, `ready`, `virtualTags`, `progress`.
5. **Show a broken merged state without an error** (§3.3, rule 7):
   - A `dependsOn` cycle: each task in the cycle counts as blocked. A readiness walk stops when it finds a task that it already visited.
   - A task in a tombstoned column, or with no column: it shows in the first column.
   - A comment on a tombstoned task: it is hidden.
   - A `renamedTo` chain with a cycle: the walk stops at the first slug that repeats, and uses that tag.
   - Two columns with the same `order`: sort them by slug.

**Schema changes need no upgrade step.** A patch only holds property values, so it does not depend on the shape of the public mutations:

- A new property: old nodes do not have it. The resolver gives its default value.
- A removed property: the projection keeps the old value, but no resolver reads it.
- A renamed property: the resolver reads the new name first, then the old name.
- The public mutations can change freely, because they are not in the log.

The data is small, so each call can do a full replay (§5.4 gives the scope). If replay time becomes a problem, add a snapshot in `cache/`. The snapshot holds the projection and the last event id of each file, and is not tracked in git. The tool must always be able to delete the cache and build it again.

### 5.4 Call path

1. Parse the GraphQL document. Run the field-name rewrite (§4.5). Validate the document against the public schema.
2. Replay the current board. Replay a related board only when the call reaches it: by an edge (for example `dependsOn`), a URI, or a `board` field. Each board is replayed at most one time for each call.
3. For a query: run the resolvers and return the response.
4. For each mutation field, in order:
   1. Resolve each forgiving ref against the `Graph` (§3.2).
   2. Make the property patches: mint the ids, compute the ordinal, set the actor. Include only the properties that change.
   3. Apply the patches to the in-memory `Graph`. If a graph rule fails, return an error for this field, and discard the patches of this field.
   4. Keep the patches in memory. Record the boards that the field changed and the boards that it read for a graph rule.
   5. Resolve the selection set of the field against the in-memory `Graph`.
5. **Commit, at the end of the call.** If the call kept at least one patch:
   1. Get an exclusive lock on the `.kanban/.lock` of each board that the call changed or read for a graph rule. Lock in the sort order of the board key, so that two calls cannot deadlock.
   2. Under the locks, check that no log of these boards changed after the replay. If a log changed, release the locks, discard all kept patches and the response, and run the call again from step 2. After 5 runs, stop and return the error `BOARD_BUSY`. The message tells the caller to send the call again.
   3. Append each kept patch to its node log in its board. Each patch has the `txn`, `ops`, and `boards` values of the full call, which are now known.
   4. Release the locks, and return the response.
6. A mutation that changes nothing writes no patch. This is the same as the Rust no-op rule.

## 6. Semantics to keep from the Rust code

| Item | Rule |
|---|---|
| Default columns | `initBoard` makes `todo` "To Do" 0, `doing` "Doing" 1, `review` "Review" 2, `done` "Done" 3. |
| Auto-init | If the first mutation runs and `.kanban` has no board, the tool initializes the board with the default columns. The default board `name` is the repo directory name. A query on an empty repo returns an empty board with that name and writes nothing. |
| Terminal column | The column with the maximum `order`. A task there is "done". |
| `ready` | All `dependsOn` targets are done. |
| Virtual tags | `READY` (not done, and all dependencies done), `BLOCKED` (at least one dependency is not done), `BLOCKING` (not done, and some task depends on it). |
| `nextTask` | From the tasks that are not done, are ready, and match the filter: sort by column order, then by ordinal. Return the first task or `null`. |
| `completeTask` | Move to the terminal column, after the last ordinal there. |
| `moveTask` | Ordinal priority: an explicit `ordinal`, then `before` or `after` a neighbor, then append at the end. A missing column is created (name = slug in title case). |
| Default column on add | The column with the minimum `order`. |
| Ordinals | Fractional index (Figma algorithm), lowercase hex, default `"80"`. Byte compatibility with Rust is not necessary because the storage is new. |
| Session actor | The session actor is the `actor` value of `KanbanTool.make`, else the OS user. When a call writes at least one other patch to a board, it also makes sure that the session actor exists in that board (an actor `set` patch if it is new). A call that writes nothing writes no actor patch. This rule is the same in the current repo and in related boards. Thus, the envelope `actor` always names a real actor. |
| Assignees | Each assignee must be a known actor. If `addTask` has no assignee, use the session actor if it was a known actor before the call. |
| Comment author | An explicit `actor`, else the session actor. The actor is made if it does not exist. |
| Column and actor slugs | The slug rule of §3.2 (lowercase, not empty). |
| Tag names | Trim, change each run of spaces to `_`, remove NUL, refuse an empty name. The slug is `normalize_slug` and then lowercase (§3.2). `auto_color` = FNV-1a 32-bit hash of the slug, modulo the 16-color palette. |
| Progress | Count the lines `- [ ]` / `- [x]` / `- [X]` in the description. |
| Dates | `due` and `scheduled` accept `YYYY-MM-DD` or RFC 3339, and are stored as dates. In `updateTask`, a missing argument = no change, and `null` = clear. |
| Task order in lists | Column order, then ordinal. The Rust code had no explicit sort. |

### 6.1 Tags: edges plus body markers

In Rust, tags are `#tag` text markers in the task body. In the graph design, a task gets its tags from two sources. The projection calculates them at read time:

```
task.tags = resolve(tags edges) ∪ resolve(#markers in the current description)
```

- **Resolve** changes each marker to its slug, then follows the `renamedTo` redirect (§6.2). Thus, an old `#bug` marker shows the tag `defect`.
- **`tagTask`** adds an edge. It does not change the text. Two branches that tag the same task merge correctly, because edges use `add` and `remove`.
- **`untagTask`** removes the edge. If the description also has the marker, `untagTask` also removes the marker from the text (a `set description` patch).
- **A marker that the agent removes from the text** removes that tag, unless an edge also holds it. No compare logic is necessary.
- **A new marker** in `addTask` or `updateTask` that names an unknown tag also writes a `set` patch for that tag. Thus, `Board.tags` lists it. If the marker names a tombstoned tag, the tool writes `delete: false` for that tag, so that the tag is live again.
- **A tag rename** does not change any text. The redirect covers edges and markers.
- **The filter `#x`** matches tags from edges and from markers.
- **`addTask(tags:)` and `updateTask(tags:)`** change only the edges.

Known cost: when the marker is in the text, `untagTask` writes the description, and for the description the last write wins.

See §12, item 7.

### 6.2 Tag rename

The tag slug is the identifier, and the task edges hold the tag URI. Thus, a rename must not break the edges that point to the old slug.

Decision: **a rename makes a redirect.** For example, `renameTag(from: "bug", to: "defect")` writes two patches:

1. New tag `defect`: `set name, color, description` (the values are copied from `bug`). If `defect` exists, this patch is not written, and `defect` keeps its own values.
2. Old tag `bug`: `set renamedTo = kanban://…/tag/defect`.

- **No task changes.** Task edges still hold `…/tag/bug`. The projection follows `renamedTo`, so `task.tags` shows `defect`.
- **Safe with merges.** If a different branch adds `bug` to a task at the same time, the edge points to `…/tag/bug`, and the redirect also covers it.
- **Filters and refs follow the redirect.** `#bug` and `#defect` both match. `addTask(tags: ["bug"])` writes an edge to `defect`.
- **A chain of renames is followed.** For example, `bug` → `defect` → `issue`. A rename that makes a cycle is refused (`TAG_RENAME_CYCLE`). A cycle that a merge makes is shown as §5.3 tells.
- **Board.tags** lists only the tags that have no `renamedTo`. One exception: in a rename cycle from a merge (§5.3), the tag where the walk stops is also listed.
- **Rename to a slug that exists** is a merge: the old tag redirects to the existing tag (only patch 2 is written).
- **All refs to a redirected slug follow the redirect.** This includes `addTag` (it returns the target and writes nothing), `updateTag`, `deleteTag`, and `renameTag`. Thus, `deleteTag(id: "bug")` after the rename deletes `defect`.
- **Delete of a redirect target.** The target gets a tombstone. Edges and markers that point to the old slug follow the redirect to the tombstone, so the tasks lose the tag. This is the same as for a direct edge (§3.3).

See §12, item 15.

### 6.3 Filter DSL

The `filter` argument keeps the grammar from `swissarmyhammer-filter-expr`. It is a short text form that is easy for a model to write.

```
expr     = or_expr
or_expr  = and_expr (("||"|"or"|"OR") and_expr)*
and_expr = not_expr (("&&"|"and"|"AND")? not_expr)*      // two terms next to each other = AND
not_expr = ("!"|"not"|"NOT") not_expr | atom
atom     = "#" body | "@" body | "^" body | "(" expr ")"
body     = [^ \t\n\r#@^$()&|!]+
```

- `#x` matches tags plus virtual tags. The match ignores case.
- `@x` matches an assignee slug, or the slug of the actor name.
- `^x` matches the task itself or a `dependsOn` target, by URI, ULID, short id, or prefix.
- The Rust `$project` atom is removed, because the `project` noun is removed.
- The `column`, `tag`, and `assignee` arguments of `tasks` are ANDed with `filter`.

### 6.4 Search

`searchTasks` uses `MetadataSearcher` from FoundationModelsMetadataRegistry. That package uses FoundationModelsRanker. Do not write a new ranker.

- **Ranking.** BM25 (word match) + trigram (partial words and typing errors) + embedding cosine (only if an embedder is set). Reciprocal rank fusion (RRF) combines the signals.
- **Item.** `TaskSearchItem` conforms to `SearchableMetadata`:
  - `id` = the task URI.
  - `renderBlock()` = the title, the tag names, and the description.
- **Mode.** Use `.retrieval`. Do not use `.selection`: it calls an LLM, and the result then changes from call to call.
- **Embedder.** Optional. `KanbanTool.make(..., embedder: (any TextEmbedding)? = nil)`. With no embedder, search uses only BM25 + trigram and needs no model. The agent can give a `PooledEmbedder`.
- **Life of the searcher.** `KanbanGraph` keeps one `MetadataSearcher` for each board, for its life. After each replay of a board, call `update(items:)` on the searcher of that board. This embeds again only the tasks that changed. Nothing is written to disk.
- **Filter.** `MetadataSearcher.search(intent:limit:)` has no filter argument. Thus, call it with `limit` = the number of tasks in the board. Then remove the tasks that do not pass `filter` (§6.3), and keep the first `first` results. `archived` and done tasks are excluded by default, the same as `tasks`.
- **Result.** `TaskHit { task: Task!, score: Float!, signals: SearchSignals }`. `SearchSignals` holds `bm25`, `trigram`, and `cosine` (null when there is no embedder).
- **Diagnostics.** If the embedder fails, the searcher falls back to BM25 + trigram. The tool records the diagnostic with swift-log. It does not write it to the event log, and it does not return an error.

See §12, item 6.

### 6.5 Undo and redo

Undo uses the event log. It never deletes or changes a line in the log. It appends new patches that put the old values back.

- **Transaction.** All patches of one tool call have the same `txn`. This includes all mutation fields in the document. `undo` reverses one transaction. Thus, "undo my last call" reverses the full call.
- **`undo`** with no argument reverses the newest transaction of the session actor that is not already undone. It skips transactions that have `undoes` set (undo and redo transactions). Thus, two `undo` calls reverse the two newest original calls. `undo(txn:)` reverses a given transaction, also one from a different actor.
- **Scope.** `undo` and `redo` with no argument look in all enabled boards in the index (§6.6).
- **`redo`** with no argument reverses the newest `undo` transaction of the session actor that is not already reversed. A redo is an undo of an undo, so the conflict rule and `force` apply to it in the same way.
- **Undone state is derived from the log.** A transaction is undone when a later transaction has `undoes` = its `txn`, and that later transaction is not itself undone. Thus, there is no stack to store, and after a git merge, the undo history includes both branches.
- **Inverse patches.** The tool calculates them from the projection just before the transaction:

  | Original | Inverse |
  |---|---|
  | `set p = v` | `set p = <old value>`, or `unset p` if there was no old value |
  | `unset p` | `set p = <old value>` |
  | `add x` to a set | `remove x` |
  | `remove x` from a set | `add x` |
  | `delete: true` | `delete: false` |
  | `delete: false` | `delete: true` |
  | the first patch of a node that a mutation made explicitly (for example `addTask`, `addTag`, `addColumn`) | `delete: true` |
  | the first patch of a node that a mutation made as a side effect (an unknown tag in `addTask`, a new actor, a new column in `moveTask`, the board in auto-init), and a tag that a `#marker` makes live again with `delete: false` (§6.1) | no inverse: the node stays |

  Patches hold only the properties that changed (§5.4), so each inverse is exact.
- **Conflict.** A later transaction that is not undone can change the same property of the same node (for a set: the same member). For a node that the transaction made, a later edge to that node is also a conflict. In that case, `undo` writes nothing and returns `UNDO_CONFLICT`. The error gives the later transactions. `undo(txn: <id>, force: true)` writes the inverse anyway, and the undo then wins (last write wins).
- **Graph rules still apply.** An inverse that breaks a rule in §3.3 is refused. For example, an undo of `deleteColumn` that would put back a column is accepted, but an undo of `addColumn` when the column now has tasks gives `COLUMN_NOT_EMPTY`.
- **Many boards.** A transaction that changes more than one board records all board keys in `boards` on each of its patches (§5.1). This is possible because the call writes all its patches at the end (§5.4). `undo` and `redo` of such a transaction need all those boards. If one board is not in the index, they write nothing and return `NOT_FOUND`, and the message names the missing board.
- **`history`** (on `Board`) lists the transactions that changed that board, newest first, with `txn`, time, actor, `ops`, `boards`, the changed nodes, and `undone`. It can filter by node and by actor. The agent uses it to find a `txn` to undo.
- **Result.** `undo` and `redo` return the `Change` that they wrote. The caller can select the changed nodes from it.

See §12, item 12.

### 6.6 Related boards (cross-repo)

A **related board** is the board of a different repo on the same disk. The tool can read and change related boards, and it can make a board in a related repo that does not have one yet. All boards use the same format.

- **Scan.** The tool looks in the parent directory of the current repo, one level down, for git repos. The tool config can add more search roots, for example `~/src`. The roots are places to look, not a copy of the keys. For each repo it finds:
  - If the repo has `.kanban/board.jsonl`, the key comes from the first board patch (the board is **enabled**).
  - If not, the key comes from the `origin` of the repo, with the same rule as §3.2 (the board is **not enabled** yet).
  - The result is an index from board key to directory, with the enabled state.
- **Index life.** The index stays in memory for the life of `KanbanGraph`. On an unknown key, the tool scans one more time.
- **Board name.** A board that is not enabled shows the repo directory name as its `name`.
- **Board refs.** A `board` argument (and `Query.board(id:)`) accepts:
  - a board key, for example `github.com/o/other`;
  - a repo directory name, for example `FoundationModelsMultitool`, if it is unique in the index;
  - a path.
- **Enable a related repo.** If the `board` argument names a related repo that is not enabled, the first mutation initializes its board (the same auto-init rule as §6). `initBoard(board:)` does the same thing explicitly. The key comes from the `origin` of that repo. A query on a repo that is not enabled returns an empty board and writes nothing.
- **Short ids.** For a mutation on an existing node, short ids, slugs, and tag names resolve in the board of that node. For a mutation that makes a node, they resolve in the board that the `board` field names, or in the current repo. A full URI always resolves in its own board.
- **Edges.** `dependsOn` can point to any board. `column`, `tags`, `assignees`, and `author` point only to nodes in the same board as the task.
- **Actors.** In each board, the patches use the actor URI of that board. The session actor rule of §6 applies in every board.
- **One transaction, many boards.** All patches of one tool call have the same `txn`, also when they go to different boards. Each patch records the keys of all these boards in `boards` (§5.1, §5.4). `undo` reverses the transaction in each board, or writes nothing if one board is missing (§6.5).
- **Git.** The tool does not commit. A change to a related board is an uncommitted change in that repo, on the branch that is checked out there.
- **Not found.** A `dependsOn` target in a board that the scan cannot find counts as not done (§3.3). A mutation on a node in a board that cannot be found gives `NOT_FOUND`, and the message lists the search roots.

See §12, item 13.

## 7. The tool

### 7.1 Arguments and output

```swift
struct KanbanArguments: ConvertibleFromGeneratedContent {
    var query: String
    var variables: [String: Map]            // GraphQLSwift `Map`; empty when not given
    var variablesError: String?             // set when `variables` cannot be decoded
    var operationName: String?

    init(_ content: GeneratedContent) throws   // forgiving decode; does not throw for bad `variables`
    static var generationSchema: GenerationSchema { get }
}
```

- `Output` is a `String` that holds the GraphQL response JSON (`{data, errors}`), encoded with `.sortedKeys`.
- **`variables` accepts each of these forms** (maximally forgiving):
  - A plain object, for example from code mode: `tools.kanban({ query, variables: { id: t.id } })`.
  - A string that holds a JSON object: `variables: JSON.stringify({ id: t.id })`.
  - A string that holds JSON text in a code fence, or with surrounding white space. The decoder removes the fence first.
  - `null`, an empty string, or no key: no variables.
- The custom `init(_ content:)` looks at the kind of the `variables` content. An object is converted directly. A string is parsed as JSON. For any other kind, or a string that is not a JSON object, `init` does not throw. It sets `variablesError`, and `call` returns a GraphQL response with the error code `INVALID_VARIABLES`. The message shows the two correct forms. `init` throws only when `query` is missing.
- **Schema of `variables`.** Multitool checks each top-level argument against its declared JSON Schema `type` before it calls the tool, and it skips a property that has no `type` (`FoundationModelsMultitool/.../Invocation/ToolInvoker.swift`, `validateType`). Thus, the `generationSchema` declares `variables` with `DynamicGenerationSchema(name:anyOf:)` (this initializer is in the FoundationModels interface of the macOS 27 SDK) of two choices:
  - a string schema, with the guide "the variables as one JSON object in text";
  - an object schema with no properties.

  The encoded JSON Schema then has `anyOf` and no top-level `type`, so Multitool passes a script object through. The on-device model can only make an empty object with the second choice. Thus, an empty object means "no variables". If the document then needs a variable, validation gives the normal GraphQL error, and the model can send the string form or put the values in the document.
- **Tests for this schema.** A unit test encodes `KanbanArguments.generationSchema` and checks that `variables` has `anyOf` and no `type`. The step 17 test sends an object and a string through Multitool. A test with a real `LanguageModelSession` checks that the on-device model makes the string form for a document with variables.
- The decoder keeps the JSON types: number, boolean, null, list, and object. GraphQL input coercion then converts them, for example a JSON number to `Int` or `Float`.
- The tool description is short. It gives the purpose of the tool, the root fields (`board`, `boards`, `node`, `nodes`), and one example query. It does not hold the schema.
- To learn the schema, the agent uses standard GraphQL introspection (`__schema`, `__type`). The engine answers from the live schema, so the answer is always correct.
- The example query in the description is also a test case, so it cannot go out of date.
- Validation errors give "did you mean" suggestions (§4.4), so the model can correct a field name without introspection.
- See §12, item 10.

### 7.2 Public API

```swift
public enum KanbanTool {
    public static let name = "kanban"
    public static func make(root: URL, actor: String?, locator: BoardLocator = .default,   // locator holds the extra search roots
                            embedder: (any TextEmbedding)? = nil) throws -> any Tool
    public static var schemaSDL: String { get }   // generated from the Graphiti schema
}

public actor KanbanGraph {                     // the engine, for direct use and for tests
    public init(root: URL, actor: String?, locator: BoardLocator, embedder: (any TextEmbedding)?) throws
    public func execute(query: String, variables: [String: Map], operationName: String?) async throws -> String
}
```

- The tool is a thin wrapper around `KanbanGraph`.
- **What `KanbanGraph` keeps across calls:** the board index (§6.6), one `MetadataSearcher` for each board (§6.4), and the optional replay cache.
- **What it builds again on each call:** the `Graph`, by replay (§5.4).
- It is an `actor`, so its state is safe. An actor can run a second call at each `await`, so the actor alone does not make calls run one at a time. Thus, `execute` also goes through a serial gate (an async queue), and calls in the same process run one at a time. The file locks and the commit check (§5.4) protect against other processes.
- A CLI target (`kanban`) runs `kanban '<document>' [--variables <json>]` against the current directory, and `kanban --schema` prints the generated SDL.

## 8. Package layout

```
FoundationModelsKanban/
  Package.swift                       # tools 6.2, .macOS("27.0")
  plan.md
  README.md
  Sources/
    FoundationModelsKanban/
      Identity/      NodeURI.swift, BoardKey.swift, ShortID.swift, RefResolver.swift
      Model/         Graph.swift (in-memory store), TaskNode.swift, ColumnNode.swift, ActorNode.swift,
                     TagNode.swift, CommentNode.swift, BoardNode.swift, Ordinal.swift
      Events/        Event.swift, EventLog.swift (read, append, lock), Replay.swift
      GraphQL/       Schema.swift (public, Graphiti), PatchSchema.swift (internal `patch`), QueryResolvers.swift,
                     MutationResolvers.swift, FieldNameRewrite.swift (§4.5), Errors.swift, Scalars.swift
      Derived/       Readiness.swift, VirtualTags.swift, Progress.swift, Timeline.swift
      Filter/        FilterParser.swift, FilterEvaluator.swift
      Search/        TaskSearchItem.swift (SearchableMetadata), TaskSearch.swift
      Tags/          TagSlug.swift, TagMarkers.swift, AutoColor.swift
      Undo/          Inverse.swift, UndoneState.swift, History.swift
      CrossRepo/     BoardLocator.swift
      Tool/          KanbanTool.swift, KanbanArguments.swift, KanbanGraph.swift
    kanban/          KanbanMain.swift (CLI)
  Tests/
    FoundationModelsKanbanTests/
```

Dependencies. Get siblings by URL, the same as CodeContext:

- `FoundationModels` (system).
- `GraphQLSwift/GraphQL` (`https://github.com/GraphQLSwift/GraphQL`) for the parser, the validator, and the executor.
- `GraphQLSwift/Graphiti` (`https://github.com/GraphQLSwift/Graphiti`) to build the schema from Swift types. See §12, item 9.
- A ULID package. Use the same package as Multitool.
- `FoundationModelsMetadataRegistry` (it also brings `FoundationModelsRanker`) for `searchTasks`. See §6.4.
- swift-argument-parser for the CLI.
- swift-log. Optional: swift-distributed-tracing and swift-metrics (API only), the same as CodeContext.
- `FoundationModelsExtras` only if we use one of its helpers. The `Operations` product is not necessary.

## 9. Linking into the agent (code mode)

1. The tool is a plain `Tool`. It does not conform to `OperationDescribing`. Thus, Multitool mounts it as one function: `tools.kanban({ query, variables })`.
2. The tool returns JSON text. Multitool parses a JSON object into structured `GeneratedContent`, so a script gets `result.data.board.task.blockedBy` as a value.
3. A script can pass `variables` as a plain object or as a JSON string. Both work (§7.1).
4. In `FoundationModelsACPAgent/Sources/FoundationModelsACPAgent/Tools/ToolCatalog.swift`:
   - Add a `kanban` config section in `Configuration/ToolSectionCodec.swift` (`ToolSection<KanbanToolOptions>`, add to `knownKeys`).
   - In `makeRegistry(context:)`, add `builder.addTool(try KanbanTool.make(...))`.
   - Add a row to the README § Tools table.
   - Add the package dependency in `FoundationModelsACPAgent/Package.swift`.
5. The ACP agent work is a separate change in that repo. This plan only makes the package ready for it.

Example script in code mode:

```js
const r = await tools.kanban({ query: `{
  board { nextTask(filter: "#kanban") { id shortId title dependsOn { id title column { name } } } }
}` });
const t = r.data.board.nextTask;
if (!t) return "no task is ready";
await tools.kanban({
  query: `mutation($id: ID!) { moveTask(input: { id: $id, column: "doing" }) { id column { name } } }`,
  variables: { id: t.id }               // a JSON string also works
});
```

## 10. Port order

Each step must compile and pass its tests before the next step starts.

1. **Package scaffold.** `Package.swift`, empty library, CLI target, test target, `README.md`.
2. **GraphQL engine.** Add `GraphQLSwift/GraphQL`. Add `GraphQLSwift/Graphiti`. Build the public schema and the internal `patch` schema from Swift types with Graphiti. Connect async resolvers under Swift 6 strict concurrency. Run one query and one mutation end to end. If the library has a Swift 6 concurrency problem, correct it in our wrapper code; do not change the engine.
3. **Identity.** `NodeURI`, `BoardKey` (from git remote), ULID minting with unique short ids, `RefResolver` (URI, ULID, short id, `^short`, prefix, slug, tag name, ambiguous result).
4. **Ordinal.** Fractional index: `first`, `after`, `before`, `between`.
5. **Schema and graph store.** The full Graphiti schema, the `Graph` store, and the query resolvers for the stored fields.
6. **Event log.** Event envelope (`id`, `at`, `actor`, `txn`, `ops`, `boards`, `undoes`), append with `flock`, the commit at the end of the call with its check under the locks (§5.4), read and sort, `.gitattributes` `merge=union`, `.gitignore`.
7. **Patches and replay.** The internal `patch` mutation (`set`, `unset`, `add`, `remove`, `delete`). The graph rules in §3.3 at write time (tombstones, cycle refusal, `COLUMN_NOT_EMPTY`). Rebuild the `Graph` from the logs, with the display rules for a broken merged state (§5.3). Record the timeline values.
8. **Derived fields.** Readiness, `blockedBy`/`blocks`, virtual tags, progress, `started`/`completed`, `Board.summary`.
9. **Tags.** Slug, name validation, auto color, the `#marker` parser, the read-time union of edges and markers, the `renamedTo` redirect, and marker removal in `untagTask`.
10. **Filter DSL.** Parser and evaluator. Use it in `tasks`, `nextTask`, and the `tasks` fields of `Column`, `Actor`, and `Tag`.
11. **Public mutations.** All mutations in §4.2 except `undo` and `redo`. The forgiving refs, the sugar mutations, auto-init, and the session actor.
12. **Errors and forgiving names.** The error codes and corrective messages in §4.4. The field-name rewrite in §4.5.
13. **Search.** `searchTasks` with `MetadataSearcher` (§6.4). Test it first with no embedder, then with an injected fake embedder.
14. **Undo and redo.** The inverse table, the undone state derived from the log, conflict detection, `force`, and the `history` query (§6.5), in one board.
15. **Cross-repo.** `BoardLocator` (scan, search roots, index), board refs, `Query.board(id:)` and `boards`, the `board` field on mutations, multi-board locks, the replay scope (§5.4), enabling a related repo, and `undo` of a transaction that spans boards (§6.6). Unknown targets count as not done.
16. **Tool and CLI.** `KanbanTool`, `KanbanArguments`, the short tool description with its tested example, and the `kanban` CLI.
17. **Multitool proof.** A test that registers the tool in a `MultiTool.Builder` and runs a `runCode` script that adds a task, reads `nextTask`, and moves the task. The script passes `variables` once as an object and once as a JSON string.

## 11. Testing

- Use Swift Testing only (`@Suite`, `@Test`, `#expect`). Do not use XCTest.
- Each test uses a temporary directory as the repo root. Use a fake `BoardKey`, and a fixed clock and ULID source, so the event output is deterministic.
- Most tests call `KanbanGraph.execute` with a GraphQL document, and compare the response JSON.
- **Port the behavior tests from Rust, not the code.** The main source is `crates/swissarmyhammer-kanban/src/dispatch/tests/` (about 200 tests). Write each test again as a GraphQL document:
  - short id and `^` resolution, and ambiguous prefixes;
  - no partial write on an error;
  - date clear and no change;
  - `tasks` filter arguments, `excludeDone`, paging;
  - move with ordinal, `before`, or `after`;
  - archive and unarchive;
  - `nextTask` with a filter;
  - auto-init;
  - the session actor fallback.
- Also port these unit tests: `types/position.rs`, `types/short_id.rs`, `tag_parser.rs` (the parse part), `virtual_tags.rs`, `task/next.rs`, and `swissarmyhammer-filter-expr`.
- Do not port the tests for the `verb noun` parser, the aliases, or the scalar-or-array list input. GraphQL types replace them.
- **Tests that are new for this design:**
  - Replay gives the same projection as the live writes (a property test over random mutation sequences).
  - Shuffle the lines of a log, then replay: the result is the same.
  - Merge two logs with `union`, then replay: the result is correct.
  - A delete makes a tombstone, and the projection ignores edges to the tombstone.
  - Undo: for each public mutation, `undo` gives the same projection as before the call, except for nodes that the call made as a side effect (§6.5). `redo` gives the same projection as after it. Undo of a call with many mutation fields reverses all of them.
  - Undo conflict: a later change to the same property gives `UNDO_CONFLICT`. `force: true` writes the inverse anyway.
  - Undo after a `union` merge of two branches: the undone state is correct for transactions from both branches.
  - `undo` with nothing to undo gives `NOTHING_TO_UNDO`.
  - `deleteTask`, then `undo`, then `redo`: the projection is the same as after `deleteTask`.
  - A commit that finds a changed log on each of 5 runs returns `BOARD_BUSY` and writes nothing.
  - Two `undo` calls in a row reverse the two newest original calls. They do not act as a redo.
  - Undo of `addTask` that made the tag `bug` as a side effect: the task gets a tombstone, and the tag `bug` stays. Undo of `addTag("bug")` after a later task used `bug` gives `UNDO_CONFLICT`.
  - Undo of a transaction that spans two boards, when one board is missing: `NOT_FOUND`, and nothing is written.
  - A dependency on an unknown remote task makes the task blocked.
  - Two temporary repos side by side: `addTask(board: "<related>")` writes to the related log. A related repo with no `.kanban/` gets a new board on its first mutation. A task in one board depends on a task in the other, and `ready` changes when the other task is done. One call that changes both boards is reversed by one `undo`.
  - A `dependsOn` cycle is refused.
  - Broken merged states (§5.3): two branches each add half of a dependency cycle; one branch deletes a column while another moves a task into it; two branches make a rename cycle. After a `union` merge, replay succeeds and the projection follows §5.3.
  - Two concurrent `execute` calls on one `KanbanGraph` run one at a time (the serial gate of §7.2).
  - Two processes add the two halves of a `dependsOn` cycle across two boards at the same time: one call gets `DEPENDENCY_CYCLE` after its commit check.
  - Two processes add a task at the same time: both tasks are written, and the short ids are unique (the commit check of §5.4).
  - `Bug` and `bug` give the same tag. An empty slug gives `INVALID_TAG_NAME` or `INVALID_SLUG`.
  - A no-op mutation writes no patch.
  - Tags from markers: `#bug` in the text gives the tag `bug`. Remove the marker from the text, and the tag goes away. `untagTask` on a marker tag removes the marker from the text. A tag that is on an edge and in a marker stays until both are removed.
  - Rename `bug` to `defect`: tasks with `bug` show `defect`, `#bug` still matches, and a branch that adds `bug` after the rename merges correctly. A rename to an existing tag writes only the redirect. A rename that makes a cycle gives `TAG_RENAME_CYCLE`.
  - Each public mutation writes only `patch` events, with only the properties that change.
  - Two branches add different tags to the same task. After a `union` merge, the task has both tags.
  - A log with an unknown property still replays. A new property on an old node gives its default value.
  - `variables` as an object, as a JSON string, as JSON in a code fence, as `null`, and as no key all give the same result. A string that is not a JSON object gives `INVALID_VARIABLES`.
  - Each error code has a test, and each message gives a correction.
  - `taskAdd`, `addTask`, and `createTask` give the same event. The response key is the name that the caller wrote. `createTask` does not map to `initBoard`.
  - A deep query (task → dependsOn → comments → author) returns the correct nested graph.
- **Tool test.** Call the `Tool` with `GeneratedContent` arguments, and compare the JSON output.
- **Code mode test.** Step 17.

## 12. Decisions

The owner made each decision below.

1. **Board noun. — DECIDED.** The root node is `Board`. One repo has one board. `Board` holds `name`, `description`, and `summary`, and it is the root of the tree. `initBoard` and `updateBoard` are its mutations. The Rust `project` noun is removed, and tags do its job.
2. **Perspectives. — DECIDED.** Removed. There is no `Perspective` node. A saved view is a GraphQL query document that a script or a skill keeps.
3. **Schema change over time. — DECIDED.** No upgrade step and no version field. Each event is a property patch (`set`, `unset`, `add`, `remove`, `delete`) on one node, and the state is the accumulated result. The public mutations are not in the log, so they can change freely (§5.1, §5.3).
4. **Board key (the `board-key` in the URI). — DECIDED.** The key is the initial git remote `origin`, normalized to `host/owner/repo` (the SSH and HTTPS forms give the same key). The first board patch records it (`set key`). After that, the tool reads the key from the log, not from git, so a clone, a move, or a remote change does not change the URIs. A repo without a remote uses `local/<directory-name>`. Known limit: a fork has the same key as its source.
5. **Log layout. — DECIDED.** One log file for each node (§5.2). Two branches that change different nodes change different files. The `union` merge driver keeps both sides when two branches change the same node. One `events.jsonl` for the full board is not used, because each branch would then change the same file.
6. **Search. — DECIDED.** Use FoundationModelsMetadataRegistry (`MetadataSearcher`), which uses FoundationModelsRanker for BM25 + trigram + optional embedding cosine with RRF fusion (§6.4). The kanban package does not write its own ranker.
7. **Tags in the description text. — DECIDED.** A task gets its tags from two sources: the `tags` edges and the `#markers` in the current description. The projection calculates the union at read time (§6.1). `tagTask` changes only edges. `untagTask` removes the edge, and also the marker if it is in the text. The Rust rule (the body text is the only source) is not used, because the last write to the description wins, and a merge can then lose a tag.
8. **Shape of `variables`. — DECIDED.** Accept both forms: a plain object (code mode) and a JSON object in a string (the on-device model). Also accept a code fence around the JSON, `null`, and no value. A custom `ConvertibleFromGeneratedContent` init does the decode. The declared schema of `variables` is `DynamicGenerationSchema(anyOf:)` of a string and an object with no properties. Multitool passes a script object, and an empty object from the model means "no variables" (§7.1).
9. **GraphQL engine. — DECIDED.** Use `GraphQLSwift/GraphQL` for parse, validate, and execute. Use `GraphQLSwift/Graphiti` to build the schema from Swift types, so that the Swift types are the one source of truth. The SDL is generated, not written. The forgiving field-name rewrite (§4.5) changes the parsed document before validation. The internal `patch` mutation is in a separate schema, so that the model cannot write a patch directly.
10. **Schema in the tool description. — DECIDED.** The description does not hold the schema. It holds the purpose, the root fields, and one tested example query. The agent learns the schema with standard introspection (§7.1). Thus, the schema has one view, and it cannot go out of date.
11. **Import of old boards. — DECIDED.** No import. The tool does not read the Rust `.kanban/` data. Replay reads only `*.jsonl` files, so old Rust files (`.yaml`, `.md`) in the same directory are ignored.
12. **Undo. — DECIDED.** Undo and redo are in the first version (§6.5). A transaction is one tool call. `undo` appends inverse patches and never changes the log. A conflict with a later change is refused unless `force: true`. The undone state is derived from the log, so it survives git merges. A `history` query lists transactions.
13. **Cross-repo location. — DECIDED.** Scan the parent directory of the current repo, plus search roots from the config, for git repos. No key-to-path map. The scan finds enabled boards (with `.kanban/board.jsonl`) and related repos that are not enabled yet (key from `origin`). The tool can read and change related boards in the same format, and its first mutation in a related repo that is not enabled makes the board there (§6.6).
14. **Mutation name order. — DECIDED.** Each mutation has the noun in its name. A generic mutation with the type as a parameter is not used, because GraphQL has no generics. The tool accepts both orders, verbNoun (`addTask`) and nounVerb (`taskAdd`), and also the verb synonyms. The SDL uses verbNoun as the one canonical form. A rewrite step before validation does the mapping (§4.5).
15. **Tag rename. — DECIDED.** Tags use the slug as identifier. A rename makes a redirect (§6.2): the old tag gets `renamedTo`, and the projection follows it for edges and for `#markers`. No task patches are necessary, and concurrent branches stay correct. A rename that changes only `name`, and a rename that changes the edge on each task, are not used.

## 13. References

- Rust kanban: `../swissarmyhammer/crates/swissarmyhammer-kanban` (ops, dispatch, tags, virtual tags, next task), `swissarmyhammer-filter-expr`, `swissarmyhammer-entity`, `swissarmyhammer-store`, `swissarmyhammer-tools/src/mcp/tools/kanban/`.
- Package conventions: `../FoundationModelsCodeContext/Package.swift` (siblings by URL, tools 6.2, macOS 27, test layout).
- Code mode: `../FoundationModelsMultitool/Sources/FoundationModelsMultitool/Surface/RegistrySource.swift` (how a plain `Tool` is mounted) and `MultiToolBuilder.swift`.
- Agent linkage: `../FoundationModelsACPAgent/Sources/FoundationModelsACPAgent/Tools/ToolCatalog.swift`.
