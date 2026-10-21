---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5g0syw9zd4f2rfabgr6n0cj
  text: |-
    Root cause found and fixed in the working tree, during the ^e60e9sx implement pass. Not committed yet.

    **Bisect:** this batch did not introduce it. 91c116c (before ^e60e9sx) gives the same failure in a fresh-process loop of `swift test --skip-build --filter CollectBoardsTests`, with the same txns and the same message: `UNDO_CONFLICT ... "01M3ZYPEF80000000000000001": 01M3ZYPFEG00Y000000000001X`. The earlier "0/10 at 91c116c" was too few runs. The failure rate is about 1 in 30 to 60 suite runs.

    **Root cause:** the hypothesis on this card was right that `undo` with no txn searches the loaded source boards. The reason they still hold events after the collect is this:
    - collectBoards loads each source as a related engine (`otherTargets` scans every copy).
    - Its commit removes each source `.kanban/` with `FileManager.removeItem`.
    - The commit never updates the sessions of those source engines, so they keep the removed board in memory until their own file watcher reads the removal.

    A debug trace (prints, since removed) showed the two cases:
    - **Pass:** the sources still hold all their events. undo targets beta's newest txn and needs beta's gate, and the commit check then finds beta's files gone. The same happens for alpha, and the last run gives NOTHING_TO_UNDO.
    - **Fail:** alpha's watcher applied an FSEvents batch while `removeItem` was still running and kept 8 of 9 events. The comment file was gone and the addTask file was still there. alpha's newest target is then addTask txn ...0001, and undoing it tombstones alpha's task. The target holds beta's merged txn ...001X, which has a dependsOn to that task, so undo throws UNDO_CONFLICT (X6) before any commit check sees that alpha is gone.

    So the write broke the commit rule: after a write of this process, the session must hold the new live graph so that the watcher finds no change. The outcome then depended on when each source's watcher read the folder during the removal.

    **Fix:**
    - `BoardStore.addToCommit(loadedBoardsAt:)` (Schema.swift) adds each loaded source to the boards of the commit, with no patch. `CollectBoardsField.write` calls it. admit therefore takes each source's serial gate, so its watcher cannot apply a batch during the removal.
    - `CommitSession.applyRemoval(of:to:)` (Commit.swift) runs after the commit removes the source `.kanban/` folders, still under the lock. It calls `applyChangedFiles` on each commit board at a source folder, so storeRelatedBoards gives each source engine an empty board. A read failure is logged, and the watcher applies the removal later.

    **Test:** `CollectBoardsTests.collectEmptiesEngineOfEachSource` uses a host with `QuietFolderEvents`, so no watcher batch ever arrives. After collect, `readSession()` of each source engine must hold no event. It failed before the fix (2 issues) and passes after.

    **Evidence:**
    - CollectBoardsTests suite: 100 of 100 fresh-process runs passed. Before the fix, HEAD failed 1 in 30 and 1 in 60.
    - Full `swift test`: 1746 tests in 145 suites passed in each of 2 runs. One more run hung on the GraphQL `PublicSchema.init` dispatch deadlock (^cnjgjaj, same stack); it was killed and rerun.

    This fix fully resolves the flake: the source engines are empty before the call gives back their gates, so the watcher timing no longer matters.
  timestamp: 2026-10-21T20:00:25.993767+00:00
position_column: todo
position_ordinal: '8880'
title: 'Flaky: CollectBoardsTests "undo does not reverse collectBoards" gets UNDO_CONFLICT under full-suite load'
---
## What
The test `undo does not reverse collectBoards` (Tests/FoundationModelsKanbanTests/CrossRepo/CollectBoardsTests.swift, `undoDoesNotReverseCollect`) failed one full `swift test` run on 2026-10-21. It expected NOTHING_TO_UNDO, but the response was:

```
{"data":{"undo":null},"errors":[{"extensions":{"code":"UNDO_CONFLICT"},"message":"Later transactions changed the same properties as transaction \"01M3ZYPEF80000000000000001\": 01M3ZYPFEG00Y000000000001X. ..."}]}
```

The test took 8.3 s in that run, and about 0.7 s for the whole suite when it runs alone. It passed in 8 filtered runs (`swift test --skip-build --filter CollectBoardsTests`) and in the next full run. Seen on top of 207bcab plus the one-line `[Key: NewValue]` change of ^e60e9sx.

Unverified hypothesis: an undo with no `txn` searches the current board and every loaded related board (`UndoMutations.searchedBoards` → `loadedTargets`). The `collectBoards` barrier (`UndoLog.target`, `transactions.last(where: \.isFinal)`) lives only in the target's log. When a source board engine is still loaded with its pre-collect session after the collect, the source's own transaction `...0001` (from `KanbanGraphTests.mutationIDs`, same actor) is a candidate there, and the undo then hits the later transaction of the second source (`GitGraphFixture.secondEngineIDs`). Find out why the source boards are normally not searched after the collect, and what timing lets them be searched.

## Acceptance Criteria
- [ ] Root cause found and recorded
- [ ] The test passes deterministically (a test forces the timing that made it fail)
