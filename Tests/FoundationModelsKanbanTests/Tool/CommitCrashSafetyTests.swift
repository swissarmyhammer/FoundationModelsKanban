import Foundation
import Synchronization
import Testing

@testable import FoundationModelsKanban

/// Tests the write side of the crash safety of a transaction on many files (divergence.md Q23, S5): each line of a
/// commit records the sorted local refs of the files that the transaction wrote in its board, and the commit appends
/// to each of these files. The fsync of each line is the work of ``EventLog/append(contentsOf:toLogOf:)``.
///
/// Each test writes the board fixture to a temporary folder. No test reads the `.kanban/` folder of this repo.
@Suite("Commit crash safety: file refs and appended files", .watcherBudget)
struct CommitCrashSafetyTests {
    /// Runs one call of a session that sets ``CommitTests/callTitle`` on each of some tasks, one mutation field for
    /// each task.
    ///
    /// - Parameters:
    ///   - tasks: The local refs of the tasks.
    ///   - session: The commit session.
    static func setCallTitle(of tasks: [LocalRef], in session: inout CommitSession) async throws {
        try await session.run { store in
            for task in tasks {
                try await CommitTests.setTitle(CommitTests.callTitle, of: task, as: CommitTests.firstOperation, in: store)
            }
        }
    }

    // MARK: - File refs

    @Test("Each line of a call that writes two files of the board records the sorted refs of the two files")
    func linesOfTwoFilesRecordBothRefs() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try CommitTests.writeBoard(in: directory)
        var session = try await CommitTests.makeSession(of: log)
        let written = [tasks[0], tasks[1]]
        try await Self.setCallTitle(of: written, in: &session)
        let events = try written.flatMap { task in try CommitTests.callEvents(of: task, in: log) }
        #expect(events.count == written.count)
        #expect(events.map(\.files) == Array(repeating: .named(written), count: events.count))
    }

    @Test("Each line of a call that writes one file records the ref of the one file")
    func linesOfOneFileRecordOneRef() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try CommitTests.writeBoard(in: directory)
        var session = try await CommitTests.makeSession(of: log)
        try await session.run { store in
            try await CommitTests.setTitle(CommitTests.callTitle, of: tasks[0], as: CommitTests.firstOperation, in: store)
            try await CommitTests.setTitle(
                CommitTests.laterCallTitle,
                of: tasks[0],
                as: CommitTests.secondOperation,
                in: store
            )
        }
        let events = try CommitTests.callEvents(of: tasks[0], in: log)
        #expect(events.map(\.patch) == (try CommitTests.callTitlePatches(of: tasks[0])))
        #expect(events.map(\.files) == Array(repeating: .named([tasks[0]]), count: events.count))
    }

    @Test("The live graph after a commit holds the events with their file refs, the same as a fresh load")
    func liveEventsHoldFileRefs() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try CommitTests.writeBoard(in: directory)
        var session = try await CommitTests.makeSession(of: log)
        let written = [tasks[0], tasks[1]]
        try await Self.setCallTitle(of: written, in: &session)
        let liveCallEvents = session.live.events.filter { event in event.at == CommitTests.callTime }
        #expect(liveCallEvents.map(\.files) == Array(repeating: .named(written), count: written.count))
        try await LiveGraphApplyTests.expectEqualToFreshLoad(session.live, of: log)
    }

    // MARK: - Appended files

    @Test("A commit appends to each file that it writes, and to no other file")
    func commitAppendsToEachWrittenFile() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try CommitTests.writeBoard(in: directory)
        let writer = RecordingLogWriter()
        var session = try await CommitTests.makeSession(of: log, writingWith: writer)
        let written = [tasks[0], tasks[1]]
        try await Self.setCallTitle(of: written, in: &session)
        #expect(Set(writer.appendedFiles) == Set(written.map(log.fileURL(for:))))
    }

    @Test("A commit on two boards appends to the files of both boards")
    func twoBoardCommitAppendsToBothBoards() async throws {
        let directory = try TemporaryDirectory()
        let app = try CommitRollbackTests.makeRepo(named: CommitRollbackTests.appName, in: directory)
        let lib = try CommitRollbackTests.makeRepo(named: CommitRollbackTests.libName, in: directory)
        let writer = RecordingLogWriter()
        let graph = try KanbanGraphTests.makeGraph(
            at: app,
            readingKeyWith: CommitRollbackTests.directoryKey(ofRepoAt:),
            writingLogsWith: writer
        )
        let response = try await KanbanGraphTests.execute(CommitRollbackTests.twoBoardCall, on: graph)
        await graph.close()
        #expect(try CrossRepoWriteTests.hasNoErrors(response))
        let boards = Set(
            writer.appendedFiles.map { file in file.deletingLastPathComponent().resolvingSymlinksInPath().path }
        )
        let libDirectory = EventLog(repositoryAt: lib).directory.resolvingSymlinksInPath().path
        #expect(boards.contains { path in path.hasPrefix(libDirectory) })
        #expect(boards.contains { path in !path.hasPrefix(libDirectory) })
    }
}

// MARK: - Recording writer

/// A log writer for tests: it writes each append through ``FileEventLogWriter``, and records the file of each one, in
/// order.
///
/// The type is a class, because all sessions of one engine share its record.
final class RecordingLogWriter: EventLogWriter {
    /// The log file of each append, in order.
    private let files = Mutex<[URL]>([])

    /// The log file of each append, in order.
    var appendedFiles: [URL] {
        files.withLock { files in files }
    }

    /// Appends the events, and records the file.
    ///
    /// - Parameters:
    ///   - events: The events.
    ///   - ref: The local ref of the node.
    ///   - log: The event log of the board.
    /// - Throws: The error of the file writer.
    func append(contentsOf events: [Event], toLogOf ref: LocalRef, in log: EventLog) throws(EventLogError) {
        try FileEventLogWriter().append(contentsOf: events, toLogOf: ref, in: log)
        let file = log.fileURL(for: ref)
        files.withLock { files in files.append(file) }
    }
}
