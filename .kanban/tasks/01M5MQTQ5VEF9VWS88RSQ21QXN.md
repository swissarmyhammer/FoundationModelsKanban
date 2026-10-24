---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5pnpp1k7sfxvtjqx9bsw20j
  text: |-
    Research done.
    - `@testable import FoundationModelsKanban` works under `swift test --package-path IntegrationTests` (debug build): a probe test read `FilterAgentPrompt.load().examples` (13 examples) and passed. Thus no public API change is necessary. The probe file is removed.
    - `KanbanHost.configure(locator:embedder:filterModel:)` has `precondition(engines.isEmpty)`. The integration suites run in parallel in one process and all use `KanbanHost.shared`. Thus a configure in one test can crash the process when a different suite loaded a board first. Plan: one support helper configures the shared host one time (with the real filter model) before the first session, and each suite gets its sessions through that helper.
    - `ModelVariablesTests` makes its own `ModelPool()`. Two pools can load the 27B model two times at the same time. Plan: one shared `PooledModel` in the helper for the two model tests.
    - The IntegrationTests package has no README or CLAUDE.md. The root README gives the run command. The model test does not skip: it requires a Metal device (a skip gives a green run that measured nothing).
    - `CONFLICT` comes only from a body diff that does not apply at replay (a merge of logs). The public API cannot make it directly, so the fixture board has no conflict task, and `#CONFLICT` selects no task there.
    - This machine has an Apple M5 Max (Metal 4), and the Hugging Face cache has `mlx-community/Qwen3.8-27B-mxfp4`.
  timestamp: 2026-10-24T10:01:05.331567+00:00
- actor: claude-code
  id: 01m5ppdz8f46epckxhc6ewj2jv
  text: |-
    Implementation landed.
    - New `IntegrationTests/Tests/FoundationModelsKanbanIntegrationTests/FilterAgentExampleTests.swift`: one test case for each example of `FilterAgentPrompt.load().examples` (through `@testable import`; no public API change). For each example: a new git repo, a fixture board made through GraphQL (actors `alice` (Alice Smith) and `will`, column `doing` named In Progress, 17 tasks with each tag, open, done, blocked, and deleted), then `translateFilter` with the English text. Checks: no message; a second `translateFilter` with the statement gives `FilterTranslation.unchanged(statement)` (attempts 0, so it parses and passes the name check); the task list of the statement is the same full response as the task list of the example statement. The attachment `translate-filter.json` records the translation and its attempts, and the output of `--attachments-path` names each file.
    - New `Support/IntegrationHost.swift`: configures `KanbanHost.shared` one time with the real filter model before the first session, gives the one shared `PooledModel`, and `requireMetalDevice()`. `BoardSmokeTests`, `CrossRepoDependencyTests`, and `ModelVariablesTests` now get their sessions from `IntegrationHost.session`, because `configure` has `precondition(engines.isEmpty)` and the suites run at the same time in one process. `ModelVariablesTests` uses `IntegrationHost.model` (shared pool) in place of its own `ModelPool()`.
    - divergence.md §17 has the new part "The integration test (card ^sq21qxn)". README "Run the tests" names the two model tests and `--attachments-path`.
    - Sanity probe (temporary file, removed): the example statements on the fixture board select different, non-empty task sets, except `#CONFLICT` (no task; only a merge of two logs makes a conflict block).
    - Real model result (Qwen 3.8 27B mxfp4, M5 Max): 13 of 13 examples pass, each with attempts 1, and each model statement is the same text as the example statement.
    - Discovery: in the full integration run, the engine logs a runtime `warning` "The scan for related boards cannot read a place" for the removed temporary container of an earlier test in the same process. This is a log line of the library, not a build warning, and it does not fail a test. It comes from the shared host that keeps the scan place of a removed repo folder. It was not changed in this card.
  timestamp: 2026-10-24T10:13:48.431525+00:00
- actor: claude-code
  id: 01m5ppe5nk3y8rmnyjbvvyy16y
  text: |-
    ### implement — changed
    - evidence: 7 files — IntegrationTests/Tests/FoundationModelsKanbanIntegrationTests/FilterAgentExampleTests.swift (new), IntegrationTests/Tests/FoundationModelsKanbanIntegrationTests/Support/IntegrationHost.swift (new), IntegrationTests/Tests/FoundationModelsKanbanIntegrationTests/BoardSmokeTests.swift, IntegrationTests/Tests/FoundationModelsKanbanIntegrationTests/CrossRepoDependencyTests.swift, IntegrationTests/Tests/FoundationModelsKanbanIntegrationTests/ModelVariablesTests.swift, divergence.md, README.md. `swift test --package-path IntegrationTests`: 4 tests in 4 suites passed (13 of 13 filter example cases, each attempts 1). Root `swift test`: 1871 tests in 161 suites passed. Only the accepted SwiftPM "missing creator" warning in the two runs.
    - next: /review
  timestamp: 2026-10-24T10:13:54.995287+00:00
depends_on:
- 01M5MQTKNM12VRRJW516RXDA32
position_column: doing
position_ordinal: '80'
title: 'Filter agent: run the prompt examples with a real model in IntegrationTests'
---
## What

Add a test to the nested `IntegrationTests/` package that runs the English examples of the system prompt through `translateFilter` with a real model (divergence.md §17, "Tests").

- Use the same model setup as `IntegrationTests/.../ModelVariablesTests.swift` (the `PooledModel` that FoundationModelsExtras gives).
- Use a fixture board that has the names of the examples.
- For each example, the result must parse, pass the name check, and select the same tasks as the expected statement on the fixture board. Do not compare the text: the model can write an equal statement in a different form.
- Record the attempts of each example in the test output.

## Acceptance criteria

- [x] Each prompt example passes with the real model.
- [x] The test reads the examples from the resource, so a new example is tested with no code change.

## Tests

- `swift test` in `IntegrationTests/` passes. Only the accepted mlx Metal and SwiftPM "missing creator" warnings are allowed. #kanbanviewkit #filter-agent