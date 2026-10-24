---
assignees:
- claude-code
depends_on:
- 01M5MQSBS3E7J746F17Z794J91
position_column: todo
position_ordinal: '8280'
title: 'Filter agent: write the system prompt as a package resource, with tested examples'
---
## What

Write the system prompt of the filter agent as a resource of the package, not as text in the code (divergence.md §17, "A smart prompt").

- Add the resource to the `FoundationModelsKanban` target (`resources:` in `Package.swift`).
- The prompt holds:
  - the grammar of the filter language: each sigil, each operator, the precedence and the implicit AND;
  - each virtual tag of `VirtualTag.allCases` and its meaning: `READY`, `BLOCKED`, `CONFLICT`, `DELETED`, `DONE`, `HIGH`, `MEDIUM`, `LOW`;
  - the rules of the default selection (plan §6.3);
  - examples of English and the filter statement for each one. Put the examples in a form that a test can read (for example a JSON list, or fenced pairs in the text that a test extracts).
- Keep the virtual tag list in one place. If the code already has the list (for example an enum), make a test that the prompt names each one, so the two cannot differ.

Note: `BLOCKING` is removed by divergence.md Q1 and C1. It is not a virtual tag, and `#BLOCKING` is an ordinary tag filter.

## Acceptance criteria

- [ ] The prompt loads from `Bundle.module` at run time.
- [ ] Each example statement parses with `FilterParser`.
- [ ] Each example statement passes the name check against a fixture board that has the names of the examples.
- [ ] A test fails when a virtual tag is not in the prompt.

## Tests

- Unit tests in `T/`: one test case for each example (parameterized), and the virtual tag test.
- `swift test` passes with no new warnings. #kanbanviewkit #filter-agent