---
depends_on:
- 01M4B3V22A3PCQRESESTYBQ2FH
position_column: todo
position_ordinal: '8380'
title: 'Identity: BoardKey from git origin'
---
## What
Calculate the board key of a repo. The basis is plan.md §3.2 and §12 item 4.
- `Sources/FoundationModelsKanban/Identity/BoardKey.swift`: read the current `origin` URL of a repo directory (run `git config --get remote.origin.url`, or read `.git/config`; a worktree has a `.git` file that points to the real git dir).
- Normalize SSH (`git@host:owner/repo.git`), HTTPS (`https://host/owner/repo.git`), and `ssh://` forms to `host/owner/repo`. Remove `.git`, and use lowercase for the host.
- No remote: `local/<directory-name>`.
- The key is never stored. Each call that opens a board reads it.

## Acceptance Criteria
- [ ] SSH, HTTPS, and `ssh://` forms of one remote give the same key.
- [ ] A repo with no remote gives `local/<directory-name>`.
- [ ] A git worktree gives the same key as its main clone.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift`: pure normalization cases, plus temporary git repos (made with `git init`, `git remote add`, `git worktree add`).
- [ ] Run `swift test --filter BoardKeyTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.