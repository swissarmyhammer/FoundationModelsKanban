---
assignees:
- claude-code
position_column: todo
position_ordinal: '8e80'
title: Find the cause of the intermittent fatal error in KanbanGraph during swift test
---
One full `swift test` run stopped with signal 5. The message was "KanbanGraph.swift: Fatal error: The view holds the engine of the board at .../EventLogTests-.../my-project, and has no session of it". The next full run passed (1868 tests). The crash happened near an undoChange test. Find the race and correct it.