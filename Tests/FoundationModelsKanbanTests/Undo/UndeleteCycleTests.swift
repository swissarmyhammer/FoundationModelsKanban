import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the `dependsOn` cycle rule when a tombstoned task becomes live again (plan.md §3.3 rule 6, divergence.md X7):
/// `undeleteTask`, and an `undo` of a `deleteTask`, run the same cycle check as a write of `dependsOn`.
///
/// Each test makes the example of divergence.md X7. A depends on B, and B depends on C. Then B is deleted, and C gets
/// a dependency on A. The cycle A → B → C → A is not there while B is a tombstone, and it comes back when B is live
/// again. The one-board tests use the fixture logs of ``KanbanGraphTests`` in a temporary directory. The cross-board
/// test makes two real git repos side by side in a ``GitSandbox``, and C is a task of the related board.
@Suite("A tombstoned task that becomes live again obeys the cycle rule", .watcherBudget, .timeLimit(.minutes(1)))
struct UndeleteCycleTests {
    /// The tasks of the example, each as its full URI, and the transaction of the delete of B.
    struct Example {
        /// The task that depends on ``b``.
        let a: String

        /// The deleted task. It depends on ``c``.
        let b: String

        /// The task that depends on ``a``.
        let c: String

        /// The transaction of the `deleteTask` of ``b``.
        let deleteTransaction: ULID
    }

    /// The example of a one-board test, with the engine and the directory of its repo.
    struct OneBoardExample {
        /// The temporary repo directory. The test keeps it, so that the directory stays until the test ends.
        let directory: TemporaryDirectory

        /// The engine of the repo.
        let graph: KanbanGraph

        /// The tasks of the example.
        let example: Example
    }

    // MARK: - Helpers

    /// Makes the example on an engine: adds B with a dependency on C and A with a dependency on B, deletes B, and
    /// then gives C a dependency on A.
    ///
    /// - Parameters:
    ///   - c: The full URI of the task C. It can be a task of a related board.
    ///   - root: The root directory of the current repo, whose log has B.
    ///   - graph: The engine of the current repo.
    /// - Returns: The tasks of the example.
    /// - Throws: An error when a response has no id, or the log of B cannot be read.
    static func makeExample(dependingOn c: String, in root: URL, on graph: KanbanGraph) async throws -> Example {
        let b = try await CrossRepoFixture.addTask(dependingOn: c, on: graph)
        let a = try await CrossRepoFixture.addTask(dependingOn: b, on: graph)
        try await CrossRepoUndoTests.runWithNoErrors(CommentTests.nodeField(MutationName.deleteTask, naming: b), on: graph)
        let deleteTransaction = try CrossRepoUndoTests.lastEvent(ofTask: b, inRepoAt: root).txn
        try await CrossRepoUndoTests.runWithNoErrors(CrossRepoCycleTests.dependencyField(from: c, to: a), on: graph)
        return Example(a: a, b: b, c: c, deleteTransaction: deleteTransaction)
    }

    /// Makes the example in one board: the fixture logs in a new temporary directory, and C, B, and A in its board.
    ///
    /// - Returns: The directory, the engine, and the tasks of the example.
    /// - Throws: An error when the fixture cannot be written, or a response has no id.
    static func makeOneBoardExample() async throws -> OneBoardExample {
        let directory = try TemporaryDirectory()
        let graph = try ColumnActorTests.makeFixtureGraph(in: directory).graph
        let c = try await CrossRepoFixture.addTask(with: "", on: graph)
        let example = try await makeExample(dependingOn: c, in: directory.url, on: graph)
        return OneBoardExample(directory: directory, graph: graph, example: example)
    }

    /// Gives the error of the cycle B → C → A → B that the check through B finds.
    ///
    /// - Parameters:
    ///   - example: The tasks of the example.
    ///   - cText: The text of C in the path: its short id for a task of the current board, else its full URI.
    /// - Returns: The error.
    /// - Throws: An error when the URI of a task holds no ULID.
    static func cycle(of example: Example, showingC cText: String) throws -> KanbanError {
        let a = try AddUpdateTaskTests.firstTaskRef(in: example.a)
        let b = try AddUpdateTaskTests.firstTaskRef(in: example.b)
        return .dependencyCycle(path: [b, cText, a, b])
    }

    /// Runs a field that makes B live again on a one-board example, and expects `DEPENDENCY_CYCLE`, no change to the
    /// logs, and B still a tombstone.
    ///
    /// - Parameters:
    ///   - name: The name of the mutation field.
    ///   - field: The field, made from the tasks of the example.
    /// - Throws: An error when the example cannot be made, or a log cannot be read.
    static func expectOneBoardCycle(of name: String, running field: (Example) -> String) async throws {
        let made = try await makeOneBoardExample()
        let root = made.directory.url
        let before = try Design.PortabilityTests.logTexts(inRepoAt: root)
        try ErrorCoverageTests.expectFailure(
            of: name,
            in: try await CommentTests.run(field(made.example), on: made.graph),
            giving: try cycle(of: made.example, showingC: try AddUpdateTaskTests.firstTaskRef(in: made.example.c)),
            coded: "DEPENDENCY_CYCLE"
        )
        #expect(try Design.PortabilityTests.logTexts(inRepoAt: root) == before)
        try expectStillDeleted(made.example, inRepoAt: root)
    }

    /// Expects that B is still a tombstone: the last event of its log is the delete.
    ///
    /// - Parameters:
    ///   - example: The tasks of the example.
    ///   - root: The root directory of the current repo.
    /// - Throws: An error when the log of B cannot be read.
    static func expectStillDeleted(_ example: Example, inRepoAt root: URL) throws {
        #expect(try CrossRepoUndoTests.lastEvent(ofTask: example.b, inRepoAt: root).patch.delete == true)
    }

    /// Makes the `undeleteTask` field of B.
    ///
    /// - Parameter example: The tasks of the example.
    /// - Returns: The field, with the selection `{ id }`.
    static func undeleteField(of example: Example) -> String {
        CommentTests.nodeField(MutationName.undeleteTask, naming: example.b)
    }

    /// Reads the logs of both repos of a cross-board test.
    ///
    /// - Parameter repos: The repos of the test.
    /// - Returns: The log texts of the current repo, then of the related repo.
    /// - Throws: An error when a log cannot be read.
    static func logTexts(of repos: CrossRepoFixture.SideBySide) throws -> [[LocalRef: String]] {
        try [repos.app, repos.lib].map { root in try Design.PortabilityTests.logTexts(inRepoAt: root) }
    }

    // MARK: - Tests

    @Test("undeleteTask of B after C depends on A gives DEPENDENCY_CYCLE, writes nothing, and B stays deleted")
    func undeleteThatClosesCycleIsRefused() async throws {
        try await Self.expectOneBoardCycle(of: MutationName.undeleteTask, running: Self.undeleteField(of:))
    }

    @Test("undo of the delete of B after C depends on A gives DEPENDENCY_CYCLE and writes nothing")
    func undoOfDeleteThatClosesCycleIsRefused() async throws {
        try await Self.expectOneBoardCycle(of: MutationName.undo) { example in
            UndoTests.reverseField(MutationName.undo, with: UndoTests.txnInput(example.deleteTransaction))
        }
    }

    @Test("undeleteTask of B gives DEPENDENCY_CYCLE when C is a task of a related board, and writes to no board")
    func crossBoardUndeleteThatClosesCycleIsRefused() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let c = try await CrossRepoWriteTests.addLibTask(on: app)
        let example = try await Self.makeExample(dependingOn: c, in: repos.app, on: app)
        let before = try Self.logTexts(of: repos)
        try ErrorCoverageTests.expectFailure(
            of: MutationName.undeleteTask,
            in: try await CommentTests.run(Self.undeleteField(of: example), on: app),
            giving: try Self.cycle(of: example, showingC: c),
            coded: "DEPENDENCY_CYCLE"
        )
        #expect(try Self.logTexts(of: repos) == before)
        try Self.expectStillDeleted(example, inRepoAt: repos.app)
        await app.close()
    }
}
