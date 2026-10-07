# Plan: FoundationModelsKanban — a task graph that you talk to with GraphQL

This package moves the kanban function of `../swissarmyhammer` (Rust) to Swift.

The tasks are a graph. GraphQL is the protocol to read and change the graph.
The package gives one `FoundationModels.Tool`, named `kanban`. Each call runs to completion. The tool call does no work after it returns.
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
3. **No background work in a tool call.** Each tool call runs to completion before it returns. `KanbanGraph` keeps the graph of each loaded board in memory, and a file watcher keeps it current when the logs change on disk (§5.6). The watcher is the only background work.
4. **Event sourcing.** The event log is the only stored data. The current state is the result of the replay of the log. The tool does not write a YAML or Markdown file for an entity.
5. **Graph.** Each entity is a node with a global URI. Each relation is an edge to the target node. In the log, an edge holds a local ref when the target is in the same board, and the full URI only when the target is in a different board (§3.2).
6. **Cross-repo.** A task in one repo can depend on a task in a different repo. The tool can also read and change the boards of other repos that it finds on the disk (§6.6).
7. **Forgiving input, strict log.** The resolvers accept loose input (short ids, slugs, tag names). The log stores only canonical, fully resolved values.
8. **Code mode.** In Multitool, a script calls `tools.kanban({ query, variables })` and gets the graph back as a structured value.
9. **Local data is portable.** The log of a board does not contain the key of that board. Ids of local nodes are stored as local refs (`task/<ULID>`), not as `kanban://` URIs. Thus, a move of the repo (a new remote, a new owner, a fork, a new directory) does not change the stored data. Only a ref to a node in a different board is stored as a full `kanban://` URI (§3.2).

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
- **Entity cache events, broadcast channels, GUI views and commands, merge-driver install.** (The Rust watcher and change events are replaced by GraphQL subscriptions, §6.7. The Rust undo stack is replaced by undo from the event log, §6.5.)
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

- **`board-key`** comes from the current git remote `origin`, normalized to `host/owner/repo`. If there is no remote, the key is `local/<directory-name>`. The tool reads the key from git each time that it opens the board. The key is **not** stored in the log. Thus, when the repo moves, the URIs of its nodes follow the repo. See §12, items 4 and 18.
- **Stored form: local ref.** The log stores the id of a node in the same board as a **local ref**: the URI without the `kanban://<board-key>/` prefix.

  | Node | Local ref | Full URI (only in GraphQL input and output) |
  |---|---|---|
  | `Board` | `board` | `kanban://<board-key>/board` |
  | `Column` | `column/doing` | `kanban://<board-key>/column/doing` |
  | `Actor` | `actor/claude-code` | `kanban://<board-key>/actor/claude-code` |
  | `Task` | `task/01K6Z3…` | `kanban://<board-key>/task/01K6Z3…` |
  | `Tag` | `tag/bug` | `kanban://<board-key>/tag/bug` |
  | `Comment` | `comment/01K6Z5…` | `kanban://<board-key>/comment/01K6Z5…` |

  - The local ref is used for: the `node` of a patch, the envelope `actor`, the edges `column`, `assignees`, `tags`, `task`, and `author`, the tag `renamedTo`, and a `dependsOn` edge to a task in the **same** board.
  - **Only a ref to a different board is stored as a full URI.** In the current design, this is a `dependsOn` edge to a task in a different repo, and the keys in the envelope `boards` (§5.1).
  - **Text is stored as written.** A `kanban://` URL in the body of a node stays in the text as the agent wrote it, fully qualified. The tool does not rewrite text. A task URL in the body of a task is a dependency marker (§6.1).
  - **Conversion is at the boundary.** A resolver changes a ref to the stored form before it makes a patch: a full URI with the key of the target board becomes a local ref, and a short form resolves to a local ref. When a resolver returns an `ID`, it adds `kanban://<board-key>/` with the current key of the board. Replay and the `Graph` store use only the stored form.
  - **One rule decides the form.** A stored ref that starts with `kanban://` is remote. All other stored refs are local to the board of the log file.
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

1. Each stored edge holds the local ref of its target. A `dependsOn` edge to a task in a different board holds the full URI of that task (§3.2).
2. A delete makes a **tombstone**. It does not change other nodes.
3. At read time, the projection ignores an edge to a tombstoned node. Thus, delete does not need cascade writes. Lists do not show a tombstone, except `tasks(deleted: true)`, which lists only deleted tasks. `node(id:)`, `nodes(ids:)`, and `NodeUpdate.node` return it with `deleted` set, so that a caller can see when the node was deleted.
4. A `dependsOn` edge to a node that is **not known** (for example, the other repo is not available) counts as **not done**. The task is then blocked. This is the same as the Rust rule "missing dependency = blocked".
5. A column that has live tasks cannot be deleted (`COLUMN_NOT_EMPTY`).
6. A `dependsOn` edge that makes a cycle is refused (`DEPENDENCY_CYCLE`). The check reads all boards on the cycle path, and the commit check of §5.4 covers these boards. The Rust code defined this error but did not use it.
7. **Rules 5 and 6 (and the rename-cycle rule in §6.2) apply only when a mutation writes patches.** Replay never refuses a log. A `union` merge of two branches can make a state that breaks a rule. §5.3 tells how the projection shows such a state.

## 4. The GraphQL API

The schema is defined in Swift (`GraphQL/Schema.swift`) with Graphiti, from the Swift node types. The SDL below is a sketch of the generated output. It is not a file in the package.

### 4.1 Types and queries (sketch)

```graphql
scalar DateTime
scalar JSON                           # any JSON value; used for the before and after values of a change

interface Node {                      # each node is a document: properties plus one Markdown body (§5.5)
  id: ID!
  body: String!                       # Markdown; "" when not set
  created: DateTime!                  # the time values are derived from the log, never stored (§5.3)
  updated: DateTime!
  deleted: DateTime                   # set only on a tombstone (§3.3)
}
# Each type below implements all Node fields. The sketch does not repeat each one.

type Board implements Node {
  id: ID!
  body: String!
  key: String!
  name: String!
  columns: [Column!]!                 # the tree: Board > Column > Task > Comment
  actors: [Actor!]!                   # shared nodes
  tags: [Tag!]!                       # shared nodes
  task(id: ID!): Task
  tasks(filter: String, column: ID, tag: ID, assignee: ID,
        excludeDone: Boolean,          # no value: true, or false when a column is named (§6.3)
        deleted: Boolean = false,      # deleted: true = only tombstones
        first: Int = 10, after: String): TaskConnection!
  nextTask(filter: String): Task
  searchTasks(query: String!, filter: String, first: Int = 10): [TaskHit!]!   # §6.4
  summary: BoardSummary!              # counts: total, ready, blocked, done, percent
  history(type: [NodeType!], node: ID, actor: ID, filter: String, derived: Boolean = true,
          since: ID, first: Int = 20): [Change!]!   # §6.5, newest first; since = only after that txn (§6.7)
}

type Change {                         # one transaction (one tool call); §6.5, §6.7
  txn: ID!  at: DateTime!  actor: Actor!  ops: [String!]!  boards: [String!]!
  undone: Boolean!  undoes: ID
  updates(type: [NodeType!], node: ID): [NodeUpdate!]!   # one item for each node that changed
}
type NodeUpdate {
  id: ID!                             # the node URI; always set, also for a deleted node
  type: NodeType!                     # BOARD | COLUMN | TASK | TAG | ACTOR | COMMENT
  kind: UpdateKind!                   # CREATED | UPDATED | DELETED | RESTORED
  source: UpdateSource!               # PATCH (a stored property changed) | DERIVED (only a derived field changed)
  fields: [FieldChange!]!
  node: Node                          # the node now; for DELETED, the tombstone with `deleted` set
}
type FieldChange {
  name: String!                       # the public field name, for example "column", "tags", "ready"
  before: JSON  after: JSON           # for a single value; null for "body"
  added: [JSON!]  removed: [JSON!]    # for a list value, for example tags, assignees, dependsOn
  diff: String                        # only for "body": a unified diff from before to after (§5.5)
}
# Change.boards has one key when the transaction changed one board.
# history(node:) and changes(node:) match a Change that has an update for that node.

type Column implements Node { id: ID!  body: String!  name: String!  order: Int!  tasks(filter: String): [Task!]! }
type Actor  implements Node { id: ID!  body: String!  name: String!  color: String  tasks(filter: String): [Task!]! }
type Tag    implements Node { id: ID!  body: String!  name: String!  color: String!  tasks(filter: String): [Task!]! }

type Task implements Node {
  id: ID!
  body: String!                       # #tag markers and kanban:// dependency markers (§6.1)
  shortId: String!
  title: String!
  column: Column!
  ordinal: String!
  assignees: [Actor!]!
  tags: [Tag!]!
  dependsOn: [Task!]!                 # can resolve across repos
  blockedBy: [Task!]!                 # derived
  blocks: [Task!]!                    # derived
  ready: Boolean!                     # derived
  virtualTags: [String!]!             # READY | BLOCKED | BLOCKING | CONFLICT
  progress: Progress!                 # derived from Markdown checklists
  comments: [Comment!]!
  created: DateTime!                  # all time values are derived from the event log (§5.3)
  updated: DateTime!
  deleted: DateTime
  started: DateTime
  completed: DateTime
}

type Comment implements Node { id: ID!  body: String!  shortId: String!  task: Task!  author: Actor!  created: DateTime!  updated: DateTime! }

type Subscription {
  changes(board: String, type: [NodeType!], node: ID, actor: ID, filter: String,
          derived: Boolean = true): Change!   # §6.7; the live form of history
}

type Query {
  board(id: String): Board            # no id = this repo, never null. With an id: a board key, repo directory name,
                                      # or path (§6.6); null only together with a NOT_FOUND error
  boards(enabled: Boolean): [Board!]! # related boards that the scan found; filter by enabled state (§6.6)
  node(id: ID!): Node                 # direct access by URI, also in a different repo
  nodes(ids: [ID!]!): [Node!]         # the nodes in the order of the ids; an id that names no node is dropped,
                                      # so no id that matches gives []. null only together with an error (for
                                      # example AMBIGUOUS_ID, the same rule as node); the other data stays
}
```

The root has only four fields. All other reads go down the tree from `board`. For example:

```graphql
{ board { columns { name tasks(filter: "#kanban") { shortId title
    comments { body author { name } } assignees { name } tags { name } } } } }
```

`TaskConnection` uses cursor paging (`edges`, `pageInfo`, `totalCount`). This replaces the Rust `page` and `page_size` params.

### 4.2 Mutations

Each Rust write op becomes one mutation field. The names use the `verbNoun` form. Each public mutation writes one or more property patches to the log (§5.1).

Each mutation takes one `input` object. The table lists the fields of that object. `input` is optional when it has no required field (for example `undo`, `redo`, `initBoard`).

**Notation.** In this plan, `f(x: v)` means `f(input: { x: v })`.

These mutations also have an optional `board` field in `input`, because they name a node by a short form or by no id, not by a node URI: `initBoard`, `updateBoard`, `addTask`, `addColumn`, `addActor`, `addTag`, and `renameTag`. A mutation on an existing node (including `addComment`, which names its task) finds its board from that node. See §6.6.

| Mutation | Fields of `input` | Patches in the log |
|---|---|---|
| `initBoard` | `name`, `body` | board: `set name`, `edit body`; 4 columns: `set name, order` (default columns). On a board that exists: only the given fields that differ; no columns are added. |
| `updateBoard` | `name`, `body` | board: `set` the given properties, `edit body` |
| `addTask` | `title!`, `body`, `column`, `ordinal`, `assignees`, `tags`, `dependsOn` | task: `set` the scalars, `edit body`, `add` the edges; one `set` patch for each unknown tag |
| `updateTask` | `id!`, and any field of `addTask` except `column` and `ordinal`. A list value replaces the list. `null` clears a field. | task: `set` / `unset` the scalars; `edit body`; `add` / `remove` the list difference |
| `moveTask` | `id!`, `column!`, `ordinal`, `before`, `after` | task: `set column, ordinal` (plus a column `set` patch if the column is new) |
| `completeTask` | `id!` | task: `set column, ordinal` (terminal column) |
| `assignTask` / `unassignTask` | `id!`, `actor!` | task: `add` / `remove` on `assignees` |
| `tagTask` / `untagTask` | `id!`, `tags!` | task: `add` / `remove` on `tags` (plus a tag `set` patch for each unknown tag) |
| `deleteTask` / `undeleteTask` | `id!` | task: `delete` true / false |
| `undo` | `txn` (optional), `force`, `board` (optional) | the inverse patches of the transaction (§6.5) |
| `redo` | `txn` (optional), `force`, `board` (optional) | the inverse patches of an `undo` transaction (§6.5) |
| `addColumn` / `updateColumn` / `deleteColumn` / `undeleteColumn` | `id`, `name`, `order`, `body` | column: `set`, `edit body` / `delete` true / false |
| `addActor` / `updateActor` / `deleteActor` / `undeleteActor` | `id`, `name`, `color`, `body`, `ensure` | actor: `set`, `edit body` / `delete` true / false |
| `addTag` / `updateTag` / `deleteTag` / `undeleteTag` | `id` (slug), `name`, `color`, `body` | tag: `set`, `edit body` / `delete` true / false (`addTag` is idempotent on slug). `updateTag` does not change the slug. |
| `renameTag` | `from!`, `to!` | new tag: `set` (only if `to` does not exist); old tag: `set renamedTo` (§6.2) |
| `addComment` / `updateComment` / `deleteComment` / `undeleteComment` | `task`, `id`, `body`, `actor` | comment: `set task, author`, `edit body` / `edit body` / `delete` true / false (plus an actor `set` patch if the author is new) |

**Delete and undelete.** There is no archive. A delete is one more patch in the log (`delete: true`), and an undelete is one more patch (`delete: false`). Each `undelete` mutation takes the id of a tombstone (a short form also resolves to a tombstone) and returns the live node. An undelete of a node that is not deleted writes nothing. `undelete` is different from `undo`: it does not need the `txn`, and it has no conflict check. The graph rules of §3.3 apply: for example, `undeleteColumn` is always accepted, and `deleteColumn` on a column with live tasks is refused.

**`body` input.** In each mutation, `body` is the full new Markdown text. The agent does not write a diff. The tool calculates the diff from the current body and writes it as an `edit` patch (§5.5). If the text does not change, the tool writes no `edit` patch.

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
- **Patches hold canonical values:** refs in the stored form of §3.2 (local refs, and full URIs only for a different board), minted ids, computed ordinals, and resolved actors. A patch does not generate an id or read the clock. Thus, replay is deterministic.
- **Many mutations in one document** run in sequence, as the GraphQL specification requires. This replaces the Rust batch input.
- **Schema changes need no upgrade step.** See §5.3 and §12, item 3.

### 4.4 Errors

The response follows the GraphQL specification: `{ "data": …, "errors": [ … ] }`.

- Each error has `message`, `path`, and `extensions.code`.
- The codes are: `INVALID_VARIABLES`, `NOT_FOUND`, `AMBIGUOUS_ID`, `ACTOR_NOT_FOUND`, `DUPLICATE_ID`, `COLUMN_NOT_EMPTY`, `DEPENDENCY_CYCLE`, `TAG_RENAME_CYCLE`, `NOTHING_TO_UNDO`, `UNDO_CONFLICT`, `INVALID_FILTER`, `INVALID_TAG_NAME`, `INVALID_SLUG`, `INVALID_ORDINAL`, `BOARD_BUSY`, `SUBSCRIPTION_NOT_IN_TOOL`.
- The message must tell the model how to correct the call. For example, an `AMBIGUOUS_ID` error gives the matching ids.
- A syntax or validation error gives the GraphQL "did you mean" suggestion. This is after the name rewrite in §4.5.
- If a mutation field fails, no patch of that field is written. The patches of the other fields of the call are written (§5.4). The tool validates all patches of a field before it keeps them.
- The tool does not throw for a GraphQL error. It returns the response JSON. The tool throws only for a fault that the caller cannot correct, for example an I/O failure.

### 4.5 Forgiving names

The agent can make many small mistakes in names. The tool corrects each name that it can match with no doubt. A rewrite step changes the parsed document before validation.

**Positions.** The rewrite applies to each name in the document:

| Position | Example of agent input | Rewritten to |
|---|---|---|
| Top-level mutation | `taskAdd`, `createTask`, `create_task` | `addTask` |
| Field in a selection | `{ task { Title, desc, labels } }` | `title`, `body`, `tags` |
| Argument and `input` field | `moveTask(input: { task_id: …, status: "doing" })` | `id`, `column` |
| Enum value | `DONE`, `Done` | the canonical value |
| Root query field | `{ tasks { … } }` | `{ board { tasks { … } } }` |

**Match steps.** For each name that the schema does not have, the step tries these in order. It stops at the first step that gives exactly one match:

1. The exact name.
2. The same name with the case and style made the same: `camelCase`, `snake_case`, `kebab-case`, and any letter case.
3. The singular or plural form.
4. For a top-level mutation: the other word order (verbNoun or nounVerb) and the verb synonyms. The synonyms are `create`/`new`/`insert` → `add`, `remove`/`rm`/`del` → `delete`, `edit`/`modify`/`set`/`patch` → `update`, `mv` → `move`, `done`/`finish`/`close` → `complete`, `label` → `tag`, `unlabel` → `untag`, and `restore` / `unarchive` / `recover` → `undelete`, `archive` → `delete`. These are the Rust verb aliases, with archive mapped to delete.
5. The alias table of the field, for example `description` / `desc` / `text` / `content` → `body`, `label` → `tag`, `status` → `column`, `assignee` → `assignees`, `task_id` → `id`.
6. A close spelling: one changed, added, or removed letter. This step applies only to names of 4 or more letters.

**Rules:**

- **No guess when there is a tie.** If one step gives two or more matches, the tool does not choose. It returns an error that lists the matching names.
- **Some mappings are never made.** The tool keeps a list of mappings that it must not make. For example, `create` never maps to `init`.
- **The schema has one name for each field.** The canonical names use camelCase, and mutations use the verbNoun form (`addTask`, `moveTask`, `initBoard`). The aliases are defined in Swift next to each field, so the Swift types stay the one source of truth (§1). Introspection shows only the canonical names, so the schema stays small.
- **The response key does not change.** For a field in a selection, the rewrite adds a GraphQL alias. For example, `taskAdd(...)` becomes `taskAdd: addTask(...)`, and `desc` becomes `desc: body`. Thus, the caller finds the result under the name that it wrote. If the caller already wrote an alias (`x: taskAdd(...)`), the step keeps `x`.
- **Root query fields.** If the root has no field with the name, but `Board` has one, the step moves the field into `board { … }`. After execution, the tool moves the result back, so the response has `data.tasks`, not `data.board.tasks`.
- **The tool tells the agent what it changed.** The response has `extensions.rewrites`, a list of `{ from, to, path }`. Thus, the agent learns the canonical names.
- If no step matches, normal validation runs and gives the "did you mean" error (§4.4).
- The rewrite does not change the log. The log holds only property patches (§5.1).

## 5. Storage: the event log

### 5.1 Event format

Each line of a log is one **property patch** on one node. The patch is a GraphQL request to one generic internal mutation, `patch`, plus an envelope:

```json
{"id":"01K6Z4...","txn":"01K6Z4...","ops":["addTask"],"at":"2026-10-06T14:49:10.690Z","actor":"actor/claude-code",
 "query":"mutation($p: PatchInput!) { patch(input: $p) }",
 "variables":{"p":{"node":"task/01K6Z3...","type":"Task",
   "set":{"title":"Port the filter DSL","column":"column/todo","ordinal":"80"},
   "add":{"tags":["tag/kanban"],
          "dependsOn":["task/01K6Y9...","kanban://github.com/o/other/task/01K6X2..."]}}}}
```

All refs are in the stored form of §3.2. The first `dependsOn` target is in the same board, so it is a local ref. The second target is in a different repo, so it is a full URI.

| Field | Meaning |
|---|---|
| `id` | The event ULID. The replay order is the sort order of this field. |
| `at` | The time of the event (UTC, RFC 3339). This is the only clock value in the event. |
| `actor` | The local ref of the actor that made the change, in the board of this log. |
| `txn` | The transaction ULID. All patches of one tool call have the same `txn` (§6.5). |
| `ops` | The names of the public mutations in the tool call, for example `["moveTask"]`. Only for `history`. Replay does not use it. |
| `boards` | Only when the transaction changes more than one board: the keys of the **other** boards that it changes. The board of this log is implied, so its own key is not stored. `undo` uses it (§6.5). |
| `undoes` | Only on the patches of `undo` and `redo`: the `txn` that this transaction reverses. |
| `query`, `variables` | A GraphQL request to the internal `patch` mutation. |

The `PatchInput` has these parts. Each part is optional, except `node` and `type`:

| Part | Meaning |
|---|---|
| `node` | The local ref of the one node that the patch changes. A patch always changes a node in the board of its log. |
| `type` | The node type (`Board`, `Column`, `Task`, `Actor`, `Tag`, `Comment`). |
| `set` | Properties to write. A value replaces the old value. |
| `unset` | Property names to clear. |
| `add` | Values to add to a set-valued property (for example `tags`, `assignees`, `dependsOn`). |
| `remove` | Values to remove from a set-valued property. |
| `delete` | `true` makes a tombstone (§3.3). `false` removes the tombstone (used by the `undelete` mutations and by `undo`). |
| `edit` | A unified diff for the Markdown `body` of the node: `{"body": "<unified diff>"}`. This is the only way that a patch changes the body (§5.5). |

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
  .gitignore                     # .lock
  .lock                          # the write lock
```

There is no cache and no snapshot. The logs are the only data on disk. `KanbanGraph` builds the `Graph` from them one time, and then keeps it live (§5.3, §5.6).

Decision: **one log file for each node.**

- Two branches that change different tasks change different files. Thus, git merges have fewer conflicts.
- When two branches change the same task, the git `union` merge driver keeps the lines from both sides. This is a built-in driver, so we do not install a custom one.
- Replay sorts the events by event ULID, not by line position. Thus, the order of lines after a merge is not important.

See §12, item 5.

### 5.3 Replay and projection

**The parallel loader.** Each patch changes exactly one node, and each node has its own log file (§5.2). Thus, the state of a node depends only on the lines of its own file, and the files can be read at the same time. The loader reads a board in **stages**, in entity order:

| Stage | Files | Joins to the stages before it |
|---|---|---|
| 1 | `board.jsonl` | — |
| 2 | `actors/*.jsonl` | — |
| 3 | `columns/*.jsonl` | — |
| 4 | `tags/*.jsonl` | `renamedTo` → tag (same stage; resolved at the end of the stage) |
| 5 | `tasks/*.jsonl` | `column` → column, `assignees` → actor, `tags` → tag, `dependsOn` → task (same stage; resolved at the end of the stage) |
| 6 | `comments/*.jsonl` | `task` → task, `author` → actor |

- **Work queue.** One stage puts all its files into a work queue. A fixed set of workers (a `TaskGroup` with `ProcessInfo.activeProcessorCount` workers) takes files from the queue until it is empty. Each worker reads one file, parses each line, sorts the events of that file by event `id`, and folds them into the state of the node (step 2 below). The stage ends when all workers are done (a barrier). Then the next stage starts.
- **Join.** Each node has a stable **slot**: an integer index into the node table of the `Graph`. A local ref gets its slot one time, and keeps it for the life of the graph. When a stage ends, the loader adds its nodes to the node table and changes each stored ref (§3.2) to the slot of its target in an earlier stage. Thus, the in-memory graph has real edges, and a resolver does not look up a ref at read time. Because edges hold slots and not object pointers, a later reload of one node (§5.6) replaces the state in its slot, and the edges from other nodes stay correct. The `Graph` is a Swift value type, so a copy is cheap (copy-on-write). A ref that has no target (a cross-board `dependsOn`, or a target that a broken merge removed, §5.3 step 5) stays as an unresolved ref.
- **Why this order.** Each stage needs only the nodes of the stages before it. For example, a task (stage 5) joins to its column (stage 3), its assignees (stage 2), and its tags (stage 4), and a comment (stage 6) joins to its task.
- **Global order.** After the last stage, the loader merges the sorted event lists of all files (a k-way merge by event `id`) into one list. Undo (§6.5), `history`, and the change feed (§6.7) use this list. The node state does not need it.
- **Load one time, then keep it live.** `KanbanGraph` loads a board with this loader the first time that a call needs it. After that, it keeps the `Graph` of the board in memory, and a file watcher keeps it current (§5.6). There is no cache on disk.

Steps 1 to 3 are done by a worker, for one node. Steps 4 and 5 are done on the joined `Graph`, after the last stage.

1. Read the `*.jsonl` file of the node. Parse each line. Sort the events of the file by event `id`.
2. Apply each patch to the empty state of the node. The state of a node is the accumulated result of its patches:
   - `set` writes a value. A later `set` of the same property wins (the order is the event ULID).
   - `unset` clears a value.
   - `add` and `remove` change the members of a set-valued property.
   - `delete: true` makes a tombstone. `delete: false` removes it.
   - `edit` applies the diff to the current body (§5.5).
3. While the patches apply, record the time values for each node: `created`, `updated`, `deleted`, `started`, `completed`. Each value is the envelope `at` of a patch. **No patch stores a time value**, and these names are not properties that a patch can `set`.
   - `created`: the time of the first patch. `updated`: the time of the last patch.
   - `deleted`: the time of the last `delete: true`, only while the node is a tombstone. A `delete: false` clears it.
   - For a task, the worker also records each `set column` as a pair (time, column). It does not calculate `started` and `completed` here, because they depend on the column order, and a column can change later.
4. Calculate the derived fields at read time: `blockedBy`, `blocks`, `ready`, `virtualTags`, `progress`, and for a task:
   - `started`: the time of the first column move to a column that is not the first column (in the current column order).
   - `completed`: the time of the last column move, only if the task is now in the terminal column.
5. **Show a broken merged state without an error** (§3.3, rule 7):
   - A `dependsOn` cycle: each task in the cycle counts as blocked. A readiness walk stops when it finds a task that it already visited.
   - A task in a tombstoned column, or with no column: it shows in the first column.
   - A comment on a tombstoned task: it is hidden.
   - A comment whose author is a tombstoned actor, and a `Change` whose actor is a tombstoned actor: `author` and `actor` return the tombstone, with `deleted` set. These fields are non-null, so the projection does not ignore this edge (an exception to §3.3, rule 3).
   - A `renamedTo` chain with a cycle: the walk stops at the first slug that repeats, and uses that tag.
   - Two columns with the same `order`: sort them by slug.

**Schema changes need no upgrade step.** A patch only holds property values, so it does not depend on the shape of the public mutations:

- A new property: old nodes do not have it. The resolver gives its default value.
- A removed property: the projection keeps the old value, but no resolver reads it.
- A renamed property: the resolver reads the new name first, then the old name.
- The public mutations can change freely, because they are not in the log.

### 5.4 Call path

1. Parse the GraphQL document. Run the name rewrite (§4.5). Validate the document against the public schema.
2. Get the live `Graph` of the current board (§5.6). First apply all file changes that the watcher has reported and that are not applied yet. Load a related board only when the call reaches it: by an edge (for example `dependsOn`), a URI, or a `board` field. A board that is not loaded yet is loaded with the parallel loader (§5.3), and then it stays live.
   - A mutation works on a **working copy** of each graph (a copy-on-write value). The live graphs do not change until the commit succeeds.
3. For a query: run the resolvers and return the response.
4. For each mutation field, in order:
   1. Resolve each forgiving ref against the `Graph` (§3.2).
   2. Make the property patches: mint the ids, compute the ordinal, set the actor. Include only the properties that change.
   3. Apply the patches to the in-memory `Graph`. If a graph rule fails, return an error for this field, and discard the patches of this field.
   4. Keep the patches in memory. Record the boards that the field changed and the boards that it read for a graph rule.
   5. Resolve the selection set of the field against the in-memory `Graph`.
5. **Commit, at the end of the call.** If the call kept at least one patch:
   1. Get an exclusive lock on the `.kanban/.lock` of each board that the call changed or read for a graph rule. Lock in the sort order of the board key, so that two calls cannot deadlock.
   2. Under the locks, check that no log of these boards changed after the live graph last read it. The check compares the file signature of each log (§5.6) and the list of files in each node directory. It does not wait for the watcher. If a log changed, apply the changed files to the live graph (§5.6), release the locks, discard the working copy, all kept patches, and the response, and run the call again from step 2. After 5 runs, stop and return the error `BOARD_BUSY`. The message tells the caller to send the call again.
   3. Append each kept patch to its node log in its board. Each patch has the `txn`, `ops`, and `boards` values of the full call, which are now known.
   4. Record the new file signature of each log that the call appended to. The working copy becomes the live graph. Thus, the watcher event for this write finds no change, and the tool does not read its own write again.
   5. Release the locks, and return the response.
6. A mutation that changes nothing writes no patch. This is the same as the Rust no-op rule.

### 5.5 Documents and the body diff

Each node is a **document**: a set of properties plus one Markdown `body`. All six node types have a body. For a task, the body holds the `#tag` markers and the `kanban://` dependency markers (§6.1). For a comment, the body is the comment text.

The log does not store the full body text on each change. A full copy on each change makes the log large, and a merge of two branches can then lose a change. Thus, the log stores each change to a body as a **unified diff**:

```json
"variables":{"p":{"node":"task/01K6Z3...","type":"Task",
  "edit":{"body":"@@ -3,1 +3,2 @@\n - [ ] parse the filter\n+- [ ] port the evaluator\n"}}}
```

- **Diff format.** Line-based unified diff, with no file header lines (`---`, `+++`). Each hunk has its `@@ -a,b +c,d @@` header and 3 lines of context. The marker `\ No newline at end of file` is used as in git. The tool calculates the diff with Swift `CollectionDifference` over the lines, so that the output is deterministic.
- **The body is always changed by `edit`.** A new node with a body gets one `edit` patch with a diff from the empty text. `set body` and `unset body` are not used. `body: null` or `body: ""` in the input writes a diff to the empty text.
- **The agent sends full text.** The `body` input of a mutation is the full new text (§4.2). The tool makes the diff. A mutation that does not change the text writes no `edit`.
- **Replay applies each hunk in event order.** A hunk applies at its line number if its context and `-` lines match there. If not, replay looks for the nearest position where they match exactly (the same as `patch` with no fuzz). This lets diffs from two branches apply after a `union` merge when they change different parts of the text.
- **A hunk that cannot apply** is not lost. Replay puts a conflict block into the body at the hunk position, in the git form:

  ```
  <<<<<<< current
  (the current lines)
  =======
  (the lines that the hunk wanted)
  >>>>>>> 01K6Z4... (the event id)
  ```

  Replay is deterministic, so all clones show the same block. A task with a conflict block gets the virtual tag `CONFLICT`, so that the filter `#CONFLICT` finds it. The other node types do not have virtual tags; for them, the block shows only in the body. The agent resolves the conflict with a normal `body` update, which writes a diff that removes the block.
- **History and subscriptions.** `FieldChange` for `body` gives `diff`, not `before` and `after` (§4.1, §6.7). When a transaction has more than one `edit` on one body, `diff` is the diff from the body before the transaction to the body after it.
- **Undo** writes the reversed diff (§6.5).

### 5.6 The live graph and the file watcher

A log can change outside the tool: a manual edit, a `git pull`, a merge, a `git checkout` of a different branch, or a write from a different process. `KanbanGraph` watches the files and updates the in-memory graph.

- **Watcher.** When `KanbanGraph` loads a board, it starts an FSEvents stream on the `.kanban/` directory of that board, with file-level events. The watcher runs for the life of `KanbanGraph`, until `close()` (§7.2). It does not depend on subscribers.
- **A repo with no `.kanban/` yet.** The watcher watches the repo directory for a new `.kanban/` directory (for example from a `git pull` or from a different process). When it comes, the tool loads the board and moves the watcher to `.kanban/`.
- **File signature.** For each log file, the graph records a signature: the file size, the modification time, and the id of the last event in the file. A watcher event for a file with the same signature is ignored. This removes the events of the writes of this process, and repeated events from FSEvents.
- **Batch.** FSEvents reports events in groups. The watcher collects the changed paths of one group into a batch, and gives the batch to the serial gate (§7.2). Thus, a batch is never applied while a call runs, and a call never sees a half-applied batch.
- **Apply a batch.** The batch uses the same work queue and the same stage order as the loader (§5.3): board, actors, columns, tags, tasks, comments. For each changed file:
  - **Changed file:** read the full file again, and fold the node again from the start. The tool does not read only the new lines, because a `union` merge or a manual edit can change or reorder any line. The new state replaces the state in the slot of the node.
  - **New file:** make a new slot. Edges that pointed to this ref and were not resolved now resolve to the new slot.
  - **Removed file** (for example after `git checkout`): remove the node from its slot. Edges to it become unresolved refs (§3.3, rule 4).
  - After the stages, join the changed nodes again, update the global event list (add the event ids that are new, remove the event ids that are gone), and update the searcher of the board (§6.4).
- **Large changes.** If a batch changes more than half of the files of a board (for example a branch switch), the watcher loads the board again with the full parallel loader. This is simpler and not slower.
- **A line that does not parse** (for example a manual edit with a typing error): the loader skips that line and records it with swift-log. The node is folded from the other lines. Replay never refuses a log (§3.3, rule 7).
- **Change feed.** After a batch is applied, the new event ids, grouped by `txn`, go to the subscribers as `Change` values (§6.7).
- **Cross-board edges.** Each loaded board has its own watcher. Thus, when a task in a related board changes, the `ready` state of the tasks that depend on it is current.
- **How current the graph is.** FSEvents can deliver an event some milliseconds after the write. The commit check of §5.4 does not depend on the watcher: under the locks, it compares the signatures directly. Thus, a write never builds on data that is not current. A query can see a write from a different process only after its FSEvents event comes in. This is accepted: a query can show old data while the watcher processes events. A query does not check the file signatures.

## 6. Semantics to keep from the Rust code

| Item | Rule |
|---|---|
| Default columns | `initBoard` makes `todo` "To Do" 0, `doing` "Doing" 1, `review` "Review" 2, `done` "Done" 3. |
| Auto-init | If the first mutation runs and `.kanban` has no board, the tool initializes the board with the default columns. The default board `name` is the repo directory name. A query on an empty repo returns an empty board with that name and writes nothing. |
| Terminal column | The column with the maximum `order`. A task there is "done". |
| `ready` | All `dependsOn` targets are done. |
| Virtual tags | `READY` (not done, and all dependencies done), `BLOCKED` (at least one dependency is not done), `BLOCKING` (not done, and some task depends on it). New in this design: `CONFLICT` (the body has a conflict block from a diff that could not apply, §5.5). |
| `nextTask` | From the tasks that are not done, are ready, and match the filter: sort by column order, then by ordinal. Return the first task or `null`. |
| `completeTask` | Move to the terminal column, after the last ordinal there. |
| `moveTask` | Ordinal priority: an explicit `ordinal`, then `before` or `after` a neighbor, then append at the end. A missing column is created (name = slug in title case). |
| Default column on add | The column with the minimum `order`. |
| Ordinals | Fractional index (Figma algorithm), lowercase hex, default `"80"`. Byte compatibility with Rust is not necessary because the storage is new. |
| Session actor | The session actor is the `actor` value of `KanbanGraph.init`, else the OS user. When a call writes at least one other patch to a board, it also makes sure that the session actor exists in that board (an actor `set` patch if it is new). A call that writes nothing writes no actor patch. This rule is the same in the current repo and in related boards. Thus, the envelope `actor` always names a real actor. |
| Assignees | Each assignee must be a known actor. If `addTask` has no assignee, use the session actor if it was a known actor before the call. |
| Comment author | An explicit `actor`, else the session actor. The actor is made if it does not exist. |
| Column and actor slugs | The slug rule of §3.2 (lowercase, not empty). |
| Tag names | Trim, change each run of spaces to `_`, remove NUL, refuse an empty name. The slug is `normalize_slug` and then lowercase (§3.2). `auto_color` = FNV-1a 32-bit hash of the slug, modulo the 16-color palette. |
| Progress | Count the lines `- [ ]` / `- [x]` / `- [X]` in the body. |
| Time values | The Rust `due` and `scheduled` fields are removed. All time values (`created`, `updated`, `deleted`, `started`, `completed`) are derived from the log (§5.3). No mutation accepts a time value. |
| Missing and `null` input | In an `update` mutation, a missing argument = no change, and `null` = clear. |
| Task order in lists | Column order, then ordinal. The Rust code had no explicit sort. |

### 6.1 Tags and dependencies: edges plus body markers

In Rust, tags are `#tag` text markers in the task body. In the graph design, a task gets its tags from two sources. The projection calculates them at read time:

```
task.tags = resolve(tags edges) ∪ resolve(#markers in the current body)
```

- **Resolve** changes each marker to its slug, then follows the `renamedTo` redirect (§6.2). Thus, an old `#bug` marker shows the tag `defect`.
- **`tagTask`** adds an edge. It does not change the text. Two branches that tag the same task merge correctly, because edges use `add` and `remove`.
- **`untagTask`** removes the edge. If the body also has the marker, `untagTask` also removes the marker from the text (an `edit body` patch, §5.5).
- **A marker that the agent removes from the text** removes that tag, unless an edge also holds it. No compare logic is necessary.
- **A new marker** in `addTask` or `updateTask` that names an unknown tag also writes a `set` patch for that tag. Thus, `Board.tags` lists it. If the marker names a tombstoned tag, the tool writes `delete: false` for that tag, so that the tag is live again.
- **A tag rename** does not change any text. The redirect covers edges and markers.
- **The filter `#x`** matches tags from edges and from markers.
- **`addTask(tags:)` and `updateTask(tags:)`** change only the edges.

When the marker is in the text, `untagTask` writes a body diff. The diff changes only the lines with the marker, so it merges with changes to other lines of the body (§5.5).

**Dependencies use the same model.** A full `kanban://<board-key>/task/<ULID>` URL in the body is a **dependency marker**:

```
task.dependsOn = resolve(dependsOn edges) ∪ resolve(kanban:// task URLs in the current body)
```

- **Only the full URL is a marker.** A short id, `^short`, or a URL to a node that is not a task is plain text.
- **The text keeps the full URL.** The URL can name this board or a different board. The tool does not rewrite it.
- **Resolve at read time.** A marker URL whose key is the current key of this board resolves in this board. All other marker URLs resolve as cross-repo refs (§6.6). A marker to a board or a task that is not found counts as not done (§3.3, rule 4).
- **`dependsOn` input** in `addTask` and `updateTask` changes only the edges. The tool stores an edge to the same board as a local ref (§3.2).
- **Remove a dependency.** `updateTask(dependsOn:)` with a shorter list removes edges. If a removed target is also a marker in the text, the tool also removes the URL from the text (an `edit body` patch), the same as `untagTask`.
- **Cycle rule.** A marker that makes a `dependsOn` cycle is refused at write time (`DEPENDENCY_CYCLE`), the same as an edge (§3.3, rule 6).
- **The filter `^x`** (§6.3) matches targets from edges and from markers.
- **Known limit.** A marker URL to this board holds the board key in the text. After a move of the repo, the old key does not match, so the marker resolves as a different board that is not found, and the task shows as blocked. An edge does not have this problem, because it is a local ref. Thus, for a dependency in the same board, the agent should use the `dependsOn` input, not a URL in the text.

See §12, items 7 and 18.

### 6.2 Tag rename

The tag slug is the identifier, and the task edges hold the tag local ref (`tag/<slug>`). Thus, a rename must not break the edges that point to the old slug.

Decision: **a rename makes a redirect.** For example, `renameTag(from: "bug", to: "defect")` writes two patches:

1. New tag `defect`: `set name, color` and `edit body` (the values are copied from `bug`). If `defect` exists, this patch is not written, and `defect` keeps its own values.
2. Old tag `bug`: `set renamedTo = tag/defect`.

- **No task changes.** Task edges still hold `tag/bug`. The projection follows `renamedTo`, so `task.tags` shows `defect`.
- **Safe with merges.** If a different branch adds `bug` to a task at the same time, the edge points to `tag/bug`, and the redirect also covers it.
- **Filters and refs follow the redirect.** `#bug` and `#defect` both match. `addTask(tags: ["bug"])` writes an edge to `defect`.
- **A chain of renames is followed.** For example, `bug` → `defect` → `issue`. A rename that makes a cycle is refused (`TAG_RENAME_CYCLE`). A cycle that a merge makes is shown as §5.3 tells.
- **Board.tags** lists only the tags that have no `renamedTo`. One exception: in a rename cycle from a merge (§5.3), the tag where the walk stops is also listed.
- **Rename to a slug that exists** is a merge: the old tag redirects to the existing tag (only patch 2 is written).
- **All refs to a redirected slug follow the redirect.** This includes `addTag` (it returns the target and writes nothing), `updateTag`, `deleteTag`, and `renameTag`. Thus, `deleteTag(id: "bug")` after the rename deletes `defect`.
- **Delete of a redirect target.** The target gets a tombstone. Edges and markers that point to the old slug follow the redirect to the tombstone, so the tasks lose the tag. This is the same as for a direct edge (§3.3).

See §12, item 15.

### 6.3 Filter DSL

The `filter` argument keeps the full language of `swissarmyhammer-filter-expr`, as the Rust kanban tool description and the `kanban` and `finish` skills (`../skills/skills/kanban`, `../skills/skills/finish`) describe it. A filter that works on the Rust tool must give the same result here, except a filter with the removed `$project` atom. This design makes three changes: it removes `$project`, it adds the column atom `%column`, and it adds `kanban://` URLs.

```
expr     = or_expr
or_expr  = and_expr (("||"|"or"|"OR") and_expr)*
and_expr = not_expr (("&&"|"and"|"AND")? not_expr)*      // two terms next to each other = AND
not_expr = ("!"|"not"|"NOT") not_expr | atom
atom     = "#" body | "@" body | "^" body                 // the Rust atoms, unchanged
         | "%" body                                      // new: column
         | url                                           // new: a bare kanban:// URL
         | "(" expr ")"
url      = "kanban://" body
body     = [^ \t\n\r#@^%$()&|!]+
```

`$` stays out of `body`, so that `$x` is a clear parse error and not part of an atom.

**Kept from Rust, with the same meaning:**

| Syntax | Matches |
|---|---|
| `#tag` | Tasks with this tag, from an edge or a `#marker` (§6.1), after the rename redirect (§6.2). Also the virtual tags `READY`, `BLOCKED`, `BLOCKING`, and the new `CONFLICT`. |
| `@user` | Tasks assigned to this actor, by actor slug or by the slug of the actor name. |
| `^id` | The task itself, or a task with this `dependsOn` target (from an edge or a marker). `id` can be a full ULID, a 7-character short id, `^short`, or a unique ULID prefix. |
| `&&` / `and` / `AND` | Both sides. |
| `\|\|` / `or` / `OR` | Either side. AND binds tighter than OR. |
| `!` / `not` / `NOT` | Negation. The keywords need a word boundary, so `nothing` is not `not`. |
| `( )` | Grouping. |
| Two atoms next to each other | Implicit AND: `#bug @alice` is `#bug && @alice`. |

- Each match ignores case, the same as Rust. A value that names nothing gives an empty result, not an error.
- An empty filter, or a filter that does not parse, gives `INVALID_FILTER`. The message gives the position (`start..end`), a specific message, and one corrected example.
- **Parser.** The parser uses `swift-parsing` (§12, item 24). Each grammar rule is one `Parser` type: `OrExpr`, `AndExpr`, `NotExpr`, `Atom`, and `Body`. `Parse`/`OneOf`/`Many` give the rules, and `Lazy` gives the recursion of `"(" expr ")"`. The keywords `and`/`or`/`not` (each case form) need a word boundary after them, so a keyword parser checks the next character without consuming it. Precedence and implicit AND are the same as the Rust grammar.
- **Error messages.** The tool does not show the `swift-parsing` error text to the agent. It reads the position of the failure from the error and writes its own message for that position. For example, "`$auth` at 0..5: `$` is removed; use `#auth` for a tag or `%auth` for a column", or "`#` at 4..5 needs a tag name".

**Removed: `$project`.** The `project` noun is removed (§2.2). `$x` gives `INVALID_FILTER`, and the message tells the agent to use `#x` for a tag or `%x` for a column.

**New: `%column`.**

| Syntax | Matches |
|---|---|
| `%doing` | Tasks in this column, by column slug or by the slug of the column name. The match ignores case. |

- Thus, `%review || (%todo && #READY)` is one filter. Before, it needed two calls with the `column` argument.
- A filter with a `%` atom (or a column URL) counts as "names a column" for the `excludeDone` default (see **Scoping arguments**). Thus, `%done` lists the done tasks.

**New: `kanban://` URLs.** A URL can be the body of an atom, or it can be an atom by itself. The `body` rule already accepts `:` and `/`, so the Rust grammar needs only the bare `url` atom.

| Syntax | Matches |
|---|---|
| `^kanban://<key>/task/<ULID>` | The same as `^id`, by full URI. The key can be a different board: then the atom matches the tasks of this board that depend on that cross-repo task. |
| `#kanban://<key>/tag/<slug>` | The same as `#slug`. |
| `@kanban://<key>/actor/<slug>` | The same as `@slug`. |
| `%kanban://<key>/column/<slug>` | The same as `%slug`. |
| `kanban://<key>/task/<ULID>` (bare) | The same as `^` with that URL. |
| `kanban://<key>/tag/<slug>` (bare) | The same as `#` with that URL. |
| `kanban://<key>/actor/<slug>` (bare) | The same as `@` with that URL. |
| `kanban://<key>/column/<slug>` (bare) | The same as `%` with that URL. |

- Thus, an agent can copy an `id` from a GraphQL result directly into a filter.
- A URL whose key is the current key of the board resolves in that board, the same as a local ref (§3.2). A tag, actor, or column URL with the key of a different board matches nothing, because those edges stay in one board (§6.6).
- A URL of the wrong type for its sigil (for example `#kanban://…/task/…`), or a board or comment URL, gives `INVALID_FILTER`. The message gives the correct form.

**Scoping arguments.** The Rust `list tasks` params stay as arguments of `tasks`. Each one is sugar for one atom and is ANDed with `filter`: `tag` = `#x`, `assignee` = `@x`, `column` = `%x`. The Rust `project` param is removed. Each takes one value; to combine values, the agent writes a `filter`. As in Rust, `excludeDone` defaults to `true` when no column is named, and to `false` when a column is named. A column is named by the `column` argument, or by a `%` atom or a column URL anywhere in `filter`.

**Where `filter` applies:** `tasks`, `nextTask`, `searchTasks`, the `tasks` fields of `Column`, `Actor`, and `Tag`, `history`, and `Subscription.changes`.

### 6.4 Search

`searchTasks` uses `MetadataSearcher` from FoundationModelsMetadataRegistry. That package uses FoundationModelsRanker. Do not write a new ranker.

- **Ranking.** BM25 (word match) + trigram (partial words and typing errors) + embedding cosine (only if an embedder is set). Reciprocal rank fusion (RRF) combines the signals.
- **Item.** `TaskSearchItem` conforms to `SearchableMetadata`:
  - `id` = the task URI.
  - `renderBlock()` = the title, the tag names, and the body.
- **Mode.** Use `.retrieval`. Do not use `.selection`: it calls an LLM, and the result then changes from call to call.
- **Embedder.** Optional. `KanbanGraph(..., embedder: (any TextEmbedding)? = nil)`. With no embedder, search uses only BM25 + trigram and needs no model. The agent can give a `PooledEmbedder`.
- **Life of the searcher.** `KanbanGraph` keeps one `MetadataSearcher` for each board, for its life. After the first load of a board, and after each commit or watcher batch that changes tasks, call `update(items:)` on the searcher of that board. This embeds again only the tasks that changed. Nothing is written to disk.
- **Filter.** `MetadataSearcher.search(intent:limit:)` has no filter argument. Thus, call it with `limit` = the number of tasks in the board. Then remove the tasks that do not pass `filter` (§6.3), and keep the first `first` results. Deleted and done tasks are excluded by default, the same as `tasks`.
- **Result.** `TaskHit { task: Task!, score: Float!, signals: SearchSignals }`. `SearchSignals` holds `bm25`, `trigram`, and `cosine` (null when there is no embedder).
- **Diagnostics.** If the embedder fails, the searcher falls back to BM25 + trigram. The tool records the diagnostic with swift-log. It does not write it to the event log, and it does not return an error.

See §12, item 6.

### 6.5 Undo and redo

Undo uses the event log. It never deletes or changes a line in the log. It appends new patches that put the old values back.

- **Transaction.** All patches of one tool call have the same `txn`. This includes all mutation fields in the document. `undo` reverses one transaction. Thus, "undo my last call" reverses the full call.
- **`undo`** with no argument reverses the newest transaction of the session actor that is not already undone. It skips transactions that have `undoes` set (undo and redo transactions). Thus, two `undo` calls reverse the two newest original calls. `undo(txn:)` reverses a given transaction, also one from a different actor.
- **Scope.** `undo` and `redo` with no argument look in the current board and in the boards that `KanbanGraph` has already loaded (§5.6). They do not load other boards. A transaction that spans boards is still found, because its patches are also in the log of each board that it changed. To undo a transaction in a board that is not loaded, the agent gives `txn` and `board`.
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
  | `edit body` with a diff | `edit body` with the reversed diff (the `-` and `+` lines change places) |
  | the first patch of a node that a mutation made explicitly (for example `addTask`, `addTag`, `addColumn`) | `delete: true` |
  | the first patch of a node that a mutation made as a side effect (an unknown tag in `addTask`, a new actor, a new column in `moveTask`, the board in auto-init), and a tag that a `#marker` makes live again with `delete: false` (§6.1) | no inverse: the node stays |

  Patches hold only the properties that changed (§5.4), so each inverse is exact.
- **Conflict.** A later transaction that is not undone can change the same property of the same node (for a set: the same member). For a node that the transaction made, a later edge to that node is also a conflict. For the body, the rule is different: a later edit to the body is a conflict only if the reversed diff does not apply to the current body with the rules of §5.5. Thus, an undo of a body change works after a later change to other lines. In a conflict, `undo` writes nothing and returns `UNDO_CONFLICT`. The error gives the later transactions. `undo(txn: <id>, force: true)` writes the inverse anyway, and the undo then wins (last write wins).
- **Graph rules still apply.** An inverse that breaks a rule in §3.3 is refused. For example, an undo of `deleteColumn` that would put back a column is accepted, but an undo of `addColumn` when the column now has tasks gives `COLUMN_NOT_EMPTY`.
- **Many boards.** A transaction that changes more than one board records the keys of the other boards in `boards` on each of its patches (§5.1). This is possible because the call writes all its patches at the end (§5.4). `undo` and `redo` of such a transaction need all those boards. If one board is not in the index, they write nothing and return `NOT_FOUND`, and the message names the missing board.
- **`history`** (on `Board`) lists the transactions that changed that board, newest first, with `txn`, time, actor, `ops`, `boards`, `undone`, and the `updates` of each node (§6.7). It can filter by node and by actor. The agent uses it to find a `txn` to undo.
- **Result.** `undo` and `redo` return the `Change` that they wrote. The caller can select its `updates` (§6.7).

See §12, item 12.

### 6.6 Related boards (cross-repo)

A **related board** is the board of a different repo on the same disk. The tool can read and change related boards, and it can make a board in a related repo that does not have one yet. All boards use the same format.

- **Scan.** The tool looks in the parent directory of the current repo, one level down, for git repos. The tool config can add more search roots, for example `~/src`. The roots are places to look, not a copy of the keys. For each repo it finds:
  - The key comes from the current `origin` of the repo, with the same rule as §3.2.
  - If the repo has `.kanban/board.jsonl`, the board is **enabled**. If not, the board is **not enabled** yet.
  - The result is an index from board key to the directories with that key, with the enabled state of each.
- **Many copies of one repo.** Git allows many copies of one repo on a disk: clones and worktrees. All copies have the same key, and this is not an error. A board key resolves to one copy with this rule:
  - The key of the current repo always resolves to the current directory.
  - A different key resolves to the first copy in scan order: the parent directory of the current repo first, then each search root in config order, and in each place the directory names in sort order. Thus, the choice is the same on each call.
  - To use a different copy, the agent gives its path in the `board` argument.
  - `Query.boards` lists each copy, with its path.
- **Index life.** The index stays in memory for the life of `KanbanGraph`. On an unknown key, the tool scans one more time.
- **Board name.** A board that is not enabled shows the repo directory name as its `name`.
- **Board refs.** A `board` argument (and `Query.board(id:)`) accepts:
  - a board key, for example `github.com/o/other`;
  - a repo directory name, for example `FoundationModelsMultitool`, if it is unique in the index;
  - a path.
- **Enable a related repo.** If the `board` argument names a related repo that is not enabled, the first mutation initializes its board (the same auto-init rule as §6). `initBoard(board:)` does the same thing explicitly. The key comes from the `origin` of that repo. A query on a repo that is not enabled returns an empty board and writes nothing.
- **Short ids.** For a mutation on an existing node, short ids, slugs, and tag names resolve in the board of that node. For a mutation that makes a node, they resolve in the board that the `board` field names, or in the current repo. A full URI always resolves in its own board.
- **Edges.** `dependsOn` can point to any board. `column`, `tags`, `assignees`, and `author` point only to nodes in the same board as the task.
- **Actors.** In each board, the patches use the actor local ref of that board.
- **Stored refs across boards.** A patch in board A that points to a node in board B holds the full URI of that node, with the current key of B. A patch never holds the key of its own board (§3.2). The session actor rule of §6 applies in every board.
- **One transaction, many boards.** All patches of one tool call have the same `txn`, also when they go to different boards. Each patch records the keys of the other boards in `boards` (§5.1, §5.4). `undo` reverses the transaction in each board, or writes nothing if one board is missing (§6.5).
- **Git.** The tool does not commit. A change to a related board is an uncommitted change in that repo, on the branch that is checked out there.
- **Not found.** A `dependsOn` target in a board that the scan cannot find counts as not done (§3.3). A mutation on a node in a board that cannot be found gives `NOT_FOUND`, and the message lists the search roots.

See §12, item 13.

### 6.7 Observe changes

GraphQL has a standard operation to observe changes: `subscription`. `KanbanGraph` runs subscriptions. The tool does not (a tool call returns one result and then ends).

```graphql
subscription { changes(board: "FoundationModelsMultitool", filter: "#kanban") {
  txn at actor { name } ops
  updates { id type kind source fields { name before after added removed }
            node { ... on Task { title column { name } ready } } } } }
```

- **One event type.** A subscription sends `Change`, the same type that `history` returns (§6.5). Thus, a subscription is the live form of `history`, and there is no second event type.
- **All node types.** A `Change` has one `NodeUpdate` for each node that the transaction changed: `Board`, `Column`, `Task`, `Tag`, `Actor`, and `Comment`. A client can show each update without one more query.
- **Kind.** `CREATED` for the first patch of a node. `DELETED` for `delete: true`. `RESTORED` for `delete: false`. `UPDATED` for each other change.
- **Fields.** Each `FieldChange` gives the public field name and the values before and after the transaction. A list field (for example `tags`, `assignees`, `dependsOn`) gives `added` and `removed`. The `body` field gives only `diff`, a unified diff from the body before the transaction to the body after it (§5.5). `before` and `after` are null for `body`, so that a large body is not sent two times. A client that needs the full text selects `node { body }`. `KanbanGraph` calculates the values from the projection just before and just after the transaction. Thus, the values are the same that a query shows, not the raw patch.
- **Derived updates.** A change to one node can change derived fields of other nodes. For example, `completeTask` on task A can make task B `ready`, change `blockedBy` and `virtualTags` of B, and change `Board.summary`. Also, a tag rename or a tag delete changes `tags` of each task that uses the tag. `KanbanGraph` compares the derived fields (§5.3, step 4) and the read-time tags (§6.1) of each task in the changed boards, before and after. It adds a `NodeUpdate` with `source: DERIVED` for each node whose values changed. The data is small, so a full compare is fast enough. `derived: false` on `changes` leaves these updates out.
- **Derived updates across boards.** A `dependsOn` edge can point to a task in a related board. When that task changes, the tasks that depend on it can become ready. Each loaded board has its own watcher (§5.6). Thus, `KanbanGraph` loads, and so watches, each board that a `dependsOn` edge of a board with a subscriber reaches.
- **Filters.** `type` keeps only updates of these node types. `node` keeps only updates of this node. `filter` (§6.3) keeps only updates of tasks that match it, and of the comments on those tasks. A `Change` with no update after the filters is not sent.
- **Arguments.** `board` (no value = the current repo), `type`, `node`, `actor`, `filter`, and `derived`. `history` takes the same filters, so that a client can catch up with `history(since:)` and then subscribe with the same arguments.
- **Changes from this process.** When `KanbanGraph` commits a call (§5.4), it sends the `Change` to each matching subscriber at once.
- **Changes from other processes, `git pull`, or a merge.** The file watcher of the board (§5.6) applies the changed files to the live graph and finds the event ids that are new. It does not use file positions, because a `union` merge can rewrite a file. It groups the new events by `txn` and sends one `Change` for each transaction, in `txn` order. The values before and after come from the live graph before and after the batch.
- **Serial gate.** A subscription stream does not hold the serial gate of `execute` (§7.2). Each `Change` is resolved through the gate, one at a time.
- **Engine.** `graphqlSubscribe` of GraphQLSwift/GraphQL returns `Result<any AsyncSequence & Sendable, GraphQLErrors>`. Graphiti declares the `changes` field with `SubscriptionField`, whose resolver returns an `AsyncSequence & Sendable`. `KanbanGraph` gives an `AsyncStream<Change>` for each subscriber.
- **In the tool.** A `subscription` sent through `KanbanTool` returns the error `SUBSCRIPTION_NOT_IN_TOOL`. The message tells the agent to use `board { history(since: <txn>) }` to get the changes after a known transaction.
- **In the CLI.** `kanban watch '<subscription>'` prints one JSON line for each event, until the user stops it.

See §12, item 17.

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
- **Tests for this schema.** A unit test encodes `KanbanArguments.generationSchema` and checks that `variables` has `anyOf` and no `type`. The step 18 test sends an object and a string through Multitool. A test with a real `LanguageModelSession` checks that the on-device model makes the string form for a document with variables.
- The decoder keeps the JSON types: number, boolean, null, list, and object. GraphQL input coercion then converts them, for example a JSON number to `Int` or `Float`.
- The tool description is short. It gives the purpose of the tool, the root fields (`board`, `boards`, `node`, `nodes`), and one example query. It does not hold the schema.
- To learn the schema, the agent uses standard GraphQL introspection (`__schema`, `__type`). The engine answers from the live schema, so the answer is always correct.
- The example query in the description is also a test case, so it cannot go out of date.
- Validation errors give "did you mean" suggestions (§4.4), so the model can correct a field name without introspection.
- See §12, item 10.

### 7.2 Public API

```swift
public actor KanbanGraph {                     // the engine: the tool, the CLI, a GUI, and tests use it
    public init(root: URL, actor: String?, locator: BoardLocator = .default,   // locator holds the extra search roots
                embedder: (any TextEmbedding)? = nil) throws
    public func execute(query: String, variables: [String: Map], operationName: String?) async throws -> String
    public func subscribe(query: String, variables: [String: Map], operationName: String?) async throws
        -> AsyncThrowingStream<String, Error>   // one GraphQL response (JSON) for each event (§6.7)
    public func close() async                     // stop all file watchers and end all subscriptions
    public static var schemaSDL: String { get }   // generated from the Graphiti schema
}

public struct KanbanTool: Tool {
    public init(graph: KanbanGraph)            // the tool wraps a graph that the caller made
    public let name = "kanban"
}
```

- **The tool takes a `KanbanGraph` in its constructor.** It is a thin wrapper: it decodes `KanbanArguments` and calls `execute`. The host makes the graph one time and can give the same graph to other clients, for example a GUI that subscribes. Thus, all clients in one process share one board index, one set of searchers, and one serial gate.
- **What `KanbanGraph` keeps across calls:** the board index (§6.6), one `MetadataSearcher` for each board (§6.4), the live `Graph`, the file signatures, and the file watcher of each loaded board (§5.6), and the active subscribers (§6.7).
- **What it makes on each call:** only a working copy of each graph for a mutation (§5.4). It does not load a board again.
- It is an `actor`, so its state is safe. An actor can run a second call at each `await`, so the actor alone does not make calls run one at a time. Thus, `execute` also goes through a serial gate (an async queue), and calls in the same process run one at a time. The file locks and the commit check (§5.4) protect against other processes.
- A CLI target (`kanban`) runs `kanban '<document>' [--variables <json>]` against the current directory. `kanban watch '<subscription>'` prints one JSON line for each event (§6.7). `kanban --schema` prints the generated SDL.

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
      Events/        Event.swift, EventLog.swift (read, append, lock), Replay.swift (fold one node),
                     Loader.swift (stages, work queue, join, k-way merge of the events)
      Body/          UnifiedDiff.swift (make, reverse), DiffApply.swift (nearest exact match, conflict block)
      GraphQL/       Schema.swift (public, Graphiti), PatchSchema.swift (internal `patch`), QueryResolvers.swift,
                     MutationResolvers.swift, NameRewrite.swift (§4.5), Errors.swift, Scalars.swift
      Derived/       Readiness.swift, VirtualTags.swift, Progress.swift, Timeline.swift
      Filter/        FilterParser.swift, FilterEvaluator.swift
      Search/        TaskSearchItem.swift (SearchableMetadata), TaskSearch.swift
      Tags/          TagSlug.swift, TagMarkers.swift, AutoColor.swift
      Undo/          Inverse.swift, UndoneState.swift, History.swift
      CrossRepo/     BoardLocator.swift
      Observe/       ChangeFeed.swift (subscribers), BoardWatcher.swift (FSEvents, batches, file signatures),
                     LiveGraph.swift (apply a batch, unresolved refs, large-change reload)
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
- `pointfreeco/swift-parsing` (`https://github.com/pointfreeco/swift-parsing`) for the filter DSL (§6.3). See §12, item 24.
- swift-log. Optional: swift-distributed-tracing and swift-metrics (API only), the same as CodeContext.
- `FoundationModelsExtras` only if we use one of its helpers. The `Operations` product is not necessary.

## 9. Linking into the agent (code mode)

1. The tool is a plain `Tool`. It does not conform to `OperationDescribing`. Thus, Multitool mounts it as one function: `tools.kanban({ query, variables })`.
2. The tool returns JSON text. Multitool parses a JSON object into structured `GeneratedContent`, so a script gets `result.data.board.task.blockedBy` as a value.
3. A script can pass `variables` as a plain object or as a JSON string. Both work (§7.1).
4. In `FoundationModelsACPAgent/Sources/FoundationModelsACPAgent/Tools/ToolCatalog.swift`:
   - Add a `kanban` config section in `Configuration/ToolSectionCodec.swift` (`ToolSection<KanbanToolOptions>`, add to `knownKeys`).
   - In `makeRegistry(context:)`, make one `KanbanGraph` and add `builder.addTool(KanbanTool(graph: graph))`. Keep the graph, so that other parts of the agent can subscribe to it.
   - Add a row to the README § Tools table.
   - Add the package dependency in `FoundationModelsACPAgent/Package.swift`.
5. The ACP agent work is a separate change in that repo. This plan only makes the package ready for it.
6. **Skills.** The skills are in the `../skills` repo. The skills that call the kanban tool (`skills/kanban`, and the skills that use it, for example `skills/finish`) use the old op-style JSON calls. They must change to GraphQL documents. That is a separate change in the `../skills` repo, after this package works. This plan does not change them.

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
3. **Identity.** `NodeURI`, `LocalRef` (the stored form, and the conversion to and from `NodeURI` with the current board key, §3.2), `BoardKey` (from the current git remote), ULID minting with unique short ids, `RefResolver` (URI, ULID, short id, `^short`, prefix, slug, tag name, ambiguous result).
4. **Ordinal.** Fractional index: `first`, `after`, `before`, `between`.
5. **Schema and graph store.** The full Graphiti schema, the `Graph` store, and the query resolvers for the stored fields.
6. **Event log.** Event envelope (`id`, `at`, `actor`, `txn`, `ops`, `boards`, `undoes`), append with `flock`, the commit at the end of the call with its check under the locks (§5.4), read and sort, `.gitattributes` `merge=union`, `.gitignore`.
7. **Patches and replay.** The internal `patch` mutation (`set`, `unset`, `add`, `remove`, `delete`, `edit`). The parallel loader of §5.3: the six stages in entity order, the work queue with a fixed number of workers, the join at the end of each stage with stable slots, and the k-way merge of the events. The live graph and the file watcher of §5.6: file signatures, batches through the serial gate, reload of changed, new, and removed files, the large-change reload, the working copy for mutations, and the signature check at commit. The body diff of §5.5: make a unified diff, apply it with the nearest exact match, and make a conflict block when a hunk cannot apply. The graph rules in §3.3 at write time (tombstones, cycle refusal, `COLUMN_NOT_EMPTY`). Rebuild the `Graph` from the logs, with the display rules for a broken merged state (§5.3). Record the timeline values.
8. **Derived fields.** Readiness, `blockedBy`/`blocks`, virtual tags, progress, the time values of §5.3 (`created`, `updated`, `deleted` on all nodes; `started`, `completed` on tasks), `Board.summary`.
9. **Tags.** Slug, name validation, auto color, the `#marker` parser, the read-time union of edges and markers, the `renamedTo` redirect, and marker removal in `untagTask`.
10. **Filter DSL.** Add `swift-parsing`. Parser and evaluator. If the library has a Swift 6 strict concurrency problem, correct it in our code, the same as step 2. Use it in `tasks`, `nextTask`, and the `tasks` fields of `Column`, `Actor`, and `Tag`.
11. **Public mutations.** All mutations in §4.2 except `undo` and `redo`. The forgiving refs, the sugar mutations, auto-init, and the session actor.
12. **Errors and forgiving names.** The error codes and corrective messages in §4.4. The name rewrite in §4.5, at all positions, with the alias tables, the list of mappings that are never made, and `extensions.rewrites`.
13. **Search.** `searchTasks` with `MetadataSearcher` (§6.4). Test it first with no embedder, then with an injected fake embedder.
14. **Undo and redo.** The inverse table, the undone state derived from the log, conflict detection, `force`, and the `history` query (§6.5), in one board.
15. **Cross-repo.** `BoardLocator` (scan, search roots, index), board refs, `Query.board(id:)` and `boards`, the `board` field on mutations, multi-board locks, the replay scope (§5.4), enabling a related repo, and `undo` of a transaction that spans boards (§6.6). Unknown targets count as not done.
16. **Observe changes.** `Change` with `NodeUpdate` and `FieldChange` for all node types, the before-and-after compare with derived updates, `Subscription.changes` with its filters, `history(since:)`, the change feed for commits in this process and for batches from the file watcher, and `kanban watch` (§6.7).
17. **Tool and CLI.** `KanbanTool`, `KanbanArguments`, the short tool description with its tested example, and the `kanban` CLI.
18. **Multitool proof.** A test that registers the tool in a `MultiTool.Builder` and runs a `runCode` script that adds a task, reads `nextTask`, and moves the task. The script passes `variables` once as an object and once as a JSON string.

## 11. Testing

- Use Swift Testing only (`@Suite`, `@Test`, `#expect`). Do not use XCTest.
- Each test uses a temporary directory as the repo root. Use a fake `BoardKey`, and a fixed clock and ULID source, so the event output is deterministic.
- Most tests call `KanbanGraph.execute` with a GraphQL document, and compare the response JSON.
- **Port the behavior tests from Rust, not the code.** The main source is `crates/swissarmyhammer-kanban/src/dispatch/tests/` (about 200 tests). Write each test again as a GraphQL document:
  - short id and `^` resolution, and ambiguous prefixes;
  - no partial write on an error;
  - field clear (`null`) and no change (missing);
  - `tasks` filter arguments, `excludeDone`, paging;
  - move with ordinal, `before`, or `after`;
  - delete and undelete (the Rust archive tests, with archive mapped to delete);
  - `nextTask` with a filter;
  - auto-init;
  - the session actor fallback.
- Also port these unit tests: `types/position.rs`, `types/short_id.rs`, `tag_parser.rs` (the parse part), `virtual_tags.rs`, `task/next.rs`, and all of `swissarmyhammer-filter-expr` (parser and evaluator, keyword boundaries, precedence, and the parse errors). The `$project` tests change: `$x` gives `INVALID_FILTER`.
- **Filter compatibility.** Each filter example in the Rust kanban tool description and in the `kanban` and `finish` skills (`../skills/skills/`) is a test case. Each gives the same tasks as in Rust, except the `$project` examples, which give `INVALID_FILTER` with a message that names `#` and `%`. A `tag`, `assignee`, or `column` argument gives the same result as its atom. `excludeDone` follows the Rust default.
- **Column atom.** `%doing` matches the tasks in `doing`, by slug and by name, with any case. `%done` lists done tasks (a `%` atom turns off the `excludeDone` default). `%review || (%todo && #READY)` gives the tasks of both parts.
- **Filter URLs.** `^`, `#`, and `@` with a full URL match the same tasks as the short form. A bare task, tag, actor, or column URL matches. An `id` copied from a query result works as a filter. A `^` URL to a task in a different board matches the tasks that depend on it. A URL of the wrong type, and a board or comment URL, give `INVALID_FILTER`.
- Do not port the tests for the `verb noun` parser, the aliases, or the scalar-or-array list input. GraphQL types replace them.
- **Tests that are new for this design:**
  - Replay gives the same projection as the live writes (a property test over random mutation sequences).
  - Shuffle the lines of a log, then replay: the result is the same.
  - Live graph (§5.6), with no subscriber active: a manual edit of a task log changes the result of the next query. A `union` merge that adds lines to a task log updates the task and adds its events to `history`. A new task file from `git pull` makes a new task, and a `dependsOn` edge that pointed to it now resolves. A removed file removes the node, and edges to it become unresolved. A `git checkout` that changes more than half of the files reloads the board, and the result equals a fresh load. A line that does not parse is skipped. After each case, the live graph equals a fresh load of the same files.
  - The tool's own writes: after a commit, the watcher event for the write does not read the file again (the signature matches).
  - A write by a different process just before a commit, before its FSEvents event comes in: the commit check finds the changed signature, applies the file, and runs the call again.
  - A failed mutation field, or a commit that runs again, does not change the live graph (the working copy is discarded).
  - Parallel loader: a load with 1 worker and a load with many workers give the same `Graph` and the same global event list. After the load, each edge to a node in the board is a direct reference, and a cross-board or missing target stays an unresolved ref. A board with no `actors/`, `tags/`, or `comments/` directory loads. A board with thousands of tasks loads with all workers busy (a test that counts the active workers).
  - Merge two logs with `union`, then replay: the result is correct.
  - A delete makes a tombstone, and the projection ignores edges to the tombstone.
  - Time values: for each of the six node types, `created` is the `at` of the first patch and `updated` is the `at` of the last patch. `deleteTask` sets `deleted`; lists do not show the task, and `node(id:)` returns it with `deleted`. `undo` of the delete, and `undeleteTask`, clear `deleted`. `undeleteTask` on a live task writes nothing. `tasks(deleted: true)` lists only deleted tasks. `archiveTask` maps to `deleteTask`, and `restoreTask` maps to `undeleteTask`. Each node type with a delete has a working undelete. `started` and `completed` follow the column moves. No log line has a time value outside the envelope `at`. An input field `created`, `due`, or `scheduled` in a mutation gives a validation error.
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
  - Stored form (§3.2): after each public mutation, no log line holds the key of its own board. A `kanban://` value is in a log only as a `dependsOn` edge to a different board, in `boards`, or in text that the agent wrote. A full URI with the key of the current board in the input is stored as a local ref.
  - Body diffs (§5.5): each mutation with `body` writes one `edit` patch with a diff, never the full text (a new node gets a diff from the empty text). A body that does not change writes no `edit`. Replay of the diffs gives the same body as the live writes. Two branches change different lines of one body: after a `union` merge, both changes are in the body. Two branches change the same line: replay makes one conflict block, all clones show the same body, the task has `#CONFLICT`, and a `body` update removes it. `FieldChange` for `body` has `diff` and null `before` and `after`. Undo of a body change after a later change to other lines works. Undo when the reversed diff does not apply gives `UNDO_CONFLICT`. `description`, `desc`, and `text` map to `body`.
  - Dependencies from markers: a `kanban://` task URL in the body gives a `dependsOn` target, for this board and for a different board. Remove the URL from the text, and the dependency goes away. `updateTask(dependsOn:)` that removes a target also removes its URL from the text. A marker that makes a cycle gives `DEPENDENCY_CYCLE`. `^x` matches a marker target.
  - Move a repo: write tasks, comments, tags, and same-board dependencies, then change the `origin` of the repo (and, in a second test, the directory name). The log files do not change. Each `id` in the output has the new key, and all edges still resolve.
  - Two copies of one repo (a clone and a worktree) side by side with the current repo: the current key resolves to the current directory. A related key with two copies resolves to the first copy in scan order on each call, and a path in `board` selects the other copy. `boards` lists both copies.
  - `undo` with no `txn` finds a transaction in a loaded related board, and does not load a board that is not loaded.
  - Two temporary repos side by side: `addTask(board: "<related>")` writes to the related log. A related repo with no `.kanban/` gets a new board on its first mutation. A task in one board depends on a task in the other, and `ready` changes when the other task is done. One call that changes both boards is reversed by one `undo`.
  - A `dependsOn` cycle is refused.
  - Broken merged states (§5.3): two branches each add half of a dependency cycle; one branch deletes a column while another moves a task into it; two branches make a rename cycle. After a `union` merge, replay succeeds and the projection follows §5.3.
  - Updates of all node types: for each public mutation, the `Change` has one `NodeUpdate` for each changed node, with the correct `kind`, and `FieldChange` values that equal a query before and after. `completeTask` on A gives a `DERIVED` update for B (`ready`, `blockedBy`, `virtualTags`) and for the board (`summary`). A tag rename gives `DERIVED` `tags` updates for the tasks that use the tag. `derived: false` leaves them out.
  - Subscriptions: a commit in this process sends one `Change` to a matching subscriber. A log line that another process appends sends one `Change`. A `union` merge that rewrites a file sends only the new transactions. A `subscription` sent through the tool gives `SUBSCRIPTION_NOT_IN_TOOL`. `history(since:)` returns only the later transactions.
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
  - Forgiving names (§4.5): a wrong case, `snake_case`, a plural, an alias, and one wrong letter each give the canonical name, at each position. A tie gives an error that lists the matches. `{ tasks }` gives the same result as `{ board { tasks } }`, under `data.tasks`. Each rewrite is in `extensions.rewrites`.
  - `taskAdd`, `addTask`, and `createTask` give the same event. The response key is the name that the caller wrote. `createTask` does not map to `initBoard`.
  - A deep query (task → dependsOn → comments → author) returns the correct nested graph.
- **Tool test.** Call the `Tool` with `GeneratedContent` arguments, and compare the JSON output.
- **Code mode test.** Step 18.

## 12. Decisions

The owner made each decision below.

1. **Board noun. — DECIDED.** The root node is `Board`. One repo has one board. `Board` holds `name`, `body`, and `summary`, and it is the root of the tree. `initBoard` and `updateBoard` are its mutations. The Rust `project` noun is removed, and tags do its job.
2. **Perspectives. — DECIDED.** Removed. There is no `Perspective` node. A saved view is a GraphQL query document that a script or a skill keeps.
3. **Schema change over time. — DECIDED.** No upgrade step and no version field. Each event is a property patch (`set`, `unset`, `add`, `remove`, `delete`) on one node, and the state is the accumulated result. The public mutations are not in the log, so they can change freely (§5.1, §5.3).
4. **Board key (the `board-key` in the URI). — DECIDED.** The key is the current git remote `origin`, normalized to `host/owner/repo` (the SSH and HTTPS forms give the same key). A repo without a remote uses `local/<directory-name>`. The key is **not** stored in the log (item 18). Thus, when a repo moves to a new remote, its URIs change with it, and its local data does not change. A fork gets its own key. Known limit: a `dependsOn` URI in a different repo that holds the old key does not resolve after the move, so that task shows as blocked (§3.3, rule 4). The agent must update that edge. The tool does not keep a list of old keys.
5. **Log layout. — DECIDED.** One log file for each node (§5.2). Two branches that change different nodes change different files. The `union` merge driver keeps both sides when two branches change the same node. One `events.jsonl` for the full board is not used, because each branch would then change the same file.
6. **Search. — DECIDED.** Use FoundationModelsMetadataRegistry (`MetadataSearcher`), which uses FoundationModelsRanker for BM25 + trigram + optional embedding cosine with RRF fusion (§6.4). The kanban package does not write its own ranker.
7. **Tags in the body text. — DECIDED.** A task gets its tags from two sources: the `tags` edges and the `#markers` in the current body. The projection calculates the union at read time (§6.1). `tagTask` changes only edges. `untagTask` removes the edge, and also the marker if it is in the text. The Rust rule (the body text is the only source) is not used, because a merge can then lose a tag. Dependencies use the same model: a full `kanban://` task URL in the body is a dependency marker, and `task.dependsOn` is the union of the edges and the markers (§6.1).
8. **Shape of `variables`. — DECIDED.** Accept both forms: a plain object (code mode) and a JSON object in a string (the on-device model). Also accept a code fence around the JSON, `null`, and no value. A custom `ConvertibleFromGeneratedContent` init does the decode. The declared schema of `variables` is `DynamicGenerationSchema(anyOf:)` of a string and an object with no properties. Multitool passes a script object, and an empty object from the model means "no variables" (§7.1).
9. **GraphQL engine. — DECIDED.** Use `GraphQLSwift/GraphQL` for parse, validate, and execute. Use `GraphQLSwift/Graphiti` to build the schema from Swift types, so that the Swift types are the one source of truth. The SDL is generated, not written. The forgiving name rewrite (§4.5) changes the parsed document before validation. The internal `patch` mutation is in a separate schema, so that the model cannot write a patch directly.
10. **Schema in the tool description. — DECIDED.** The description does not hold the schema. It holds the purpose, the root fields, and one tested example query. The agent learns the schema with standard introspection (§7.1). Thus, the schema has one view, and it cannot go out of date.
11. **Import of old boards. — DECIDED.** No import. The tool does not read the Rust `.kanban/` data. Replay reads only `*.jsonl` files, so old Rust files (`.yaml`, `.md`) in the same directory are ignored.
12. **Undo. — DECIDED.** Undo and redo are in the first version (§6.5). A transaction is one tool call. `undo` appends inverse patches and never changes the log. A conflict with a later change is refused unless `force: true`. The undone state is derived from the log, so it survives git merges. A `history` query lists transactions.
13. **Cross-repo location. — DECIDED.** Scan the parent directory of the current repo, plus search roots from the config, for git repos. No key-to-path map. The scan finds enabled boards (with `.kanban/board.jsonl`) and related repos that are not enabled yet (key from `origin`). The tool can read and change related boards in the same format, and its first mutation in a related repo that is not enabled makes the board there (§6.6).
14. **Mutation name order. — DECIDED.** Each mutation has the noun in its name. A generic mutation with the type as a parameter is not used, because GraphQL has no generics. The tool accepts both orders, verbNoun (`addTask`) and nounVerb (`taskAdd`), and also the verb synonyms. The SDL uses verbNoun as the one canonical form. A rewrite step before validation does the mapping (§4.5).
15. **Tag rename. — DECIDED.** Tags use the slug as identifier. A rename makes a redirect (§6.2): the old tag gets `renamedTo`, and the projection follows it for edges and for `#markers`. No task patches are necessary, and concurrent branches stay correct. A rename that changes only `name`, and a rename that changes the edge on each task, are not used.
16. **Forgiving names. — DECIDED.** The rewrite of §4.5 applies to every name: mutations, selection fields, arguments and `input` fields, enum values, and root query fields. It matches by style and case, singular and plural, an alias table, and one wrong letter. It never guesses on a tie, and it reports each change in `extensions.rewrites`.
17. **Observe changes. — DECIDED.** Use GraphQL subscriptions (`Subscription.changes`) on `KanbanGraph`. The event is `Change`, the same type as `history`. It has one `NodeUpdate` for each changed node of all six types, with field values before and after, and `DERIVED` updates for nodes whose derived fields changed (for example a task that becomes ready). Commits in this process are sent at once. Changes from other processes and merges come from the file watcher of the board (§5.6, item 25). The tool takes a `KanbanGraph` in its constructor and does not run subscriptions; an agent polls with `history(since:)`.
18. **Local ids in the log. — DECIDED.** The GraphQL `ID` is the full `kanban://<board-key>/<type>/<local-id>` URI, in input and in output. The log stores a ref to a node in the same board as a local ref (`task/<ULID>`, `tag/bug`), with no scheme and no board key (§3.2). Only a ref to a node in a different board is stored as a full URI: a cross-repo `dependsOn` edge and the envelope `boards`. Body text is stored as the agent wrote it, so a `kanban://` URL in the text stays fully qualified. A task URL in the body of a task is a dependency marker, the same as a `#tag` marker (§6.1). Thus, a repo can move in git (a new remote, owner, or directory) with no change to its data.
19. **Documents with a Markdown body. — DECIDED.** Each node is a document: properties plus one Markdown `body`. The field is `body` on all six node types. It replaces `description` (Board, Tag, Task) and `text` (Comment); these old names are aliases (§4.5). The log stores each change to a body as a unified diff in an `edit` patch, not as the full text (§5.5). Thus, the log stays small, and two branches that change different lines of one body merge. A hunk that cannot apply after a merge makes a git-style conflict block in the body and the virtual tag `CONFLICT`. `FieldChange` for `body` gives `diff`, not `before` and `after`. Undo writes the reversed diff.
20. **Time values are derived. — DECIDED.** The Rust `due` and `scheduled` fields are removed, together with the `Date` scalar and `INVALID_DATE`. All six node types have `created`, `updated`, and `deleted` (on the `Node` interface). A task also has `started` and `completed`. All these values are derived from the envelope `at` of the patches during replay (§5.3). No patch stores a time value, and no mutation accepts one. A tombstone is not in lists, but `node(id:)` returns it with `deleted` set.
21. **No archive; delete and undelete. — DECIDED.** The Rust archive (`archived`, `archiveTask`, `unarchiveTask`) is removed. A delete is a `delete: true` patch in the log, and an undelete is a `delete: false` patch. Each node type that has a delete mutation also has an undelete mutation (`undeleteTask`, `undeleteColumn`, `undeleteActor`, `undeleteTag`, `undeleteComment`). `tasks(deleted: true)` lists the deleted tasks. The verbs `archive` and `unarchive` / `restore` map to `delete` and `undelete` (§4.5).
22. **Filter language. — DECIDED.** Keep the Rust filter language (`#tag`, `@user`, `^id`, `&&`/`and`, `||`/`or`, `!`/`not`, `()`, implicit AND), so that the filters in the existing tool description and skills still work. Remove `$project`; `$x` gives `INVALID_FILTER` with a correction. Add the column atom `%column`. The language also accepts `kanban://` URLs: as the body of `^`, `#`, `@`, and `%`, and as a bare atom whose node type gives the meaning (task, tag, actor, or column). The Rust scoping params `tag`, `assignee`, and `column` and the Rust `excludeDone` default are kept; a `%` atom also counts as a named column (§6.3).
23. **Parallel load, no cache. — DECIDED.** There is no cache and no snapshot on disk. `KanbanGraph` loads each board from the logs the first time that a call needs it, and then keeps it live (item 25). A parallel loader reads the node files with a work queue and a fixed set of workers. It reads in stages, in entity order: board, actors, columns, tags, tasks, comments. At the end of each stage, it joins the new nodes to the nodes of the earlier stages, so that the in-memory graph has direct edges. Each worker folds one node from its own file, because each patch changes one node (§5.3).
24. **Filter parser. — DECIDED.** Use `pointfreeco/swift-parsing` for the filter DSL. It is the Swift parser-combinator library that is most like `chumsky`, which the Rust code uses. Thus, the Swift grammar has the same shape as the Rust grammar, and the language can grow. The tool writes its own `INVALID_FILTER` messages from the failure position; it does not show the library error text.
25. **Live graph with a file watcher. — DECIDED.** `KanbanGraph` keeps the `Graph` of each loaded board in memory. An FSEvents watcher on the `.kanban/` directory of each loaded board runs for the life of `KanbanGraph`, also when there is no subscriber. A manual edit, a `git pull`, a merge, a branch switch, or a write from a different process makes a batch of changed files. The batch goes through the serial gate, and the tool reads each changed file again, folds its node again, and joins it in entity order (§5.6). Edges hold stable slots, so a reload of one node does not break other nodes. File signatures let the tool ignore its own writes. The commit check compares signatures under the lock, so a write never depends on the timing of FSEvents. A query can show old data until the watcher has processed the events; this is accepted. A mutation works on a copy-on-write working copy, which becomes the live graph only after the commit.
26. **Many copies of one repo. — DECIDED.** Clones and worktrees of one repo have the same key, and this is normal, not an error. The current key resolves to the current directory. A related key resolves to the first copy in a fixed scan order, and a path in `board` selects a different copy (§6.6).
27. **Undo scope. — DECIDED.** `undo` and `redo` with no `txn` search only the current board and the boards that are already loaded. They do not load more boards (§6.5).
28. **Log line format. — DECIDED.** Each log line keeps the full GraphQL request (`query` and `variables`) to the internal `patch` mutation, plus the envelope (§5.1). Each line is a complete GraphQL request.
29. **Skills. — DECIDED.** The skills are in the `../skills` repo. Their change to GraphQL is a separate change there (§9).

## 13. References

- Rust kanban: `../swissarmyhammer/crates/swissarmyhammer-kanban` (ops, dispatch, tags, virtual tags, next task), `swissarmyhammer-filter-expr`, `swissarmyhammer-entity`, `swissarmyhammer-store`, `swissarmyhammer-tools/src/mcp/tools/kanban/`.
- Package conventions: `../FoundationModelsCodeContext/Package.swift` (siblings by URL, tools 6.2, macOS 27, test layout).
- Code mode: `../FoundationModelsMultitool/Sources/FoundationModelsMultitool/Surface/RegistrySource.swift` (how a plain `Tool` is mounted) and `MultiToolBuilder.swift`.
- Agent linkage: `../FoundationModelsACPAgent/Sources/FoundationModelsACPAgent/Tools/ToolCatalog.swift`.
- Skills that use the tool (changed in a separate change): `../skills/skills/kanban`, `../skills/skills/finish`.
