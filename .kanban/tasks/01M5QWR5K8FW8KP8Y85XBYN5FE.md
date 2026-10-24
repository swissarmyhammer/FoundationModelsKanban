---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5qx2xz3sb2yse4j0n4g5cfz
  text: |-
    Research and work done.

    - Script check: from `FileManager.default.temporaryDirectory/a`, the raw walk goes `/var` -> `/` -> `/..` -> `/../..` and does not stop. The standardized form of each `/..` parent is `/`. The fault is not only for URLs from `temporaryDirectory`: each walk that gets to `file:///` through `deletingLastPathComponent()` gets `file:///../` next. Existing tests did not find it, because each one has a `.kanban/` above the folder or gives a `top`.
    - No folder above the temporary directory of the user on this machine has a `.kanban/` (checked `/var/folders/.../T` up to `/`, and also `/private`, `/private/var`).
    - RED: the new test `BareBoardTests.folderWithNoBoardUpToRootIsItsOwnBoardRoot` did not stop. `perl -e 'alarm 60'` killed `swift test --skip-build --filter BareBoardTests` after 60 s (exit 142). The orphan `swiftpm-testing-helper` process continued to use the CPU, and I killed it by hand. Thus a direct call hangs the run before the fix; after the fix, the direct call is safe, so the test uses a direct call and no bounded check.
    - GREEN: the fix adds `.standardizedFileURL` to the parent in `BareBoard.nearestBoardFolder(from:below:)`. The test passes in 0.006 s.
    - Search of Sources for other walks up: `URL.realPathOfNearestItem` (BoardLocator.swift) already standardizes the parent. `WorktreePaths.topLevel(seenFrom:)` (BoardKey.swift) uses `sequence(first:)` with the guard `pathComponents.count > 1`; a script showed that it stops at `file:///` (count 1), so it has no fault. All other uses of `deletingLastPathComponent()` (ScanChange, BoardLocator.places, CollectBoardsField, EventLog, Commit, KanbanHost) take one parent only and do not loop. No other change.
    - divergence.md: no change. The documented behavior (search up to the root) does not change; the fix makes the code do it.
  timestamp: 2026-10-24T21:29:21.123929+00:00
- actor: claude-code
  id: 01m5qx3h70n26fk5ctav89rv8f
  text: |-
    Correction to the comment above: the walk in BoardKey.swift is `RepoPaths.topLevel(seenFrom:)`, not `WorktreePaths.topLevel(seenFrom:)`. The finding does not change: it stops at `file:///`.

    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsKanban/CrossRepo/BareBoard.swift (parent standardized), Tests/FoundationModelsKanbanTests/CrossRepo/BareBoardTests.swift (new regression test). RED: filtered test did not stop, killed after 60 s. GREEN: filtered test passed. Full `swift test`: 1873 tests in 163 suites passed, 0 failures; only warning is SwiftPM "missing creator" for mlx-swift_Cmlx.bundle.
    - next: /review
  timestamp: 2026-10-24T21:29:40.832951+00:00
- actor: claude-code
  id: 01m5qx7nkjejassgrwfk7dyr33
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (aa702af). 0 findings, 0 confirmed, 0 refuted. 7 validator runs attempted, 0 failed. 2 files reviewed. 4 .kanban files not reviewed because of .reviewignore.
    - next: none. The task is in done.
  timestamp: 2026-10-24T21:31:56.402011+00:00
- actor: claude-code
  id: 01m5qx885btptgadahkgnjrkc0
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — BareBoard.swift, BareBoardTests.swift
    - test: green — swift test, 1873 passed in 163 suites, 0 failed, 0 skipped
    - commit: aa702af
    - review: clean — 0 findings
  timestamp: 2026-10-24T21:32:15.403028+00:00
position_column: done
position_ordinal: ffc280
title: BareBoard.nearestBoardFolder loops forever at the file system root
---
## Problem

`BareBoard.nearestBoardFolder(from:below:)` in `Sources/FoundationModelsKanban/CrossRepo/BareBoard.swift:27` does not stop when the folder is not in a git repo and no folder up to `/` has a `.kanban/`. KanbanViewKit found this bug.

## Cause

The walk uses `candidate.deletingLastPathComponent()` and compares `parent.path` with `candidate.path`. For some URLs, for example a URL from `FileManager.default.temporaryDirectory`, the parent of `file:///` is `file:///../`. Its path is `/..`, which is not equal to `/`. The walk then goes to `/../..`, and it does not stop.

Repro (verified): start from `FileManager.default.temporaryDirectory.appendingPathComponent("a")`. The walk goes `/var` → `/` → `/..` → `/../..` and continues.

## Fix

- [x] Standardize the parent: `candidate.deletingLastPathComponent().standardizedFileURL`. This is the same as `realPathOfNearestItem` in `CrossRepo/BoardLocator.swift:591`. The parent of `/` is then `/`, and the guard returns `nil`.
- [x] Add a regression test: make a temporary folder outside git with no `.kanban/` up to `/`, start from a URL that `FileManager.default.temporaryDirectory` gives, and make sure that `nearestBoardFolder(from:below: nil)` returns `nil` and `BareBoard.root(of:)` returns the folder.
- [x] Look for other walks up the folders that use `deletingLastPathComponent()` with no standardization, and correct them the same way.

## Acceptance

- The walk stops at `/` and returns `nil`.
- The regression test passes, and the full test suite is green with no new warnings.
#bug #kanbanviewkit