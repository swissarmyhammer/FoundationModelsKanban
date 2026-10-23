---
assignees:
- claude-code
depends_on:
- 01M5MQTKNM12VRRJW516RXDA32
position_column: todo
position_ordinal: '8580'
title: 'Filter agent: run the prompt examples with a real model in IntegrationTests'
---
## What

Add a test to the nested `IntegrationTests/` package that runs the English examples of the system prompt through `translateFilter` with a real model (divergence.md §17, "Tests").

- Use the same model setup as `IntegrationTests/.../ModelVariablesTests.swift` (the `PooledModel` that FoundationModelsExtras gives).
- Use a fixture board that has the names of the examples.
- For each example, the result must parse, pass the name check, and select the same tasks as the expected statement on the fixture board. Do not compare the text: the model can write an equal statement in a different form.
- Record the attempts of each example in the test output.

## Acceptance criteria

- [ ] Each prompt example passes with the real model.
- [ ] The test reads the examples from the resource, so a new example is tested with no code change.

## Tests

- `swift test` in `IntegrationTests/` passes. Only the accepted mlx Metal and SwiftPM "missing creator" warnings are allowed. #kanbanviewkit #filter-agent