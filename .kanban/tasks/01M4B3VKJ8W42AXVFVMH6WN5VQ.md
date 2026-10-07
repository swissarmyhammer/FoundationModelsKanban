---
comments:
- actor: wballard
  id: 01m4b8yw9zbqe7bkx8c9ddtt4h
  text: |-
    Research done.
    - NodeURI and StoredRef take the board key as a String (`boardKey:`, `inBoard:`). This task keeps that API. BoardKey is a new value type; a caller gives `key.description` to NodeURI.
    - No code in Sources or Tests runs a process or makes a temporary directory yet. BoardKey.swift adds a small internal `Git` runner (Foundation `Process`, `/usr/bin/env git`, no shell). The tests use the same runner to make temporary repos.
    - Plan: `git -C <dir> config --get remote.origin.url` (status 1 = no key). With no remote, `git rev-parse --path-format=absolute --git-common-dir` gives the main clone, so a worktree with no remote also gets the key of its main clone (`local/<main-directory-name>`).
    - A remote with no host (a local path or `file://`) is not a `host/owner/repo` form, so it throws `BoardKeyError.invalidRemoteURL`. The port and the user part of a URL are removed, so `ssh://git@host:22/o/r` and `git@host:o/r` give the same key.
    - plan.md §11 says other tests use a fake BoardKey; `BoardKey(remoteURL:)` makes one with no git.
  timestamp: 2026-10-07T13:31:01.823090+00:00
- actor: wballard
  id: 01m4b94ywnf93f8j9xcq183hqv
  text: |-
    Implementation landed (TDD: 13 tests written first; RED run had 29 issues from stub bodies; GREEN after the real code).
    - New: `Sources/FoundationModelsKanban/Identity/BoardKey.swift` — `BoardKey` (`init(remoteURL:)`, `init(localDirectoryName:)`, `static read(fromRepoAt:)`), `BoardKeyError` (`invalidRemoteURL`, `gitUnavailable`, `gitFailed`), and the internal `Git` runner (`Git.run(withArguments:inDirectory:)`, Foundation `Process` with `/usr/bin/env git`, argument list, no shell).
    - New: `Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift` — normalization cases (11 forms of one remote, host case, nested groups, 9 invalid remotes), and temporary git repos (`git init`, `git remote add`, `git remote set-url`, `git worktree add`) through a `GitSandbox` test helper that uses the production `Git` runner.
    - NodeURI and LocalRef are unchanged; they still take the key as a String. A caller gives `key.description`.
    - Decisions: the port and the user of a remote are removed; the path keeps its case; a remote with no host (local path, `file://`) throws `invalidRemoteURL`; a directory that is not in a git repo throws `gitFailed`. A worktree with no remote gets `local/<main-clone-name>` from `git rev-parse --git-common-dir`.
    - Evidence: `swift test --filter BoardKeyTests` 13 tests (29 test cases with arguments) pass; full `swift test` 135 tests in 9 suites pass; `swift build --build-tests` has no warnings; no line over 120 characters.
  timestamp: 2026-10-07T13:34:21.077551+00:00
- actor: wballard
  id: 01m4b9567as7n9jzr63ferk7tw
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsKanban/Identity/BoardKey.swift, Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift; `swift test --filter BoardKeyTests` 13 tests pass; `swift test` 135 tests in 9 suites pass, 0 warnings
    - next: /review
  timestamp: 2026-10-07T13:34:28.586398+00:00
- actor: wballard
  id: 01m4b9d41518hfx0eb7vdrertb
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (1e0bf67). 0 findings, 0 confirmed, 7 refuted. 2 files reviewed. 4 .kanban/ files are not reviewed because of .reviewignore.
    - next: none. The task is in done.
  timestamp: 2026-10-07T13:38:48.485167+00:00
- actor: wballard
  id: 01m4b9dbrtbwknhfj8qwryvwnb
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files (BoardKey.swift, BoardKeyTests.swift)
    - test: green — swift test, 135 passed, 0 warnings
    - commit: 1e0bf67
    - review: clean — 0 findings
  timestamp: 2026-10-07T13:38:56.410088+00:00
depends_on:
- 01M4B3V22A3PCQRESESTYBQ2FH
position_column: done
position_ordinal: '8780'
title: 'Identity: BoardKey from git origin'
---
## What
Calculate the board key of a repo. The basis is plan.md §3.2 and §12 item 4.
- `Sources/FoundationModelsKanban/Identity/BoardKey.swift`: read the current `origin` URL of a repo directory (run `git config --get remote.origin.url`, or read `.git/config`; a worktree has a `.git` file that points to the real git dir).
- Normalize SSH (`git@host:owner/repo.git`), HTTPS (`https://host/owner/repo.git`), and `ssh://` forms to `host/owner/repo`. Remove `.git`, and use lowercase for the host.
- No remote: `local/<directory-name>`.
- The key is never stored. Each call that opens a board reads it.

## Acceptance Criteria
- [x] SSH, HTTPS, and `ssh://` forms of one remote give the same key.
- [x] A repo with no remote gives `local/<directory-name>`.
- [x] A git worktree gives the same key as its main clone.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift`: pure normalization cases, plus temporary git repos (made with `git init`, `git remote add`, `git worktree add`).
- [x] Run `swift test --filter BoardKeyTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.