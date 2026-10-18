import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests `undo` and `redo` of a call that changed the current board and the second copy of a related repo
/// (divergence.md X5, S8): each worktree has its own board with the same key, so the `boards` value of the events
/// cannot tell which copy the call changed. The undo finds each copy by its events, writes nothing when no loaded
/// copy has them, and takes a copy that its `boards` input names by a path.
///
/// Each test makes the current repo, the related repo, and a worktree of the related repo in a ``GitSandbox``. The
/// related repo comes first in scan order, so its key resolves to the first copy, and the worktree is the second
/// copy. The engines read the worktree tops and the board keys from git. One test instead makes a worktree of the
/// current repo: the `boards` value of the events then names no key, because both copies have the key of the board
/// of the event.
@Suite("Cross-repo: undo and redo on a second copy of a repo", .watcherBudget)
struct CrossRepoCopyUndoTests {
    /// The repos of a sandbox with the current repo and two copies of the related repo.
    struct Copies {
        /// The sandbox of the test. It removes the repos when the test ends.
        let sandbox: GitSandbox

        /// The current repo, ``BoardLocatorTests/appName``.
        let app: URL

        /// The first copy of the related repo in scan order, ``BoardLocatorTests/firstCopyName``.
        let firstCopy: URL

        /// The second copy of the related repo in scan order: a worktree of the first copy,
        /// ``BoardLocatorTests/secondCopyName``.
        let secondCopy: URL

        /// Runs git to make the repos in a new sandbox.
        ///
        /// - Returns: The sandbox and its repos.
        /// - Throws: An error when a directory cannot be made, or when a git command fails.
        static func make() async throws -> Copies {
            let sandbox = try GitSandbox()
            let app = try await sandbox.makeRepo(named: BoardLocatorTests.appName, origin: BoardLocatorTests.appOrigin)
            let firstCopy = try await sandbox.makeRepo(
                named: BoardLocatorTests.firstCopyName,
                origin: BoardLocatorTests.libOrigin
            )
            let secondCopy = try await sandbox.addWorktree(named: BoardLocatorTests.secondCopyName, to: firstCopy)
            return Copies(sandbox: sandbox, app: app, firstCopy: firstCopy, secondCopy: secondCopy)
        }
    }

    /// The tasks of one call that changed the current board and the second copy, and the transaction of the call.
    struct CopyCall {
        /// The full URI of the task of the current board.
        let app: String

        /// The full URI of the task of the second copy.
        let copy: String

        /// The transaction of the call.
        let txn: ULID
    }

    // MARK: - Helpers

    /// Runs one call that adds one task to the current board and one task to the second copy, which the call names
    /// by its path.
    ///
    /// - Parameters:
    ///   - repos: The repos of the test.
    ///   - graph: The engine of the current repo.
    /// - Returns: The tasks and the transaction of the call.
    /// - Throws: An error when the response has no id for a field, or when a log cannot be read.
    static func addTaskToAppAndSecondCopy(of repos: Copies, on graph: KanbanGraph) async throws -> CopyCall {
        try await addTask(toAppAt: repos.app, andCopyAt: repos.secondCopy, on: graph)
    }

    /// Runs one call that adds one task to the current board and one task to a copy, which the call names by its
    /// path.
    ///
    /// - Parameters:
    ///   - app: The worktree top of the current repo.
    ///   - copy: The worktree top of the copy.
    ///   - graph: The engine of the current repo.
    /// - Returns: The tasks and the transaction of the call.
    /// - Throws: An error when the response has no id for a field, or when a log cannot be read.
    static func addTask(toAppAt app: URL, andCopyAt copy: URL, on graph: KanbanGraph) async throws -> CopyCall {
        let tasks = try await CrossRepoUndoTests.addTaskToEachBoard(on: graph, relatedBoard: copy.path)
        let txn = try CrossRepoUndoTests.lastEvent(ofTask: tasks.app, inRepoAt: app).txn
        return CopyCall(app: tasks.app, copy: tasks.lib, txn: txn)
    }

    /// Runs the call of ``addTaskToAppAndSecondCopy(of:on:)`` with a first engine of the current repo, and then
    /// closes that engine.
    ///
    /// - Parameter repos: The repos of the test.
    /// - Returns: The tasks and the transaction of the call.
    /// - Throws: An error when the engine cannot start, or when the response has no id.
    static func addTaskWithEngineClosed(in repos: Copies) async throws -> CopyCall {
        let first = try GitGraphFixture.makeGraph(at: repos.app)
        let call = try await addTaskToAppAndSecondCopy(of: repos, on: first)
        await first.close()
        return call
    }

    /// Gives the newest event of the task of the current board and of the task of the second copy.
    ///
    /// - Parameters:
    ///   - call: The call that added the tasks.
    ///   - repos: The repos of the test.
    /// - Returns: The newest event of each task.
    /// - Throws: An error when a log cannot be read or has no event.
    static func lastEvents(of call: CopyCall, in repos: Copies) throws -> [Event] {
        try lastEvents(of: call, appAt: repos.app, copyAt: repos.secondCopy)
    }

    /// Gives the newest event of the task of the current board and of the task of the copy that the call changed.
    ///
    /// - Parameters:
    ///   - call: The call that added the tasks.
    ///   - app: The worktree top of the current repo.
    ///   - copy: The worktree top of the copy that the call changed.
    /// - Returns: The newest event of each task.
    /// - Throws: An error when a log cannot be read or has no event.
    static func lastEvents(of call: CopyCall, appAt app: URL, copyAt copy: URL) throws -> [Event] {
        [
            try CrossRepoUndoTests.lastEvent(ofTask: call.app, inRepoAt: app),
            try CrossRepoUndoTests.lastEvent(ofTask: call.copy, inRepoAt: copy),
        ]
    }

    /// Expects that one undo transaction tombstoned the task of the current board and the task of the second copy.
    ///
    /// - Parameters:
    ///   - call: The call that added the tasks.
    ///   - repos: The repos of the test.
    /// - Throws: An error when a log cannot be read or has no event.
    static func expectUndone(_ call: CopyCall, in repos: Copies) throws {
        expectOneReverse(of: call.txn, wrote: try lastEvents(of: call, in: repos), deleting: true)
    }

    /// Expects that one `undo` or `redo` transaction that reversed a transaction wrote each event, with
    /// `undoes` = the reversed transaction.
    ///
    /// - Parameters:
    ///   - txn: The reversed transaction: the call for an `undo`, the undo for a `redo`.
    ///   - events: The newest event of each task that the call added.
    ///   - isDeleted: `true` when each event must be a tombstone (an `undo` of the call), `false` when each event must
    ///     make the task live again (a `redo` of the call).
    static func expectOneReverse(of txn: ULID, wrote events: [Event], deleting isDeleted: Bool) {
        #expect(events.allSatisfy { event in event.patch.delete == isDeleted && event.undoes == txn }, "\(events)")
        #expect(Set(events.map(\.txn)).count == 1)
    }

    /// Makes the `input` fields of an `undo` of a transaction with a `boards` list.
    ///
    /// - Parameters:
    ///   - txn: The transaction to reverse.
    ///   - references: The board refs of the `boards` list.
    /// - Returns: The `input` fields.
    static func txnInput(_ txn: ULID, boards references: [String]) -> String {
        UndoTests.txnInput(txn) + ", boards: " + AddUpdateTaskTests.list(of: references)
    }

    /// Reads the log texts of the current repo and of each copy of the related repo.
    ///
    /// - Parameter repos: The repos of the test.
    /// - Returns: The log texts of the current repo and of the second copy, and `true` when the first copy has a
    ///   `.kanban/` directory.
    /// - Throws: An error when a log cannot be read.
    static func boardState(of repos: Copies) throws -> (logs: [[LocalRef: String]], firstCopyHasBoard: Bool) {
        let logs = try [repos.app, repos.secondCopy].map { root in try Design.PortabilityTests.logTexts(inRepoAt: root) }
        return (logs, CrossRepoWriteTests.hasBoardDirectory(inRepoAt: repos.firstCopy))
    }

    // MARK: - Second copy

    @Test("undo reverses a call in the current board and in the second copy of a related repo")
    func undoReversesSecondCopy() async throws {
        let repos = try await Copies.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let call = try await Self.addTaskToAppAndSecondCopy(of: repos, on: app)
        try await CrossRepoUndoTests.runWithNoErrors(CrossRepoUndoTests.undoField, on: app)
        try Self.expectUndone(call, in: repos)
        await app.close()
    }

    @Test("redo puts back a call in the current board and in the second copy of a related repo")
    func redoRestoresSecondCopy() async throws {
        let repos = try await Copies.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let call = try await Self.addTaskToAppAndSecondCopy(of: repos, on: app)
        try await CrossRepoUndoTests.runWithNoErrors(CrossRepoUndoTests.undoField, on: app)
        let redo = UndoTests.reverseField(MutationName.redo, with: "")
        try await CrossRepoUndoTests.runWithNoErrors(redo, on: app)
        let events = try Self.lastEvents(of: call, in: repos)
        #expect(events.allSatisfy { event in event.patch.delete == false && event.undoes != nil }, "\(events)")
        await app.close()
    }

    @Test("undo finds a second copy that a different session of the host loaded")
    func undoReachesCopyOfHostTable() async throws {
        let repos = try await Copies.make()
        let host = HostFixture.makeGitHost()
        let writer = try await host.session(workingDirectory: repos.app, actor: KanbanHostTests.firstActor)
        let call = try await Self.addTaskToAppAndSecondCopy(of: repos, on: writer)
        let reader = try await host.session(workingDirectory: repos.app, actor: KanbanHostTests.secondActor)
        let undo = UndoTests.reverseField(MutationName.undo, with: UndoTests.txnInput(call.txn))
        try await CrossRepoUndoTests.runWithNoErrors(undo, on: reader)
        try Self.expectUndone(call, in: repos)
        await host.close()
    }

    @Test("undo(boards:) with the path of the second copy reaches a copy that no engine loaded")
    func boardsInputNamesSecondCopy() async throws {
        let repos = try await Copies.make()
        let call = try await Self.addTaskWithEngineClosed(in: repos)
        let app = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        let input = Self.txnInput(call.txn, boards: [repos.secondCopy.path])
        try await CrossRepoUndoTests.runWithNoErrors(UndoTests.reverseField(MutationName.undo, with: input), on: app)
        try Self.expectUndone(call, in: repos)
        await app.close()
    }

    // MARK: - Copy of the current repo

    /// The name of the worktree of the current repo in ``WorktreeCall``.
    static let appWorktreeName = "app-worktree"

    /// One call that changed the current board and a second worktree of the current repo. Both boards have the same
    /// key, so the `boards` value of the events of the call names no key.
    struct WorktreeCall {
        /// The sandbox of the test. It removes the repos when the test ends.
        let sandbox: GitSandbox

        /// The current repo, ``BoardLocatorTests/appName``.
        let app: URL

        /// The second worktree of the current repo, ``CrossRepoCopyUndoTests/appWorktreeName``.
        let worktree: URL

        /// The engine of the current repo. The test closes it.
        let graph: KanbanGraph

        /// The tasks and the transaction of the call.
        let call: CopyCall

        /// Makes the current repo and its worktree, and runs one call that adds one task to the current board and one
        /// task to the worktree, which the call names by its path.
        ///
        /// - Returns: The repos, the engine, and the call.
        /// - Throws: An error when a git command fails, when the engine cannot start, or when the response has no id.
        static func make() async throws -> WorktreeCall {
            let sandbox = try GitSandbox()
            let app = try await sandbox.makeRepo(named: BoardLocatorTests.appName, origin: BoardLocatorTests.appOrigin)
            let worktree = try await sandbox.addWorktree(named: CrossRepoCopyUndoTests.appWorktreeName, to: app)
            let graph = try GitGraphFixture.makeGraph(at: app)
            let call = try await CrossRepoCopyUndoTests.addTask(toAppAt: app, andCopyAt: worktree, on: graph)
            return WorktreeCall(sandbox: sandbox, app: app, worktree: worktree, graph: graph, call: call)
        }

        /// Gives the newest event of the task of the current board and of the task of the worktree.
        ///
        /// - Returns: The newest event of each task.
        /// - Throws: An error when a log cannot be read or has no event.
        func lastEvents() throws -> [Event] {
            try CrossRepoCopyUndoTests.lastEvents(of: call, appAt: app, copyAt: worktree)
        }
    }

    @Test("undo reverses a call in the current board and in a second worktree of the current repo")
    func undoReversesWorktreeOfCurrentRepo() async throws {
        let repos = try await WorktreeCall.make()
        try await CrossRepoUndoTests.runWithNoErrors(CrossRepoUndoTests.undoField, on: repos.graph)
        Self.expectOneReverse(of: repos.call.txn, wrote: try repos.lastEvents(), deleting: true)
        await repos.graph.close()
    }

    @Test("redo puts back a call in the current board and in a second worktree of the current repo")
    func redoRestoresWorktreeOfCurrentRepo() async throws {
        let repos = try await WorktreeCall.make()
        try await CrossRepoUndoTests.runWithNoErrors(CrossRepoUndoTests.undoField, on: repos.graph)
        let undone = try repos.lastEvents()
        Self.expectOneReverse(of: repos.call.txn, wrote: undone, deleting: true)
        let undoTxn = try #require(undone.first).txn
        let redo = UndoTests.reverseField(MutationName.redo, with: "")
        try await CrossRepoUndoTests.runWithNoErrors(redo, on: repos.graph)
        Self.expectOneReverse(of: undoTxn, wrote: try repos.lastEvents(), deleting: false)
        await repos.graph.close()
    }

    // MARK: - Board not reached

    @Test("undo gives NOT_FOUND with the board key and writes nothing on any board when no loaded copy has the call")
    func unreachedCopyWritesNothing() async throws {
        let repos = try await Copies.make()
        let call = try await Self.addTaskWithEngineClosed(in: repos)
        let before = try Self.boardState(of: repos)
        let app = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        let undo = UndoTests.reverseField(MutationName.undo, with: UndoTests.txnInput(call.txn))
        let response = try await CommentTests.run(undo, on: app)
        let expected = KanbanError.transactionBoardNotLoaded(
            transaction: call.txn.ulidString,
            board: try CrossRepoWriteTests.libKey()
        )
        try ErrorCoverageTests.expectFailure(of: MutationName.undo, in: response, giving: expected, coded: "NOT_FOUND")
        let after = try Self.boardState(of: repos)
        #expect(after.logs == before.logs)
        #expect(after.firstCopyHasBoard == before.firstCopyHasBoard)
        await app.close()
    }
}
