---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m51c5nd3xvbme3ah32ehv3xh
  text: |-
    Research:
    - The first commit is made in S/Identity/BoardKey.swift, `makeFirstCommitIfNeeded(in:)`: `git commit-tree <empty tree> -m BoardKey.firstCommitMessage` ("Initial commit"), then `git update-ref HEAD <commit> ""`. The message, the author, and the time are the only inputs, so two repos in the same second get the same hash.
    - Plan: keep the subject "Initial commit" (the test `repoWithoutCommitGetsEmptyFirstCommit` reads %s), and add a second paragraph with a new ULID (`ULID().ulidString`, the same source as SystemULIDSource). The ULID makes each commit different, also with a fixed commit time.
    - RED test: in BoardKeyTests, make two empty repos, read the two keys at the same time with `gitEnvironment: GitSandbox.fixedDateEnvironment` (same author, same time), and expect different keys. With the current code the keys are equal.
    - Fixtures: TemporaryGitRepo (IntegrationTests) and ReadmeExamplesTests.ExampleBoard make their own first commit before the engine runs. Decision: keep both. They give HEAD before the engine starts, and the fixture docs state that as a contract. The engine fix does not make them wrong.
  timestamp: 2026-10-16T03:30:27.363308+00:00
- actor: claude-code
  id: 01m51d1a9rj5vcm8n6xp4q0syj
  text: |-
    Implementation landed:
    - RED: new test `BoardKeyTests.firstCommitsAtSameTimeGiveDifferentKeys`. It makes two empty repos and reads the two keys at the same time with `BoardKey.read(fromRepoAt:gitEnvironment:)` and `GitSandbox.fixedDateEnvironment` (same author, same commit time). Before the fix, the test failed: the two keys were equal.
    - GREEN: `makeFirstCommitIfNeeded(in:)` now gives `commit-tree` two message paragraphs: the subject `Initial commit` (`firstCommitMessage`, not changed) and the trailer `Kanban-Root-ID: <new ULID>` (new `firstCommitTrailerName` and private `makeFirstCommitTrailer()`, which uses `SystemULIDSource`). The existing test that reads the subject with `%s` still passes.
    - divergence.md M8: the commit-tree command now shows the trailer, and a new DECIDED item records why (same hash, same key, wrong board for a cross-board ref and for undo, which finds the home board by key in the host table, ^wwntbag). It also records the fixture decision.
    - Fixtures: kept the first commits in IntegrationTests/.../Support/TemporaryGitRepo.swift and ReadmeExamplesTests.ExampleBoard. They are not pure duplicates: they make HEAD before the engine starts, and their docs state that as a contract. Their messages are unique, so their keys stay unique also without the engine fix.
    - Test runs: the first full `swift test` had 8 issues, all the 60-second time limit (machine load average 115 to 131). The failing suites passed alone. The second full run had 192 issues, all time limits or watcher waits under the same load; the 20 failing suites (153 tests) passed alone. The third full run passed: 1553 tests in 123 suites, 0 failures, only the accepted "missing creator" warning. IntegrationTests passed: 3 tests in 3 suites.
  timestamp: 2026-10-16T03:45:33.496475+00:00
- actor: claude-code
  id: 01m51d1hdzehw6w0fkn38cm63d
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/Identity/BoardKey.swift, Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift (1 new test), divergence.md (M8). `swift test`: 1553 tests in 123 suites passed (third full run; the earlier runs failed only on time limits and watcher waits under load average 115 to 131, and each failing suite passed alone). `swift test --package-path IntegrationTests`: 3 tests passed. Fixture first commits kept (not pure duplicates).
    - next: /test, then /review. The task stays in doing.
  timestamp: 2026-10-16T03:45:40.799086+00:00
- actor: claude-code
  id: 01m51d9z5eqg2rxp30abyhj676
  text: |-
    ### test — green
    - evidence: swift build exit 0, only the SwiftPM "missing creator" warning. swift test: 1553 tests in 123 suites passed, 0 failed, 0 skipped. swift test --package-path IntegrationTests --scratch-path (scratchpad)/integration-build: 3 tests in 3 suites passed, 0 failed, 0 skipped. No other warning. Only one full run was needed. Machine load was about 90, but no time limit failed.
    - logs: scratchpad build.log, test-run1.log, integration-run1.log
    - next: review
  timestamp: 2026-10-16T03:50:17.006211+00:00
- actor: claude-code
  id: 01m51db6906cq6n02s2mhdjpqg
  text: |-
    ### commit — changed
    - evidence: local commit "fix(identity): make the engine first commit unique for each repo (^pwpn97e)". Files: Sources/FoundationModelsKanban/Identity/BoardKey.swift, Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift, divergence.md, and the changed .kanban/tasks/ files (01M503RY... and 01M4ZJW4...). Not staged: Package.resolved, .kanban/mcp.17281.log. I fixed one extra space of indent on 4 new lines in divergence.md. Not pushed. The sha is in the step record that the caller receives.
    - next: review
  timestamp: 2026-10-16T03:50:57.056584+00:00
- actor: claude-code
  id: 01m51dpj1q1n2t7s4xeqf75ch6
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (ca81d8e). 0 findings, 0 confirmed, 0 refuted. 2 files reviewed (Sources/FoundationModelsKanban/Identity/BoardKey.swift, Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift). Not reviewed: 4 .kanban/ files (ignore rule) and divergence.md (no validator matches it).
    - boxes: I compared each acceptance and test item with the work and ticked all 5. The first commit has the trailer `Kanban-Root-ID: <new ULID>`. The test `firstCommitsAtSameTimeGiveDifferentKeys` makes two empty repos in a temporary folder (GitSandbox) and reads the two keys at the same time with the same author and time. The test step record says `swift test` passed (1553 tests) and IntegrationTests passed (3 tests).
    - next: none. The task is in done.
  timestamp: 2026-10-16T03:57:09.559859+00:00
- actor: claude-code
  id: 01m51dq08jhm450crv9mn8cjr5
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — BoardKey.swift (Kanban-Root-ID trailer), BoardKeyTests.swift, divergence.md M8
    - test: green — swift test, 1553 passed; IntegrationTests 3 passed
    - commit: ca81d8e
    - review: clean — 0 findings
  timestamp: 2026-10-16T03:57:24.114963+00:00
position_column: done
position_ordinal: ff9080
title: Make the first commit that the engine makes unique for each repo, so two new repos never get the same board key
---
## What
divergence.md M7 and M8: the board key is `local/<root commit>`. When a repo has no commit, the engine makes an empty first commit.

The ^rs0bhrb integration test found a real problem. Two new repos that the engine sets up in the same second get empty first commits with the same author, message, and time. Thus the two commits have the same hash, and the two boards get the same key. A board then treats a task of the other board as its own, and a cross-board ref gives `NOT_FOUND`.

The test fixture now makes its own unique first commit (`IntegrationTests/.../Support/TemporaryGitRepo.swift`). The engine code still has the problem. This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

## Acceptance Criteria
- [x] The empty first commit that the engine makes has content that is different for each repo (for example, the message includes the repo folder name or a new ULID), so two repos never share a root commit hash.
- [x] Two new repos that the engine sets up in the same second get different board keys.

## Tests
- [x] A test makes two repos with no commit at the same time, lets the engine make the first commits, and checks that the two board keys are different.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.