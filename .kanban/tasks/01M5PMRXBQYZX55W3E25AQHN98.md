---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5pr8s7p087vrkq2xt6rxfy0
  text: |-
    Research: the cause.

    - The check is the assertionFailure in KanbanGraph.publish(_:skipping:). It compares two dictionaries that are keyed by the canonical path of the root of each engine: `engines` (loadedEngines) and `sessions` (loadedSessions). Each one calls `current.root.canonicalPath` again.
    - `URL.canonicalPath` is `standardizedFileURL.resolvingSymlinksInPath().path`. Foundation removes `/private` only when the path without `/private` exists. Thus the result changes when the folder is removed. Probe (scratch swift script): for `/private/var/.../my-project`, the result is `/var/.../my-project` while the folder exists, and `/private/var/.../my-project` after `removeItem`. A `/var/...` or `/tmp/...` URL gives the same result before and after.
    - The root of an engine comes from `git rev-parse --show-toplevel` (BoardKey.worktreeTop), which gives the real path `/private/tmp/fmk-tests/...` for the test folders (TestFolderRoot puts them in `/tmp`).
    - At the end of a test, `TemporaryDirectory.deinit` removes the folder (name `EventLogTests-<UUID>`). The file watcher of a board that is not closed then sends batches, and each batch runs `publish`. When the removal of the folder happens between the two `canonicalPath` reads, `engines` has the key `/tmp/...` and `sessions` has the key `/private/tmp/...` (or the opposite), and the assertion stops the process (signal 5).
    - The same unstable key can also break other compares of paths (admit in KanbanGraph, `changed` keys against `sessions` keys), but they only drop changes or log.
    - ScanChange already knows of this hazard (its `components(of:)` reads no file for that reason).

    Plan: make `URL.canonicalPath` stable when a folder goes away: the real path (`realpath(3)`) of the nearest folder that exists, then the rest of the path, then `/private` removed when the top folder under `/private` is a link from `/`. The result for a path that exists stays the same as before. TDD: a test that removes a folder whose URL has the `/private` form, and expects the same canonical path before and after.
  timestamp: 2026-10-24T10:45:55.574398+00:00
- actor: claude-code
  id: 01m5prh32xrxnz4tkq06n4rt88
  text: |-
    Implementation landed.

    - Reproduction: I did not run the full suite in a loop. The crash needs the removal of a folder in a window of a few microseconds (between the two `canonicalPath` reads in `publish`), so a loop gives no reliable result. In its place, a unit test proves the cause with no timing: `CanonicalPathTests.realPathKeepsCanonicalPathAfterRemoval` makes `<TemporaryDirectory>/my-project`, takes its real path `/private/tmp/fmk-tests/.../EventLogTests-<UUID>/my-project` (the form git gives), removes the folder, and expects the canonical path `/tmp/...` before and after.
    - RED (one run, `swift test --filter CanonicalPathTests`): after the removal, `canonicalPath` was `/private/tmp/fmk-tests/.../EventLogTests-.../my-project` and not `/tmp/fmk-tests/.../EventLogTests-.../my-project`. This is the path of the crash message on the card.
    - GREEN: `URL.canonicalPath` (Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift) is now the real path (`realpath(3)`) of the nearest item that exists, then the parts of the path that do not exist, and `/private` is removed when a link at the root points to the top folder. The check reads only the link (`/tmp`), so the result does not change when the folder goes away. For a folder that exists, the result is the same as before. The new `URL.realPath` holds the one `realpath(3)` call; `WatchedPlace.realPath(of:)` in ScanChange.swift now uses it, so the code is not repeated.
    - The assertion in `KanbanGraph.publish(_:skipping:)` stays. It is correct.
    - divergence.md: new entry R19 in section 11.
    - Full suite (one run, `swift test`): 1872 tests in 162 suites passed. Only the accepted SwiftPM "missing creator" warning.
    - Not done: no change to `publish` itself. With a stable `canonicalPath`, its two reads give the same key. Only a change of a symbolic link inside the path during a round could still make them differ.
  timestamp: 2026-10-24T10:50:27.805123+00:00
- actor: claude-code
  id: 01m5prh3gvkc4804panwmgkakz
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift, Sources/FoundationModelsKanban/CrossRepo/ScanChange.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CanonicalPathTests.swift (new), divergence.md. RED then GREEN with `swift test --filter CanonicalPathTests`; full `swift test`: 1872 tests in 162 suites passed, only the accepted "missing creator" warning.
    - next: /review
  timestamp: 2026-10-24T10:50:28.251983+00:00
position_column: doing
position_ordinal: '80'
title: Find the cause of the intermittent fatal error in KanbanGraph during swift test
---
One full `swift test` run stopped with signal 5. The message was "KanbanGraph.swift: Fatal error: The view holds the engine of the board at .../EventLogTests-.../my-project, and has no session of it". The next full run passed (1868 tests). The crash happened near an undoChange test. Find the race and correct it.