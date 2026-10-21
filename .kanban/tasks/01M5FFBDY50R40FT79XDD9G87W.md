---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5g7y8qcqpscjxaj83wsx1tr
  text: |-
    ### research + implement
    - Where the mismatches are written down: the ^esc56vk card lists only `LinkStatus.OK` in the 09:53 section, and that one was already fixed. The other five are named but not written out ("not listed here"). Each one was traced here from the code.
    - linkTarget: `StoredLink.target` comes from `Graph.storedLinks(inBoard:)`. A dependsOn edge that is a slot or an unresolved local ref goes through `Graph.uri(of:inBoard:)` / `StoredRef.uri(inBoard:)`, and so it gets the current key of the board. "As the board stores it" was wrong. Remote edges stay unresolved (`Graph.resolve`) and keep their own key. Body links and moved lines are parsed full URIs.
    - linkStatus: `LinkedBoard.check(of:)`. A loaded board gives MISSING_NODE first, then OK or OLD_NAME by `BoardSnapshot.oldName(named:)`. An unreadable board gives OK or OLD_NAME by the name only, and the node is not checked. notFound gives DANGLING. "OK: the board and the node are found" was wrong for an unreadable board. Same cause in the `LinkStatus.ok/.oldName` doc comments (LinkCheck.swift). The oldName doc no longer makes the OldBoardName warning claim, because it does not hold on the collectBoards own-name path.
    - collectResultRepairs: `checkedLinks` of the merged snapshot, naming the source names, then `LinkRepair.init(of:checked:)` (OLD_NAME gets the current key, DANGLING gets no new URI, OK and MISSING_NODE are dropped), plus `reached` (= otherRepairs only with reach). The old text said "each with its new target", which is wrong for DANGLING, and it did not say the check runs after the merge.
    - collectResultOtherLinks: `sourceLinks` checks each link of each `otherTargets` board whose key is a source name against `.loaded(merged snapshot)`, and keeps only the LinkRepair results. Those are OLD_NAME only: the target has the node, and the name is an old name after `addCollected` (keepBoardNames drops the source board IDs, so the source names are old names). The old text left out the node rule. Same cause in `collectReach` (schema) and in the CollectReport / CollectBoardsArguments.reach / collectBoards doc comments (CollectBoardsField.swift).
    - VirtualTag: `hasVirtualTag`. READY = live && !done && isReady. BLOCKED = live && !isReady, so a done task can be BLOCKED. isReady = `BlockerWalk.blockers` empty: a dependency blocks when it is not done, or when it leads back to the task. `liveDependencies` drops tombstoned dependencies, and an unloaded cross-board dependency is not done. DELETED: "only a filter that names this tag shows it" was wrong, because a ^id or ~task atom also shows it (taskFilter). Same cause in DONE (the tag needs a live task) and in the READY/BLOCKED case doc comments and the hasVirtualTag doc comment. VirtualTagsTests requires one sentence per explanation.
    - Discovered: Documentation/kanban/SKILL.md has the old READY/BLOCKED/DELETED/DONE wording. New task ^3wvnyrd.
    - Golden: `swift test --filter EndpointConventionTests` was RED on the golden test, then re-recorded with GRAPHQL_GOLDEN_RECORD=1. The SDL diff is description lines only: linkTarget and linkStatus (in LinkCheck and LinkRepair), repairs, otherLinks, and collectBoards reach. The virtual tag explanations are runtime data, not SDL.
  timestamp: 2026-10-21T22:05:07.180340+00:00
- actor: claude-code
  id: 01m5g7ybg8axwm3v69n2s2am0a
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/GraphQL/SchemaDescription.swift, Sources/FoundationModelsKanban/GraphQL/CollectBoardsField.swift, Sources/FoundationModelsKanban/CrossRepo/LinkCheck.swift, Sources/FoundationModelsKanban/Derived/VirtualTags.swift, Tests/Fixtures/kanban.graphql. Golden test RED, then recorded, then GREEN (4 passed). `swift test`: 1750 tests in 146 suites passed, exit 0. The only build warning is the third-party "missing creator for mutated node … mlx-swift_Cmlx.bundle". There are no package-code warnings. All 3 checkboxes are ticked. Not committed; the task stays in doing.
    - next: /review
  timestamp: 2026-10-21T22:05:10.024768+00:00
depends_on:
- 01M5F23SEC4X5S9D80NESC56VK
position_column: doing
position_ordinal: '80'
title: Correct the older schema descriptions that do not match their resolvers (links, collect results, virtual tags)
---
## What
The second review of ^esc56vk (2026-10-21) found descriptions that are older than that task and do not match their resolvers:
- `linkStatus` and `linkTarget` (GraphQL/CheckLinksField.swift around :158, and GraphQL/SchemaDescription.swift)
- `collectResultRepairs` and `collectResultOtherLinks` (GraphQL/SchemaDescription.swift)
- `VirtualTag.explanation` for READY, BLOCKED and DELETED

The exact mismatch for each is in the "Review Findings (2026-10-21 09:53)" section and the review comment on ^esc56vk.

Read each resolver path end to end, then rewrite the description as a short statement that is plainly true. Re-record Tests/Fixtures/kanban.graphql with GRAPHQL_GOLDEN_RECORD=1.

## Acceptance Criteria
- [x] Each listed description matches its resolver behavior
- [x] The golden SDL is re-recorded and the golden test passes

## Tests
- [x] `swift test` is green