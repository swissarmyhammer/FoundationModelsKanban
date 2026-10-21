import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the `undoChange` conflict rule across boards (plan.md §6.5 "Conflict", divergence.md X6 and R13): a later
/// edge to a node that the undo would tombstone is a conflict, also when the edge comes from a task of a different
/// board.
///
/// Each test makes the example of divergence.md X6 in two real git repos side by side in a ``GitSandbox``. Call 1
/// adds `lib#X`. Call 2 adds `app#Y`. Then `undoChange(input: { txn: call1 })` runs on the engine of the current repo,
/// which has loaded both boards.
@Suite("Cross-repo: undo conflict across boards", .watcherBudget)
struct CrossRepoUndoConflictTests {
    /// The example: the task `X` of the related board, the transaction of call 1, and the transaction of call 2.
    struct Example {
        /// The full URI of the task `X` of the related board.
        let libTask: String

        /// The transaction of call 1, which added `X`.
        let first: ULID

        /// The transaction of call 2, which added `Y` to the current board.
        let second: ULID
    }

    // MARK: - Helpers

    /// Makes the example: call 1 adds `X` to the related board, and call 2 adds `Y` to the current board.
    ///
    /// - Parameters:
    ///   - repos: The repos of the test.
    ///   - graph: The engine of the current repo.
    ///   - input: Makes the other fields of the `input` object of call 2 from the full URI of `X`.
    /// - Returns: The example.
    /// - Throws: An error when a response has no id, or a log cannot be read.
    static func makeExample(
        in repos: CrossRepoFixture.SideBySide,
        on graph: KanbanGraph,
        addingY input: (String) -> String
    ) async throws -> Example {
        let libTask = try await CrossRepoWriteTests.addLibTask(on: graph)
        let first = try CrossRepoUndoTests.lastEvent(ofTask: libTask, inRepoAt: repos.lib).txn
        let appTask = try await CrossRepoFixture.addTask(with: input(libTask), on: graph)
        let second = try CrossRepoUndoTests.lastEvent(ofTask: appTask, inRepoAt: repos.app).txn
        return Example(libTask: libTask, first: first, second: second)
    }

    /// Makes the example, runs `undoChange(input: { txn: call1 })`, and expects `UNDO_CONFLICT` with call 2, and no
    /// change to the logs of either repo.
    ///
    /// - Parameter input: Makes the other fields of the `input` object of call 2 from the full URI of `X`.
    /// - Throws: An error when the example cannot be made, or a log cannot be read.
    static func expectConflict(addingY input: (String) -> String) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let example = try await makeExample(in: repos, on: app, addingY: input)
        let before = try UndeleteCycleTests.logTexts(of: repos)
        let field = UndoTests.reverseField(MutationName.undoChange, with: UndoTests.txnInput(example.first))
        try ErrorCoverageTests.expectFailure(
            of: MutationName.undoChange,
            in: try await CommentTests.run(field, on: app),
            giving: .undoConflict(
                transaction: example.first.ulidString,
                laterTransactions: [example.second.ulidString]
            ),
            coded: "UNDO_CONFLICT"
        )
        #expect(try UndeleteCycleTests.logTexts(of: repos) == before)
        await app.close()
    }

    /// Makes the example, runs `undoChange(input: { txn: call1 })`, and expects success with no errors, a tombstone
    /// for `lib#X` in the log of the related repo, and `undoes` set to call 1.
    ///
    /// - Parameters:
    ///   - isForced: `true` to send `force: true`, which writes the inverse also when a later transaction conflicts.
    ///   - input: Makes the other fields of the `input` object of call 2 from the full URI of `X`.
    /// - Throws: An error when the example cannot be made, the undo gives an error, or a log cannot be read.
    static func expectTombstone(forcing isForced: Bool, addingY input: (String) -> String) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let example = try await makeExample(in: repos, on: app, addingY: input)
        let txnInput = UndoTests.txnInput(example.first, forcing: isForced)
        let undo = UndoTests.reverseField(MutationName.undoChange, with: txnInput)
        try await CrossRepoUndoTests.runWithNoErrors(undo, on: app)
        let undoEvent = try CrossRepoUndoTests.lastEvent(ofTask: example.libTask, inRepoAt: repos.lib)
        #expect(undoEvent.patch.delete == true)
        #expect(undoEvent.undoes == example.first)
        await app.close()
    }

    /// The other fields of call 2 that give `app#Y` an edge to `X`.
    ///
    /// - Parameter libTask: The full URI of `X`.
    /// - Returns: The `dependsOn` field.
    static func edge(to libTask: String) -> String {
        "dependsOn: \(AddUpdateTaskTests.list(of: [libTask]))"
    }

    /// The other fields of call 2 that give `app#Y` a body marker of `X`.
    ///
    /// - Parameter libTask: The full URI of `X`.
    /// - Returns: The `body` field.
    static func bodyMarker(of libTask: String) -> String {
        #"body: "Needs \#(libTask)""#
    }

    // MARK: - Tests

    @Test("undo of the call that added lib#X, after app#Y depends on X, gives UNDO_CONFLICT and writes nothing")
    func laterEdgeFromOtherBoardConflicts() async throws {
        try await Self.expectConflict(addingY: Self.edge(to:))
    }

    @Test("undo of the call that added lib#X, after a body marker of X in app#Y, gives UNDO_CONFLICT, writes nothing")
    func laterBodyMarkerFromOtherBoardConflicts() async throws {
        try await Self.expectConflict(addingY: Self.bodyMarker(of:))
    }

    @Test("forced undo of the call that added lib#X, after app#Y depends on X, tombstones X")
    func forcedUndoWithLaterEdgeFromOtherBoardTombstones() async throws {
        try await Self.expectTombstone(forcing: true, addingY: Self.edge(to:))
    }

    @Test("forced undo of the call that added lib#X, after a body marker of X in app#Y, tombstones X")
    func forcedUndoWithLaterBodyMarkerFromOtherBoardTombstones() async throws {
        try await Self.expectTombstone(forcing: true, addingY: Self.bodyMarker(of:))
    }

    @Test("undo of the call that added lib#X, when no task of a different board refers to X, tombstones X")
    func undoWithNoLaterEdgeFromOtherBoardWorks() async throws {
        try await Self.expectTombstone(forcing: false) { _ in #"body: "No dependency""# }
    }
}
