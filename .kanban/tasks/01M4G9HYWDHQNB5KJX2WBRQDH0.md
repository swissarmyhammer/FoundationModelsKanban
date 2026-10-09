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