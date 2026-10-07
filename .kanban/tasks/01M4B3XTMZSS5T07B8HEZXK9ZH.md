---
comments:
- actor: wballard
  id: 01m4bgh5602937qf9nv9qr4pvv
  text: |-
    Research done.
    - Rust `tag_parser.rs` scans a line by bytes: it skips fence lines, lines in a fence, heading lines, and inline code. A marker is `#` (not glued to `[A-Za-z0-9_]` before it), then an ASCII letter or digit, then `[A-Za-z0-9-]*`. The Swift port normalizes the text to a `Slug` (lowercase), so `#Bug` and `#bug` give the same tag. The remove helper compares the normalized slug.
    - `DependencyMarkers.removing` and the tag remove need the same line framing: split a body into lines with their breaks, trim the trailing whitespace of an edited line, and drop the break before an emptied last line. Plan: extract this into a shared `Body/BodyLines.swift` and make `DependencyMarkers` use it. The URL scan does not fit the `#tag` scan, so it stays apart.
    - The tag remove takes one adjacent space with the marker (Rust rule). The dependency remove does not. This difference stays.
    - Tombstones stay in the `Graph` (node with `fields.deleted`), so the redirect walk can see them. `Graph` has no node enumeration; `Board.tags` needs one, so `Graph` gets an internal `allSlots`.
    - No ARCHITECTURE.md. plan.md §8 does not list a shared lines file in `Body/`; the new file extends that layout.
  timestamp: 2026-10-07T15:43:20.768663+00:00
- actor: wballard
  id: 01m4bgtr9k8yfvzwxextk0jtv7
  text: |-
    Implementation landed (TDD: both suites failed to compile first, then passed).
    - New `Body/BodyLines.swift`: shared line rules (`lines(of:)`, `content(of:)`, `editedLine(withText:replacing:)`, `body(joining:with:)`). `DependencyMarkers.removing` now uses it; its own copies of these helpers are gone. Existing DependencyMarkersTests still pass.
    - New `Tags/TagMarkers.swift`: `TagMarkers.slugs(in:)` (parse, slugs in text order, unique), `TagMarkers.removing(markersOf:from:)` (case-insensitive by slug, takes one adjacent space, keeps skipped lines byte for byte), `TagMarkers.tagBearingFlags(of:)` (fence and heading walk). `Graph.tagSlots(of:)`, `Graph.boardTagSlots`, `Graph.renameTarget(ofTagAt:)` give `task.tags`, `Board.tags`, and the redirect walk (RefResolver can use `renameTarget` to reach a tombstone).
    - `Graph.allSlots` added (Board.tags needs to enumerate tags). `Unicode.Scalar.isASCIIAlphanumeric` changed from fileprivate to internal, for reuse by the marker scan.
    - Decisions: a marker or edge to a tag that the graph does not have gives no tag (no slot to return). A `renamedTo` edge with no target in the graph drops the tag; it is also not in Board.tags.
    - Rust `append_tag` and `rename_tag` are not ported (not in scope; plan §6.2 rename does not change text). The append round-trip cases are ported as fixed tagged inputs for the remove.
    - Note: plan.md §8 lists no `Body/BodyLines.swift`; the layout list needs that file added.
  timestamp: 2026-10-07T15:48:35.251896+00:00
- actor: wballard
  id: 01m4bgtv8rssphehxmm8mfcr8x
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsKanban/Body/BodyLines.swift (new), Sources/FoundationModelsKanban/Tags/TagMarkers.swift (new), Sources/FoundationModelsKanban/Derived/DependencyMarkers.swift, Sources/FoundationModelsKanban/Model/Graph.swift, Sources/FoundationModelsKanban/Tags/TagSlug.swift, Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift (new), Tests/FoundationModelsKanbanTests/Tags/TagResolveTests.swift (new). `swift test --filter 'TagMarkersTests|TagResolveTests'`: 23 tests in 2 suites passed. `swift test`: 336 tests in 21 suites passed, no build warnings. `periphery scan --retain-public --report-exclude 'Tests/**' -- --build-system native --build-tests`: no findings in changed files (4 earlier findings in GraphQL/Errors.swift only).
    - next: /review
  timestamp: 2026-10-07T15:48:38.296157+00:00
- actor: wballard
  id: 01m4bh2tmxjc7rk6zr8xgdt3s8
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD; 1 finding (1 confirmed, 0 refuted) — Sources/FoundationModelsKanban/Tags/TagMarkers.swift:101 (swift/access-control)
    - next: Change `fileprivate` to `private` on `markers(inLine:)`. Remove this cause from all of TagMarkers.swift. Then run the review again.
  timestamp: 2026-10-07T15:52:59.805001+00:00
- actor: wballard
  id: 01m4bh34spma1xqh1am5habfen
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 7 files (Body/BodyLines.swift, Tags/TagMarkers.swift, Derived/DependencyMarkers.swift, Model/Graph.swift, Tags/TagSlug.swift, TagMarkersTests.swift, TagResolveTests.swift)
    - test: green — swift test, 336 passed, 0 warnings
    - commit: d9f6082
    - review: findings — Sources/FoundationModelsKanban/Tags/TagMarkers.swift:101
  timestamp: 2026-10-07T15:53:10.198534+00:00
- actor: wballard
  id: 01m4bh4hdwp22d72k2ypcj97tg
  text: |-
    Fix for the swift/access-control finding.
    - `TagMarkers.markers(inLine:)` changed from `fileprivate` to `private`. Only `TagMarkers` and its extensions in the same file call it.
    - Checked each other `fileprivate` member in the changed files. They must stay `fileprivate`, because a different type in the same file calls them, and a `private` member of an extension is visible only to the same type:
      - `Unicode.Scalar.isMarkerSlugScalar` (TagMarkers.swift): `TagMarkers.marker(in:at:)` calls it.
      - `Substring.isFenceLine` and `Substring.isHeadingLine` (TagMarkers.swift): `TagMarkers.tagBearingFlags(of:)` calls them.
      - `Slug.init?(nonEmptySlugOf:)` (TagSlug.swift): `TagName.init(normalizing:)` calls it.
    - `Body/BodyLines.swift`, `Derived/DependencyMarkers.swift`, and `Model/Graph.swift` have no `fileprivate` member.
    - TDD note: this change has no behavior change, so no new test. The compiler is the check.
  timestamp: 2026-10-07T15:53:55.900583+00:00
- actor: wballard
  id: 01m4bh4jhd27wqy8w92bdpxhee
  text: |-
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsKanban/Tags/TagMarkers.swift. `swift test`: 336 tests in 21 suites passed, build complete with 0 compiler warnings.
    - next: /review
  timestamp: 2026-10-07T15:53:57.037249+00:00
depends_on:
- 01M4B3XHRVFA2YDCJC76MAFQR5
- 01M4B3VX4HPNXHC77F2RKYE37K
position_column: doing
position_ordinal: '80'
title: 'Tags at read time: markers and rename redirect'
---
## What
Calculate the tags of a task. The basis is plan.md §6.1 and §6.2.
- `Sources/FoundationModelsKanban/Tags/TagMarkers.swift`: parse `#tag` markers in a body (port the parse part of `../swissarmyhammer/crates/swissarmyhammer-kanban/src/tag_parser.rs`), and normalize each to its slug.
- Redirect walk: follow `renamedTo` from tag to tag. A cycle (from a merge) stops at the first slug that repeats, and uses that tag.
- `task.tags` = resolve(tag edges) ∪ resolve(markers in the current body). A resolve that ends at a tombstone drops the tag.
- `Board.tags` lists the live tags with no `renamedTo`, plus the stop tag of a rename cycle.
- Helper to remove a marker from a body (the `untagTask` mutation uses it later).

## Acceptance Criteria
- [x] `#bug` in the body gives the tag `bug`; an edge and a marker to one tag give it one time.
- [x] After a redirect `bug → defect`, an edge to `bug` and a marker `#bug` both show `defect`.
- [x] A rename cycle does not loop, and gives the stop tag.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift` (ported parse tests) and `TagResolveTests.swift` (union, redirect, chain, cycle, tombstone).
- [x] Run `swift test --filter TagMarkersTests` and `--filter TagResolveTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-07 10:49)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/Tags/TagMarkers.swift:101` `swift/access-control` — `markers(inLine:)` uses `fileprivate` but should use `private`. The function is only called from within `TagMarkers` and its extensions—specifically from `slugs()` at line 50 and from `editedLine()` at line 207. Private access is sufficient; fileprivate unnecessarily exposes it to sibling types in the file. Change `fileprivate static func markers(inLine text: Substring)` to `private static func markers(inLine text: Substring)`.
