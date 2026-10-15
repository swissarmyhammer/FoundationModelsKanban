import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the `undo` conflict rule across boards (plan.md §6.5 "Conflict", divergence.md X6 and R13): a later edge to a
/// node that the undo would tombstone is a conflict, also when the edge comes from a task of a different board.
///
/// Each test makes the example of divergence.md X6 in two real git repos side by side in a ``GitSandbox``. Call 1
/// adds `lib#X`. Call 2 adds `app#Y`. Then `undo(call1)` runs on the engine of the current repo, which has loaded both
/// boards.
@Suite("Cross-repo: undo conflict across boards", .watcherBudget, .timeLimit(.minutes(1)))
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

    /// Makes the example, runs `undo(call1)`, and expects `UNDO_CONFLICT` with call 2, and no change to the logs of
    /// either repo.
    ///
    /// - Parameter input: Makes the other fields of the `input` object of call 2 from the full URI of `X`.
    /// - Throws: An error when the example cannot be made, or a log cannot be read.
    static func expectConflict(addingY input: (String) -> String) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let example = try await makeExample(in: repos, on: app, addingY: input)
        let before = try UndeleteCycleTests.logTexts(of: repos)
        let field = UndoTests.reverseField(MutationName.undo, with: UndoTests.txnInput(example.first))
        try ErrorCoverageTests.expectFailure(
            of: MutationName.undo,
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

    // MARK: - Tests

    @Test("undo of the call that added lib#X, after app#Y depends on X, gives UNDO_CONFLICT and writes nothing")
    func laterEdgeFromOtherBoardConflicts() async throws {
        try await Self.expectConflict { libTask in "dependsOn: \(AddUpdateTaskTests.list(of: [libTask]))" }
    }

    @Test("undo of the call that added lib#X, after a body marker of X in app#Y, gives UNDO_CONFLICT, writes nothing")
    func laterBodyMarkerFromOtherBoardConflicts() async throws {
        try await Self.expectConflict { libTask in #"body: "Needs \#(libTask)""# }
    }

    @Test("undo of the call that added lib#X, when no task of a different board refers to X, tombstones X")
    func undoWithNoLaterEdgeFromOtherBoardWorks() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let example = try await Self.makeExample(in: repos, on: app) { _ in #"body: "No dependency""# }
        let field = UndoTests.reverseField(MutationName.undo, with: UndoTests.txnInput(example.first))
        try await CrossRepoUndoTests.runWithNoErrors(field, on: app)
        let undoEvent = try CrossRepoUndoTests.lastEvent(ofTask: example.libTask, inRepoAt: repos.lib)
        #expect(undoEvent.patch.delete == true)
        #expect(undoEvent.undoes == example.first)
        await app.close()
    }
}
