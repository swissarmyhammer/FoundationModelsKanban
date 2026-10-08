---
comments:
- actor: wballard
  id: 01m4drgwyn6b2dgwk3z3zb9zr3
  text: |-
    Research done. Findings:
    - All the changed API is internal: `Git`, `BoardKey`, `BoardKeyError`, the `BoardKeyReader` typealias, and `BoardLocator.scan` are internal. The public `KanbanGraph.init(root:actor:locator:embedder:)` does not change, so the CLI (Sources/kanban/KanbanMain.swift) and the IntegrationTests package need no source change for the engine.
    - `KanbanGraph` reads the key lazily: `loadedSession()` calls `keyReader(root)`, and `rescan()` calls `locator.scan(...)`. Both are actor methods under the serial gate, so they can become async with no change to the init. `resolution(of:currentKey:)`, `rescan()` and `loadEachCopy()` get `await`.
    - `Process` (NSTask) is `NS_SWIFT_SENDABLE`, so a Sendable run object can hold it. `DispatchWorkItem` is not Sendable.
    - A git alias with `!` runs in `sh`, whose parent is git (`/usr/bin/env` execs git), so `$PPID` in the alias is the pid of the child that `Git.run` starts. The cancel test uses this to check that the child is gone.
    - On a time-out or a cancel, a grandchild (`sh` and `sleep` of an alias) can keep the pipes open after git ends. Thus the run must not wait for the pipes after a stop, as the old code also did not.
    - Test helpers that run git: `GitSandbox.runGit` (and `makeRepo`, `addWorktree`), `CountingKeyReader.key`, `BoardLocatorTests.scan`, `CrossRepoFixture.SideBySide.init`, `PortabilityTests.RepoMove`, and IntegrationTests `TemporaryGitRepo.runGitInit` (it uses `waitUntilExit`). `GitGraphFixture` and `KanbanProcess` do not block (the graph reads the key lazily; `KanbanProcess` already uses async streams).
    - `EventLogTests.becomesTrue(within:_:)` is an internal poll with a deadline; the new tests reuse it.
    Plan: `Git.run` becomes async. A private `GitRun` object (Mutex state) collects the exit status (terminationHandler) and the two pipes (readabilityHandler, no blocked thread), and resumes one checked continuation when all three are done, or at once on a stop. A child task of `async let` sleeps for the time limit and stops the run with `gitTimedOut`. `withTaskCancellationHandler` stops the run with a new `BoardKeyError.gitCancelled(arguments:)`. A stop terminates git.
  timestamp: 2026-10-08T12:41:29.813691+00:00
- actor: wballard
  id: 01m4dspfv8q54tj46c3h32bfhg
  text: |-
    Implementation notes:
    - `Git.run` is now `async throws(BoardKeyError)` with `timeLimit: Duration` (default `Git.defaultTimeLimit`, 30 s). A private `GitRecord` (Mutex state, no reference to the process, so no handler cycle) records the exit status (`terminationHandler`) and both pipes (`readabilityHandler`, no blocked thread, both read at the same time), and resumes one `CheckedContinuation` when all three are done. An `async let` child sleeps for the limit and then stops the run with `gitTimedOut`; `withTaskCancellationHandler` stops it with the new `BoardKeyError.gitCancelled(arguments:)`. A stop terminates git and returns at once; it does not wait for the pipes, because the shell of an alias can keep them open. stdin stays `/dev/null`. `PipeReader` (serial-queue blocking reads) is removed.
    - `BoardKey.read`, `BoardKeyReader`, `BoardLocator.scan` are async. `scan` now reads the keys of new repos in a task group (keeps scan order with `compactMap`), so the scan has no `var` accumulator. `KanbanGraph.loadedSession`, `resolution(of:currentKey:)`, `rescan()` await. Public API: no change (all changed declarations are internal; `KanbanGraph.init(root:actor:locator:embedder:)` is the same).
    - Test helpers: `GitSandbox.runGit/makeRepo/addWorktree`, `CountingKeyReader.key`, `BoardLocatorTests.scan`, `TwoCopies.init`, `CrossRepoFixture.SideBySide.init`, `PortabilityTests.RepoMove`, `KanbanCLITests.makeRepo` are async. IntegrationTests `TemporaryGitRepo.runGitInit` waits for an async stream from `terminationHandler` with a 30 s limit (no `waitUntilExit`).
    - RED (old blocking `Git.run`, compile-only stub of `gitCancelled`): `sleepWakesWhileGitRuns` failed on `waited < slowCommandDuration` (20.1 s); `cancelledCommandStopsGit` failed on the elapsed time and on "an error was expected but none was thrown". GREEN: BoardKeyTests 18 pass (sleep test 5.13 s, cancel test 0.13 s, time-out test 0.38 s, parallel 0.12 s).
    - Discovery: the deadline test of EventLogTests still waits about 1.2 s after its 300 ms deadline in a full run (was 1.5 to 1.9 s). Likely sources: the new sleep test starts 4 x CPU git + sh + sleep processes at the same moment, and other tests still do blocking file and flock work. Not in the scope of this card.
  timestamp: 2026-10-08T13:02:01.576549+00:00
- actor: wballard
  id: 01m4dspm6bqqh9e2804x89yprg
  text: |-
    ### implement — changed
    - evidence: Sources: Identity/BoardKey.swift, CrossRepo/BoardLocator.swift, Tool/KanbanGraph.swift. Tests: Identity/BoardKeyTests.swift (2 new tests, shared `runningGitInParallel` helper), CrossRepo/{BoardLocatorTests, CrossRepoFixture, CrossRepoReadTests, CrossRepoWriteTests, CrossRepoUndoTests, CrossRepoCycleTests, CrossRepoEventBoardTests, CrossRepoActorTests}.swift, Design/PortabilityTests.swift, CLI/KanbanCLITests.swift, Observe/SubscriptionTests.swift; IntegrationTests Support/TemporaryGitRepo.swift. Public API: no change.
    - `swift build --build-tests`: only the accepted `missing creator` warning. swiftlint no_magic_numbers / line_length / force_*: 0 findings. periphery: no unused code.
    - 5 root runs, `timeout 120 swift test --skip-build`: 963 tests in 67 suites pass each; 8.221 s, 8.947 s, 9.661 s, 8.904 s, 8.898 s. EventLogTests deadline test: 1.311, 1.585, 1.555, 1.534, 1.498 s (before: 2.040, 2.032, 1.824, 1.896, 2.201 s).
    - IntegrationTests `swift build --build-tests && swift test` (300 s limit): 1 test passed.
    - next: /review
  timestamp: 2026-10-08T13:02:06.027847+00:00
position_column: doing
position_ordinal: '80'
title: Git.run blocks a Swift cooperative thread while git runs
---
## What
`Git.run` (Sources/FoundationModelsKanban/Identity/BoardKey.swift) starts git and then blocks its thread in `DispatchGroup.wait` until git ends. The engine calls it synchronously from async code: `BoardKey.read(fromRepoAt:)` is the `readingKeyWith` reader of `KanbanGraph` and of `BoardLocator.scan`. Many tests also call it through `GitSandbox.runGit` and `BoardKey.read` from async test functions.

Each call blocks one thread of the Swift cooperative pool, which has about one thread for each processor. In a full parallel `swift test` run, these blocked threads make other async waits late (found in ^aazpa67: a 300 ms deadline wait ended 3.21 s after its start, because its `Task.sleep` wake-ups had no free pool thread).

## Approach
Give `Git.run` an async form that waits for the end of git with no blocked thread (for example a continuation that `terminationHandler` and the two pipe reads resume), and make `BoardKey.read`, the `readingKeyWith` closure type, `BoardLocator.scan`, and the `KanbanGraph` set-up async. Keep the named time limit and `BoardKeyError.gitTimedOut`.

## Acceptance Criteria
- [x] No production path blocks a cooperative thread while git runs.
- [x] The test helpers that run git (`GitSandbox.runGit`) do not block a cooperative thread.
- [x] `BoardKeyTests.parallelCommandsAllEnd` and the time-out tests still pass.

## Tests
- [x] A test that runs many git commands at the same time as a `Task.sleep` wait shows that the sleep wakes near its deadline.
- [x] Run the full root `swift test` 5 times; expect all pass.