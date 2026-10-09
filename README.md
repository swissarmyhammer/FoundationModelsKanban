# FoundationModelsKanban

FoundationModelsKanban is a kanban task graph for Swift. You read and change
the graph with GraphQL: one document goes in, and one `{data, errors}`
response comes out. The package moves the kanban function of the Rust
`swissarmyhammer` tool to Swift. It gives a `KanbanGraph` engine and a
FoundationModels `kanban` tool for in-process agents. Each board is an event
log in the `.kanban/` directory of its folder. The folder can be a git repo, but
git is not necessary. The port is not complete. See [plan.md](plan.md) for the
design and the port order.

## Get started

The package has no command-line tool. You use it from Swift. It needs macOS 27
and Swift 6.2.

Add the package to the dependencies of your `Package.swift`:

```swift
.package(url: "https://github.com/swissarmyhammer/FoundationModelsKanban.git", branch: "main"),
```

Then add the `FoundationModelsKanban` product to your target. The examples
below also give GraphQL variables as `Map` values. For these, add the `GraphQL`
product of [GraphQLSwift/GraphQL](https://github.com/GraphQLSwift/GraphQL) and
`import GraphQL`.

### 1. Open a board in a folder

Make one `KanbanGraph` for the folder that you choose:

```swift
import Foundation
import FoundationModelsKanban

let graph = try KanbanGraph(root: URL(filePath: "/path/to/my-project"), actor: nil)
```

- The board is in `<root>/.kanban/`. For the example above, the board is in
  `/path/to/my-project/.kanban/`.
- The folder does not have to be a git repo. In a folder that is not a git
  repo, the board key is `local/<folder-name>`, for example `local/my-project`.
  In a git repo with an `origin` remote, the key comes from the remote, for
  example `github.com/owner/repo`.
- `actor` is the name of the actor of your changes. `nil` uses the name of the
  user of the operating system.
- The engine reads nothing until the first call. A query on a folder with no
  `.kanban/` directory gives an empty board, and it writes no file.
- The first mutation makes the board. The new board has the default columns
  `todo` (To Do), `doing` (Doing), `review` (Review), and `done` (Done).

Make one engine for each folder, and give it to each client in your process.
When you do not need the engine any more, call `await graph.close()`.

### 2. Add and list tasks

`execute(query:variables:operationName:)` runs one GraphQL document. It gives
the response (`{data, errors}`) as JSON text with sorted keys. A GraphQL error
does not throw: the response has it in `errors`.

This mutation adds the actor `alice`, and a task with the tag `bug` that
`alice` does. The title comes from a variable:

```swift
let added = try await graph.execute(
    query: """
        mutation($title: String!) {
          addActor(input: { id: "alice", name: "Alice" }) { name }
          addTask(input: { title: $title, tags: ["bug"], assignees: ["alice"] }) {
            title column { name } tags { name } assignees { name }
          }
        }
        """,
    variables: ["title": "Fix the login bug"],
    operationName: nil
)
```

The response:

```json
{"data":{"addActor":{"name":"Alice"},"addTask":{"assignees":[{"name":"Alice"}],"column":{"name":"To Do"},"tags":[{"name":"bug"}],"title":"Fix the login bug"}}}
```

The mutation also made the board with its default columns. This query reads
them:

```swift
let columns = try await graph.execute(query: """
    { board { columns { name } } }
    """, variables: [:], operationName: nil)
```

The response:

```json
{"data":{"board":{"columns":[{"name":"To Do"},{"name":"Doing"},{"name":"Review"},{"name":"Done"}]}}}
```

Each list takes one `filter` (see [Filters](#filters)). These queries read the
tasks that have the tag `bug` and the assignee `alice`, the five newest changes
that have a column update, and the changes of one node:

```swift
let bugsOfAlice = try await graph.execute(query: """
    { board { tasks(filter: "#bug && @alice") { edges { node { id title } } } } }
    """, variables: [:], operationName: nil)

let columnChanges = try await graph.execute(query: """
    { board { history(filter: "~column", first: 5) { txn ops updates { id kind } } } }
    """, variables: [:], operationName: nil)

let nodeChanges = try await graph.execute(query: """
    { board { history(filter: "^01jabcd") { txn actor { name } updates { fields { name before after } } } } }
    """, variables: [:], operationName: nil)
```

- The first response has the task `Fix the login bug`. Its `id` is a URI, for
  example `kanban://local/my-project/task/<ULID>`.
- The second response has the first transaction. Its `ops` are `addActor` and
  `addTask`. Its updates are the four new columns, with the kind `CREATED`.
- `01jabcd` is a short id. Put the short id of a node of your board there. When
  no node has the short id, the history is empty.

### 3. Give the tool to a model

`KanbanTool` is a FoundationModels `Tool` with the name `kanban`. It takes one
GraphQL document, and it runs the document on the engine that you give it:

```swift
import FoundationModels

let session = LanguageModelSession(
    tools: [KanbanTool(graph: graph)],
    instructions: "Use the kanban tool to read and change the task board."
)
let answer = try await session.respond(to: "Which task is next?")
```

The tool does not close the engine. The tool does not run a subscription.

### 4. Code mode

In code mode, the model writes one JavaScript script that calls more than one
tool. Put `KanbanTool` in a `MultiTool` of
[FoundationModelsMultitool](https://github.com/swissarmyhammer/FoundationModelsMultitool),
and give the `MultiTool` to the session:

```swift
import FoundationModelsMultitool

let registry = try MultiTool.Builder()
    .addTool(KanbanTool(graph: graph))
    .buildRegistry()
let session = LanguageModelSession(
    tools: [MultiTool(registry: registry)],
    instructions: "Use runCode to read and change the task board."
)
```

The script calls the tool as `tools.kanban({ query, variables })`. `variables`
can be a JavaScript object or a JSON string. This script adds a task, reads the
next task with the tag `docs`, and moves it to the `doing` column:

```js
await tools.kanban({
  query: `mutation($title: String!) { addTask(input: { title: $title, tags: ["docs"] }) { id } }`,
  variables: { title: "Write the docs" }
});
const r = await tools.kanban({ query: `{ board { nextTask(filter: "#docs") { id title } } }` });
const t = r.data.board.nextTask;
if (!t) return "no task is ready";
const moved = await tools.kanban({
  query: `mutation($id: ID!) { moveTask(input: { id: $id, column: "doing" }) { title column { name } } }`,
  variables: JSON.stringify({ id: t.id })
});
return moved.data.moveTask;
```

The result of the script:

```json
{"column":{"name":"Doing"},"title":"Write the docs"}
```

### 5. Watch changes

`subscribe(query:variables:operationName:)` runs a `subscription` document. It
gives an `AsyncThrowingStream` with one GraphQL response for each change. A
change comes from a call of this process, or from a change of a log file, for
example after `git pull`. This subscription gets the updates of the tasks that
have the tag `bug`, and the updates of each comment:

```swift
let changes = try await graph.subscribe(query: """
    subscription { changes(filter: "#bug || ~comment") { txn ops updates { id type kind } } }
    """, variables: [:], operationName: nil)
let watcher = Task {
    for try await change in changes {
        print(change)
    }
}
```

This mutation adds a second task with the tag `bug`. The stream then gives one
change. Its `ops` are `addTask`, and its one update is the new task, with the
kind `CREATED`:

```swift
_ = try await graph.execute(query: """
    mutation { addTask(input: { title: "Fix the logout bug", tags: ["bug"] }) { title } }
    """, variables: [:], operationName: nil)
```

`close()` stops the file watchers and ends each stream. After `close()`, the
loop of `watcher` ends:

```swift
await graph.close()
```

### 6. The layout of `.kanban/`

The first mutation makes the `.kanban/` directory in the folder of the board.
Each node has its own log file. Each line of a log file is one event of that
node:

```text
.kanban/
  board.jsonl               # the events of the board node
  columns/<slug>.jsonl      # one log for each column
  actors/<slug>.jsonl       # one log for each actor
  tags/<slug>.jsonl         # one log for each tag
  tasks/<ULID>.jsonl        # one log for each task
  comments/<ULID>.jsonl     # one log for each comment
  .gitattributes            # *.jsonl merge=union
  .gitignore                # .lock
  .lock                     # the write lock
```

- The logs are the only data on disk. There is no cache.
- In a git repo, add the `.kanban/` directory to git. The `.gitattributes`
  file sets the built-in `union` merge driver for each log. Thus, when two
  branches change the same node, a merge keeps the lines of the two branches.
- The `.gitignore` file keeps the lock file out of git.

See plan.md §5.2 for the full design.

## Filters

Each list takes one `filter` (plan.md §6.3). The same filter selects the tasks
of a list and the updates of the change feed.

The tasks that have the tag `bug` and the assignee `alice`:

```graphql
{ board { tasks(filter: "#bug && @alice") { edges { node { id title } } } } }
```

The five newest changes that have a column update:

```graphql
{ board { history(filter: "~column", first: 5) { txn ops updates { id kind } } } }
```

The changes that have an update of one node:

```graphql
{ board { history(filter: "^01jabcd") { txn actor { name } updates { fields { name before after } } } } }
```

A subscription to the updates of the tasks that have the tag `bug`, and to the
updates of each comment. `KanbanGraph.subscribe` runs a subscription. The
`kanban` tool does not run a subscription.

```graphql
subscription { changes(filter: "#bug || ~comment") { txn ops updates { id type kind } } }
```

- `~type` keeps the updates of one node type: `~task`, `~column`, `~tag`,
  `~actor`, `~comment`, or `~board`.
- `^id` keeps the updates of one node. On a task, it also keeps the updates of
  the tasks that depend on it.
- A task atom (`#tag`, `@actor`, `%column`) matches only a task.
- `history` and `changes` take no `type`, `node`, `actor`, or `derived`
  argument. To get the author of a change, read `actor` of the `Change`.

## Run the tests

A package boundary separates the two test suites:

- `swift test` runs the unit suite. The unit tests need no model and no
  network.
- `swift test --package-path IntegrationTests` runs the integration suite in
  the nested [`IntegrationTests`](IntegrationTests) package. These tests use
  real external systems, for example a real git repo. The model test uses
  Qwen 3.8 (`mlx-community/Qwen3.8-27B-mxfp4`), which MLX runs. It needs a
  Mac with a Metal device, and it downloads the model (about 14 GB) into the
  Hugging Face cache when the cache does not have it.

The package structure selects the suite. No environment variable changes it.
The root `Package.swift` declares one test target, the unit suite, so a root
`swift test` cannot run an integration test. The integration target is only in
the nested package. CI runs the two suites through the shared `swift-ci`
workflow (see [`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

The nested package commits its own `Package.resolved`, with the same pins as
the root `Package.resolved`. When you change the root pins, copy them to
`IntegrationTests/Package.resolved`.

## Known build warnings

A clean `swift build --build-tests` shows two kinds of warnings. These
warnings are known, and the build check accepts them:

1. The SwiftPM warning
   `warning: missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)`.
2. The `-Wc++17-extensions` warnings from the Metal sources in
   `.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal/`.

Both warnings come from a dependency chain:
`FoundationModelsMetadataRegistry` → `FoundationModelsExtras` → `mlx-swift`.
The `searchTasks` query uses `FoundationModelsMetadataRegistry`.

The root package cannot fix these warnings. SwiftPM does not let a root
package set the build settings of the targets of a dependency. Also, the
registry has no product without the MLX dependency. The fix must come from
the dependency chain or from SwiftPM.

These two warnings are the only accepted warnings. A warning from the
sources of this package, or a different warning from a dependency, still
fails the build check.
