---
assignees:
- claude-code
position_column: todo
position_ordinal: b380
title: 'plan.md: the variables model test uses Qwen 3.8, not the on-device model'
---
## What
The user decided on 2026-10-08 (card ^qjfsmrp) that the real-model test of `variables` uses `mlx-community/Qwen3.8-27B-mxfp4`, not the on-device `SystemLanguageModel`. With the on-device model, guided generation sent `"variables": {}` in 3 of 3 runs. Qwen 3.8 sent the string form with the value in 3 of 3 runs.
plan.md still names the on-device model in these places:
- §7.1 "Tests for this schema": "A test with a real `LanguageModelSession` checks that the on-device model makes the string form".
- §7.1 the schema text: "The on-device model can only make an empty object with the second choice."
- §12 item 8: "a JSON object in a string (the on-device model)".
`Sources/FoundationModelsKanban/Tool/KanbanArguments.swift` has the same words in its doc comment ("the on-device model sends").

## Acceptance Criteria
- [ ] plan.md names Qwen 3.8 (`mlx-community/Qwen3.8-27B-mxfp4`, in `IntegrationTests/`) as the model of the test, and records the measured on-device result (`{}` in 3 of 3 runs).
- [ ] The doc comment of `KanbanArguments` agrees with plan.md.

## Tests
- [ ] No code change. `swift build --build-tests` shows only the accepted warnings.