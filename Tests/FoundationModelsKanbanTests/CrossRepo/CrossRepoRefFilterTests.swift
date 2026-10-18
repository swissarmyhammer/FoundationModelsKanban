import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the filter atom `^<task of a different board>` on `history` and on the change feed (plan.md §6.3, §6.5,
/// §6.7, divergence.md R14): the atom keeps the updates of the tasks of the current board that depend on that task,
/// and leaves out the updates of the other tasks.
///
/// Each test makes real git repos side by side in a ``GitSandbox``. No test reads or changes the `.kanban/` directory
/// of this repo.
@Suite("Cross-repo: a ^ filter with a task of a different board", .watcherBudget)
struct CrossRepoRefFilterTests {
    /// The `input` field of the title change that a test writes.
    static let titleInput = #"title: "Later""#

    /// The tasks of a test: a task of the related board, a task of the current board that depends on it, and a task
    /// of the current board with no dependency.
    struct Tasks {
        /// The full URI of the task of the related board.
        let target: String

        /// The full URI of the task of the current board that depends on ``target``.
        let dependent: String

        /// The full URI of the task of the current board with no dependency.
        let other: String

        /// The arguments of a field whose filter is the `^` atom with the URI of ``target``.
        var filterArguments: String {
            #"(filter: "^\#(target)")"#
        }
    }

    // MARK: - Helpers

    /// Adds the tasks of a test through the engine of the current repo.
    ///
    /// - Parameter app: The engine of the current repo.
    /// - Returns: The tasks.
    /// - Throws: An error when a call fails.
    static func makeTasks(on app: KanbanGraph) async throws -> Tasks {
        let target = try await CrossRepoWriteTests.addLibTask(on: app)
        let dependent = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        let other = try await CrossRepoFixture.addTask(with: "", on: app)
        return Tasks(target: target, dependent: dependent, other: other)
    }

    /// Changes the title of a task with an `updateTask` call.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - app: The engine of the current repo.
    /// - Throws: An error when the call fails.
    static func changeTitle(of task: String, on app: KanbanGraph) async throws {
        let response = try await CommentTests.run(
            CommentTests.nodeField(MutationName.updateTask, naming: task, with: titleInput),
            on: app
        )
        #expect(try CrossRepoWriteTests.hasNoErrors(response), "\(response)")
    }

    // MARK: - Tests

    @Test("history with ^ and a task of a related board keeps only the updates of the tasks that depend on it")
    func historyKeepsDependentsOfRelatedTask() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let tasks = try await Self.makeTasks(on: app)
        let response = try await KanbanGraphTests.execute(
            "{ board { history\(tasks.filterArguments) { updates { id } } } }",
            on: app
        )
        let board = try KanbanGraphTests.object(named: "board", in: response)
        let changes = try #require(board["history"] as? [[String: Any]], "\(response)")
        let updates = changes.flatMap { change in change["updates"] as? [[String: Any]] ?? [] }
        #expect(Set(updates.compactMap { update in update["id"] as? String }) == [tasks.dependent], "\(response)")
        await app.close()
    }

    @Test("changes with ^ and a task of a related board sends the change of a dependent task, not of another task")
    func changesSendsChangeOfDependent() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let tasks = try await Self.makeTasks(on: app)
        let stream = try await SubscriptionTests.subscribe(
            SubscriptionTests.subscription(tasks.filterArguments),
            on: app
        )
        try await Self.changeTitle(of: tasks.other, on: app)
        try await Self.changeTitle(of: tasks.dependent, on: app)
        let expected = SubscriptionTests.event(
            txn: try await SubscriptionTests.latestTxn(on: app),
            operation: MutationName.updateTask,
            updates: [SubscriptionTests.update(ofNode: tasks.dependent, kind: .updated)]
        )
        let events = try await SubscriptionTests.events(
            SubscriptionTests.oneEvent, of: stream, afterChangeAt: repos.app
        )
        #expect(events == [expected])
        await app.close()
    }
}
