---
depends_on:
- 01M4B3VF41P7FCKEC4MFT9GWA0
- 01M4B3VR0CTZWWGMDJBT7YF4W0
position_column: todo
position_ordinal: '8980'
title: 'Event model: envelope and PatchInput lines'
---
## What
The format of one log line. The basis is plan.md §5.1 and §12 item 28.
- `Sources/FoundationModelsKanban/Events/Event.swift`: `Event` with envelope fields `id`, `txn`, `ops`, `at`, `actor` (a local ref), `boards` (optional; the keys of the other boards only), `undoes` (optional), and `query` + `variables` (the full GraphQL request to the internal `patch` mutation).
- `PatchInput`: `node` (local ref), `type`, `set`, `unset`, `add`, `remove`, `delete`, `edit` (`{"body": "<unified diff>"}`). All refs in the stored form (`StoredRef`).
- Encode one event as one JSON line with sorted keys. Decode a line. A line that does not decode gives a typed error (the loader skips it later).
- No time value in a patch: `set` refuses the names `created`, `updated`, `deleted`, `started`, `completed`.

## Acceptance Criteria
- [ ] An event round-trips line → `Event` → line with the same bytes.
- [ ] The example line of plan.md §5.1 decodes.
- [ ] A line never holds the key of its own board (the encoder works only with `StoredRef`).

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Events/EventTests.swift`: round trip, the plan example, bad lines, the refused `set` names.
- [ ] Run `swift test --filter EventTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.