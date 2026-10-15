---
assignees:
- claude-code
position_column: todo
position_ordinal: b480
title: Make the first commit that the engine makes unique for each repo, so two new repos never get the same board key
---
## What
divergence.md M7 and M8: the board key is `local/<root commit>`. When a repo has no commit, the engine makes an empty first commit.

The ^rs0bhrb integration test found a real problem. Two new repos that the engine sets up in the same second get empty first commits with the same author, message, and time. Thus the two commits have the same hash, and the two boards get the same key. A board then treats a task of the other board as its own, and a cross-board ref gives `NOT_FOUND`.

The test fixture now makes its own unique first commit (`IntegrationTests/.../Support/TemporaryGitRepo.swift`). The engine code still has the problem. This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

## Acceptance Criteria
- [ ] The empty first commit that the engine makes has content that is different for each repo (for example, the message includes the repo folder name or a new ULID), so two repos never share a root commit hash.
- [ ] Two new repos that the engine sets up in the same second get different board keys.

## Tests
- [ ] A test makes two repos with no commit at the same time, lets the engine make the first commits, and checks that the two board keys are different.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.