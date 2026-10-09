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

    /// A board of the one-board tests. The writer of its session makes the second append fail.
    struct FailingBoard {
        /// The temporary repo directory. The board keeps it, so that the directory stays until the test ends.
        let directory: TemporaryDirectory

        /// The event log of the board.
        let log: EventLog

        /// The refs of the fixture tasks.
        let tasks: [LocalRef]

        /// The writer of the session. It makes the second append fail.
        let writer: FaultingLogWriter

        /// The commit session of the board.
        var session: CommitSession
    }

    /// Writes the board fixture, and makes its commit session with a writer that makes the second append fail.
    ///
    /// - Returns: The board.
    static func makeFailingBoard() async throws -> FailingBoard {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try CommitTests.writeBoard(in: directory)
        let writer = FaultingLogWriter(failingAppend: secondAppend)
        let session = try await CommitTests.makeSession(of: log, writingWith: writer)
        return FailingBoard(directory: directory, log: log, tasks: tasks, writer: writer, session: session)
    }

    /// Runs a call, and expects the fault of the writer.
    ///
    /// - Parameter call: Runs the call.
    static func expectFault(_ call: () async throws -> Void) async throws {
        do {
            try await call()
            Issue.record("The call did not give the fault of the writer")
        } catch let error as EventLogError {
            #expect(error == FaultingLogWriter.fault)
        }
    }

    /// Runs one call of a session that sets ``CommitTests/callTitle`` on two tasks, one task in each mutation field,
    /// and expects the fault of the writer.
    ///
    /// - Parameters:
    ///   - session: The commit session.
    ///   - first: The task of the first mutation field.
    ///   - second: The task of the second mutation field.
    static func expectFault(
        running session: inout CommitSession,
        settingTitlesOf first: LocalRef,
        _ second: LocalRef
    ) async throws {
        try await expectFault {
            try await session.run { store in
                let title = CommitTests.callTitle
                try await CommitTests.setTitle(title, of: first, as: CommitTests.firstOperation, in: store)
                try await CommitTests.setTitle(title, of: second, as: CommitTests.secondOperation, in: store)
            }
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

    /// The two repos of a two-board test, and the engine of the current repo.
    struct TwoBoards {
        /// The temporary directory that holds the two repos. The value keeps it, so that the directory stays until the
        /// test ends.
        let directory: TemporaryDirectory

        /// The root directory of the current repo.
        let app: URL

        /// The root directory of the related repo.
        let lib: URL

        /// The engine of the current repo. Its writer makes the first append to the related board fail.
        let graph: KanbanGraph
    }

    /// Makes the two repos of a two-board test, and the engine of the current repo. The writer of the engine makes
    /// the first append to the related board fail.
    ///
    /// - Returns: The repos and the engine.
    static func makeTwoBoards() throws -> TwoBoards {
        let directory = try TemporaryDirectory()
        let app = try makeRepo(named: appName, in: directory)
        let lib = try makeRepo(named: libName, in: directory)
        let graph = try KanbanGraphTests.makeGraph(
            at: app,
            readingKeyWith: directoryKey(ofRepoAt:),
            writingLogsWith: FaultingLogWriter(failingAppend: firstAppend, toBoardAt: lib)
        )
        return TwoBoards(directory: directory, app: app, lib: lib, graph: graph)
    }

    /// Runs the two-board call, and expects the fault of the writer.
    ///
    /// - Parameter graph: The engine of the current repo.
    static func expectTwoBoardFault(on graph: KanbanGraph) async throws {
        try await expectFault {
            _ = try await KanbanGraphTests.execute(twoBoardCall, on: graph)
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
        var board = try await Self.makeFailingBoard()
        let (log, tasks) = (board.log, board.tasks)
        let before = try log.nodeFileSignatures()
        try await Self.expectFault(running: &board.session, settingTitlesOf: tasks[0], tasks[1])
        #expect(board.writer.appendCount == Self.secondAppend)
        #expect(try log.nodeFileSignatures() == before)
        #expect(board.session.live.signatures == before)
        #expect(try CommitTests.title(of: tasks[0], in: board.session) == tasks[0].description)
        #expect(try CommitTests.callEvents(of: tasks[0], in: log).isEmpty)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(board.session.live, of: log)
    }

    @Test("When the append to a new node file fails, the file does not exist after the call")
    func failedAppendToNewFileRemovesFile() async throws {
        var board = try await Self.makeFailingBoard()
        let log = board.log
        let newTask = LocalRef.task(ULID(timestamp: ReplayTests.date(atStep: CommitTests.callStep)))
        let before = try log.nodeFileSignatures()
        try await Self.expectFault(running: &board.session, settingTitlesOf: board.tasks[0], newTask)
        #expect(!FileManager.default.fileExists(atPath: log.fileURL(for: newTask).path))
        #expect(try log.nodeFileSignatures() == before)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(board.session.live, of: log)
    }

    @Test("After a failed commit, the next call commits in its first run and sees no part of the failed transaction")
    func nextCallAfterFailureWorks() async throws {
        var board = try await Self.makeFailingBoard()
        let (log, tasks) = (board.log, board.tasks)
        try await Self.expectFault(running: &board.session, settingTitlesOf: tasks[0], tasks[1])
        let runs = Mutex(0)
        try await board.session.run { store in
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
        #expect(try CommitTests.title(of: tasks[1], in: board.session) == tasks[1].description)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(board.session.live, of: log)
    }

    // MARK: - Two boards

    @Test("When the append of board 2 fails, no file of either board changes, and board 1 reads as before")
    func failedSecondBoardChangesNeitherBoard() async throws {
        let boards = try Self.makeTwoBoards()
        let (app, lib, graph) = (boards.app, boards.lib, boards.graph)
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
        let boards = try Self.makeTwoBoards()
        let graph = boards.graph
        try await Self.expectTwoBoardFault(on: graph)
        let response = try await KanbanGraphTests.execute(Self.twoBoardCall, on: graph)
        #expect(try CrossRepoWriteTests.hasNoErrors(response))
        #expect(try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: graph).contains(Self.newBoardName))
        let boardEvents = try EventLog(repositoryAt: boards.app).readLog(of: .board).events
        #expect(boardEvents.filter { event in event.ops == [MutationName.updateBoard, MutationName.addTask] }.count == 1)
        let libLog = EventLog(repositoryAt: boards.lib)
        let libTitles = try libLog.nodeRefs(ofType: .task).compactMap { ref in
            (try libLog.readLog(of: ref).node?.state as? TaskNode)?.title
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
