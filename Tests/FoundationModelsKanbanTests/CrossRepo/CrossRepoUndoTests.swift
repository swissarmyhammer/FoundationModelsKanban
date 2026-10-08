import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests `undo` and `redo` across boards (plan.md §6.5 "Scope" and "Many boards", §6.6): one `undo` reverses a call
/// in each board that the call changed, a missing board gives `NOT_FOUND` and nothing is written, and a call with no
/// `txn` searches only the current board and the loaded boards.
///
/// Each test makes two real git repos side by side in a ``GitSandbox``. The engines read the board keys from git.
@Suite("Cross-repo: undo and redo across boards", .timeLimit(.minutes(1)))
struct CrossRepoUndoTests {
    /// The response key of the field that adds a task to the current board.
    static let appField = "app"

    /// The response key of the field that adds a task to the related board.
    static let libField = "lib"

    /// The `undo` field with no `input`.
    static let undoField = UndoTests.reverseField(MutationName.undo, with: "")

    // MARK: - Helpers

    /// Runs one call that adds one task to the current board and one task to the related board.
    ///
    /// - Parameter graph: The engine of the current repo.
    /// - Returns: The full URI of each new task.
    /// - Throws: An error when the response has no id for a field.
    static func addTaskToEachBoard(on graph: KanbanGraph) async throws -> (app: String, lib: String) {
        let libInput = CrossRepoWriteTests.boardField(try CrossRepoWriteTests.libKey())
        let mutation = AddUpdateTaskTests.mutation(
            of: "\(appField): " + AddUpdateTaskTests.addTask(with: ""),
            "\(libField): " + AddUpdateTaskTests.addTask(with: libInput)
        )
        let data = try NameRewriteTests.data(of: try await KanbanGraphTests.execute(mutation, on: graph))
        return (try id(of: appField, in: data), try id(of: libField, in: data))
    }

    /// Gives the `id` of the node that one field of a response gives.
    ///
    /// - Parameters:
    ///   - field: The response key of the field.
    ///   - data: The `data` object of the response.
    /// - Returns: The id.
    /// - Throws: An error when the field gives no id.
    static func id(of field: String, in data: [String: Any]) throws -> String {
        try #require((data[field] as? [String: Any])?["id"] as? String, "\(data)")
    }

    /// Reads the newest event of the log of a task.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - root: The root directory of the repo of the task.
    /// - Returns: The last event of the task log.
    /// - Throws: An error when the log cannot be read or has no event.
    static func lastEvent(ofTask task: String, inRepoAt root: URL) throws -> Event {
        try #require(try CrossRepoWriteTests.events(ofTask: task, inRepoAt: root).last)
    }

    /// Runs a field, and expects that the response has no error.
    ///
    /// - Parameters:
    ///   - field: The mutation field.
    ///   - graph: The engine.
    /// - Throws: An error when the response is not a JSON object.
    static func runWithNoErrors(_ field: String, on graph: KanbanGraph) async throws {
        let response = try await CommentTests.run(field, on: graph)
        #expect(try CrossRepoWriteTests.hasNoErrors(response), "\(response)")
    }

    /// Adds one task to the related board with a first engine of the current repo, and then closes that engine.
    ///
    /// - Parameter repos: The repos of the test.
    /// - Returns: The full URI of the new task.
    /// - Throws: An error when the engine cannot start, or when the response has no id.
    private static func addLibTask(withEngineClosedIn repos: CrossRepoFixture.SideBySide) async throws -> String {
        let first = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await CrossRepoWriteTests.addLibTask(on: first)
        await first.close()
        return task
    }

    /// Runs `undo` or `redo` with a `txn` and a `board` field that names the related board, on a new engine of the
    /// current repo. The new engine has not loaded the related board before the field, and the helper closes it
    /// after the field.
    ///
    /// - Parameters:
    ///   - name: `undo` or `redo`.
    ///   - txn: The transaction to reverse.
    ///   - repos: The repos of the test.
    ///   - ids: The ULID source of the new engine. Its ids must sort after the ids of each earlier engine.
    /// - Throws: An error when the engine cannot start, or when the board key cannot be read.
    private static func reverse(
        _ name: String,
        transaction txn: ULID,
        onNewEngineIn repos: CrossRepoFixture.SideBySide,
        mintingFrom ids: FixedULIDSource
    ) async throws {
        let input = UndoTests.txnInput(txn) + ", " + CrossRepoWriteTests.boardField(try CrossRepoWriteTests.libKey())
        let app = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: ids)
        try await runWithNoErrors(UndoTests.reverseField(name, with: input), on: app)
        await app.close()
    }

    /// Adds one task to the related board with a first engine, and then reverses that call with `undo`, a `txn`, and
    /// a `board` field on a second engine that has not loaded the related board.
    ///
    /// - Parameter repos: The repos of the test.
    /// - Returns: The full URI of the task.
    /// - Throws: An error when an engine cannot start, or when a log cannot be read.
    private static func addAndUndoLibTask(in repos: CrossRepoFixture.SideBySide) async throws -> String {
        let task = try await addLibTask(withEngineClosedIn: repos)
        try await reverse(
            MutationName.undo,
            transaction: try lastEvent(ofTask: task, inRepoAt: repos.lib).txn,
            onNewEngineIn: repos,
            mintingFrom: GitGraphFixture.secondEngineIDs
        )
        return task
    }

    // MARK: - Many boards

    @Test("One undo reverses a call that changed two boards, with one txn that undoes the call in both boards")
    func oneUndoReversesBothBoards() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let tasks = try await Self.addTaskToEachBoard(on: app)
        let original = try Self.lastEvent(ofTask: tasks.app, inRepoAt: repos.app).txn
        try await Self.runWithNoErrors(Self.undoField, on: app)
        let undoEvents = [
            try Self.lastEvent(ofTask: tasks.app, inRepoAt: repos.app),
            try Self.lastEvent(ofTask: tasks.lib, inRepoAt: repos.lib),
        ]
        #expect(undoEvents.allSatisfy { event in event.patch.delete == true && event.undoes == original })
        #expect(Set(undoEvents.map(\.txn)).count == 1)
        await app.close()
    }

    @Test("One redo puts back both boards of a call that one undo reversed")
    func oneRedoRestoresBothBoards() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let tasks = try await Self.addTaskToEachBoard(on: app)
        try await Self.runWithNoErrors(Self.undoField, on: app)
        try await Self.runWithNoErrors(UndoTests.reverseField(MutationName.redo, with: ""), on: app)
        let redoEvents = [
            try Self.lastEvent(ofTask: tasks.app, inRepoAt: repos.app),
            try Self.lastEvent(ofTask: tasks.lib, inRepoAt: repos.lib),
        ]
        #expect(redoEvents.allSatisfy { event in event.patch.delete == false })
        await app.close()
    }

    @Test("undo of a call whose other board is missing gives NOT_FOUND with the board name, and writes nothing")
    func missingBoardGivesNotFoundAndWritesNothing() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let first = try GitGraphFixture.makeGraph(at: repos.app)
        _ = try await Self.addTaskToEachBoard(on: first)
        await first.close()
        try FileManager.default.removeItem(at: repos.lib)
        let before = try Design.PortabilityTests.logTexts(inRepoAt: repos.app)
        let second = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        let response = try await CommentTests.run(Self.undoField, on: second)
        let expected = KanbanError.boardNotFound(
            reference: try CrossRepoWriteTests.libKey(),
            searchRoots: [repos.sandbox.root.path]
        )
        try ErrorCoverageTests.expectFailure(of: MutationName.undo, in: response, giving: expected, coded: "NOT_FOUND")
        #expect(try Design.PortabilityTests.logTexts(inRepoAt: repos.app) == before)
        await second.close()
    }

    // MARK: - Scope

    @Test("undo with no txn finds a transaction in a loaded related board, and does not load a board")
    func undoWithNoTxnSearchesLoadedBoardsOnly() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let task = try await Self.addLibTask(withEngineClosedIn: repos)
        let app = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        let beforeLoad = try await CommentTests.run(Self.undoField, on: app)
        try ErrorCoverageTests.expectFailure(
            of: MutationName.undo,
            in: beforeLoad,
            giving: .nothingToUndo,
            coded: "NOTHING_TO_UNDO"
        )
        _ = try await CrossRepoReadTests.board("name", of: CrossRepoWriteTests.libKey(), on: app)
        try await Self.runWithNoErrors(Self.undoField, on: app)
        #expect(try Self.lastEvent(ofTask: task, inRepoAt: repos.lib).patch.delete == true)
        await app.close()
    }

    @Test("undo with txn and board reverses a transaction of a related board that is not loaded")
    func undoWithBoardReachesBoardThatIsNotLoaded() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let task = try await Self.addAndUndoLibTask(in: repos)
        #expect(try Self.lastEvent(ofTask: task, inRepoAt: repos.lib).patch.delete == true)
    }

    @Test("redo with txn and board puts back a transaction of a related board that is not loaded")
    func redoWithBoardReachesBoardThatIsNotLoaded() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let task = try await Self.addAndUndoLibTask(in: repos)
        let undo = try Self.lastEvent(ofTask: task, inRepoAt: repos.lib).txn
        // The `txn` of `redo` names the undo transaction: the transaction that the redo reverses.
        try await Self.reverse(
            MutationName.redo,
            transaction: undo,
            onNewEngineIn: repos,
            mintingFrom: GitGraphFixture.thirdEngineIDs
        )
        let redo = try Self.lastEvent(ofTask: task, inRepoAt: repos.lib)
        #expect(redo.patch.delete == false)
        #expect(redo.undoes == undo)
    }
}
