import Foundation
import Synchronization
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the rollback of a commit whose append or signature read fails (plan.md §5.4 step 5.5): each log file that
/// the commit wrote keeps its lines and gets the abort record of the transaction, replay ignores the transaction, no
/// log file shrinks, no live graph changes, and the next call works normally.
///
/// Most tests give the commit a ``FaultingLogWriter``. The writer appends the lines of each append, and then it makes
/// one append fail. Thus the lines of the append that failed are on disk too, and the abort record must cover them.
@Suite("Commit rollback: a failed transaction is aborted by an appended record", .watcherBudget)
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
    /// - Parameter writer: The writer of the session. The default writes the lines of each append, makes the second
    ///   append fail, and writes each abort record.
    /// - Returns: The board.
    static func makeFailingBoard(
        writingWith writer: FaultingLogWriter = FaultingLogWriter(failingAppend: secondAppend)
    ) async throws -> FailingBoard {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try CommitTests.writeBoard(in: directory)
        let session = try await CommitTests.makeSession(of: log, writingWith: writer)
        return FailingBoard(directory: directory, log: log, tasks: tasks, writer: writer, session: session)
    }

    /// Runs a call, and gives the event log error that it throws.
    ///
    /// - Parameter call: Runs the call.
    /// - Returns: The error, or `nil` when the call did not throw an ``EventLogError``. The test then records an
    ///   issue.
    static func logError(of call: () async throws -> Void) async throws -> EventLogError? {
        do {
            try await call()
        } catch let error as EventLogError {
            return error
        }
        Issue.record("The call did not give an event log error")
        return nil
    }

    /// Runs a call, and expects the fault of the writer.
    ///
    /// - Parameter call: Runs the call.
    static func expectFault(_ call: () async throws -> Void) async throws {
        #expect(try await logError(of: call) == FaultingLogWriter.fault)
    }

    /// Runs one call of a session that sets ``CommitTests/callTitle`` on two tasks, one task in each mutation field,
    /// and gives the event log error of the call.
    ///
    /// - Parameters:
    ///   - session: The commit session.
    ///   - first: The task of the first mutation field.
    ///   - second: The task of the second mutation field.
    /// - Returns: The error, or `nil` when the call did not throw an ``EventLogError``.
    static func logError(
        running session: inout CommitSession,
        settingTitlesOf first: LocalRef,
        _ second: LocalRef
    ) async throws -> EventLogError? {
        try await logError {
            try await session.run { store in
                let title = CommitTests.callTitle
                try await CommitTests.setTitle(title, of: first, as: CommitTests.firstOperation, in: store)
                try await CommitTests.setTitle(title, of: second, as: CommitTests.secondOperation, in: store)
            }
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
        #expect(try await logError(running: &session, settingTitlesOf: first, second) == FaultingLogWriter.fault)
    }

    /// Gives the line of the abort record of a transaction, without its line break (plan.md §5.1).
    ///
    /// - Parameter txn: The transaction ULID.
    /// - Returns: The text of the line.
    static func abortLine(of txn: ULID) -> String {
        "{\"abort\":\"\(txn.ulidString)\"}"
    }

    /// Gives the lines of a log file, without their line breaks.
    ///
    /// - Parameter file: The log file.
    /// - Returns: The lines, in file order.
    static func lines(of file: URL) throws -> [String] {
        try EventLogTests.text(of: file).split(separator: "\n").map(String.init)
    }

    /// Gives the transaction of the lines that a failed call left in a log file: the lines with the time of the test
    /// calls. The lines are read as text, so that the check sees each line on disk, also a line that replay skips.
    ///
    /// - Parameter file: The log file.
    /// - Returns: The transaction ULID of the call.
    static func failedTransaction(inFileAt file: URL) throws -> ULID {
        let events = try lines(of: file).compactMap { line in try? Event(parsing: line) }
        let transactions = Set(events.filter { event in event.at == CommitTests.callTime }.map(\.txn))
        #expect(transactions.count == 1)
        return try #require(transactions.first)
    }

    /// Checks that the log file of a node holds the lines of the failed call, then the abort record of the transaction
    /// of the call as its last line, and that replay reads no event of the call.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - log: The event log of the board.
    static func expectAborted(_ ref: LocalRef, in log: EventLog) throws {
        let file = log.fileURL(for: ref)
        let txn = try failedTransaction(inFileAt: file)
        #expect(try lines(of: file).last == abortLine(of: txn))
        #expect(try CommitTests.callEvents(of: ref, in: log).isEmpty)
    }

    /// Checks that no node file of a board is smaller than before a failed call, and that each node file of before is
    /// still there.
    ///
    /// - Parameters:
    ///   - before: The signature of each node file before the call.
    ///   - log: The event log of the board.
    static func expectNoFileShrank(since before: [LocalRef: FileSignature], in log: EventLog) throws {
        let after = try log.nodeFileSignatures()
        for (ref, signature) in before {
            let size = try #require(after[ref], "The failed call removed the file of \(ref)").size
            #expect(size >= signature.size, "The failed call shrank the file of \(ref)")
        }
    }

    /// Gives the size of a file.
    ///
    /// - Parameter file: The file.
    /// - Returns: The size, in bytes.
    static func size(of file: URL) throws -> Int {
        try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
    }

    /// Gives a fake key from the name of the repo directory, and does not run git. The directory name stands in for
    /// the root commit.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The fake local key of the directory name.
    @Sendable
    static func directoryKey(ofRepoAt root: URL) -> BoardKey {
        BoardKey(rootCommit: root.lastPathComponent)
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

    /// Gives the title of each task that replay reads from the logs of a repo.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The titles, in no fixed order.
    static func taskTitles(ofRepoAt root: URL) throws -> [String] {
        let log = EventLog(repositoryAt: root)
        return try log.nodeRefs(ofType: .task).compactMap { ref in
            (try log.readLog(of: ref).node?.state as? TaskNode)?.title
        }
    }

    // MARK: - One board

    @Test("When the second append fails, each written file keeps its lines, ends with the abort record, and replay ignores the call")
    func failedAppendIsAborted() async throws {
        var board = try await Self.makeFailingBoard()
        let (log, tasks) = (board.log, board.tasks)
        try await Self.expectFault(running: &board.session, settingTitlesOf: tasks[0], tasks[1])
        #expect(board.writer.appendCount == Self.secondAppend)
        try Self.expectAborted(tasks[0], in: log)
        try Self.expectAborted(tasks[1], in: log)
        #expect(try CommitTests.title(of: tasks[0], in: board.session) == tasks[0].description)
        try await LiveGraphApplyTests.expectSameStateAsFreshLoad(board.session.live, of: log)
    }

    @Test("When the signature read after each append fails, each written file ends with the abort record, and replay ignores the call")
    func failedSignatureReadIsAborted() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try CommitTests.writeBoard(in: directory)
        var session = try await CommitTests.makeSession(of: log, writingWith: UnreadableLogWriter())
        let error = try #require(try await Self.logError(running: &session, settingTitlesOf: tasks[0], tasks[1]))
        let path: String? = if case .fileSystem(let path, _) = error { path } else { nil }
        #expect([tasks[0], tasks[1]].map { task in log.fileURL(for: task).path }.contains(try #require(path)))
        try Self.expectAborted(tasks[0], in: log)
        try Self.expectAborted(tasks[1], in: log)
        try await LiveGraphApplyTests.expectSameStateAsFreshLoad(session.live, of: log)
    }

    @Test("A failed commit never shrinks a log file: each written file grows past its size after the append")
    func failedCommitNeverShrinksFile() async throws {
        var board = try await Self.makeFailingBoard()
        let (log, tasks) = (board.log, board.tasks)
        let before = try log.nodeFileSignatures()
        try await Self.expectFault(running: &board.session, settingTitlesOf: tasks[0], tasks[1])
        try Self.expectNoFileShrank(since: before, in: log)
        let appended = board.writer.largestSizes
        #expect(appended.count == Self.secondAppend)
        for (file, largest) in appended {
            #expect(try Self.size(of: file) > largest, "The rollback shrank \(file.lastPathComponent)")
        }
    }

    @Test("When the append to a new node file fails, the file stays, ends with the abort record, and gives no node")
    func failedAppendToNewFileKeepsFile() async throws {
        var board = try await Self.makeFailingBoard()
        let log = board.log
        let newTask = LocalRef.task(ULID(timestamp: ReplayTests.date(atStep: CommitTests.callStep)))
        let before = try log.nodeFileSignatures()
        try await Self.expectFault(running: &board.session, settingTitlesOf: board.tasks[0], newTask)
        try Self.expectNoFileShrank(since: before, in: log)
        try Self.expectAborted(newTask, in: log)
        #expect(try log.readLog(of: newTask).node == nil)
        try await LiveGraphApplyTests.expectSameStateAsFreshLoad(board.session.live, of: log)
    }

    @Test("When the abort records cannot be written, the load holds the transaction whose file has no line")
    func failedAbortFallsBackToTransactionCheck() async throws {
        let writer = FaultingLogWriter(failingAppend: Self.secondAppend, writingFailedAppend: false, failingAborts: true)
        var board = try await Self.makeFailingBoard(writingWith: writer)
        let (log, tasks) = (board.log, board.tasks)
        try await Self.expectFault(running: &board.session, settingTitlesOf: tasks[0], tasks[1])
        let written = try CommitTests.callEvents(of: tasks[0], in: log)
        #expect(written.count == 1)
        #expect(try CommitTests.callEvents(of: tasks[1], in: log).isEmpty)
        let fresh = try await BoardLoader(reading: log).load()
        #expect(fresh.heldEvents == written)
        #expect(try LiveGraphApplyTests.task(tasks[0], in: fresh.graph).title == tasks[0].description)
    }

    @Test("After a failed commit, the next call reads the abort records, runs again, and sees no part of the failed transaction")
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
        #expect(runs.withLock { count in count } == CommitTests.runsAfterOneChange)
        #expect(try CommitTests.callEvents(of: tasks[0], in: log).map(\.patch) == [laterPatch])
        #expect(try CommitTests.callEvents(of: tasks[1], in: log).isEmpty)
        #expect(try CommitTests.title(of: tasks[1], in: board.session) == tasks[1].description)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(board.session.live, of: log)
    }

    // MARK: - Two boards

    @Test("When the append of board 2 fails, no file of either board shrinks, and both boards read as before")
    func failedSecondBoardChangesNeitherBoard() async throws {
        let boards = try Self.makeTwoBoards()
        let (app, lib, graph) = (boards.app, boards.lib, boards.graph)
        let queryBefore = try await KanbanGraphTests.execute(KanbanGraphTests.boardQuery, on: graph)
        let (appBefore, libBefore) = (try Self.signatures(ofRepoAt: app), try Self.signatures(ofRepoAt: lib))
        try await Self.expectTwoBoardFault(on: graph)
        try Self.expectNoFileShrank(since: appBefore, in: EventLog(repositoryAt: app))
        try Self.expectNoFileShrank(since: libBefore, in: EventLog(repositoryAt: lib))
        #expect(try Self.lines(of: EventLog.boardLogURL(inRepositoryAt: app)).last?.hasPrefix("{\"abort\":") == true)
        #expect(!(try Self.taskTitles(ofRepoAt: lib)).contains(Self.libTaskTitle))
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
        let callEvents = boardEvents.filter { event in event.ops == [MutationName.updateBoard, MutationName.addTask] }
        // The call also writes one board names patch to the board log (divergence.md M9), in the same transaction.
        let (names, changes) = (
            callEvents.filter { event in BoardMutationTests.isBoardNamesPatch(event.patch) },
            callEvents.filter { event in !BoardMutationTests.isBoardNamesPatch(event.patch) }
        )
        #expect(changes.count == 1)
        #expect(names.count == 1)
        #expect(Set(callEvents.map(\.txn)).count == 1)
        #expect(try Self.taskTitles(ofRepoAt: boards.lib).filter { title in title == Self.libTaskTitle }.count == 1)
        await graph.close()
    }
}

// MARK: - Faulting writer

/// A log writer for tests: it appends the lines of each append through ``FileEventLogWriter``, and then it makes one
/// append fail, so that the commit must abort the lines that the failed append wrote too.
///
/// The type is a class, because all sessions of one engine share its count of appends.
final class FaultingLogWriter: EventLogWriter {
    /// The error of the append that fails.
    static let fault = EventLogError.fileSystem(path: "faulting-writer", detail: "The test writer fails this append")

    /// The error of each abort record, when the writer makes the abort records fail.
    static let abortFault = EventLogError.fileSystem(path: "faulting-writer", detail: "The test writer fails each abort")

    /// The number of the append that fails, from 1.
    private let failingAppend: Int

    /// The `.kanban/` directory of the board whose appends the writer counts, or `nil` to count each append.
    private let countedBoard: EventLog?

    /// `true` when the append that fails writes its lines before it fails.
    private let writesFailingAppend: Bool

    /// `true` when each abort record fails and writes nothing.
    private let failsAborts: Bool

    /// The number of appends that the writer counted.
    private let appends = Mutex(0)

    /// The largest size of each file right after an append that wrote lines to it.
    private let sizes = Mutex<[URL: Int]>([:])

    /// Makes a writer that makes one append fail.
    ///
    /// - Parameters:
    ///   - failingAppend: The number of the append that fails, from 1.
    ///   - root: The root directory of the repo of the board whose appends the writer counts, or `nil` to count each
    ///     append.
    ///   - writesFailingAppend: `true` when the append that fails writes its lines before it fails. The default is
    ///     `true`.
    ///   - failsAborts: `true` when each abort record fails and writes nothing. The default is `false`.
    init(
        failingAppend: Int,
        toBoardAt root: URL? = nil,
        writingFailedAppend writesFailingAppend: Bool = true,
        failingAborts failsAborts: Bool = false
    ) {
        self.failingAppend = failingAppend
        countedBoard = root.map(EventLog.init(repositoryAt:))
        self.writesFailingAppend = writesFailingAppend
        self.failsAborts = failsAborts
    }

    /// The number of appends that the writer counted.
    var appendCount: Int {
        appends.withLock { count in count }
    }

    /// The largest size of each file right after an append that wrote lines to it, by file.
    var largestSizes: [URL: Int] {
        sizes.withLock { sizes in sizes }
    }

    /// Appends the events, and then fails when the append is the failing append. The failing append writes its lines
    /// first when the writer was made so.
    ///
    /// - Parameters:
    ///   - events: The events.
    ///   - ref: The local ref of the node.
    ///   - log: The event log of the board.
    /// - Throws: ``fault`` for the failing append, or the error of the file writer.
    func append(contentsOf events: [Event], toLogOf ref: LocalRef, in log: EventLog) throws(EventLogError) {
        let isCounted = countedBoard.map { board in log.isBoardDirectory(at: board.directory) } ?? true
        let fails = isCounted && countAppend() == failingAppend
        if !fails || writesFailingAppend {
            try FileEventLogWriter().append(contentsOf: events, toLogOf: ref, in: log)
            try recordSize(of: log.fileURL(for: ref))
        }
        guard !fails else {
            throw Self.fault
        }
    }

    /// Appends the abort record of a transaction, or fails when the writer makes the abort records fail.
    ///
    /// - Parameters:
    ///   - txn: The transaction ULID.
    ///   - ref: The local ref of the node.
    ///   - log: The event log of the board.
    /// - Throws: ``abortFault`` when the writer makes the abort records fail, or the error of the file writer.
    func appendAbort(of txn: ULID, toLogOf ref: LocalRef, in log: EventLog) throws(EventLogError) {
        guard !failsAborts else {
            throw Self.abortFault
        }
        try FileEventLogWriter().appendAbort(of: txn, toLogOf: ref, in: log)
    }

    /// Adds one append to the count of appends.
    ///
    /// - Returns: The number of the append, from 1.
    private func countAppend() -> Int {
        appends.withLock { count in
            count += 1
            return count
        }
    }

    /// Records the size of a file right after an append, when it is larger than each size that the writer recorded
    /// for the file before.
    ///
    /// - Parameter file: The file.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the size cannot be read.
    private func recordSize(of file: URL) throws(EventLogError) {
        let size: Int
        do {
            size = try CommitRollbackTests.size(of: file)
        } catch {
            throw .fileSystem(path: file.path, detail: String(describing: error))
        }
        sizes.withLock { sizes in sizes[file] = max(sizes[file] ?? .zero, size) }
    }
}

// MARK: - Unreadable writer

/// A log writer for tests: it appends the lines of each append through ``FileEventLogWriter``, and then it takes away
/// the read permission of the file, so that the signature read after the appends fails. The abort record of a file
/// gives the permission back first, the same as a fault that goes away, and then it writes the record.
struct UnreadableLogWriter: EventLogWriter {
    /// The permissions of a file that the writer made unreadable: the owner writes, and nobody reads.
    static let unreadableMode = 0o200

    /// The permissions of a log file that the abort record gives back: the owner reads and writes, the others read.
    static let readableMode = 0o644

    /// Appends the events, and then makes the file unreadable.
    ///
    /// - Parameters:
    ///   - events: The events.
    ///   - ref: The local ref of the node.
    ///   - log: The event log of the board.
    /// - Throws: The error of the file writer, or ``EventLogError/fileSystem(path:detail:)`` when the permissions
    ///   cannot change.
    func append(contentsOf events: [Event], toLogOf ref: LocalRef, in log: EventLog) throws(EventLogError) {
        try FileEventLogWriter().append(contentsOf: events, toLogOf: ref, in: log)
        try Self.setMode(Self.unreadableMode, ofFileAt: log.fileURL(for: ref))
    }

    /// Makes the file readable again, and then appends the abort record of a transaction.
    ///
    /// - Parameters:
    ///   - txn: The transaction ULID.
    ///   - ref: The local ref of the node.
    ///   - log: The event log of the board.
    /// - Throws: The error of the file writer, or ``EventLogError/fileSystem(path:detail:)`` when the permissions
    ///   cannot change.
    func appendAbort(of txn: ULID, toLogOf ref: LocalRef, in log: EventLog) throws(EventLogError) {
        try Self.setMode(Self.readableMode, ofFileAt: log.fileURL(for: ref))
        try FileEventLogWriter().appendAbort(of: txn, toLogOf: ref, in: log)
    }

    /// Sets the permissions of a file.
    ///
    /// - Parameters:
    ///   - mode: The permissions.
    ///   - file: The file.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the permissions cannot change.
    private static func setMode(_ mode: Int, ofFileAt file: URL) throws(EventLogError) {
        do {
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
        } catch {
            throw .fileSystem(path: file.path, detail: String(describing: error))
        }
    }
}
