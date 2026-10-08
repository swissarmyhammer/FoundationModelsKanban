---
comments:
- actor: wballard
  id: 01m4cx8a9d6b47w635y5c6vyh4
  text: |-
    Research and first RED run.

    - Package.swift: added `FoundationModelsMultitool` by URL (`swissArmyHammerOrg`, branch main), linked only to the test target. Resolve and build pass. The build shows only the accepted SwiftPM "missing creator" warning in this incremental build. A full clean-build warning scan is not done yet.
    - Real Multitool API (checkout 1155c16): `try MultiTool.Builder().addTool(tool).buildRegistry()` gives a `MultiTool.Registry`; `MultiTool(registry:)` is the `runCode` tool; `call(arguments: RunCodeArguments(code:))` gives the rendered result (the JSON of the return value). A direct call has no ToolContext, so it runs inline (no background envelope).
    - The `variables` object form passes Multitool validation: the schema property is a `$ref` with `anyOf` and no `type`. At render time Multitool logs `schema element widened to any` for `args.variables`. That is a runtime log line, not a build warning.
    - New test: `Tests/FoundationModelsKanbanTests/Multitool/CodeModeTests.swift`, `scriptAddsReadsAndMoves` (the plan.md §9 script). RED result: `The snippet failed: undefined is not an object (evaluating 'r.data.board')`.

    BLOCKER: a decision that only a person can make.
    plan.md §9 item 2 says: "Multitool parses a JSON object into structured GeneratedContent, so a script gets result.data.board... as a value." This is not true for a plain `Tool` whose `Output` is `String`. `MultiTool.performInvocation` calls `ArgumentMarshaler.renderOutput(output)`, which decodes `output.generatedContent.jsonString`. For a `String` output, that is a JSON string, so the script gets a JS string. Only `OperationVerbTool` (for `OperationDescribing` tools) parses JSON text, and plan.md §9 item 1 says that the kanban tool does not conform to `OperationDescribing`.
    Thus the acceptance criterion "The script gets result.data.board.nextTask as a structured value" conflicts with plan.md §7.1 ("Output is a String that holds the GraphQL response JSON") and §9 item 1. Each fix changes a recorded decision:
    1. Change `KanbanTool.Output` to `GeneratedContent` (parsed from the response JSON). The script then gets an object. This changes §7.1 and the existing KanbanToolTests, which compare the output text.
    2. Make the kanban tool conform to `OperationDescribing`. This changes §9 item 1 and the `tools.kanban(...)` path.
    3. Change Multitool to parse JSON text from a `String` output. That is a change in the other repo.
    4. Keep the String output and let the script call `JSON.parse(r)`. This does not meet the acceptance criterion.
    Not done until the decision: the code-mode test passes, the log check (task in `doing`), and the on-device model test.
  timestamp: 2026-10-08T04:44:57.005353+00:00
- actor: wballard
  id: 01m4cx8ex5b1t1btwjdtr8jg1w
  text: |-
    Second conflict to decide with the first one. The card puts the real `LanguageModelSession` test in `CodeModeTests.swift` (the unit target) with a Swift Testing trait. The `test-integrity/test-partitioning` validator says that a test against a real model is an integration test and must be in a nested `IntegrationTests/` package, and that the root `swift test` must not see it. The card and the validator cannot both be correct. A person must choose the location of the model test.

    ### implement — stuck
    - evidence: Package.swift (FoundationModelsMultitool test dependency), Tests/FoundationModelsKanbanTests/Multitool/CodeModeTests.swift (RED: script gets a string, `r.data` is undefined). Model test not written. Full suite not run.
    - next: a person decides how the script gets a structured response (options 1 to 4 above) and where the real-model test lives. Then implement continues.
  timestamp: 2026-10-08T04:45:01.733903+00:00
- actor: wballard
  id: 01m4cx92hjwnbyask0yda64dke
  text: |-
    ### finish iteration 1 — stuck
    - implement: stuck — 2 decisions are for a person (see the blocker comments):
      1. Multitool gives the script a JS string for a `Tool` with `String` output, so `result.data.board.nextTask` is not a structured value. This conflicts with plan.md §7.1 (output is `String`) and §9 item 1 (no `OperationDescribing`).
      2. The card puts the on-device model test in the unit target with a trait, but the `test-partitioning` validator requires a real-model test in a nested `IntegrationTests/` package.
    - test: not run — the work is blocked
    - commit: none on main. The partial work is parked on the local branch `wip/qjfsmrp-multitool` (Package.swift with the Multitool test dependency, Multitool/CodeModeTests.swift, which is red).
    - review: not run
  timestamp: 2026-10-08T04:45:21.842450+00:00
- actor: wballard
  id: 01m4dpq2h0ks4kk5stg82snsw0
  text: |-
    ### Decisions from the user (2026-10-08)
    1. **Output:** the script must get the tool result as a JS object. Multitool will change: when a plain `Tool` returns a `String` that holds JSON, the script gets the parsed value. `KanbanTool` keeps its `String` output (plan.md §7.1 stays) and does not conform to `OperationDescribing`. The Multitool session (foundationmodelsmultitool-34) got the request. This task waits for that Multitool commit, and for the user to push it, because Kanban gets Multitool by URL.
    2. **Input:** a code mode script can give `variables` as a JS object or as a JSON string. Both forms must work, and the test must prove both.
    3. **On-device model test:** it goes in the nested `IntegrationTests/` package (task ^7j3aar6), not in the unit target. The unit target keeps the code mode test that needs no model.
    - The partial work is on the local branch `wip/qjfsmrp-multitool` (931b3ea).
  timestamp: 2026-10-08T12:09:54.976824+00:00
- actor: wballard
  id: 01m4dq5t7sz72hteqst9jtdn7h
  text: |-
    ### Multitool dependency ready (local only)
    - **Commit:** FoundationModelsMultitool 5bbaec4. `ArgumentMarshaler.renderOutput` gives a runCode script the parsed JS value when a `String` output holds one JSON object or array. Other text, also JSON scalars, stays a string.
    - **Input:** no Multitool change was necessary. An `anyOf` [string, object with no properties] field with no top-level `type` passes a JS object as an object, and a JSON string as a string.
    - **Tests:** 5 Multitool tests cover the change, and its review found 0 findings.
    - **Blocked:** the commit is NOT pushed. This task can use it only after the user pushes it, because Kanban gets Multitool by URL. After the push, run `swift package update FoundationModelsMultitool` here.
    - **Other failures:** 4 Multitool tests (HostAndEmitter, RunBinding, InnerTerminalEvent) fail. They also fail on 1155c16 without this change.
  timestamp: 2026-10-08T12:17:58.009097+00:00
- actor: wballard
  id: 01m4dwmbv81v3ctbshb0w7trq1
  text: |-
    ### Multitool update from its session
    - The pushed SHA is 24f65ed, not 5bbaec4. It was rebased onto origin/main, and the code change is the same.
    - CI run 37784111273 for 24f65ed passed ("Build & test" and "Integration").
    - The 4 Multitool event tests that failed before came from old local dependency checkouts, and they pass after `swift package update`.
    - Multitool tracks its sibling packages on `main`. A full `swift package update` here moves MetadataRegistry, Ranker and Extras, and then `TaskSearch.swift` does not compile (`TextEmbedding`). That is a decision for the user, so this task does not do a full update.
  timestamp: 2026-10-08T13:53:17.672679+00:00
- actor: wballard
  id: 01m4dxrz15g95g1bxqszbgn6px
  text: |-
    BLOCKER: the Multitool dependency cannot resolve to a revision that has the feature without a break of the root build. A person must decide.

    What I did:
    - Package.swift: I added only the Multitool test dependency (the `multitoolPackage` constant, the `.package(url: git@github.com:swissarmyhammer/FoundationModelsMultitool.git, branch: "main")` line, and the test-target product). The newer `main` content stays. I restored `Tests/FoundationModelsKanbanTests/Multitool/CodeModeTests.swift` from `wip/qjfsmrp-multitool` (931b3ea). Both are in the working tree, not committed.

    Step 1: `swift package resolve` gives exit 0, but it pins Multitool at the old cached revision 1155c1684865 (no JSON-output feature). MetadataRegistry 91d4225, Ranker d75a67c and Extras 130eb40 stay.

    Step 2: `swift package update FoundationModelsMultitool` fails. Exact resolver output (last lines):
    ```
    Working copy of git@github.com:swissarmyhammer/FoundationModelsMultitool.git resolved at main (24f65ed)
    error: exhausted attempts to resolve the dependencies graph, with the following dependencies unresolved:
    * 'swift-case-paths' from https://github.com/pointfreeco/swift-case-paths
    ```
    (Only swift-parsing refers to swift-case-paths, through its `CasePaths` trait. The root turns that trait off with `traits: []`.)

    Step 3: To get a diagnosis, I set only the Multitool pin in Package.resolved to 24f65ed46b39 and kept MetadataRegistry, Ranker, Extras, Router and CodeContext at their old pins. `swift package resolve` gives exit 0. `swift build --build-tests` fails in Multitool:
    ```
    .build/checkouts/FoundationModelsMultitool/Sources/FoundationModelsMultitool/RegistryBundle.swift:155:71: error: cannot convert value of type '(any PooledEmbedding)?' to expected argument type '(any TextEmbedding)?'
    .build/checkouts/FoundationModelsMultitool/Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift:173:74: error: cannot convert value of type '(any PooledEmbedding)?' to expected argument type '(any TextEmbedding)?'
    ```
    Cause: the breaking Multitool commit b4e34f0 ("refactor!: use the FoundationModels LanguageModel and Extras PooledEmbedding directly") needs the new `main` of Ranker, MetadataRegistry, Router and CodeContext.

    Step 4: I also moved Extras to 5c1c638, MetadataRegistry to 858f5da, Ranker to 6156346 (all origin/main). Then CodeContext f396b6b failed (`.build/checkouts/FoundationModelsCodeContext/Sources/FoundationModelsCodeContext/Embedding/TextEmbedding.swift:17:57: error`). With CodeContext 97caa23 and Router 85b96f3 also moved, Multitool compiles, and the root build fails:
    ```
    Sources/FoundationModelsKanban/Search/TaskSearch.swift:24:39: error: cannot find type 'TextEmbedding' in scope
    ```

    Result: the only resolution that has the feature (Multitool 24f65ed) moves MetadataRegistry, Ranker and Extras (and also CodeContext and Router), and the root build then breaks in TaskSearch. As the instructions say, I did not port TaskSearch, and I did not pin Multitool to an old revision. I restored Package.resolved to HEAD.

    Decision for a person, one of:
    1. Port `TaskSearch` (and its tests and the search fake) from `TextEmbedding` to the new MetadataRegistry/Ranker API (`PooledEmbedding`), as a separate task before this one. Then pin all six siblings to their current `main`.
    2. Put the JSON-output feature on a Multitool branch that is before b4e34f0, and refer to that branch here.
    Also note: `swift package update <one package>` fails on the swift-case-paths trait issue. Only a manual pin change resolved.
  timestamp: 2026-10-08T14:13:16.965767+00:00
- actor: wballard
  id: 01m4dxs2xjsrew8pw3p2w08fjz
  text: |-
    ### implement — stuck
    - evidence: Package.swift (Multitool test dependency only), Tests/FoundationModelsKanbanTests/Multitool/CodeModeTests.swift (from wip 931b3ea, not changed). No Multitool revision with the feature (24f65ed) builds with the old MetadataRegistry/Ranker/Extras pins. With the new pins, the root build fails at Sources/FoundationModelsKanban/Search/TaskSearch.swift:24:39 `cannot find type 'TextEmbedding' in scope`. Package.resolved restored to HEAD. No test run. IntegrationTests not changed. The model test was not written and did not run.
    - next: a person chooses option 1 (port TaskSearch to the new API in a separate task) or option 2 (a Multitool branch with the feature before b4e34f0). Then implement continues.
  timestamp: 2026-10-08T14:13:20.946952+00:00
- actor: wballard
  id: 01m4dxt4jpwjqnkhcsa96r46ne
  text: |-
    ### finish iteration 2 — stuck
    - implement: stuck. Multitool 24f65ed (the JSON-output feature) comes after the breaking commit b4e34f0. It needs current `main` of Extras, MetadataRegistry, Ranker, CodeContext and Router. With those, the root build fails at `Sources/FoundationModelsKanban/Search/TaskSearch.swift:24:39: cannot find type 'TextEmbedding' in scope`. `swift package update FoundationModelsMultitool` also fails (`swift-case-paths` unresolved). Only a manual change of the pins in `Package.resolved` resolves.
    - A person must choose:
      1. move `TaskSearch` (and its tests and search fake) from `TextEmbedding` to `PooledEmbedding` in a new task first, then pin all sibling packages to current `main`;
      2. put the feature on a Multitool branch before b4e34f0.
    - test: not run.
    - commit: none. The working tree on `main` went back to HEAD so that `main` stays green. `CodeModeTests.swift` is the same as on `wip/qjfsmrp-multitool` (931b3ea). The `Package.swift` change to make again: a `let multitoolPackage = "FoundationModelsMultitool"`, `.package(url: "\(swissArmyHammerOrg)\(multitoolPackage).git", branch: "main")`, and `.product(name: multitoolPackage, package: multitoolPackage)` in the test target only.
    - review: not run.
  timestamp: 2026-10-08T14:13:55.414945+00:00
- actor: claude-code
  id: 01m4dznpmw2w0amb6g34y11pmq
  text: |-
    Root unit test done.
    - Package.swift: `multitoolPackage` constant, `.package(url: "\(swissArmyHammerOrg)\(multitoolPackage).git", branch: "main")`, product only in the test target.
    - `swift package resolve` (no `swift package update`) picked the current origin/main of each sibling. No manual pin edit was necessary: Multitool 24f65ed, CodeContext 97caa23, Router 85b96f3, Extras 5c1c638, MetadataRegistry 858f5da, Ranker 6156346.
    - `swift build --build-tests`: only the accepted warning `missing creator for mutated node`. The Multitool runtime log line `schema element widened to any` for `args.variables` is a test log line, not a build warning.
    - CodeModeTests.swift restored from wip 931b3ea and changed: the script returns the two mutation responses whole, so a GraphQL error is an assertion failure, not a JS TypeError. The test also checks the log: the last event of the task sets `column` to `doing` (reuses `CrossRepoWriteTests.events(ofTask:inRepoAt:)` and `doingSlug`).
    - TDD: the test passed at once, because the behavior is already in Multitool 24f65ed and KanbanTool. To prove that it can fail, I made one temporary mutation in `KanbanArguments.decodedVariables` (refuse the string form). RED: `CodeModeTests.swift:77 Expectation failed: Self.dataField("moveTask", of: result["moved"])` with `INVALID_VARIABLES`. Mutation reverted (Sources has no diff), GREEN.
  timestamp: 2026-10-08T14:46:27.228250+00:00
- actor: claude-code
  id: 01m4e02ts0xc90za7a5y0qwm5g
  text: |-
    BLOCKER: the on-device model does not make the string form of `variables`. A person must decide.

    What I did:
    - IntegrationTests/Package.swift: added Multitool (`multitoolPackageName`, `.package(url: "\(swissArmyHammerOrg)\(multitoolPackageName).git", branch: "main")`, product in the test target). Reason: SwiftPM does not resolve the test-only dependencies of the `..` path package, so before this change the IntegrationTests graph had no Multitool, CodeContext or Router. After `swift package resolve`, IntegrationTests/Package.resolved has the same pins as the root (no identity and no state differs). Note for review: the test target links the Multitool product but no file imports it; the link only stops the SwiftPM "dependency is not used by any target" warning.
    - New test `IntegrationTests/Tests/FoundationModelsKanbanIntegrationTests/ModelVariablesTests.swift`: a real `LanguageModelSession(tools: [KanbanTool(graph:)])` in a `TemporaryGitRepo`. The prompt gives the document `mutation($title: String!) { addTask(input: { title: $title }) { id title } }` and the value of `title`. It does not tell the model how to send the variables. Gate: `.enabled(if: SystemLanguageModel.default.availability == .available, "...")`, the same availability check as the Multitool bare-session scenarios. The test requires a `kanban` call whose `variables` is a string that holds the title, and then that the board has the task.

    Result: the on-device model IS available on this machine, and the test ran. In 3 of 3 runs (one with the temporary decode mutation, two on the true code) the model sent:
    `{"query": "mutation($title: String!) { addTask(input: { title: $title }) { id title } }", "variables": {}}`
    Failure: `ModelVariablesTests.swift:102: Expectation failed: Self.variablesText(of: call.arguments)`.
    The model picks the empty-object choice of the `anyOf`, not the string choice. Thus the premise of plan.md §7.1 ("The guide of the string choice asks the model for one JSON object in text") does not hold for this model. Also: the SDK has no description on a plain `DynamicGenerationSchema(type: String.self)` (only `guides`), so the description is on the `anyOf` node, as in the code now. The plan text "a string schema, with the guide ..." cannot be written more exactly.

    Decision for a person, one of:
    1. Change the schema of `variables` (plan.md §7.1), for example only a string for the model. Then Multitool rejects a JS object from a script, because the schema has a `type` again, and the decision 2 on this card (a script can give an object) breaks. Multitool could then need a change.
    2. Accept that the model sends `{}` and puts the values in the document, or sends the string form only when the prompt asks for it. Then the model test must check a different behavior, and plan.md §7.1 and §12 item 10 change.
    3. Change the tool description or the property description so that the model picks the string choice, and measure it again with this test. This is a product change outside this card, and the result of the model is not sure.
    4. Remove the model test from this card and record the measured behavior.

    Root unit work is complete and green: Package.swift (Multitool test dependency), Package.resolved (Multitool 24f65ed, CodeContext 97caa23, Router 85b96f3 and the current main of Extras, MetadataRegistry, Ranker, all by `swift package resolve`), CodeModeTests.swift. The three acceptance criteria are ticked.
  timestamp: 2026-10-08T14:53:37.440579+00:00
- actor: claude-code
  id: 01m4e02zgmhswk8r8dz5fb4243
  text: |-
    ### implement — stuck
    - evidence: Package.swift, Package.resolved, Tests/FoundationModelsKanbanTests/Multitool/CodeModeTests.swift, IntegrationTests/Package.swift, IntegrationTests/Package.resolved, IntegrationTests/Tests/FoundationModelsKanbanIntegrationTests/ModelVariablesTests.swift. Sources has no diff. Pins (root = IntegrationTests): Multitool 24f65ed, CodeContext 97caa23, Router 85b96f3, Extras 5c1c638, MetadataRegistry 858f5da, Ranker 6156346. Root: `swift build --build-tests` OK (only the accepted `missing creator` warning); `swift test --skip-build` 3 of 3 runs, 965 tests in 68 suites pass. IntegrationTests: `swift build --build-tests && swift test` — smoke test pass, ModelVariablesTests fail (`ModelVariablesTests.swift:102`, the model sent `"variables": {}`). The on-device model is available and the model test ran.
    - next: a person chooses one of the 4 options in the blocker comment. Then implement continues with the model test.
  timestamp: 2026-10-08T14:53:42.292344+00:00
- actor: claude-code
  id: 01m4e0ws9e323qgq7rhws3s0cp
  text: |-
    ### Decision from the user (2026-10-08)
    - The model test uses Qwen 3.8, not the Apple on-device `SystemLanguageModel`. It stays an integration test in `IntegrationTests/`.
    - Reason found: with the on-device model, guided generation picked the `anyOf` object branch (an object with no properties) and sent `"variables": {}` in 3 of 3 runs.
  timestamp: 2026-10-08T15:07:47.886352+00:00
- actor: claude-code
  id: 01m4e10z6h92fbpmfp82r48k93
  text: |-
    Research for the Qwen 3.8 model test.
    - Model id: `mlx-community/Qwen3.8-27B-mxfp4`. The siblings use this id: Router `IntegrationTests/.../Qwen38ToolAnswerIntegrationTests.swift` and `Support/Qwen38ResidentModel.swift`, Multitool `IntegrationTests/.../Support/LiveRouterFixture.swift` (`generationModel`), ACPAgent `AgentConfiguration.defaultStandard`. No sibling uses a different "Qwen 3.8" id (the other hit, `mlx-community/Qwen3.8-27B-4bit`, is only in a plan note, "never driven").
    - Load path with no Router: Extras `PooledModel(ref:pool:)` is a FoundationModels `LanguageModel`. `LanguageModelSession(model: PooledModel(...), tools:)` loads the model on the first generation call through `ModelPool` and `MLXModelLoader`. Multitool b4e34f0 uses the same type (`RouterDiscoverySeams.pooledModel(of:)`), and Extras `IntegrationTests/.../PooledModelIntegrationTests.swift` and `Support/ToolSession.swift` run `LanguageModelSession(model:tools:)` this way.
    - MLX: `qwen3_5` is in `MLXLLM` `LLMModelFactory`, which Extras links. Extras `MetalLibraryBootstrap` links `mlx.metallib` beside the test binary. CI already gives `integration-metallib-glob: "*Cmlx*/default.metallib"` in `.github/workflows/ci.yml`.
    - Cache: `HubCache.default`, `~/.cache/huggingface/hub/models--mlx-community--Qwen3.8-27B-mxfp4`. On this machine it is present, 14 GB (3 safetensors files). No download is necessary.
    - Gate and time limit: the siblings do not skip a real-model test. Extras `ModelAvailability.requireMetalDevice()` fails the test with `#require(MTLCreateSystemDefaultDevice() != nil)`, "A skip gives a green run that measured nothing". Each real-model suite has a `.timeLimit` (Extras 10 min, Multitool `IntegrationHangGuard` 30 min) and runs serialized. Extras uses greedy sampling with a named `maximumResponseTokens`.
    - IntegrationTests/Package.swift needs the `FoundationModelsExtras` product, declared by the same URL and branch as the root. The Multitool product of the last iteration is not imported by a file, so it is removed (the Qwen path does not need it).
  timestamp: 2026-10-08T15:10:05.009399+00:00
- actor: claude-code
  id: 01m4e1cgsjv9tc44k57c6jn2nd
  text: |-
    ### implement — changed
    - evidence:
      - Files: IntegrationTests/Package.swift (the `FoundationModelsExtras` product, same URL and branch as the root, replaces the Multitool product that no file imported), IntegrationTests/Package.resolved (now differs from HEAD only by `originHash`; every pin equals the root pin, the Multitool, CodeContext and Router subtree is not in this graph), IntegrationTests/Tests/FoundationModelsKanbanIntegrationTests/ModelVariablesTests.swift (rewritten for Qwen 3.8). Root Package.swift, Package.resolved and CodeModeTests.swift are not changed in this iteration.
      - Model: `mlx-community/Qwen3.8-27B-mxfp4`, `LanguageModelSession(model: PooledModel(ref:pool: ModelPool()), tools: [KanbanTool(graph:)])`, greedy sampling, 4096 response tokens. `MLXModelLoader` loads it from `~/.cache/huggingface/hub/models--mlx-community--Qwen3.8-27B-mxfp4` (14 GB, present, no download). Gate: `#require(MTLCreateSystemDefaultDevice() != nil)`, no skip (Extras pattern). Hang guard `.timeLimit(.minutes(30))` (Multitool `IntegrationHangGuard` value).
      - The check accepts the string form or an object, and requires `variables.title == "Write the release notes"`, and the task on the board.
      - Mutation proof: the check over `{"variables": {}}` fails with `GeneratedContent does not contain a property 'title'. Content: {}`. Reverted.
      - Model run 1: `"variables": "{\"title\": \"Write the release notes\"}"`, pass, 11.7 s (test), 19.9 s (process).
      - Model run 2: `"variables": "{\"title\": \"Write the release notes\"}"`, pass, 8.2 s (test), 13.5 s (process).
      - Model run 3 (full `swift build --build-tests && swift test` in IntegrationTests): `"variables": "{\"title\": \"Write the release notes\"}"`, pass, 8.2 s (test); smoke test pass; 2 tests in 2 suites passed.
      - Root: `swift build --build-tests` OK, only the accepted `missing creator for mutated node` warning. `swift test --skip-build` 3 runs, each exit 0 in about 13 s; runs 2 and 3 report 965 tests in 68 suites passed.
    - New task ^qg3rt2m: plan.md §7.1 and §12 item 8, and the `KanbanArguments` doc comment, still name the on-device model for this test.
    - next: /review.
  timestamp: 2026-10-08T15:16:23.474550+00:00
depends_on:
- 01M4DPPYA338NYS7JAA7J3AAR6
- 01M4DYAT2V3CEKMMZ8SBHJSNMM
position_column: doing
position_ordinal: '80'
title: 'Multitool proof: code mode end to end'
---
## What
Prove that the tool works in code mode. The basis is plan.md §9 and §10 step 18.
- Add `FoundationModelsMultitool` as a test dependency (by URL, the same as the other siblings).
- `Tests/FoundationModelsKanbanTests/Multitool/CodeModeTests.swift`: register `KanbanTool(graph:)` in a `MultiTool.Builder`, and run a `runCode` script that adds a task, reads `nextTask`, and moves the task to `doing`. The script passes `variables` once as an object and once as a JSON string (the plan.md §9 example script).
- A second test with a real `LanguageModelSession` checks that the on-device model makes the string form of `variables` for a document with variables. Mark it so that it runs only when the on-device model is available (a Swift Testing trait), and reports as skipped with a reason otherwise.

## Acceptance Criteria
- [x] The script gets `result.data.board.nextTask` as a structured value.
- [x] Both `variables` forms work through Multitool, which passes the object through because the schema has `anyOf` and no `type`.
- [x] After the script, the task is in `doing` in the log.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Multitool/CodeModeTests.swift`.
- [x] Run `swift test --filter CodeModeTests`; expect all pass (the model test is skipped only when the model is not available).

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.