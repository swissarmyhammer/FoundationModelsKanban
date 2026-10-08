---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4e26m4qc0q1zcm3nt6mr71n
  text: |-
    Research: a search of Sources, Tests, IntegrationTests, README.md and plan.md for "on-device", "SystemLanguageModel" and "string form" found 4 places that said the on-device model makes the string form: plan.md §7.1 (schema text, "Tests for this schema"), plan.md §12 item 8, the `KanbanArguments` doc comment. Also README.md "Run the tests" said "A test that uses the on-device model needs a Mac with Apple Intelligence turned on". That is not true now: the model test uses Qwen 3.8 through MLX, and it needs a Metal device and the model in the Hugging Face cache. `ModelVariablesTests.swift` already agrees. plan.md line 12 ("Target: macOS 27, on-device") is about the product target, not the test, so it did not change.
    Note: the rules dump for .swift is 750 000 characters. It was not read whole. The change in Swift is only a doc comment.

    ### implement — changed
    - evidence: 3 files — plan.md (§7.1 schema text with a "Measured result" list, §7.1 "Tests for this schema", §12 item 8; changed paragraphs wrapped to 120 characters), Sources/FoundationModelsKanban/Tool/KanbanArguments.swift (doc comment only), README.md (the model test needs a Metal device, not Apple Intelligence). No added line is longer than 120 characters. `swift build --build-tests` exit 0, only the accepted `missing creator for mutated node` warning. `swift test --skip-build` (120 s limit) exit 0, 965 tests in 68 suites passed after 7.6 s.
    - next: /review.
  timestamp: 2026-10-08T15:30:38.871227+00:00
position_column: doing
position_ordinal: '80'
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
- [x] plan.md names Qwen 3.8 (`mlx-community/Qwen3.8-27B-mxfp4`, in `IntegrationTests/`) as the model of the test, and records the measured on-device result (`{}` in 3 of 3 runs).
- [x] The doc comment of `KanbanArguments` agrees with plan.md.

## Tests
- [x] No code change. `swift build --build-tests` shows only the accepted warnings.