---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m6rwqe2y274eny4sf99kdkge
  text: |-
    Design accepted by the peer session, with these changes:
    - Ref resolve order: (1) a node with the slug of the primary id exists -> use it; (2) else a node whose stored aliases match the id or an alias -> use that node; (3) else create the slug node.
    - Do NOT call addActorType(). `Query.viewer: Viewer!`, `type Viewer { actor: Actor! }`, where Actor is the BOARD Actor node (the resolved node of the write actor), now with `aliases: [String!]!`. The board Actor is a superset of the Extras Actor fields (id, name, aliases); the doc comment says so.
    - No viewer -> the session actor's node in the same form.
    - Extra test: `viewer { actor { id } }` equals `actor { id }` of a change that the same caller wrote.
    - Version stays "2" (additive).
  timestamp: 2026-11-06T16:58:00.670301+00:00
- actor: claude-code
  id: 01m6rwrehf6m3ddvncvje0njq6
  text: Picked up. The session that picked up this task has no shell tool and no file edit tool. It cannot run swift build, swift test, swift package update or git. It sends the full work to an implementer sub agent that has these tools.
  timestamp: 2026-11-06T16:58:33.903310+00:00
- actor: claude-code
  id: 01m6rwt6jvfc75w8v44hv0q945
  text: |-
    Blocker: the implementer sub agent also has no shell tool and no file edit tool. Its tools are Read, Write, Glob, Grep, the sah tools (kanban, code_context, review, diagnostics, git read ops, ralph), Artifact and browser tools. A tool search for a shell tool found none. Thus it cannot run `swift package update FoundationModelsExtras`, `swift build`, `swift test`, `git commit` or `git push`. TDD needs a test run to see each test fail before the code change, and the task needs a full green test run, a commit and a push. Thus no work was done and no file was changed. A session with a Bash tool must do this task.

    ### implement — stuck
    - evidence: no files changed; no shell tool in the implementer session (no Bash, no Edit).
    - next: run the implement step in a session that has a Bash tool and an Edit tool.
  timestamp: 2026-11-06T16:59:31.291051+00:00
- actor: claude-code
  id: 01m6s19dqsj161c11vzwe4ertz
  text: |-
    ### implement — changed
    - evidence: Extras dbbd53e, mlx-swift-lm stable 021b934. New: Tool/SessionActor.swift, GraphQL/ViewerField.swift, Tests/.../Tool/ViewerActorTests.swift (12 tests). divergence.md §26. Golden SDL updated (additive only; version stays "2").
    ### test — green
    - evidence: `swift test`: 1910 tests in 166 suites passed; no new build warnings.
    - note: the subscription keeps its start actor because each event runs with the store of the start; no test observes this from outside, because a subscription event gives no field of the subscriber.
  timestamp: 2026-11-06T18:17:44.441364+00:00
position_column: done
position_ordinal: ffc680
title: Write each change as the actor of the caller (viewer actor)
---
Step 4 of 5 of the "write each change as the person who made it" work (Extras dbbd53e, ACPClient, ACPAgent done).

## Problem
KanbanGraph writes each event with its fixed `sessionActor` (KanbanGraph.swift:43, :737, :1091). `execute(... viewer:)` uses the viewer only for BoardReach. Thus a change that a person makes through the ACP GraphQL tunnel is recorded as the agent. Also `undoChange(input: {})` by the agent can find the wrong actor.

## Scope
1. Write actor of each call: `viewer?.actor` when present, else the session actor. Pass it to each `actingAs:` site and each place that records an actor (comment author, rejectTask author, translateFilter).
2. Map GraphQLActor to a kanban actor: ref `actor/<slug of id>`, name, aliases. Create or update the actor node at the first write. A write under an alias id resolves to the existing actor node.
3. Schema: `addActorType()`, `Query.viewer { actor }`. Bump endpoint version if necessary.
4. `undoChange` / `redoChange` with no txn: newest change of the caller's actor (with aliases).
5. A subscription keeps its start viewer.
6. Deterministic tests (see acceptance).

## Acceptance
- [ ] A call with a viewer actor records that actor; a call with no viewer records the session actor.
- [ ] Two actors on one board give the correct actor on each change of Board.history.
- [ ] `viewer { actor }` is correct with and without a viewer.
- [ ] `undoChange({})` by the agent skips the newer change of the person, and the reverse.
- [ ] An alias id counts as the same person.
- [ ] `swift build` and `swift test` pass with no new warnings. Push, and send the commit to the peer session.

#viewer-actor