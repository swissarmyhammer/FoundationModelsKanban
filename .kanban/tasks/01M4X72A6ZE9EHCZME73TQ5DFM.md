---
assignees:
- claude-code
position_column: todo
position_ordinal: '9080'
title: Skip task URLs in code blocks, inline code, and headings for dependency markers
---
## What
divergence.md Q5 (DECIDED: no), D1, and §11 "Q5". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem (D1): a task URL in a code block is a dependency. Tag markers skip fenced blocks and headings (S/Tags/TagMarkers.swift:88-98) and inline code (:121-156). Dependency markers do not skip them (S/Derived/DependencyMarkers.swift:32-36,65-93). An example URL in a code block can block a task or cause `DEPENDENCY_CYCLE`.

Decided behavior: use the same rule as for tag markers. A task URL in a fenced code block, in inline code, or in a heading is not a dependency.
- Change S/Derived/DependencyMarkers.swift:32-36,65-93. Use the same skip logic as S/Tags/TagMarkers.swift:88-98,121-156 (share one helper if you can).
- The removal of a URL by `updateTask(dependsOn:)` (which removes the URLs that the new list drops from the body) must use the same rule: it must not change a URL in code or in a heading.
- The cycle check and the write check (Q3) also use only the counted markers.

## Acceptance Criteria
- [ ] A task URL in a fenced code block does not make a dependency.
- [ ] A task URL in inline code does not make a dependency.
- [ ] A task URL in a heading does not make a dependency.
- [ ] A task URL in normal text still makes a dependency.
- [ ] `updateTask(dependsOn: [])` removes a URL in normal text, and keeps the same URL in a code block.
- [ ] A URL in a code block that would close a cycle does not give `DEPENDENCY_CYCLE`.

## Tests
- [ ] One test for each skip case (fenced, inline, heading) and one for normal text.
- [ ] A test for the removal rule of `updateTask(dependsOn:)`.
- [ ] A test that a URL in code does not cause `DEPENDENCY_CYCLE`.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.