---
assignees:
- claude-code
position_column: todo
position_ordinal: ad80
title: Use one FSEvents stream for each host, not one for each watched folder
---
## What
The test step of ^gz2mxwz measured the FSEvents stream limit with a scratch probe. The limit is for the whole system, not for one process. On this machine one process got only 36 streams before `FSEventStreamStart` failed. With a second probe that held 20 streams, a third probe got only 16. Other apps on the machine hold the rest.

Now the Swift package starts one FSEvents stream for each watched folder:
- one for each board engine (S/Tool/BoardEngine.swift);
- one for each scan place (S/CrossRepo/ScanCache.swift, ^3prjnb4);
- one for each board that cannot be read (^z4jcv8j).

A process with many ACP sessions and many related boards can thus run out of streams. Then a watcher does not start, and the board does not see manual edits. This breaks the user's rule "file watch detection to allow manual poking of files" (divergence.md §16).

Change: `KanbanHost` keeps one FSEvents stream for all the folders that it watches. `FSEventStreamCreate` takes an array of paths. When the set of folders changes (a board loads or closes, a scan place is added), make a new stream for the new set, start it, and then stop the old stream, so that no event is lost. Send each event to the engine, scan place, or unreadable board that owns its path.

Keep the current behavior for each owner: the same batches, the same full compare when events are lost, and the same event for a directory inside `.kanban/` (^qys059z).

## Acceptance Criteria
- [ ] A host with N boards, M scan places, and K unreadable boards uses one FSEvents stream (two for a short time while the set changes).
- [ ] Each owner still gets exactly the events for its own paths.
- [ ] A change in the set of folders loses no event.
- [ ] All existing watcher tests still pass.

## Tests
- [ ] A test that opens many boards and scan places and checks that the host holds one stream.
- [ ] A test that adds a board while another board gets a change, and checks that the change still arrives.
- [ ] A test that events for two boards go to the right engine.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.