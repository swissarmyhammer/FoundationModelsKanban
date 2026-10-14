---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4xe86smp2reytsy8wx8eyxs
  text: |-
    Research done.
    - The key read is BoardKey.read(fromRepoAt:) in S/Identity/BoardKey.swift. Now it gives local/<main-clone-name> (RepoPaths.mainCloneName from --git-common-dir). After this change, mainCloneName, commonDirectory, and --git-common-dir are dead. Remove them. Replace init(mainCloneName:) with init(rootCommit:).
    - Callers of the key reader: KanbanGraph (root key and the BoardLocator scan), GitGraphFixture, BoardLocatorTests, PortabilityTests. Fake keys with init(mainCloneName:): KanbanGraphTests.boardKey, CommitRollbackTests.directoryKey, EventLogTests.
    - PortabilityTests.RepoMove.newDirectoryName expects a new key after a rename. With M7 the key does not change on a rename. Update that case.
    - Fixtures with `git init` and no commit: ReadmeExamplesTests.ExampleBoard and IntegrationTests TemporaryGitRepo. The engine now makes the first commit there, so git needs an identity. Give each fixture a local user.name and user.email, so that CI with no global identity still passes.
    - README "Get started" says local/<main-clone-name>. Update it.
    - Probe (git 2.56): `git commit-tree <empty tree> -m ...` with a temp GIT_CONFIG_GLOBAL that has user.useConfigOnly=true and GIT_CONFIG_NOSYSTEM=1 fails with status 128 and "Author identity unknown ... no email was given and auto-detection is disabled". Without useConfigOnly, git can guess an email from the host name and succeed, so the test sets useConfigOnly. `git update-ref HEAD <c> ""` refuses when the branch exists ("reference already exists"). Use this old value "" so that two reads at the same time cannot make two first commits.
    - Git.run needs an environment parameter (default: inherit) for the no-identity test, like the existing timeLimit parameter.
    - Scope note: the BoardLocator scan also calls the key reader for each sibling repo. A sibling repo with no commit thus also gets the first commit. This follows the card ("before Swift reads the key"). The KanbanHost task (^r0acd) can narrow this when it splits the session start from the scan.
  timestamp: 2026-10-14T14:49:50.132546+00:00
- actor: claude-code
  id: 01m4xejy68rzrqw04gtd2e17d4
  text: |-
    Implementation progress.
    - RED: the new BoardKeyTests did not compile (no init(rootCommit:), no firstCommitMessage, no read(fromRepoAt:gitEnvironment:), no Git.run environment). This is the expected failure for a missing feature.
    - BoardKey.swift: init(mainCloneName:) is replaced by init(rootCommit:) (first 12 hex digits). read(fromRepoAt:) now calls read(fromRepoAt:gitEnvironment: nil). The read checks the repo, makes the first commit when HEAD names no commit (hash-object of the empty tree, commit-tree, update-ref HEAD <c> "" so that two reads at the same time cannot make two commits), then reads origin, else local/<lowest root commit of HEAD>. RepoPaths no longer reads --git-common-dir (mainCloneName was dead). New private RepoGit carries the directory and the git environment. Git.run has a new `environment` parameter (default nil = inherit).
    - Decision: "no commit" means HEAD names no commit (rev-parse --verify --quiet HEAD exits 1). This also covers an unborn orphan branch, where the key cannot be read without a commit.
    - Correction to the first comment: the KanbanHost task is ^1qr0acd.
    - A subagent updates the other callers (CommitRollbackTests, KanbanGraphTests, EventLogTests, PortabilityTests), the docs in BoardLocator.swift and README.md, ReadmeExamplesTests, and IntegrationTests TemporaryGitRepo (local git identity for the first commit).
  timestamp: 2026-10-14T14:55:41.768643+00:00
- actor: claude-code
  id: 01m4xg0bsecbgj5hwgg5bfssq6
  text: |-
    ### implement — changed
    - evidence: `swift test` 1157 tests in 84 suites passed. One warning: the accepted SwiftPM "missing creator" warning. `swift test --filter BoardKeyTests`: all pass, also the new tests (empty first commit, staged files stay staged, no new commit in a repo with commits, two root commits use the lowest SHA in both merge orders, clone and worktree have the same key, the no-identity error tells the reason from git, engine in a repo with no commit).
    - files: Sources/FoundationModelsKanban/Identity/BoardKey.swift, Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift (docs), README.md, Tests/.../Identity/BoardKeyTests.swift, Tests/.../ReadmeExamplesTests.swift, Tests/.../Design/PortabilityTests.swift, Tests/.../Events/EventLogTests.swift, Tests/.../Tool/CommitRollbackTests.swift, Tests/.../Tool/KanbanGraphTests.swift, IntegrationTests/.../Support/TemporaryGitRepo.swift.
    - note: the integration package builds with 0 errors only with a separate --scratch-path. The usual `IntegrationTests/.build/checkouts` gives "Operation not permitted" when SwiftPM removes old checkouts. This is a file permission problem on this machine, not a code problem. The integration tests were not run.
    - next: /review
  timestamp: 2026-10-14T15:20:30.254245+00:00
- actor: claude-code
  id: 01m4xh2yf6nrw98s9y27gb34xh
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 10 files
    - test: green — swift test, 1157 passed, 0 failed, 0 skipped (IntegrationTests not run: SwiftPM checkout permission error 513)
    - commit: 8c31c28
    - review: findings — Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift:164, Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift:167, Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift:206, Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift:811, Tests/FoundationModelsKanbanTests/ReadmeExamplesTests.swift:119
  timestamp: 2026-10-14T15:39:23.494990+00:00
- actor: claude-code
  id: 01m4xhepryw38pyf13pckyh1y6
  text: |-
    Review findings fixed (all 5 checked).
    - reuse (BoardKeyTests 164/167/206): new static GitSandbox.headSHA(of:) runs `rev-parse HEAD`. headKey(of:) calls it. All rev-parse HEAD reads in the file use it (also the second read in repoWithCommitsGetsNoNewCommit).
    - fluent-usage (811): environmentWithoutIdentity() is now makeEnvironmentWithoutIdentity(). The call site and the four doc references changed.
    - reuse (ReadmeExamplesTests 119): new static GitSandbox.initializeRepo(at:withIdentity:) runs `git init` and the identityConfig `git config` steps. makeEmptyRepo and ExampleBoard.init call it. ExampleBoard.init also uses GitSandbox.makeFolder.
    - Same cause in the whole file: makeRepo also ran its own `git init` with `-c` identity arguments. makeRepo now calls makeEmptyRepo, then commits with the local identity config. identityArguments and unsignedArguments are dead and are removed. The commit message is the constant startCommitMessage. makeRepo keeps the current commit time (not fixedCommitDate), so two repos made in one test do not get the same root commit.
    - GitSandbox.runGit and GitSandbox.output are now static (they use no instance state), so the static helpers can call them. Call sites in BoardKeyTests and PortabilityTests use GitSandbox.runGit / GitSandbox.output.
    - Note: the IntegrationTests TemporaryGitRepo has a third copy of the init and identity steps. It is in a different SwiftPM package and cannot import GitSandbox from the unit test target, so it stays.
  timestamp: 2026-10-14T15:45:48.830718+00:00
- actor: claude-code
  id: 01m4xhes0ebqg5y0qsh23nhf3y
  text: |-
    ### implement — changed
    - evidence: `swift test --filter 'BoardKeyTests|ReadmeExamplesTests|PortabilityTests'` 51 tests passed; `swift test` 1157 tests in 84 suites passed, 0 failed. Only warning: the accepted SwiftPM "missing creator" warning. Files: Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift, Tests/FoundationModelsKanbanTests/ReadmeExamplesTests.swift, Tests/FoundationModelsKanbanTests/Design/PortabilityTests.swift.
    - next: /review
  timestamp: 2026-10-14T15:45:51.118817+00:00
depends_on:
- 01M4X6XKP0Y832GDRHQ1MG22VF
position_column: doing
position_ordinal: '80'
title: Key a repo with no remote by its root commit, and make a first commit when the repo has none
---
## What
divergence.md §16, M7 and M8 (DECIDED). The user: "we will need to be able to provide an identifier for a kanban in a repo with no remote" and "just make a first commit." This is work on the Swift package (S/ = Sources/FoundationModelsKanban/). The key code is in S/Identity/BoardKey.swift.

M7, the key of a git repo with no usable `origin` remote:
- The key is `local/<root commit>`, with the first 12 hex digits of the root commit of `HEAD` (`git rev-list --max-parents=0 HEAD`).
- When the history has more than one root commit, use the lowest SHA, so that the key is the same each time.
- The key is unique. It does not change when the folder moves or gets a new name. All clones and worktrees of the repo have the same key, as for a repo with a remote.
- Known results (no work): when the repo later gets an `origin` remote, the key changes to the remote key. An orphan branch with a different history gives a different key.
- There is no key that the user sets (no `kanban.key` in git config, and no key file).

M8, a repo with no commit:
- Before Swift reads the key, it makes one empty first commit when the repo has no commit. Then the key is `local/<root commit>` from the start.
- Do NOT use `git commit`. The commit must not take the files that the user staged. Make the commit from the empty tree: `git commit-tree <empty tree> -m "Initial commit"` (the empty tree is `git hash-object -t tree /dev/null`, or `4b825dc642cb6eb9a060e54bf8d69288fbee4904`). Then set the current branch to it with `git update-ref HEAD <commit>`. The index and the working files do not change.
- When git cannot make the commit (for example, no `user.name` or `user.email` is set), the call gives an error that tells why (include the git message).
- A repo that has commits gets no new commit.

## Acceptance Criteria
- [ ] A repo with no `origin` remote has the key `local/<first 12 hex of the root commit>`.
- [ ] A repo with two root commits uses the lowest SHA.
- [ ] Two clones (or a clone and a worktree) of a repo with no remote have the same key.
- [ ] A new repo with no commit gets one empty commit on its current branch, and the key comes from that commit.
- [ ] Staged files stay staged and are not in the new commit. The working files do not change.
- [ ] When git cannot commit, the error tells the reason.

## Tests
- [ ] A new repo with no commit gets one empty commit and a `local/<root commit>` key.
- [ ] Staged files stay staged and are not in the commit.
- [ ] A repo with commits gets no new commit.
- [ ] A repo with two root commits (merge of an orphan branch) uses the lowest SHA.
- [ ] A repo with no `user.name`/`user.email` (set `GIT_CONFIG_GLOBAL` and `HOME` to a temp folder) gives a clear error.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-14 10:32)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 9 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift:164` `reuse/reuse` — The test reads the HEAD SHA with a direct `rev-parse HEAD` call. GitSandbox.headKey(of:) already runs that same command inside the sandbox, but it returns a BoardKey, not the SHA, so the test cannot use it and repeats the command. Add a GitSandbox helper such as headSHA(of:) that runs `rev-parse HEAD` and returns the SHA. Have headKey(of:) call it, and use it here and in the other rev-parse calls.
- [x] `Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift:167` `reuse/reuse` — The second root SHA is read with a direct `rev-parse HEAD` call, which repeats the same command as line 164 and GitSandbox.headKey(of:). Use the shared HEAD SHA helper suggested for line 164.
- [x] `Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift:206` `reuse/reuse` — The test reads HEAD with a direct `rev-parse HEAD` call, which repeats the command already used inside GitSandbox.headKey(of:). Use the shared HEAD SHA helper suggested for line 164.
- [x] `Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift:811` `swift/fluent-usage` — `environmentWithoutIdentity()` is a factory. It creates a new folder and config file, then returns a new environment dictionary. The rule says factory methods begin with `make`, so this name reads like a property getter and does not signal that the call writes files. Rename the method to `makeEnvironmentWithoutIdentity()`, and update the call sites at lines 216 and 218 to match.
- [x] `Tests/FoundationModelsKanbanTests/ReadmeExamplesTests.swift:119` `reuse/reuse` — ExampleBoard.init repeats the repo setup that GitSandbox.makeEmptyRepo(named:withIdentity:) already does: it runs `git init --quiet`, then writes each GitSandbox.identityConfig pair with `git config`, and checks each status with the same require pattern. Two copies of this setup must now be kept in step, and a change to one will not reach the other. Move the init and identity-config steps into one shared static helper that takes a folder URL, such as a static form of GitSandbox.makeEmptyRepo. Call it from both GitSandbox.makeEmptyRepo and ExampleBoard.init so the setup exists once.
