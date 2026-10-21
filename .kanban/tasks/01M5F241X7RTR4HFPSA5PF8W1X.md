---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f3wevvk6t8jk1876aaxc6g
  text: |-
    ### Update from foundationmodelsmultitool-bc (2026-10-21)
    EXTRAS-10 is on FoundationModelsExtras origin/main: the code commit is f126153 and the tip is 11ffe56. To finish this task, run `swift package update FoundationModelsExtras`, check that Package.resolved points at 11ffe56 or later, and confirm that the full suite still builds and passes.

    The API, all in Sources/FoundationModelsExtras/GraphQL/:
    - `actor ChangeLog<Event>`: `init(capacity: Int = 1024)`, `append(_:)`, `cursor`, and `changes(after:where:)`. Each stream element is a `ChangeLogEntry<Event> { cursor: String, at: Date, event }`. `changes(after: nil)` gives only live events.
    - Codes: `GraphQLToolkitError.notFound(kind:id:)` gives NOT_FOUND, and `.resyncRequired(reason:)` gives RESYNC_REQUIRED.
    - `ChangedIDs` and `IDChange` in IDChange.swift (optional helpers).

    Behaviour changes:
    - In GraphQLRun.swift, a `subscribe` stream that throws a coded error sends one final `{"errors":[…]}` with extensions.code, and then ends normally.
    - A live subscriber that is more than `capacity` events behind gets RESYNC_REQUIRED.
  timestamp: 2026-10-21T11:34:59.195231+00:00
- actor: claude-code
  id: 01m5f4a4rg0yj490p778cvtpjx
  text: |-
    ### Implementation notes
    - `swift package update FoundationModelsExtras` FAILS on this toolchain (Swift 6.4): `error: exhausted attempts to resolve the dependencies graph ... unresolved: 'swift-case-paths'`. Cause: swift-parsing 0.15.2 has a trait-conditional dependency on swift-case-paths (`condition: .when(traits: ["CasePaths"])`), and kanban disables it with `traits: []`; the partial update resolver does not honour that. Extras itself does not depend on swift-parsing. Workaround that works: set the Extras pin revision in Package.resolved to 11ffe56014d81bcec75a8244c8e82cd7f4197014 (= origin/main tip, checked with git ls-remote) and run `swift package resolve`; it accepts the pin, changes nothing else, and checks out 11ffe56.
    - Same pin change in IntegrationTests/Package.resolved, then `swift package --package-path IntegrationTests resolve`; checkout at 11ffe56.
    - Breakage: the library compiles unchanged. One test file broke: Tests/FoundationModelsKanbanTests/Tool/AgentPlanPostTests.swift imports both FoundationModelsExtras and `@testable FoundationModelsKanban`, and Extras now exports a public `DateTime` that collides with kanban's internal `DateTime` ("'DateTime' is ambiguous for type lookup"). Fixed by qualifying the two uses as `FoundationModelsKanban.DateTime`. No other test file imports Extras and uses a colliding name (checked DateTime, CodedError, ChangeLog, ChangeLogEntry, GraphQLToolkitError, ChangedIDs, IDChange). The toolkit migration (^jk3fc4g) is not done here.
    - Verified the Extras source at 11ffe56: `public actor ChangeLog<Event>` with `init(capacity:)`, `append(_:)`, `cursor`, `changes(after:where:)`, random epoch per instance; `GraphQLToolkitError.notFound(kind:id:)` -> NOT_FOUND and `.resyncRequired(reason:)` -> RESYNC_REQUIRED in GraphQL/CodedError.swift.
    - Build: `swift build --build-tests` clean (only SwiftPM's "missing creator for mutated node" mlx bundle notice). `swift build --package-path IntegrationTests --build-tests` clean apart from third-party mlx-swift C++17 warnings and the same notice. `swift test`: 1703 tests in 140 suites passed.
  timestamp: 2026-10-21T11:42:27.600554+00:00
- actor: claude-code
  id: 01m5f4a8pdykxna2dswccejnht
  text: |-
    ### implement — changed
    - evidence: 3 files — Package.resolved, IntegrationTests/Package.resolved (Extras pin 5c1c638 -> 11ffe56014d81bcec75a8244c8e82cd7f4197014), Tests/FoundationModelsKanbanTests/Tool/AgentPlanPostTests.swift (2 uses qualified as FoundationModelsKanban.DateTime). swift build --build-tests: clean; IntegrationTests build: clean; swift test: 1703 tests / 140 suites passed.
    - next: /test, then /review. Task left in doing; not committed.
  timestamp: 2026-10-21T11:42:31.629993+00:00
- actor: claude-code
  id: 01m5f4dd40ef2dja1evck56wbp
  text: |-
    ### test — green
    - evidence: `swift test` in FoundationModelsKanban — 1703 tests in 140 suites passed, 0 failed, 0 skipped. No compiler warnings in package code. The only `warning:` line is the build tool's "missing creator for mutated node" on the third-party mlx-swift_Cmlx.bundle (out of scope). Other "warning" lines are expected runtime log output from the "Replay skips a log line that does not decode" tests.
    - scope: the uncommitted change (FoundationModelsExtras bump to 11ffe56, DateTime qualified in AgentPlanPostTests.swift) built and passed with no edits. IntegrationTests were not run.
    - next: review/commit
  timestamp: 2026-10-21T11:44:14.464066+00:00
- actor: claude-code
  id: 01m5f4gph4n80c0y2v37jfem2a
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (91c116c): 0 findings, 0 confirmed, 0 refuted; 7 validator runs attempted, 0 failed. Reviewed 1 file (Tests/.../Tool/AgentPlanPostTests.swift). Not reviewed: 14 .kanban/ files (.reviewignore), and IntegrationTests/Package.resolved and Package.resolved (no validator matches them). No earlier Review Findings sections. The "Tests: none here; the KANBAN-7 task covers them" box is satisfied by design, as the caller said.
    - next: task moved to done; KANBAN-7 (^e60e9sx) is unblocked
  timestamp: 2026-10-21T11:46:02.404644+00:00
- actor: claude-code
  id: 01m5f4h1rfke5xvedh7q2ymkkw
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files (both Package.resolved → Extras 11ffe56, DateTime qualified in AgentPlanPostTests)
    - test: green — swift test, 1703 tests / 140 suites passed
    - commit: 91c116c
    - review: clean — none
  timestamp: 2026-10-21T11:46:13.903603+00:00
position_column: done
position_ordinal: ffa880
title: 'External gate: EXTRAS-10 ChangeLog and NOT_FOUND/RESYNC_REQUIRED land in FoundationModelsExtras main'
---
## What
Gate task with no code in this repo. KANBAN-7 (e60e9sx) must use `ChangeLog<Event>` and the toolkit codes `NOT_FOUND` and `RESYNC_REQUIRED` from EXTRAS-10 (TestudoApp/features/packages/foundationmodels-extras.md, EXTRAS-9 rev 2). As of 2026-10-21, EXTRAS-10 has no owner; the Multitool session (foundationmodelsmultitool-bc) is raising this with the user.

The agreed shape (EXTRAS-9 rev 2): the cursor is opaque (`String`), and ChangeLog has a random epoch per instance. A cursor that is too old, comes from another epoch, or is after the newest event gives `RESYNC_REQUIRED`. `ChangeLog.changes(after:where:)` filters per subscriber after the replay and keeps the order.

Complete this task when Extras main has ChangeLog with that API and the two codes.

## Acceptance Criteria
- [x] Extras main has ChangeLog (`append`, `cursor`, `changes(after:where:)`, epoch) and the NOT_FOUND / RESYNC_REQUIRED codes
- [x] Package.resolved in this repo is updated to that Extras commit

## Tests
- [ ] None here; the KANBAN-7 task covers them