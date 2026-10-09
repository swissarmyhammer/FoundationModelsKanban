---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4ga6qv1arnscxr8dpjdswxe
  text: |-
    Research done. Findings:
    - `ShortID.canonicalMatch` uses `ulids.first` for the short-id form, so a shared short id gives `.found` of the first ULID. Fix: give `.ambiguous` with each owner.
    - Mutations resolve through `RefResolver.ulidRef`, which already throws `AMBIGUOUS_ID` on `.ambiguous`. But `KanbanError.ambiguousID(reference:matches:[ShortID])` shows only short ids, and "Send one of these short ids" is wrong when the matches share one short id. Plan: a new case with the code `AMBIGUOUS_ID` that lists the full ids, used when the short ids of the matches are not unique.
    - Filter: `FilterEvaluator` resolves `^id` among the task and its dependencies only (port of the Rust `short_ref_matches`), so a shared short id matches both tasks and gives no error. `resolvedRef` also swallows each error. Plan: when the evaluator is made, check the `^` value against all task and comment ULIDs of the graph (live or tombstoned); a short id that two or more of them share throws `AMBIGUOUS_ID`. An ambiguous prefix keeps the Rust rule (it matches nothing).
    - The throw goes up through `TaskFilter`, `TaskSelection.tasks(in:)`, and `ChangeFilter`. All callers but `ChangeFeed.publish` can throw. The subscription checks the filter against the current view when it starts, so the subscribe call gives `AMBIGUOUS_ID`. A later publish (after a merge) cannot throw into an `AsyncStream`; it logs the error and sends no change to that subscriber.
  timestamp: 2026-10-09T12:29:00.129743+00:00
- actor: claude-code
  id: 01m4gazbvnx0mrhh25hsjj060k
  text: |-
    Implementation landed (TDD: each new test was seen RED first).
    - `ShortID.resolve`: the short-id form now gives `.ambiguous` when two or more ULIDs have the short id. New `ShortID.ulids(withShortIDOf:among:)`.
    - New error case `KanbanError.sharedShortID(reference:ids:)`, code `AMBIGUOUS_ID`. Its message lists the full ULIDs, because "Send one of these short ids" is wrong when the short ids are the same. `KanbanError.ambiguity(of:among:)` picks `ambiguousID` (short ids unique) or `sharedShortID` (else). `RefResolver.ulidRef` uses it.
    - `RefResolver.checkShortIDIsUnique`: before a ULID-form resolve, the short id is checked against all nodes of the ULID types, live AND tombstoned (card: "live or tombstoned"). So a live task plus a tombstone with the same short id also gives `AMBIGUOUS_ID`.
    - Filter: `FilterEvaluator.init`, `TaskFilter.init`, `TaskSelection.tasks(in:)`, and `ChangeFilter.applied/updates` now throw. The `^id` atom checks the value against all tasks and comments of the board. An ambiguous PREFIX in a filter keeps the Rust rule (matches nothing); only a shared short id throws.
    - Subscription: `ChangeFilter.check(against:)` runs at subscribe, so the subscribe call gives `AMBIGUOUS_ID`. If a later merge makes the short id shared, `ChangeFeed` logs the error and ends that subscriber stream (an `AsyncStream` cannot carry the error).
    - Error ids are in board order: the loader orders nodes by ref, so the order of the ULIDs.
    - Test helpers: `KanbanGraphTests.writeTask(_:titled:mintingFrom:to:)` (given ULID), `SubscriptionTests.errorCode(of:)` is now internal, and the `FilterEvaluatorTests` helpers throw.
  timestamp: 2026-10-09T12:42:27.061096+00:00
- actor: claude-code
  id: 01m4gazfwhb0epj39fvw1knvqk
  text: |-
    ### implement — changed
    - evidence: 17 files. Sources: Identity/ShortID.swift, Identity/RefResolver.swift, GraphQL/Errors.swift, GraphQL/TaskSelection.swift, Filter/FilterEvaluator.swift, Filter/TaskFilter.swift, Observe/ChangeFilter.swift, Observe/ChangeFeed.swift, Observe/ChangeSubscription.swift, Observe/Change.swift, Undo/History.swift. Tests: Identity/SharedShortIDTests.swift (new, 8 tests), Identity/ShortIDTests.swift (+4), GraphQL/KanbanErrorTests.swift (+2), Filter/FilterEvaluatorTests.swift, Observe/SubscriptionTests.swift, Tool/KanbanGraphTests.swift. `swift test`: 1034 tests in 73 suites passed, 0 failed; only the accepted SwiftPM "missing creator for mutated node" warning.
    - next: /review
  timestamp: 2026-10-09T12:42:31.185837+00:00
- actor: claude-code
  id: 01m4gb7qrw0y8671xanewh9jh3
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD; engine counts: 1 finding (1 confirmed, 0 refuted). Sources/FoundationModelsKanban/Identity/RefResolver.swift:327 (code-hygiene/magic-numbers-swift). Caller check: the commit message of 8b68b37 is not correct. It says that a shared short id no longer gives AMBIGUOUS_ID and that the resolver picks a task. The code gives AMBIGUOUS_ID (KanbanError.sharedShortID).
    - next: Replace the magic number at RefResolver.swift:327 with a named constant, and remove each other magic number in that file. Write the commit message again so that it agrees with the diff. Then review again.
  timestamp: 2026-10-09T12:47:01.404579+00:00
- actor: claude-code
  id: 01m4gb83zcb2j60nd7k2f4z2xk
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 17 files
    - test: green — swift test, 1034 tests in 73 suites passed
    - commit: 8b68b37
    - review: findings — Sources/FoundationModelsKanban/Identity/RefResolver.swift:327, commit 8b68b37 message
  timestamp: 2026-10-09T12:47:13.900933+00:00
- actor: claude-code
  id: 01m4gbcjeey7xjwvakr6xnbymh
  text: |-
    Review findings worked.
    - Commit message (done first, before the code edit): 8b68b37 was not pushed (no remote branch contains it). `git commit --amend --only -m ...` changed only the message. New HEAD: 957b8d9. Subject: "fix(identity): give AMBIGUOUS_ID for a short id that tasks share". Body: a short id that two or more tasks share now gives AMBIGUOUS_ID, the message shows the full ULIDs of the matches, the resolver does not pick a task, and no change occurs. Check: `git show --stat HEAD` before and after is the same, and the tree sha is the same.
    - Magic number: RefResolver.swift had one magic number only (`owners.count < 2` in `checkShortIDIsUnique`). New `private static let sharedShortIDOwnerCount = 2`, with a doc comment. RED: `swiftlint lint` with `only_rules: [no_magic_numbers]` and `allowed_numbers: [0, 1, -1, 100]` gave 1 violation at RefResolver.swift:327. GREEN: the same command gives 0 violations for the file. No behavior change, so the current SharedShortIDTests hold the behavior.
  timestamp: 2026-10-09T12:49:39.790597+00:00
- actor: claude-code
  id: 01m4gbcmzqv12chtc3rnezt5ks
  text: |-
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsKanban/Identity/RefResolver.swift (uncommitted). Commit 8b68b37 message amended to 957b8d9 (same tree, same file list). swiftlint no_magic_numbers on RefResolver.swift: 1 violation before, 0 after. `swift test`: 1034 tests in 73 suites passed, 0 failed; only the accepted SwiftPM "missing creator for mutated node" warning.
    - next: /test, /commit, /review
  timestamp: 2026-10-09T12:49:42.391066+00:00
position_column: doing
position_ordinal: '80'
title: Short id shared by two tasks gives AMBIGUOUS_ID
---
## What
`Sources/FoundationModelsKanban/Identity/ShortID.swift:120-128` (`canonicalMatch`) returns the first match in slot order and never returns `.ambiguous`. The doc comment at line 139 says that a merge can make two tasks with the same short id. Then `deleteTask(id:"^abc1234")` changes one of the two tasks with no error. plan.md §3.2 says short ids are a "unique ULID prefix (git style)".

- When two or more live or tombstoned nodes have the short id, return `.ambiguous` and give `AMBIGUOUS_ID` with the candidate ids in the message (the same as for an ambiguous ULID prefix).

## Acceptance Criteria
- [x] With two tasks that share a short id, `^<short>` in a mutation and in a filter gives `AMBIGUOUS_ID` and changes nothing.
- [x] A short id that one task has still resolves.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Identity/ShortIDTests.swift`: a graph with two ULIDs that give the same short id.
- [x] A mutation test that checks the error code and that no patch is written.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-09 07:44)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 17 file(s) reviewed, 50 not reviewed.

> 50 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 50 file(s)

- [x] `Sources/FoundationModelsKanban/Identity/RefResolver.swift:327` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.

### Commit message of 8b68b37
- [x] `commit 8b68b37` `commit/message-accuracy` — The commit message is not correct for the diff. It says "A short id that two tasks share no longer gives AMBIGUOUS_ID. The resolver now picks the correct task." The diff does the opposite: `ShortID.resolve` returns `.ambiguous` for a shared short id, and `RefResolver.checkShortIDIsUnique` throws `KanbanError.sharedShortID`, which has the code `AMBIGUOUS_ID` (`Errors.swift`). The resolver does not pick a task. Write the message again (`git commit --amend`, or a new commit if the commit is pushed) so that it says: a short id that two or more tasks share now gives `AMBIGUOUS_ID` with the full ULIDs of the matches, and no change occurs. Also change the subject line: "resolve a short id shared by two tasks" tells the reader that the id resolves to a task.