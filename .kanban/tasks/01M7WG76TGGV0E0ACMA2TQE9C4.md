---
assignees:
- claude-code
position_column: done
position_ordinal: ffcd80
title: Remove the parallel git tests of the test helper GitProcess
---
CI run 44343306842 (909c903, runner m3u1, 32 cores) failed in `GitProcessTests.sleepWakesWhileGitRuns` with `.timedOut`. The test started 4 git commands for each processor (128 on m3u1) while the other suites ran.

3054fe1 added the test when the product code ran git. Since 999274b the product code reads git with libgit2, and `GitProcess` is only a test helper. Thus the parallel tests protect no product behavior, and they make the CI runs slow and not reliable.

## Steps
- [x] 7e301ba gave the parallel tests a limit of 180 s. CI run 44739384263: the job "Build & test" passed.
- [x] Remove the two parallel tests ("A short sleep wakes near its deadline..." and "Git commands in more tasks than processors all end") and their helpers. Keep the tests for large standard error, time-out, and cancel.
- [x] `swift test` passes (1933 tests).
- [ ] Push, and send the CI result to testudoapp-9a.