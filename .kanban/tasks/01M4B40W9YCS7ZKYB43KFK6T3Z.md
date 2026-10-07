---
comments:
- actor: wballard
  id: 01m4bpam8var22v34xnn5wdxrv
  text: 'Research done. plan.md §4.5 gives the six match steps and the rules; §12 items 14, 16, 19, 21 give the verbNoun form, the synonyms, and the old names `description`/`text` as aliases of `body`. The Rust `Verb::from_alias` (swissarmyhammer-kanban/src/types/operation.rs) maps `create` to `Init`; the plan maps `create` to `add`, so the never list keeps `create` -> `init` out. A second real risk: `tag` and `task` differ by one letter, so step 6 could map `addTag` to `addTask`; the never list also holds `tag` <-> `task`. The card names no Rust tests to port. The schema (Schema.swift) declares fields with Graphiti `Field(...)`, which has no place for aliases, so the alias table goes into Schema.swift beside the field lists, keyed by the GraphQL field name. Nothing calls the matcher in production yet; the rewrite task ^... (Forgiving names: rewrite the document) will call it.'
  timestamp: 2026-10-07T17:24:38.299784+00:00
- actor: wballard
  id: 01m4bpmt0fddk8z1v2r1h2k7dd
  text: |-
    Implementation landed (TDD). RED: the new test file did not compile (no `CanonicalName`, `NameMatch`, `NameMatcher`). GREEN: 22 tests (66 cases) pass. A mutation check proved the never-list test: with `NeverMapping.all` empty, `neverListBlocksStepMatch` failed at the `createBoard` expectation; the list was then restored.

    Design: `NameMatcher.match(for:among:at:)` returns `NameMatch` (`.found(canonical:)`, `.tie(matches:)`, `.notFound`). The steps are the compiler-checked `MatchStep` enum in plan order. Each step compares a lowercase word key (camel/snake/kebab split). The never filter runs at every step; it blocks a candidate only when the agent word becomes the forbidden word (both words absent on the other side). Aliases are the `GraphQLFieldAliases.byName` table in Schema.swift beside the field lists; `CanonicalName(field:)` reads it.

    What did not work: my first never-list idea (`tag` <-> `task`) was wrong. `tag` and `task` differ by two edits, so step 6 never maps one to the other. Transpositions (`titel`, `reday`) are two edits too; step 6 does not accept them, as the plan says (one changed, added, or removed letter).

    For the rewrite task (^... Forgiving names: rewrite the document): `NamePosition` has only `.topLevelMutation` and `.anyOther`, because only step 4 depends on the position. The root-query move into `board { }` is the rewrite's job, not the matcher's.

    Periphery: no findings in the changed files. It reports 4 assign-only properties in `Errors.swift` (`ResponseError` / `Extensions`); these existed before this task.
  timestamp: 2026-10-07T17:30:11.855668+00:00
- actor: wballard
  id: 01m4bpmw4s3ft58ss9bmvzzdz0
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/GraphQL/NameMatcher.swift (new), Sources/FoundationModelsKanban/GraphQL/Schema.swift (alias table + `CanonicalName(field:)`), Tests/FoundationModelsKanbanTests/GraphQL/NameMatcherTests.swift (new). `swift test --filter NameMatcherTests`: 22 tests passed. `swift test`: 481 tests in 31 suites passed, 0 compiler warnings. swiftlint (magic numbers, docs, force rules, length 120): 0 violations. periphery (native build): 0 findings in the changed files.
    - next: /review
  timestamp: 2026-10-07T17:30:14.041791+00:00
depends_on:
- 01M4B3YQSXZCGCB08FVP8QCSF3
position_column: doing
position_ordinal: '8180'
title: 'Forgiving names: the name matcher'
---
## What
Match a wrong name to one canonical name. The basis is plan.md §4.5 (Match steps, Rules).
- `Sources/FoundationModelsKanban/GraphQL/NameMatcher.swift`: given a name and the list of valid names at one position, try in order and stop at the first step with exactly one match: exact; same case and style (`camelCase`, `snake_case`, `kebab-case`, any case); singular or plural; for a top-level mutation, the other word order and the verb synonyms (`create`/`new`/`insert` → `add`, `remove`/`rm`/`del` → `delete`, `edit`/`modify`/`set`/`patch` → `update`, `mv` → `move`, `done`/`finish`/`close` → `complete`, `label` → `tag`, `unlabel` → `untag`, `restore`/`unarchive`/`recover` → `undelete`, `archive` → `delete`); the alias table; one changed, added, or removed letter (names of 4 or more letters).
- A tie at a step gives a result that lists the matches; no guess.
- A list of mappings that are never made (for example `create` never maps to `init`).
- Aliases are declared in Swift next to each field (for example `description`/`desc`/`text`/`content` → `body`, `status` → `column`, `assignee` → `assignees`, `task_id` → `id`).

## Acceptance Criteria
- [x] `taskAdd`, `createTask`, `create_task` each give `addTask`.
- [x] A tie gives the list of matches, not one name.
- [x] `createBoard` does not give `initBoard`.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/GraphQL/NameMatcherTests.swift`: each step, ties, the never list.
- [x] Run `swift test --filter NameMatcherTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.