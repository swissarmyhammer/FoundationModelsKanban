---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gwnrtqdfft154qynbaebhy
  text: |-
    Research:
    - `WorkingCopy.renameTag` (GraphQL/TagMutations.swift) writes the new tag only when `graph.hasNode(target)` is false. A tombstone target gets only the `renamedTo` patch on the source.
    - `WorkingCopy.ensureLiveTag` already does the correct thing for both cases: an unknown tag gets one add patch, and a known tag follows the rename redirect and gets `delete: false` at the end of the chain (`apply` writes no patch for a live tag). Plan: `renameTag` calls `ensureLiveTag(target, setting:body:at:)` in place of its own `hasNode` branch. This removes the copy of the add branch.
    - Choice (task leaves it open): when the target slug is itself redirected, the undelete goes to the end of the target chain, the same as `ensureLiveTag` and `addTag` (plan.md §6.2: all refs to a redirected slug follow the redirect).
    - Undo: the inverse of `delete: false` is `delete: true`, and the inverse of the `renamedTo` set is an unset. No undo code change is expected.
    - Test helpers: session tests in `Undo/UndoTests.swift` (`projection(of:)`, `reverse(in:)`), `ChangeBuilderTests.baseSession` (adds tag `bug`), `TagMutationTests` field builders. The new test file goes in `Tests/FoundationModelsKanbanTests/Tags/`.
  timestamp: 2026-10-09T17:51:47.031881+00:00
- actor: claude-code
  id: 01m4gwvj2pcr1b802hvz4gt1dm
  text: |-
    Implementation:
    - RED: 3 new tests in `Tests/FoundationModelsKanbanTests/Tags/TagRenameToTombstoneTests.swift` failed for the expected reason (the rename returned `deleted` set, the task had no tags, the target log had no `delete: false`).
    - GREEN: `WorkingCopy.renameTag` now calls `ensureLiveTag(target, setting:body:at:)` in place of its own `hasNode` branch. An unknown target gets the add patch as before; a known target follows its rename chain, and a tombstone at the end gets `delete: false`. No undo code change was necessary: the undo writes `delete: true` on the target and unsets `renamedTo`, and the full projection equals the projection before the rename.
    - `TagMutationTests.autoColorSetting(of:)` is now internal, so the new suite reuses it.
    - plan.md §6.2 "Rename to a slug that exists" now states the `delete: false` patch and the undo.
    - Choice: when the target slug is itself redirected, the `delete: false` goes to the end of the target chain, the same as `addTag` (plan.md §6.2: all refs to a redirected slug follow the redirect).
  timestamp: 2026-10-09T17:54:56.726990+00:00
- actor: claude-code
  id: 01m4gwvkwvyh0p34pncgzgwwqp
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/GraphQL/TagMutations.swift, Tests/FoundationModelsKanbanTests/Tags/TagRenameToTombstoneTests.swift (new), Tests/FoundationModelsKanbanTests/Mutations/TagMutationTests.swift, plan.md. `swift test --filter TagRenameToTombstoneTests`: 3 passed. `swift test`: 1092 tests in 79 suites passed; only build warning is the accepted SwiftPM "missing creator for mutated node".
    - next: /review
  timestamp: 2026-10-09T17:54:58.587971+00:00
- actor: claude-code
  id: 01m4gx47zmd7s84ytv520tsvqt
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 4 files
    - test: green — swift test, 1092 tests in 79 suites passed
    - commit: 1926bb5
    - review: findings — Sources/FoundationModelsKanban/GraphQL/TagMutations.swift:247
  timestamp: 2026-10-09T17:59:41.300786+00:00
- actor: claude-code
  id: 01m4gxdsrypk5zvhz4ppk6p2ng
  text: |-
    Finding `completeness/invariant-propagation` (TagMutations.swift renameTag):
    - New test `mergeIntoLiveTargetWritesNoTargetPatch` in `Tags/TagRenameToTombstoneTests.swift` asserts the exact target patch list after a rename to a live tag: only the `addTag` patch of the setup (`deletesAfterMerge = []`). The setup helper is now `sessionWithTarget(isDeleted:inRepoAt:)`, shared by the 4 tests.
    - What is written today: the test passed before the code change. `WorkingCopy.apply` (Tool/Commit.swift) drops a patch that changes nothing, so the `delete: false` on a live target never reached the log. The contract depended on that drop.
    - Code: new `WorkingCopy.undeleteTag(redirectedFrom:at:)` follows the redirect and writes `delete: false` only when the chain end is a tombstone (explicit `isDeleted` check). `ensureLiveTag` uses it. `renameTag` now has an explicit branch: a known target calls `undeleteTag(redirectedFrom:at:)`, an unknown target calls `addNode` with the name, the color and the body of the source. The doc comments of `renameTag` and of the helper say that a merge into a live tag writes no patch on the target, and that the check does not depend on the commit path.
    - plan.md §6.2 "Rename to a slug that exists" now also says: a merge into a live tag writes no patch on the target.
  timestamp: 2026-10-09T18:04:54.430903+00:00
- actor: claude-code
  id: 01m4gxdvk3tgw2trsdcca7jhnh
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/GraphQL/TagMutations.swift, Tests/FoundationModelsKanbanTests/Tags/TagRenameToTombstoneTests.swift, plan.md. `swift test --filter 'TagRenameToTombstoneTests|TagMutationTests'`: 32 tests in 2 suites passed. `swift test`: 1093 tests in 79 suites passed; only build warning is the accepted SwiftPM "missing creator for mutated node".
    - next: /review
  timestamp: 2026-10-09T18:04:56.291801+00:00
- actor: claude-code
  id: 01m4gxma81czfmjqrq14w6wsn5
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD, 2 findings (2 confirmed, 0 refuted) — Tests/FoundationModelsKanbanTests/Tags/TagRenameToTombstoneTests.swift:43, Tests/FoundationModelsKanbanTests/Tags/TagRenameToTombstoneTests.swift:99. The HEAD commit message (64ba233) is true for the diff: undeleteTag(redirectedFrom:at:) is added, renameTag has a known/unknown target branch, the live-target test is added, and the doc comments, plan.md §6.2 and the kanban files are updated.
    - next: /implement — correct the 2 reuse/reuse findings
  timestamp: 2026-10-09T18:08:27.905868+00:00
- actor: claude-code
  id: 01m4gxmbmr2x6jybdcb2razbfs
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 3 files
    - test: green — swift test, 1093 tests in 79 suites passed
    - commit: 64ba233
    - review: findings — Tests/FoundationModelsKanbanTests/Tags/TagRenameToTombstoneTests.swift:43, Tests/FoundationModelsKanbanTests/Tags/TagRenameToTombstoneTests.swift:99
  timestamp: 2026-10-09T18:08:29.336908+00:00
- actor: claude-code
  id: 01m4gxt7xkka3njd2994fh5sn6
  text: |-
    Findings `reuse/reuse` (Tags/TagRenameToTombstoneTests.swift):
    - `sessionWithTarget(isDeleted:inRepoAt:)` now calls `HistoryTests.taggedSession(inRepoAt:running:)` with a fields closure: the `addTag` of `defect`, and the `deleteTag` of `defect` when `isDeleted` is true. The copy of the base setup and the run loop is gone. `taggedSession` was already internal, so no visibility change was necessary.
    - New helper `renamedSession(isDeleted:inRepoAt:)`: the setup, then `renameBugToDefect(in:)`. It returns the session, the fixture task and the `renameTag` value. `renamedTaskShowsTarget` uses it, so its copy of setup-then-rename is gone too.
    - New helper `expectRename(isDeleted:writing:)`: makes the repo, runs `renamedSession`, expects the exact `renameTag` value and the exact target patch list. `renameRevivesTarget` passes `deletesAfterRename`; `mergeIntoLiveTargetWritesNoTargetPatch` passes `deletesAfterMerge`. This follows the `static func expect...` helper pattern of the other suites (for example `UndoTests.expectProjection`).
    - `undoRestoresDeletedTarget` keeps its own steps: it must read the projection between the setup and the rename.
  timestamp: 2026-10-09T18:11:42.131821+00:00
- actor: claude-code
  id: 01m4gxt99vs55kdfgpthsp4jme
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/Tags/TagRenameToTombstoneTests.swift. `swift test --filter TagRenameToTombstoneTests`: 4 tests in 1 suite passed. `swift test`: 1093 tests in 79 suites passed; the only build warning is the accepted SwiftPM "missing creator for mutated node".
    - next: /review
  timestamp: 2026-10-09T18:11:43.547837+00:00
depends_on:
- 01M4G9J9NMNJR8NZPSYPC53Z77
position_column: doing
position_ordinal: '80'
title: Rename to a deleted tag makes the target tag live again
---
## What
`Sources/FoundationModelsKanban/GraphQL/TagMutations.swift:234-241`: `graph.hasNode(target)` is true for a tombstone. Thus a rename to a deleted slug writes only `renamedTo`, and the target stays deleted. Each task with the old tag loses it, and the mutation returns a tombstone. plan.md §6.2: "Rename to a slug that exists is a merge."

- When the target exists and is a tombstone, also write `delete: false` on the target, the same as `ensureLiveTag` and `tagRefs` do.
- Undo of the rename must reverse both patches.

## Acceptance Criteria
- [x] `deleteTag(defect)`, then `renameTag(from:"bug", to:"defect")`: the target is live, and each task that had `bug` has `defect`.
- [x] `undo` of that rename gives the state from before the rename (the target deleted, tasks with `bug`).

## Tests
- [x] Tests in `Tests/FoundationModelsKanbanTests/Tags/` (tag rename tests).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-09 12:57)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/GraphQL/TagMutations.swift:247` `completeness/invariant-propagation` — A rename to the slug of a live tag (a merge) now goes through ensureLiveTag, which always applies a `delete: false` patch to an existing target, not only to a tombstone. The doc comment at lines 227-229 says a merge writes no patch 1 and that only a tombstoned chain end gets `delete: false`. The code writes an extra `delete: false` patch to a live target, so the log gains an event the documented contract does not describe. Either guard the rename call so `delete: false` is written only when the chain end of the target is a tombstone, or update the doc comment at lines 227-229 to say a merge also writes `delete: false` on a live target. Add a rename-to-live-tag test that asserts the exact target patch list, so the chosen behaviour is locked.

## Review Findings (2026-10-09 13:06)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 3 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/Tags/TagRenameToTombstoneTests.swift:43` `reuse/reuse` — sessionWithTarget rebuilds the base-setup-then-run-fields pattern that already exists in HistoryTests.session and HistoryTests.taggedSession. Its only extra work is the tag field plus the addTag and optional deleteTag fields, which taggedSession can take through its fields closure. A parallel helper gives the suite a second copy of the setup logic to keep in step. Replace the body of sessionWithTarget with a call to HistoryTests.taggedSession(inRepoAt: directory) { refs in [TagMutationTests.addTag(named: TagMutationTests.defect)] + (isDeleted ? [CommentTests.nodeField(MutationName.deleteTag, naming: TagMutationTests.defect)] : []) }. Then drop the duplicated base-setup and run loop. If the task field must stay separate, keep only the fields closure in this file and reuse session(inRepoAt:running:).
- [x] `Tests/FoundationModelsKanbanTests/Tags/TagRenameToTombstoneTests.swift:99` `reuse/reuse` — The new test mergeIntoLiveTargetWritesNoTargetPatch repeats the body of renameRevivesTarget. The only differences are the isDeleted flag, the expected delete values, and the test name. The author copied the test instead of extending the existing one, so the two copies can drift apart. Move the shared steps into one helper, such as a static func that takes isDeleted and the expected deletes and returns the renamed map and the target patches. Then have both tests call it with their own values. Keep the test names and the per-case constants (deletesAfterRename, deletesAfterMerge) in their own tests.
