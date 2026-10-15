---
name: kanban
description: Do the next task of the kanban board. Use when the user says "kanban", "/kanban", "next task", "what's the next task", or "pick up work". Gets the next ready task from the board, moves it to doing, does the work, and moves it to review.
license: MIT OR Apache-2.0
compatibility: Requires the `tools.kanban` function of a code-mode host such as FoundationModelsMultitool, with the `KanbanTool` of FoundationModelsKanban. The model calls it in the `runCode` tool.
metadata:
  author: swissarmyhammer
  version: "1.0.0"
---

# Kanban

Do the tasks of the kanban board.

{% include "_partials/sah-findings-are-requirements" %}

## Use the board for all task tracking

- The board is your todo list. Do not use TodoWrite, TaskCreate, or a different task tool. Use only `kanban`. The board is the one record for all agent sessions.
- A subtask is one line of a GFM checklist (`- [ ]` or `- [x]`) in the `body` of the task. There is no subtask API. Put the checklist in the body when you add the task, or change the body with `updateTask`.

## Call the tool

In the `runCode` tool, call `tools.kanban({ query, variables })`. `query` is one GraphQL document. `variables` is an object, or a string that holds a JSON object. The result is the GraphQL response: `data`, `errors`, and `extensions`.

```js
const r = await tools.kanban({ query: `{ board { name summary { total ready done } } }` });
return { board: r.data.board, errors: r.errors ?? [], warnings: r.extensions?.warnings ?? [] };
```

```json
{"board":{"name":"my-project","summary":{"done":0,"ready":0,"total":0}},"errors":[],"warnings":[]}
```

- Each error has `extensions.code`, for example `NOT_FOUND`. The `message` tells you how to correct the call.
- Read `extensions.warnings` after each call. A warning tells you that the call did the work in a different way than you asked. Each warning has a `message` and a `code`. The call is done, and its changes are written.
- All mutation fields of one document are one transaction. `undo` reverses all of the transaction.
- To learn the schema, query `__schema` or `__type`.

## The board

- The board is in the `.kanban/` folder at the top folder of the git worktree (`git rev-parse --show-toplevel`). Each worktree has its own board. Commit `.kanban/` with the code. Thus the task changes go on the branch of the code, and git merges the boards when it merges the branches.
- A query on a repo that has no board gives an empty board, and it writes no file. The first mutation makes the board, with the columns `todo`, `doing`, `review`, and `done`. The board name is the name of the folder.
- A folder that is not in a git repo has no board. Each call then gives `NOT_A_REPO`. Tell the user.
- A `.kanban/` folder of the old Rust kanban gives `INCOMPATIBLE_BOARD`. Do not change that folder. Tell the user to remove it. Remove it only when the user tells you to remove it.
- A call names the current board, unless an input `board` field or a full `kanban://` URI names a different board.
- Each session has its own actor. Your changes have your actor, so `undo` with no `txn` reverses only your work.

## Add tasks

`addTask` puts a task at the end of the first column. Put the subtasks in the body as a checklist. The examples of this skill run in order on one board, so the later examples use these tasks.

```js
const r = await tools.kanban({
  query: `mutation($checklist: String!) {
    login: addTask(input: { title: "Fix the login bug", tags: ["bug"], body: $checklist }) {
      title column { name } tags { name } progress { completed total }
    }
    docs: addTask(input: { title: "Write the docs", tags: ["docs"] }) { title column { name } }
  }`,
  variables: { checklist: "- [ ] Find the cause\n- [ ] Add a test" }
});
return r.data;
```

```json
{"docs":{"column":{"name":"To Do"},"title":"Write the docs"},"login":{"column":{"name":"To Do"},"progress":{"completed":0,"total":2},"tags":[{"name":"bug"}],"title":"Fix the login bug"}}
```

- An `addTask` with no `assignees` assigns your actor, when your actor was on the board before the call.
- Each `id` in a response is a full URI, for example `kanban://github.com/owner/repo/task/<ULID>`. Each task also has a `shortId`. When you name a task in text, write `^` and the `shortId`, for example `^rc9rb4g`. Copy the `shortId` from the response. Do not make a short form of the ULID yourself.

## Process

### 1. Get the next task

`nextTask` gives the first ready task in board order: the column order, then the place in the column. A ready task is open, and each of its dependencies is done. Add a filter to choose the work.

```js
const r = await tools.kanban({ query: `{ board { nextTask(filter: "#bug") { id title ready } } }` });
const t = r.data.board.nextTask;
if (!t) return { next: null };
return { title: t.title, ready: t.ready };
```

```json
{"ready":true,"title":"Fix the login bug"}
```

### 2. Take the task

There is no claim operation. The agents themselves decide which agent does which task. Two agents can get the same task from `nextTask`, so take the task immediately: assign yourself, and move the task to `doing`. A comment with no `actor` has your actor as its `author`. Thus the first comment also gives you your actor id.

```js
const t = (await tools.kanban({ query: `{ board { nextTask(filter: "#bug") { id } } }` })).data.board.nextTask;
const c = await tools.kanban({
  query: `mutation($id: ID!) { addComment(input: { task: $id, body: "Picked up." }) { author { id } } }`,
  variables: { id: t.id }
});
const me = c.data.addComment.author.id;
const r = await tools.kanban({
  query: `mutation($id: ID!, $me: ID!) {
    assignTask(input: { id: $id, actor: $me }) { title }
    moveTask(input: { id: $id, column: "doing" }) { column { name } assignees { id } }
  }`,
  variables: { id: t.id, me }
});
const moved = r.data.moveTask;
return { column: moved.column.name, mine: moved.assignees.some(a => a.id === me) };
```

```json
{"column":"Doing","mine":true}
```

### 3. Read the task

Read the body, the checklist, and the comments. The comments record the work of the agents before you. Do not repeat an approach that a comment says did not work.

```js
const r = await tools.kanban({
  query: `{ board { task(id: "fix-the-login-bug") { title body column { name } comments { body } } } }`
});
return r.data.board.task;
```

```json
{"body":"- [ ] Find the cause\n- [ ] Add a test","column":{"name":"Doing"},"comments":[{"body":"Picked up."}],"title":"Fix the login bug"}
```

### 4. Do each subtask, and check it off immediately

After each subtask, change its `- [ ]` to `- [x]` in the body. Do not wait to check off many subtasks together. Keep all other text of the body. `body` is the full new text: the tool calculates the change.

```js
const t = (await tools.kanban({ query: `{ board { task(id: "fix-the-login-bug") { id body } } }` })).data.board.task;
const r = await tools.kanban({
  query: `mutation($id: ID!, $body: String!) { updateTask(input: { id: $id, body: $body }) { progress { completed total } } }`,
  variables: { id: t.id, body: t.body.replace("- [ ] Find the cause", "- [x] Find the cause") }
});
return r.data.updateTask.progress;
```

```json
{"completed":1,"total":2}
```

### 5. Record the progress

Add a comment with `addComment`, as in step 2. Record the milestones, the approaches that did not work and why, the facts that you did not expect, and the blockers. The next agent reads them.

### 6. Move the task to review

Move the task to `review` when each subtask is `- [x]`. Do not use `completeTask`: it moves the task to `done` and skips the review. Then stop, and tell the user that the task is ready for `/review`.

```js
const r = await tools.kanban({ query: `mutation { moveTask(input: { id: "fix-the-login-bug", column: "review" }) { column { name } } }` });
return r.data.moveTask;
```

```json
{"column":{"name":"Review"}}
```

## Task refs

An input or an argument that takes a task accepts each of these refs:

| Ref | Example |
|---|---|
| The full URI | `kanban://github.com/owner/repo/task/01KT6SA4911JQPK09YQRC9RB4G` |
| The full ULID | `01KT6SA4911JQPK09YQRC9RB4G` |
| The short id: the last 7 characters of the ULID, in lowercase | `rc9rb4g` |
| The short id with `^` | `^rc9rb4g` |
| The stored form `<type>/<id>` | `task/rc9rb4g` |
| The slug of the title | `fix-the-login-bug` |
| A ULID prefix that only one task has | `01KT6SA49` |

```js
const t = (await tools.kanban({ query: `{ board { task(id: "fix-the-login-bug") { id shortId } } }` })).data.board.task;
const ulid = t.id.split("/").pop();
const refs = [t.id, ulid, t.shortId, "^" + t.shortId, "task/" + t.shortId, "fix-the-login-bug"];
const titles = [];
for (const ref of refs) {
  const r = await tools.kanban({ query: `query($ref: ID!) { board { task(id: $ref) { title } } }`, variables: { ref } });
  titles.push(r.data.board.task.title);
}
const prefix = await tools.kanban({
  query: `query($ref: ID!) { board { task(id: $ref) { title } } }`,
  variables: { ref: ulid.slice(0, 2) }
});
return { titles, prefix: prefix.errors[0].extensions.code };
```

```json
{"prefix":"AMBIGUOUS_ID","titles":["Fix the login bug","Fix the login bug","Fix the login bug","Fix the login bug","Fix the login bug","Fix the login bug"]}
```

- Only the full URI can name a task on a different board. Each other ref names a task of the current board, or of the board that the `board` field names. A short ref never names a task on a different board.
- A ULID or a short id wins over a title slug.
- Two tasks can have the same short id or the same title slug. Then the ref names the first match: a live task before a deleted task, then the lowest ULID. The response gives a warning.
- A ULID prefix that two or more tasks have gives `AMBIGUOUS_ID`. The message lists the matching ids. Send the full id.
- A column, an actor, or a tag ref is its slug or its name, for example `doing` or `Doing`.

## Dependencies

A task is blocked until each of its dependencies is done. A task is done when it is in the last column (the column with the highest `order`).

- Put the dependencies in `dependsOn`. The input name `blockedBy` also works, but `dependsOn` is the correct name.
- A dependency on a task of the same board can be each ref of the table above. A dependency on a task of a different repo must be the full `kanban://<board-key>/task/<ULID>` URI.
- `blockedBy` in a response lists the dependencies that are not done.
- A dependency that no loaded board has blocks the task, and `unresolvedDependsOn` shows its URI. The write gives a warning: `DEPENDENCY_BOARD_NOT_FOUND` for a board that the tool cannot find, or `DEPENDENCY_TASK_NOT_FOUND` for a task that a found board does not have.
- A dependency that makes a cycle gives `DEPENDENCY_CYCLE`.

```js
const r = await tools.kanban({
  query: `mutation {
    addTask(input: {
      title: "Ship the release",
      dependsOn: ["write-the-docs", "kanban://github.com/example/other/task/01J00000000000000000000000"]
    }) { ready virtualTags blockedBy { title } unresolvedDependsOn }
  }`
});
return { task: r.data.addTask, warnings: r.extensions.warnings.map(w => w.code) };
```

```json
{"task":{"blockedBy":[{"title":"Write the docs"}],"ready":false,"unresolvedDependsOn":["kanban://github.com/example/other/task/01J00000000000000000000000"],"virtualTags":["BLOCKED","MEDIUM"]},"warnings":["DEPENDENCY_BOARD_NOT_FOUND"]}
```

A full task URL in the body is also a dependency. A task URL in a code block, in inline code, or in a heading is not a dependency.

```js
const docs = (await tools.kanban({ query: `{ board { task(id: "write-the-docs") { id } } }` })).data.board.task;
const body = "Do this after " + docs.id + " is done.\n\nThe example `" + docs.id + "` is not a dependency.";
const r = await tools.kanban({
  query: `mutation($body: String!) { addTask(input: { title: "Announce the release", body: $body }) { dependsOn { title } } }`,
  variables: { body }
});
return r.data.addTask;
```

```json
{"dependsOn":[{"title":"Write the docs"}]}
```

When the docs task is done, the announce task is ready. The ship task stays blocked, because its other dependency does not resolve. `blockedBy` is empty, so read `unresolvedDependsOn`.

```js
await tools.kanban({ query: `mutation { moveTask(input: { id: "write-the-docs", column: "done" }) { title } }` });
const r = await tools.kanban({
  query: `{ board {
    announce: task(id: "announce-the-release") { ready }
    ship: task(id: "ship-the-release") { ready blockedBy { title } unresolvedDependsOn }
  } }`
});
return r.data.board;
```

```json
{"announce":{"ready":true},"ship":{"blockedBy":[],"ready":false,"unresolvedDependsOn":["kanban://github.com/example/other/task/01J00000000000000000000000"]}}
```

`updateTask` with `dependsOn` replaces the list. A dependency that the new list does not have is removed, also its URL in the body.

```js
const r = await tools.kanban({
  query: `mutation { updateTask(input: { id: "ship-the-release", dependsOn: ["write-the-docs"] }) { ready dependsOn { title } unresolvedDependsOn } }`
});
return r.data.updateTask;
```

```json
{"dependsOn":[{"title":"Write the docs"}],"ready":true,"unresolvedDependsOn":[]}
```

## Virtual tags

The tool calculates these tags. A filter uses them as `#READY`, `#DONE`, and so on. A real tag cannot have one of these names.

| Tag | The task |
|---|---|
| `READY` | is open, and each of its dependencies is done. |
| `BLOCKED` | has at least one dependency that is not done. |
| `CONFLICT` | has a conflict block in its body, from a merge of two body changes. |
| `DELETED` | is deleted. A list shows a deleted task only when the filter names `#DELETED`. |
| `DONE` | is in the last column. |
| `HIGH` | is in the first third of the open tasks, in board order. |
| `MEDIUM` | is in the second third of the open tasks. |
| `LOW` | is in the last third of the open tasks. |

BLOCKING is not a virtual tag: `#BLOCKING` is an ordinary tag filter. To find the work that blocks a task, read its `blockedBy`.

## Filters

`tasks`, `nextTask`, `searchTasks`, `history`, and the `tasks` field of a column, an actor, or a tag take one `filter`. There is no `column`, `tag`, or `assignee` argument: write the atom.

| Atom | Matches |
|---|---|
| `#tag` | the tasks with this tag, also a virtual tag |
| `@actor` | the tasks that this actor is assigned to |
| `%column` | the tasks in this column |
| `^id` | the task with this ref, and the tasks that depend on it. `id` is a ULID, a short id, a short id with `^` (`^^rc9rb4g`), or a title slug (`^fix-the-login-bug`). A shared short id or title slug matches each task that has it. |
| `~type` | each node of this type: `task`, `column`, `tag`, `actor`, `comment`, or `board`. Use it with `history`. |
| a `kanban://` URL | the same as the atom of its node type, for example `@kanban://<board-key>/actor/<slug>` |
| `&&` or `and` | both sides |
| `\|\|` or `or` | one side or the two sides |
| `!` or `not` | the opposite |
| `( )` | a group |
| two atoms next to each other | both atoms: `#bug @alice` is `#bug && @alice` |

- A list with no filter gives each task that is not deleted, also the done tasks. Use `!#DONE` for the open tasks.
- A filter that does not parse gives `INVALID_FILTER`, with the position and a correct example.

```js
const login = (await tools.kanban({ query: `{ board { task(id: "fix-the-login-bug") { assignees { id } } } }` })).data.board.task;
const filters = {
  ready: "#READY",
  done: "#DONE",
  bugsInReview: "#bug && %review",
  afterDocs: "^write-the-docs && !#DONE",
  high: "#HIGH",
  mine: "@" + login.assignees[0].id
};
const lists = {};
for (const [name, filter] of Object.entries(filters)) {
  const r = await tools.kanban({
    query: `query($filter: String!) { board { tasks(filter: $filter) { nodes { title } } } }`,
    variables: { filter }
  });
  lists[name] = r.data.board.tasks.nodes.map(t => t.title);
}
return lists;
```

```json
{"afterDocs":["Ship the release","Announce the release"],"bugsInReview":["Fix the login bug"],"done":["Write the docs"],"high":["Ship the release"],"mine":["Ship the release","Announce the release","Fix the login bug"],"ready":["Ship the release","Announce the release","Fix the login bug"]}
```

## Priority

A task has no priority field. The place of the task in its column is its priority. `HIGH`, `MEDIUM`, and `LOW` come from that place. To change the priority, move the task with `moveTask` and `before` or `after` a different task. Give only one of `before`, `after`, and `ordinal`: two of them give `CONFLICTING_PLACEMENT`.

A `priority` input also moves the task in its column, and gives the warning `PRIORITY_IS_POSITION`:

| `priority` value | Move |
|---|---|
| `urgent`, `critical`, `high`, `P0`, `P1`, `true` | to the top of the column |
| `low`, `P3`, `P4` | to the end of the column |
| `medium`, `normal`, `P2`, and each other value | no move |

```js
const r = await tools.kanban({
  query: `mutation {
    moveTask(input: { id: "announce-the-release", column: "todo", before: "ship-the-release" }) { title }
    addTask(input: { title: "Fix the crash", tags: ["bug"], priority: "urgent" }) { title }
  }`
});
const todo = await tools.kanban({ query: `{ board { tasks(filter: "%todo") { nodes { title virtualTags } } } }` });
return { warnings: r.extensions.warnings.map(w => w.code), todo: todo.data.board.tasks.nodes };
```

```json
{"todo":[{"title":"Fix the crash","virtualTags":["READY","HIGH"]},{"title":"Announce the release","virtualTags":["READY","HIGH"]},{"title":"Ship the release","virtualTags":["READY","MEDIUM"]}],"warnings":["PRIORITY_IS_POSITION"]}
```

## Tags

- `tagTask` and `untagTask` add and remove tags. `addTask` and `updateTask` take a full `tags` list. A tag that the board does not have is made.
- A `#tag` in the body is also a tag. `untagTask` also removes it from the body.
- `renameTag` with `from` and `to` renames a tag. The old name then points to the new tag.

```js
const r = await tools.kanban({
  query: `mutation {
    tagTask(input: { id: "fix-the-crash", tags: ["release"] }) { tags { name } }
    untagTask(input: { id: "fix-the-crash", tags: ["bug"] }) { tags { name } }
  }`
});
return r.data;
```

```json
{"tagTask":{"tags":[{"name":"bug"},{"name":"release"}]},"untagTask":{"tags":[{"name":"release"}]}}
```

## Undo and redo

- `undo` with no `txn` reverses your newest transaction that is not undone. Your actor is the actor of your session, so `undo` does not reverse the work of a different session.
- `redo` reverses your newest `undo`.
- `history` lists the transactions, newest first. To reverse a given transaction, give its `txn`: `undo(input: { txn: "<txn>" })`.
- A later change to the same data gives `UNDO_CONFLICT`. Read the later transactions in the message before you use `force: true`.

```js
await tools.kanban({ query: `mutation { addTask(input: { title: "A wrong task" }) { title } }` });
const undo = await tools.kanban({ query: `mutation { undo { ops } }` });
const history = await tools.kanban({ query: `{ board { history(first: 2) { ops undone } } }` });
const deleted = await tools.kanban({ query: `{ board { tasks(filter: "#DELETED") { nodes { title } } } }` });
const redo = await tools.kanban({ query: `mutation { redo { ops } }` });
const back = await tools.kanban({ query: `{ board { task(id: "a-wrong-task") { title } } }` });
return {
  undo: undo.data.undo.ops,
  history: history.data.board.history,
  deleted: deleted.data.board.tasks.nodes.map(t => t.title),
  redo: redo.data.redo.ops,
  back: back.data.board.task.title
};
```

```json
{"back":"A wrong task","deleted":["A wrong task"],"history":[{"ops":["undo"],"undone":false},{"ops":["addTask"],"undone":true}],"redo":["redo"],"undo":["undo"]}
```

## Forgiving names

The tool accepts a name that is close enough, for example `createTask`, `task_id`, `labels`, or `status`. It rewrites the name to the canonical name, and `extensions.rewrites` tells you the change. Use the canonical names of this skill: a name that is close to two names gives `AMBIGUOUS_NAME`. A removed parameter of the old Rust kanban (for example `project` or `due`) gives the warning `REMOVED_PARAMETER`, and the call ignores it.

## Guidelines

- Do each subtask. Do not skip a subtask, and do not check it off before you do the work.
- When a task is blocked or not clear, record it in a comment.
- Run the tests after each subtask.
- Move the task to review only when each subtask is done and the tests pass.
- When you find new work, add a new task. Do not keep it only in your memory.
