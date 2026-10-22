---
position_column: todo
position_ordinal: '80'
title: Write and read the event log through Extras JSONLFile (append mode, one line per write, fsync per line)
---
## What
The user decided (2026-10-22) that every `.jsonl` file in our packages is written and read through one Extras type, `JSONLFile`:
- It is append-only and opens the file in append mode.
- Each record goes out as one full line in a single unbuffered write, followed by an fsync.
- A removal is an appended tombstone record, never a rewrite. Readers fold the records so the last line for a key wins.

There is no backward compatibility (ARCHITECTURE.md), so the old code is replaced outright.

This waits on the FoundationModelsExtras `JSONLFile` card, 01M5HS4C6FBNTAX30161HP0BS5 on FoundationModelsRouter's board. Bump the Extras pin when it lands.

## Where
- `Sources/FoundationModelsKanban/Events/EventLog.swift` opens a FileHandle, seeks to the end and writes there (:138, :193-194, :203). Use `JSONLFile.append` instead, and read the log back with `JSONLFile` too.

## Subtasks
- [ ] Failing test first: an append only grows the file, and each line is fsynced
- [ ] Move EventLog onto JSONLFile and delete the seek-to-end handle code
- [ ] `swift test` passes, zero warnings #recording #cross-repo