---
depends_on:
- 01M4B3YYXT069TKADQ93CBAA93
- 01M4B3X08THVXHAJEQ4Z8PDB4H
- 01M4B4ADV9EPW7N9VGBVBVV8WM
- 01M4B4A8735GAP57Q8ZVDP5HY2
position_column: todo
position_ordinal: '9680'
title: 'Commit path: patch mutation, locks, signature check'
---
## What
The write side of a call. The basis is plan.md §5.4 steps 4 to 6.
- `Sources/FoundationModelsKanban/GraphQL/PatchSchema.swift`: the internal `patch` mutation applies one `PatchInput` to a working `Graph`.
- `Sources/FoundationModelsKanban/Tool/Commit.swift`: a mutation field works on a copy-on-write working copy. It makes patches (only the properties that change), applies them, checks the graph rules, and keeps them. A failed field discards only its own patches.
- Commit at the end of the call: lock each changed or rule-read board in key order; under the locks, compare the file signatures and the list of node files with the live graph; if a log changed, apply the changed files, discard the working copy, and run the call again; after 5 runs, return `BOARD_BUSY`. Append each patch with the `txn`, `ops`, and `boards` of the full call. Record the new signatures, then the working copy becomes the live graph.
- A call that changes nothing writes nothing.

## Acceptance Criteria
- [ ] A failed mutation field writes none of its patches; the other fields of the call are written.
- [ ] A file that changes before the commit makes the call run again; 5 changed runs give `BOARD_BUSY` and write nothing.
- [ ] A failed field or a run again does not change the live graph.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Tool/CommitTests.swift`: drive the commit with a test mutation; simulate a write by a different process between the load and the commit.
- [ ] Run `swift test --filter CommitTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.