---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gy6hg4vg8d44xsskaha034
  text: |-
    Research:
    - moveTask (TaskOperationMutations `columnRef(forMoveTo:)`) and addComment (CommentMutations `authorRef(for:)`) test `NodeURI.hasScheme(atStartOf:)`. For a URI they call `RefResolver.nodeRef`/`actorRef`, and `RefResolver.storedRef` does the parse, the type check (`parsedURI(from:in:)`) and the board check (`NodeURI.localRef(inBoard:)`). A wrong type or a different board gives `notFound(type:reference:)` with the text as written.
    - These steps are private in RefResolver.swift, and `storedRef` needs a node that exists. An add mutation can make a new node, so the plan is one new RefResolver method that does the same parse, type and board steps, and gives the local id of the URI without a graph lookup. A short form stays as the caller wrote it.
    - `NodeURI(parsing:)` does not normalize the local id. The resolver normalizes it in the lookup (`Slug.normalizedText`, `TagName`). The add mutations keep their slug rule on the local id.
    - A URI that ends with `board` parses as the board URI, so `kanban://<key>/column/board` gives NOT_FOUND of the column type. A reserved slug through a URI needs a local id such as `BOARD-`, which the slug rule changes to `board`.
    - plan.md §3.2 "Target board": for a mutation that makes a node, the target board is the `board` field or the current repo. Thus the add mutations keep `MutationBoard.named(board)`, and a URI with a different board key gives NOT_FOUND, the same as a moveTask column URI of a different board.
    - Test helpers to reuse: ColumnActorTests (`id(of:)`, `respond`, `respondWritingNothing`, `failure`, `patches`, `setting`), TagMutationTests (`tagJSON`, `addTag(with:)`), ReservedSlugTests.Refusal and VirtualTagNameTests.refusals.
  timestamp: 2026-10-09T18:18:25.156428+00:00
- actor: claude-code
  id: 01m4gyf4430k3ttedd8bdjnqpp
  text: |-
    Implementation landed (TDD: RED showed only the URI cases fail, GREEN after the change).

    - `RefResolver.newNodeKey(for:ofType:)` (Identity/RefResolver.swift): the resolve step for an id of a node that a mutation can make. It uses the same private steps as `storedRef` (the path of moveTask and addComment): `parsedURI(from:in:)` for the parse and the type check, `NodeURI.localRef(inBoard:)` for the board check, and `Lookup.notFound` for the error. It gives the local id of the URI, and the graph does not need the node. A short form stays as written.
    - `RefResolver.slug(ofNewNode:named:ofType:)` (ColumnActorMutations.swift): one helper for addColumn and addActor, so the two resolvers do not copy the slug step.
    - addTag uses `newNodeKey` for the id. With a URI id and no name, the tag name is the local id of the URI, the same as a plain id gives its text as the name.
    - The slug rule of each type applies to the local id (the resolver lookup does the same). Then `addNode` runs `checkSlugIsNotReserved()`, so a URI id gets the reserved-slug check and the virtual-tag check.

    Choices where the card is open (closest to plan.md §3.2 "Target board", §4.2):
    - The add mutations keep `MutationBoard.named(board)`. A URI with the key of a different board gives `NOT_FOUND` of the expected type, the same as a moveTask column URI of a different board.
    - A URI whose last segment is `board` parses as the board URI, so it gives `NOT_FOUND` before the reserved-slug check. The reserved-slug URI tests use the local id `BOARD-`, which the slug rule changes to `board`.

    Tests:
    - ColumnActorTests: `addColumnAppendsColumn` and `addActorEnsureExisting` now take the slug and the URI as arguments; new `addColumnURIOfOtherBoard`.
    - TagMutationTests: `addTagIsIdempotent` now takes the uppercase name and the tag URI as arguments; new `addTagWithTaskURI` (`notFound(type: .tag, reference: <task URI>)`).
    - ReservedSlugTests: new cases `addColumnByURI`, `addActorByURI`, `addTagByURI`, with the shared helpers `idField(_:id:)` and `uri(of:id:)`; the ID cases use `idField` too.
    - VirtualTagNameTests: new row `(.addTagByURI, "Done", .done)`.
  timestamp: 2026-10-09T18:23:06.371612+00:00
- actor: claude-code
  id: 01m4gyf7g1kg3hwz63qdb2reww
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsKanban/Identity/RefResolver.swift, Sources/FoundationModelsKanban/GraphQL/ColumnActorMutations.swift, Sources/FoundationModelsKanban/GraphQL/TagMutations.swift, Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift, Tests/FoundationModelsKanbanTests/Mutations/TagMutationTests.swift, Tests/FoundationModelsKanbanTests/Mutations/ReservedSlugTests.swift, Tests/FoundationModelsKanbanTests/Mutations/VirtualTagNameTests.swift. `swift test`: 1095 tests in 79 suites passed, 0 failures. The only build warning is the accepted SwiftPM "missing creator for mutated node" warning.
    - next: /review
  timestamp: 2026-10-09T18:23:09.825586+00:00
- actor: claude-code
  id: 01m4gypqnkyjzgqmgygpntv7g1
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD, 3 findings (3 confirmed, 0 refuted) — Sources/FoundationModelsKanban/GraphQL/TagMutations.swift:102, Sources/FoundationModelsKanban/Identity/RefResolver.swift:88, Sources/FoundationModelsKanban/Identity/RefResolver.swift:93. The HEAD commit message agrees with the diff. Each acceptance criterion has a test.
    - next: /implement the open items in "## Review Findings (2026-10-09 13:25)"
  timestamp: 2026-10-09T18:27:15.763957+00:00
- actor: claude-code
  id: 01m4gyps3sw10qjqtg7275b6m1
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 7 files
    - test: green — swift test, 1095 tests in 79 suites passed
    - commit: 4aaa5b0
    - review: findings — Sources/FoundationModelsKanban/GraphQL/TagMutations.swift:102, Sources/FoundationModelsKanban/Identity/RefResolver.swift:88, Sources/FoundationModelsKanban/Identity/RefResolver.swift:93
  timestamp: 2026-10-09T18:27:17.241265+00:00
- actor: claude-code
  id: 01m4gz08rwnqc35aybwgbmx2hr
  text: |-
    Review findings of 2026-10-09 13:25 are fixed. This is a refactor only. Behavior does not change.

    - RefResolver.swift: each URI step now has one copy. `RefText(_:)` trims the ref and sorts it into a short form or a URI. `localKey(forURI:)` maps a URI with `localRef(inBoard:)` and `shortForm(of:)`. `target(of:in:)` returns a `RefTarget` (`.shortForm`, `.sameBoard(key:)`, `.otherBoard(NodeURI)`): it uses `RefText`, `parsedURI(from:in:)` and `localKey(forURI:)`. `storedRef` and `newNodeKey` call `target(of:in:)`. Each keeps its own handling: storedRef makes the remote ref, and newNodeKey throws NOT_FOUND. `anyLocalRef` calls `RefText` and `localKey(forURI:)`. It keeps its `try?` parse and has no type check.
    - The helper returns an enum and not `String?`, because storedRef needs the parsed URI for `remoteRef`. A `String?` helper would make storedRef parse the URI two times.
    - `newNodeKey(for: String, ...)` still returns the untrimmed reference for a short form. If it returned the trimmed text, the error text of `invalidSlug` and `invalidTagName` would change for a whitespace-only id.
    - ColumnActorMutations.swift: the new `RefResolver.newNodeKey(for: NodeID?, named:ofType:)` is the shared id-to-key step. `slug(ofNewNode:named:ofType:)` applies `Slug(columnOrActorName:)` to it. addTag (TagMutations.swift) applies `TagName` to it. The tag name is `TagName(input.name ?? key)` and the slug is `TagName(key).slug`. The values and the error order are the same as before.
  timestamp: 2026-10-09T18:32:28.188250+00:00
- actor: claude-code
  id: 01m4gz0ag0zhxa0zw8qcx6pz6s
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/Identity/RefResolver.swift, Sources/FoundationModelsKanban/GraphQL/ColumnActorMutations.swift, Sources/FoundationModelsKanban/GraphQL/TagMutations.swift. `swift test`: 1095 tests in 79 suites passed, 0 failures. The only build warning is the accepted SwiftPM "missing creator for mutated node" warning. All 3 review findings are checked.
    - next: /test, then /review
  timestamp: 2026-10-09T18:32:29.952460+00:00
- actor: claude-code
  id: 01m4gz8kp1z05p6s09edpeyp0z
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD, 1 finding (1 confirmed, 0 refuted) — Sources/FoundationModelsKanban/Identity/RefResolver.swift:110. The 3 prior findings are checked. The HEAD commit message (7321ac8) agrees with the diff: the refactor does not change behavior, and each helper that the message names is in the diff.
    - next: /implement the open item in "## Review Findings (2026-10-09 13:35)"
  timestamp: 2026-10-09T18:37:01.505842+00:00
- actor: claude-code
  id: 01m4gz8mqpegjn510m7k28pb6n
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 3 files
    - test: green — swift test, 1095 tests in 79 suites passed
    - commit: 7321ac8
    - review: findings — Sources/FoundationModelsKanban/Identity/RefResolver.swift:110
  timestamp: 2026-10-09T18:37:02.582330+00:00
- actor: claude-code
  id: 01m4gzftydfc2h455wex0snzgr
  text: |-
    Review finding of 2026-10-09 13:35 (RefResolver.swift:110 reuse/reuse) is fixed. This is a refactor only. Behavior does not change.

    - The finding gives two options. This change uses the second option: the parse is optional, and both callers share it. `target(of:in:)` cannot serve `anyLocalRef` directly, because `anyLocalRef` has no expected type before the parse. The `Lookup` of a URI takes its type from the URI.
    - New private `target(of:) -> RefTarget?` (no expected type). It is now the only place in RefResolver.swift that calls `NodeURI(parsing:)` and `localKey(forURI:)`. It returns `nil` when a URI does not parse.
    - `RefTarget.sameBoard` now holds the node type of the URI: `.sameBoard(key:type:)`. The new `RefTarget.canName(_:)` does the type check. A short form can name each type, and a URI names only the type in the URI.
    - `target(of:in:)` now calls `target(of:)` and throws `lookup.notFound` when the result is `nil` or `canName` is false. The errors and their order are the same as before: a URI that does not parse and a URI of a wrong type both give NOT_FOUND before the board check.
    - `parsedURI(from:in:)` is removed. Its parse is in `target(of:)`, and its type check is in `canName`.
    - `anyLocalRef` makes one call to `target(of:)`, and has no `RefText` switch: `.shortForm` tries each type, `.sameBoard(key, type)` resolves with that type and tombstones, and `.otherBoard` or `nil` gives `nil`.
    - New characterization test in NodeQueryTests: `node(id:)` with a `kanban://` URI that does not parse returns null and no error. It passed before and after the refactor. It pins the nil path of `anyLocalRef`, which no test had covered.
  timestamp: 2026-10-09T18:40:58.317661+00:00
- actor: claude-code
  id: 01m4gzfywswxy894r6bfbqaec0
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsKanban/Identity/RefResolver.swift, Tests/FoundationModelsKanbanTests/GraphQL/NodeQueryTests.swift. `swift test`: 1096 tests in 79 suites passed, 0 failures. The only build warning is the accepted SwiftPM "missing creator for mutated node" warning. The finding RefResolver.swift:110 is checked; all findings on the card are checked.
    - next: /test, then /review
  timestamp: 2026-10-09T18:41:02.361038+00:00
depends_on:
- 01M4G9JDQ98082KJQTMWE86DV8
position_column: doing
position_ordinal: '80'
title: addTag, addColumn and addActor accept a full kanban:// URI as id
---
## What
`Sources/FoundationModelsKanban/GraphQL/TagMutations.swift:94-95` and `Sources/FoundationModelsKanban/GraphQL/ColumnActorMutations.swift:140` and `:223` make the slug from `input.id.text` with `TagName(normalizing:)` or `Slug(columnOrActorName:)`. They do not check for the `kanban://` scheme first. Thus `addTag(input:{id:"kanban://github.com/o/r/tag/bug"})` makes a tag `kanban-github-com-o-r-tag-bug`, and `addActor(ensure:true)` with an actor URI makes a second actor. plan.md §3.2: "a full URI with the key of the target board becomes a local ref". `moveTask` and `addComment` already do this check.

- Use the same resolve step as `moveTask` and `addComment`: when the id is a `kanban://` URI, parse it, check the node type (tag, column, actor), check the board, and use its slug.
- A URI of a wrong node type gives the same error as in `moveTask`.

## Acceptance Criteria
- [x] `addTag` with the URI of an existing tag returns that tag and makes no new tag.
- [x] `addActor(ensure:true)` with the URI of an existing actor returns that actor.
- [x] `addColumn` with a column URI uses the slug of the URI.
- [x] A task URI in `addTag` gives an error.

## Tests
- [x] Tests in `Tests/FoundationModelsKanbanTests/Mutations/` for each acceptance criterion.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-09 13:25)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/TagMutations.swift:102` `duplication/duplication` — addTag repeats the id-to-slug path that RefResolver.slug(ofNewNode:named:ofType:) already has: take the id, call newNodeKey(for:ofType:), then build the slug from the key. The tag version differs only in its slug type (TagName instead of Slug(columnOrActorName:)), so the two paths can drift apart. Give the id-to-key step one shared helper, for example a RefResolver method that returns the new node key from an optional NodeID and a name. Each caller then builds its own slug type: TagName for tags, Slug(columnOrActorName:) for columns and actors.
- [x] `Sources/FoundationModelsKanban/Identity/RefResolver.swift:88` `duplication/duplication` — newNodeKey repeats the URI-to-local-id steps of storedRef and anyLocalRef: trim the text, check the scheme, parse the URI, map it with localRef(inBoard:), and take shortForm(of:). If one of these steps changes, the three copies can drift apart. Extract one private helper, for example localKey(forURI:in:), that returns the short form of a URI in this board, or nil. Call it from storedRef, anyLocalRef and newNodeKey. Each caller keeps its own error or nil handling.
- [x] `Sources/FoundationModelsKanban/Identity/RefResolver.swift:93` `reuse/reuse` — `newNodeKey(for:ofType:)` repeats the URI branch of `storedRef(for:ofType:acceptingRemote:includingTombstones:)`: it parses the text with `parsedURI(from:in:)`, takes `localRef(inBoard:)`, and converts the result with `shortForm(of:)`. Two copies of the same board-key check mean a future change to URI handling has to be made in both places. Extract a helper, for example `sameBoardShortForm(of text: String, in lookup: Lookup) throws(KanbanError) -> String?`, that returns the short form of a URI when it names this board. Call it from `storedRef` and from `newNodeKey`, so each keeps only its own lookup and its own remote-ref handling.

## Review Findings (2026-10-09 13:35)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Sources/FoundationModelsKanban/Identity/RefResolver.swift:110` `reuse/reuse` — The `.uri` branch of `anyLocalRef` repeats the parse-and-check-key steps that `target(of:in:)` and `parsedURI(from:in:)` already do, instead of calling them. It parses with `NodeURI(parsing:)` and then calls `localKey(forURI:)`, which is the same sequence `target(of:in:)` runs. The new code is a parallel copy of existing logic, so a future fix to URI parsing or board-key handling would have to be made in two places. Route the `.uri` case through `target(of:in:)`. Wrap it in `try?` and map a throw to `nil`, and map `.otherBoard` to `nil`, so that the nil-on-failure contract of `anyLocalRef` is kept. Alternatively, have `parsedURI` take a flag or return an optional so both callers share one parse. Either way, the `RefText` switch in `anyLocalRef` can then also be replaced by one call to `target(of:in:)`.
