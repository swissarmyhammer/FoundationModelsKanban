import Foundation
import Synchronization
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the write side of the crash safety of a transaction on many files (divergence.md Q23, S5): each line of a
/// commit records the sorted local refs of the files that the transaction wrote in its board, and the commit calls
/// fsync on each file that it appended to, after all appends of the transaction.
///
/// Each test writes the board fixture to a temporary folder. No test reads the `.kanban/` folder of this repo.
@Suite("Commit crash safety: file refs and fsync", .watcherBudget)
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

    /// Checks that each file of the appends of a writer is synchronized one time, and that each synchronize comes
    /// after the last append.
    ///
    /// - Parameter steps: The steps of the writer, in order.
    static func expectEachAppendedFileSynchronizedAfterAppends(_ steps: [RecordingLogWriter.Step]) throws {
        let appended = steps.filter { step in step.kind == .append }.map(\.file)
        let synchronized = steps.filter { step in step.kind == .synchronize }.map(\.file)
        #expect(!appended.isEmpty)
        #expect(Set(synchronized) == Set(appended))
        #expect(synchronized.count == Set(appended).count)
        let lastAppend = try #require(steps.lastIndex { step in step.kind == .append })
        let firstSynchronize = try #require(steps.firstIndex { step in step.kind == .synchronize })
        #expect(lastAppend < firstSynchronize)
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

    // MARK: - fsync

    @Test("A commit synchronizes each file that it appended to, after the last append")
    func commitSynchronizesEachAppendedFile() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try CommitTests.writeBoard(in: directory)
        let writer = RecordingLogWriter()
        var session = try await CommitTests.makeSession(of: log, writingWith: writer)
        let written = [tasks[0], tasks[1]]
        try await Self.setCallTitle(of: written, in: &session)
        let steps = writer.steps
        try Self.expectEachAppendedFileSynchronizedAfterAppends(steps)
        #expect(Set(steps.map(\.file)) == Set(written.map(log.fileURL(for:))))
    }

    @Test("A commit on two boards synchronizes each file of both boards, after the last append of both boards")
    func twoBoardCommitSynchronizesEachFile() async throws {
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
        let steps = writer.steps
        try Self.expectEachAppendedFileSynchronizedAfterAppends(steps)
        let boards = Set(steps.map { step in step.file.deletingLastPathComponent().resolvingSymlinksInPath().path })
        let libDirectory = EventLog(repositoryAt: lib).directory.resolvingSymlinksInPath().path
        #expect(boards.contains { path in path.hasPrefix(libDirectory) })
        #expect(boards.contains { path in !path.hasPrefix(libDirectory) })
    }

    @Test("A synchronize of a log file that is not there gives a file system error")
    func synchronizeOfMissingFileFails() throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let task = LocalRef.task(ULID())
        let error = #expect(throws: EventLogError.self) { try log.synchronize(logOf: task) }
        #expect(Self.fileSystemPath(of: error) == log.fileURL(for: task).path)
    }

    /// Gives the path of a ``EventLogError/fileSystem(path:detail:)`` error.
    ///
    /// - Parameter error: The error.
    /// - Returns: The path, or `nil` for no error or a different error.
    static func fileSystemPath(of error: EventLogError?) -> String? {
        switch error {
        case .fileSystem(let path, _)?: path
        default: nil
        }
    }
}

// MARK: - Recording writer

/// A log writer for tests: it writes each append and each synchronize through ``FileEventLogWriter``, and records
/// the file of each one, in order.
///
/// The type is a class, because all sessions of one engine share its record.
final class RecordingLogWriter: EventLogWriter {
    /// One call of the writer.
    struct Step: Hashable, Sendable {
        /// The kind of a call.
        enum Kind: Hashable, Sendable {
            /// An append of lines to a log file.
            case append

            /// An fsync of a log file.
            case synchronize
        }

        /// The kind of the call.
        let kind: Kind

        /// The log file of the call.
        let file: URL
    }

    /// The calls of the writer, in order.
    private let calls = Mutex<[Step]>([])

    /// The calls of the writer, in order.
    var steps: [Step] {
        calls.withLock { steps in steps }
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
        record(.append, of: ref, in: log)
    }

    /// Synchronizes the log file, and records the file.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - log: The event log of the board.
    /// - Throws: The error of the file writer.
    func synchronize(logOf ref: LocalRef, in log: EventLog) throws(EventLogError) {
        try FileEventLogWriter().synchronize(logOf: ref, in: log)
        record(.synchronize, of: ref, in: log)
    }

    /// Records one call.
    ///
    /// - Parameters:
    ///   - kind: The kind of the call.
    ///   - ref: The local ref of the node of the file.
    ///   - log: The event log of the board.
    private func record(_ kind: Step.Kind, of ref: LocalRef, in log: EventLog) {
        let step = Step(kind: kind, file: log.fileURL(for: ref))
        calls.withLock { steps in steps.append(step) }
    }
}
