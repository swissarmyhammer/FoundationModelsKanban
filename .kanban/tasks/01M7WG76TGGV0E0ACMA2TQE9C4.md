---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Give the parallel git tests a time limit that a loaded CI runner can meet
---
CI run 44343306842 (909c903, runner m3u1, 32 cores) failed in `GitProcessTests.sleepWakesWhileGitRuns` with `.timedOut`. The test starts 128 `sleep 5` git commands while the other suites run. The time limit of `GitProcess.run` starts before git starts, so it also counts the wait for a thread and the start of the process. Alone, the test passes in 5.3 s. This is a limit that is too tight under load, not a defect in `GitProcess`.

## Steps
- [x] The two parallel tests use `parallelGitLimit` (180 s), not `GitProcess.defaultTimeLimit`.
- [x] `swift test` passes (1935 tests).
- [ ] Push, and send the CI result to testudoapp-9a. #bug #test