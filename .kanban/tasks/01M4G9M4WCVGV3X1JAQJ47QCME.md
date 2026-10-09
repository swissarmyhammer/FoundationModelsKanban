---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4h532mcwf6hhsf72zkbvb6x
  text: |-
    Research:
    - `BoardKey.read(fromRepoAt:)` runs `git config --get remote.origin.url`, then `git rev-parse --git-common-dir`. Callers: `KanbanGraph.init(root:actor:...)`, `GitGraphFixture.makeGraph`, `BoardLocatorTests`, `PortabilityTests`. `BoardLocator` gives only top-level repo folders (folders with a `.git` entry) to the key reader, so the new rules do not change the keys that the locator reads.
    - `BoardLocator.key(ofRepoAt:)` must still get `gitCancelled` to stop a scan. Thus the new read must not catch a cancel or a time-out. It catches only `gitUnavailable` (git cannot start) and a failure status of `git rev-parse`.
    - Two existing tests state the old rules and must change: `subdirectoryGivesKeyOfRepo` (now `local/<subfolder-name>`) and `directoryOutsideRepoThrows` (now `local/<folder-name>`). `engineOutsideRepoThrows` changes to expect success.
    - Plan: one `git rev-parse --path-format=absolute --show-toplevel --git-common-dir` call gives the top-level folder and the common git folder. When the top-level folder is not `root` (canonical paths), the key is `local/<folder-name>`. An `origin` that `BoardKey(remoteURL:)` refuses gives `local/<main-clone-name>`.
  timestamp: 2026-10-09T20:18:51.660968+00:00
- actor: claude-code
  id: 01m4h5cmw7pw5y16vbqj41fttw
  text: |-
    Implementation landed.
    - RED: 6 new or changed BoardKeyTests cases and `KanbanGraphTests.boardInPlainFolder` failed with `gitFailed` (not a git repo) and `invalidRemoteURL` (local origin). The subfolder case gave the repo key.
    - GREEN: `BoardKey.read` now runs one `git rev-parse --path-format=absolute --show-toplevel --git-common-dir`. A failure status of git (not a repo, or git not installed: `/usr/bin/env` exits 127) or `gitUnavailable` gives `local/<folder-name>`. When the top-level path (canonical) is not `root`, the key is `local/<folder-name>`. An `origin` that `BoardKey(remoteURL:)` refuses gives `local/<main-clone-name>`. A time-out and a cancel still throw, so `BoardLocator` still stops on a cancel.
    - Choice for an open rule: each `origin` that gives no key (no host, and also a host with no path) gives `local/<main-clone-name>`. This is closest to plan.md "a repo without a remote uses local/<directory-name>".
    - Changed old tests that stated the old rules: `subdirectoryGivesKeyOfRepo` (now `local/Sources`), `directoryOutsideRepoThrows` (now `local/plain-directory`), `engineOutsideRepoThrows` (now `engineOutsideRepoGivesLocalKey`, success with `local/<folder-name>`). Removed the unused `isGitFailure` helper.
    - Docs: `KanbanGraph` type doc, `root` property doc, and both `init` docs say "The folder of the board". plan.md §2.1, §3.1 diagram, §3.2, §12 items 1 and 4 updated. §3.1 and §12 item 1 also said "one board per repo", so they changed too, to stay true.
    - BoardLocator.repos(in:) is not changed (^fv1dcq3).
  timestamp: 2026-10-09T20:24:05.255509+00:00
- actor: claude-code
  id: 01m4h5cqnbs02v08yqvyp5k0v9
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/Identity/BoardKey.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift, plan.md. `swift test`: 1100 tests in 80 suites passed, 0 failures. The only build warning is the accepted SwiftPM "missing creator for mutated node".
    - next: /review
  timestamp: 2026-10-09T20:24:08.107348+00:00
- actor: claude-code
  id: 01m4h5kwrsvw9snvzzex1xgank
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 5 files
    - test: green — swift test, 1100 tests in 80 suites passed; IntegrationTests build complete
    - commit: 64a693d
    - review: findings — Sources/FoundationModelsKanban/Identity/BoardKey.swift:187, Sources/FoundationModelsKanban/Identity/BoardKey.swift:203
  timestamp: 2026-10-09T20:28:02.713683+00:00
- actor: claude-code
  id: 01m4h5vnxhdkfcpk4hrwkzpfqr
  text: |-
    Review findings (iteration 2) done. Decisions from the orchestrator.
    - Finding BoardKey.swift:187 (repoPaths): `repoPaths` now gives `nil` only when git cannot start (`gitUnavailable`), when `/usr/bin/env` exits with `Git.programNotFoundStatus` (127, git is not installed), or when the standard error has `BoardKey.notInRepoMessage` ("not a git repository", case-insensitive match). Each other failure status throws `gitFailed(arguments: repoPathsArguments, status:, message: errorOutput)`. Helper: `isNoRepoFailure(_:)`. Doc comments of `read` and `repoPaths` state this rule.
    - Finding BoardKey.swift:203 (originKey): the fallback stays. Doc comment of `originKey` and of `read`, and plan.md §3.2 and §12 item 4, say that an `origin` with no host, or with a host but no path, gives `local/<main-clone-name>`, so that a board always opens.
    - Discovery: a corrupt `.git/HEAD` does NOT make a git failure in a repo. Git then does not see the folder as a repo, and prints "fatal: not a git repository", so it gives the local key. The new test uses a `.git/config` that git cannot read ("not a config line"): exit 128, standard error "fatal: bad config line 1 in file .git/config\n" (git 2.55.0).
    - Tests: `gitFailureInRepoThrows` (RED: returned "local/broken-repo"; GREEN after the change), `originWithoutPathGivesLocalKey` (origin `https://example.com/`; it passed at once, because it documents behavior that stays). The not-a-repo test `folderOutsideRepoGivesLocalKey` stays.
  timestamp: 2026-10-09T20:32:17.841003+00:00
- actor: claude-code
  id: 01m4h5vqabakws7aggx18tgcf2
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/Identity/BoardKey.swift, Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift, plan.md. `swift test`: 1102 tests in 80 suites passed, 0 failures. The only build warning is the accepted SwiftPM "missing creator for mutated node".
    - next: /review
  timestamp: 2026-10-09T20:32:19.275700+00:00
- actor: claude-code
  id: 01m4h60jjrjtz7rtqv7pc03hcc
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 3 files
    - test: green — swift test, 1102 tests in 80 suites passed
    - commit: d660cf2
    - review: clean — 0 findings
  timestamp: 2026-10-09T20:34:58.264963+00:00
- actor: claude-code
  id: 01m4h60n72yt5av015jkymt17x
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD — 0 findings (7 attempted, 1 refuted, 0 confirmed). Both prior items in "Review Findings (2026-10-09 15:26)" are checked. The HEAD commit message (d660cf2) agrees with the diff: repoPaths throws gitFailed for each non-repo failure status, the no-host and no-path origin fallback is documented in the doc comments and plan.md, and the tests gitFailureInRepoThrows and originWithoutPathGivesLocalKey are added. plan.md and .kanban/ were not reviewed (no validator, .reviewignore).
    - next: task moved to done. BoardLocator work continues in ^fv1dcq3.
  timestamp: 2026-10-09T20:35:00.962390+00:00
depends_on:
- 01M4G9GXTJSANGYS1315NRZSQH
- 01M4G9GQ28QA3Z7MYQG9JE3H3Z
position_column: done
position_ordinal: d980
title: 'BoardKey: a board works in any folder, git is not required'
---
## What
The owner decided that git is not required. `KanbanGraph(root:)` must open and make a board in any folder. Now `BoardKey.read(fromRepoAt:)` (`Sources/FoundationModelsKanban/Identity/BoardKey.swift:128-133`) runs `git config` and `git rev-parse`, and a folder that is not in a git repo throws `gitFailed`. A remote `origin` that is a local path (`/srv/git/repo.git`, `../upstream`, `file:///…`) throws `invalidRemoteURL` (`BoardKey.swift:49-57`, `:128-133`).

This task changes only the board key. The task ^fv1dcq3 ("BoardLocator finds boards in folders that are not git repos") changes the locator. This task runs after ^9je3h3z, because both tasks change `Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift`.

Rules for `BoardKey.read`:
- When `root` is the git top-level directory (or the root of a worktree), the key comes from git, as now.
- When `root` is not in a git repo, or git is not installed, the key is `local/<folder-name>`. `<folder-name>` is the last path component of `root`.
- When `root` is a subfolder of a git repo (not its top-level directory), the key is `local/<folder-name>`. Thus two boards in one repo never have the same key.
- When `origin` has no host (a local path or `file://`), the key is `local/<main-clone-name>` (the same as a repo with no remote).
- `.kanban/` stays at `<root>/.kanban/`. `root` is the folder that the caller gives. Do not search up for a git top-level directory.

Other changes:
- The doc comment of `KanbanGraph.init`: change "The root directory of the repo" to "The folder of the board".
- Update plan.md: §2.1 (`Board` = the board of one folder; a git repo is one case), §3.2, §12 item 4. Say that a folder that is not a git repo, or a subfolder of a git repo, gets `local/<folder-name>`.

## Acceptance Criteria
- [x] `KanbanGraph(root: <temp folder with no .git>)` + `addTask` makes `<root>/.kanban/` and returns a task id with the key `local/<folder-name>`.
- [x] `KanbanGraph(root: <subfolder of a git repo>)` gives the key `local/<subfolder-name>`, not the key of the repo.
- [x] A repo whose `origin` is a local path opens with the key `local/<main-clone-name>`.
- [x] Each existing git test still passes.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift`: no repo, a subfolder of a git repo, and a local-path `origin`.
- [x] `Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift`: open a board in a plain temp folder and run a mutation and a query.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-09 15:26)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/Identity/BoardKey.swift:187` `completeness/public-output-contract` — repoPaths returns nil for every non-zero git status. A real failure inside a repo, such as a corrupt repo or a git safe.directory refusal, is treated as 'not in a repo'. The board then gets the key local/<folder-name> with no error or warning. The doc comments say that a failure in a repo throws gitFailed, so the code contradicts its own contract and silently hides the problem. Return nil only when git reports that the directory is not in a repo (for example, by checking the message, or by a separate check). For any other non-zero status, throw .gitFailed(arguments: repoPathsArguments, status: result.status, message: result.errorOutput), as originURL already does. Add one test that makes rev-parse fail inside a repo and checks that the error is thrown.
- [x] `Sources/FoundationModelsKanban/Identity/BoardKey.swift:203` `completeness/public-output-contract` — The new originKey uses try? on BoardKey(remoteURL:). So an origin URL that is malformed (for example, a host with no path) now gives no error. It silently falls back to local/<main-clone-name>. The old read path threw invalidRemoteURL for such a remote. The new code does not warn or return the error, and no test checks this case. The change hides a bad origin, and the operator is not told. Decide the intended behaviour for a malformed origin. If the fallback to local/<main-clone-name> is correct, state that in the doc comment of originKey and add one test that gives a malformed origin and checks the local key. If the error should reach the caller, use try and let invalidRemoteURL propagate, as the old code did, and keep the fallback only for the no-host case that the doc names.
