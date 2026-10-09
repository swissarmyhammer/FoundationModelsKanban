import Foundation
import Synchronization
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the rollback of a commit whose append fails (plan.md §5.4 step 5.5): no log file of a board keeps a part of
/// the transaction, no live graph changes, and the next call works normally.
///
/// Each test gives the commit a ``FaultingLogWriter``. The writer appends the lines of each append, and then it makes
/// one append fail. Thus the rollback must also remove the lines of the append that failed.
@Suite("Commit rollback: no part of a failed transaction stays on disk")
struct CommitRollbackTests {
    /// The number of the append that fails in a call that writes two node files of one board: the second append.
    static let secondAppend = 2

    /// The number of the first append to a board.
    static let firstAppend = 1

    /// The directory name of the current repo of the two-board tests.
    static let appName = "app"

    /// The directory name of the related repo of the two-board tests. The call names the related board with it.
    static let libName = "lib"

    /// The new name of the current board in the two-board call.
    static let newBoardName = "Port"

    /// The title of the task that the two-board call adds to the related board.
    static let libTaskTitle = "Port the lexer"

    /// The two-board call: it changes the current board first, and then it adds a task to the related board.
    static let twoBoardCall = """
        mutation {
            updateBoard(input: { name: "\(newBoardName)" }) { name }
            addTask(input: { board: "\(libName)", title: "\(libTaskTitle)" }) { id }
        }
        """

    // MARK: - Fixture

    /// Runs one call of a session, and expects the fault of the writer.
    ///
    /// - Parameters:
    ///   - session: The commit session.
    ///   - call: Runs the call against the store of the working copy.
    static func expectFault(
        running session: inout CommitSession,
        _ call: @Sendable (BoardStore) async throws -> Void
    ) async throws {
        do {
            try await session.run(call)
            Issue.record("The call did not give the fault of the writer")
        } catch let error as EventLogError {
            #expect(error == FaultingLogWriter.fault)
        }
    }

    /// Reads the key of a repo from the name of its directory, and does not run git.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The local key of the directory name.
    @Sendable
    static func directoryKey(ofRepoAt root: URL) -> BoardKey {
        BoardKey(localDirectoryName: root.lastPathComponent)
    }

    /// Makes a repo with a `.git` directory and the fixture logs of ``KanbanGraphTests``.
    ///
    /// - Parameters:
    ///   - name: The name of the repo directory.
    ///   - directory: The temporary directory that holds the repo.
    /// - Returns: The root directory of the repo.
    static func makeRepo(named name: String, in directory: TemporaryDirectory) throws -> URL {
        let root = directory.url.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: root.appending(path: BoardKey.gitDirectoryName, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        _ = try KanbanGraphTests.writeFixture(inRepoAt: root)
        return root
    }

    /// Makes the engine of the current repo of a two-board test. Its writer makes the first append to the related
    /// board fail.
    ///
    /// - Parameters:
    ///   - app: The root directory of the current repo.
    ///   - lib: The root directory of the related repo.
    /// - Returns: The engine.
    static func makeTwoBoardGraph(at app: URL, failingIn lib: URL) throws -> KanbanGraph {
        try KanbanGraphTests.makeGraph(
            at: app,
            readingKeyWith: directoryKey(ofRepoAt:),
            writingLogsWith: FaultingLogWriter(failingAppend: firstAppend, toBoardAt: lib)
        )
    }

    /// Runs the two-board call, and expects the fault of the writer.
    ///
    /// - Parameter graph: The engine of the current repo.
    static func expectTwoBoardFault(on graph: KanbanGraph) async throws {
        do {
            _ = try await KanbanGraphTests.execute(twoBoardCall, on: graph)
            Issue.record("The call did not give the fault of the writer")
        } catch let error as EventLogError {
            #expect(error == FaultingLogWriter.fault)
        }
    }

    /// Gives the signature of each node file of a repo.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The signatures, by local ref.
    static func signatures(ofRepoAt root: URL) throws -> [LocalRef: FileSignature] {
        try EventLog(repositoryAt: root).nodeFileSignatures()
    }

    // MARK: - One board

    @Test("When the second append fails, no log file changes and the live graph and signatures stay the same")
    func failedSecondAppendChangesNothing() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try CommitTests.writeBoard(in: directory)
        let writer = FaultingLogWriter(failingAppend: Self.secondAppend)
        var session = try await CommitTests.makeSession(of: log, writingWith: writer)
        let before = try log.nodeFileSignatures()
        try await Self.expectFault(running: &session) { store in
            try await CommitTests.setTitle(CommitTests.callTitle, of: tasks[0], as: CommitTests.firstOperation, in: store)
            try await CommitTests.setTitle(CommitTests.callTitle, of: tasks[1], as: CommitTests.secondOperation, in: store)
        }
        #expect(writer.appendCount == Self.secondAppend)
        #expect(try log.nodeFileSignatures() == before)
        #expect(session.live.signatures == before)
        #expect(try CommitTests.title(of: tasks[0], in: session) == tasks[0].description)
        #expect(try CommitTests.callEvents(of: tasks[0], in: log).isEmpty)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(session.live, of: log)
    }

    @Test("When the append to a new node file fails, the file does not exist after the call")
    func failedAppendToNewFileRemovesFile() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try CommitTests.writeBoard(in: directory)
        var session = try await CommitTests.makeSession(
            of: log,
            writingWith: FaultingLogWriter(failingAppend: Self.secondAppend)
        )
        let newTask = LocalRef.task(ULID(timestamp: ReplayTests.date(atStep: CommitTests.callStep)))
        let before = try log.nodeFileSignatures()
        try await Self.expectFault(running: &session) { store in
            try await CommitTests.setTitle(CommitTests.callTitle, of: tasks[0], as: CommitTests.firstOperation, in: store)
            try await CommitTests.setTitle(CommitTests.callTitle, of: newTask, as: CommitTests.secondOperation, in: store)
        }
        #expect(!FileManager.default.fileExists(atPath: log.fileURL(for: newTask).path))
        #expect(try log.nodeFileSignatures() == before)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(session.live, of: log)
    }

    @Test("After a failed commit, the next call commits in its first run and sees no part of the failed transaction")
    func nextCallAfterFailureWorks() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try CommitTests.writeBoard(in: directory)
        var session = try await CommitTests.makeSession(
            of: log,
            writingWith: FaultingLogWriter(failingAppend: Self.secondAppend)
        )
        try await Self.expectFault(running: &session) { store in
            try await CommitTests.setTitle(CommitTests.callTitle, of: tasks[0], as: CommitTests.firstOperation, in: store)
            try await CommitTests.setTitle(CommitTests.callTitle, of: tasks[1], as: CommitTests.secondOperation, in: store)
        }
        let runs = Mutex(0)
        try await session.run { store in
            CommitTests.countRun(in: runs)
            try await CommitTests.setTitle(
                CommitTests.laterCallTitle,
                of: tasks[0],
                as: CommitTests.firstOperation,
                in: store
            )
        }
        let laterPatch = try ReplayTests.titlePatch(setting: CommitTests.laterCallTitle, of: tasks[0])
        #expect(runs.withLock { count in count } == 1)
        #expect(try CommitTests.callEvents(of: tasks[0], in: log).map(\.patch) == [laterPatch])
        #expect(try CommitTests.callEvents(of: tasks[1], in: log).isEmpty)
        #expect(try CommitTests.title(of: tasks[1], in: session) == tasks[1].description)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(session.live, of: log)
    }

    // MARK: - Two boards

    @Test("When the append of board 2 fails, no file of either board changes, and board 1 reads as before")
    func failedSecondBoardChangesNeitherBoard() async throws {
        let directory = try TemporaryDirectory()
        let app = try Self.makeRepo(named: Self.appName, in: directory)
        let lib = try Self.makeRepo(named: Self.libName, in: directory)
        let graph = try Self.makeTwoBoardGraph(at: app, failingIn: lib)
        let queryBefore = try await KanbanGraphTests.execute(KanbanGraphTests.boardQuery, on: graph)
        let (appBefore, libBefore) = (try Self.signatures(ofRepoAt: app), try Self.signatures(ofRepoAt: lib))
        try await Self.expectTwoBoardFault(on: graph)
        #expect(try Self.signatures(ofRepoAt: app) == appBefore)
        #expect(try Self.signatures(ofRepoAt: lib) == libBefore)
        #expect(try await KanbanGraphTests.execute(KanbanGraphTests.boardQuery, on: graph) == queryBefore)
        await graph.close()
    }

    @Test("After a failed two-board call, the same call commits, and each board holds its change one time")
    func twoBoardCallAfterFailureWorks() async throws {
        let directory = try TemporaryDirectory()
        let app = try Self.makeRepo(named: Self.appName, in: directory)
        let lib = try Self.makeRepo(named: Self.libName, in: directory)
        let graph = try Self.makeTwoBoardGraph(at: app, failingIn: lib)
        try await Self.expectTwoBoardFault(on: graph)
        let response = try await KanbanGraphTests.execute(Self.twoBoardCall, on: graph)
        #expect(try CrossRepoWriteTests.hasNoErrors(response))
        #expect(try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: graph).contains(Self.newBoardName))
        let boardEvents = try EventLog(repositoryAt: app).readLog(of: .board).events
        #expect(boardEvents.filter { event in event.ops == [MutationName.updateBoard, MutationName.addTask] }.count == 1)
        let libTasks = try EventLog(repositoryAt: lib).nodeRefs(ofType: .task)
        let libTitles = try libTasks.compactMap { ref in
            (try EventLog(repositoryAt: lib).readLog(of: ref).node?.state as? TaskNode)?.title
        }
        #expect(libTitles.filter { title in title == Self.libTaskTitle }.count == 1)
        await graph.close()
    }
}

// MARK: - Faulting writer

/// A log writer for tests: it appends the lines of each append through ``FileEventLogWriter``, and then it makes one
/// append fail, so that the commit must remove the lines that the failed append wrote too.
///
/// The type is a class, because all sessions of one engine share its count of appends.
final class FaultingLogWriter: EventLogWriter {
    /// The error of the append that fails.
    static let fault = EventLogError.fileSystem(path: "faulting-writer", detail: "The test writer fails this append")

    /// The number of the append that fails, from 1.
    private let failingAppend: Int

    /// The `.kanban/` directory of the board whose appends the writer counts, or `nil` to count each append.
    private let countedBoard: EventLog?

    /// The number of appends that the writer counted.
    private let appends = Mutex(0)

    /// Makes a writer that makes one append fail.
    ///
    /// - Parameters:
    ///   - failingAppend: The number of the append that fails, from 1.
    ///   - root: The root directory of the repo of the board whose appends the writer counts, or `nil` to count each
    ///     append.
    init(failingAppend: Int, toBoardAt root: URL? = nil) {
        self.failingAppend = failingAppend
        countedBoard = root.map(EventLog.init(repositoryAt:))
    }

    /// The number of appends that the writer counted.
    var appendCount: Int {
        appends.withLock { count in count }
    }

    /// Appends the events, and then fails when the append is the failing append.
    ///
    /// - Parameters:
    ///   - events: The events.
    ///   - ref: The local ref of the node.
    ///   - log: The event log of the board.
    /// - Throws: ``fault`` for the failing append, or the error of the file writer.
    func append(contentsOf events: [Event], toLogOf ref: LocalRef, in log: EventLog) throws(EventLogError) {
        try FileEventLogWriter().append(contentsOf: events, toLogOf: ref, in: log)
        guard countedBoard.map({ board in log.isBoardDirectory(at: board.directory) }) ?? true else {
            return
        }
        let number = appends.withLock { count in
            count += 1
            return count
        }
        guard number != failingAppend else {
            throw Self.fault
        }
    }
}
