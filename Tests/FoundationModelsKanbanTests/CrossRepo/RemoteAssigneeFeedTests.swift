import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the change feed of a board whose task has an assignee that is an actor of a different board (divergence.md
/// Q21): a move to a different board stores the assignee as the full URI of the actor on the old board. When the old
/// board changes that actor, the change feed of the target board sends an update for the moved task.
///
/// Each test makes two real git repos side by side in a ``GitSandbox``. Each repo gets a unique first commit. No test
/// reads or changes the `.kanban/` directory of this repo. Each test closes each engine that it makes.
@Suite("Cross-repo: the change feed of a task with an assignee of a different board", .watcherBudget)
struct RemoteAssigneeFeedTests {
    /// The new name of the assignee after the rename.
    private static let newName = "Alice Jones"

    /// The selection of each event: the id, the kind, and the changed fields of each update, and the names of the
    /// assignees of the node now.
    private static let selection = """
        { updates { id kind fields { name removed } node { ... on Task { assignees { name } } } } }
        """

    /// The result of one test run.
    private struct FeedRun {
        /// The full URI of the moved task on the related board.
        let task: String

        /// The full URI of the assignee on the old board.
        let actor: String

        /// The next event of the subscription after the mutation, or `nil` when the stream ended with no event.
        let event: String?
    }

    /// Moves a task with an assignee of the current board to the related board, subscribes to the task changes of the
    /// related board, runs one actor mutation on the old board, and reads the next event of the subscription.
    ///
    /// - Parameters:
    ///   - operation: The actor mutation, for example `updateActor`.
    ///   - input: The other fields of the input of the mutation, or `""` for none.
    /// - Returns: The moved task, the assignee, and the event.
    /// - Throws: An error when a git command fails, or when a call fails.
    private static func run(_ operation: String, with input: String = "") async throws -> FeedRun {
        let transfer = try await CrossRepoTransferTests.makeAssignedTransfer(MutationName.moveTask)
        let lib = try CrossRepoTransferTests.makeLibGraph(in: transfer.repos)
        let document = SubscriptionTests.subscription(SubscriptionTests.taskArguments, selecting: selection)
        let stream = try await SubscriptionTests.subscribe(document, on: lib)
        let app = try GitGraphFixture.makeGraph(at: transfer.repos.app, mintingFrom: GitGraphFixture.thirdEngineIDs)
        let field = CommentTests.nodeField(operation, naming: transfer.actor, with: input)
        let response = try await CommentTests.run(field, on: app)
        #expect(try CrossRepoWriteTests.hasNoErrors(response), "\(response)")
        let events = try await SubscriptionTests.events(
            SubscriptionTests.oneEvent, of: stream, afterChangeAt: transfer.repos.app
        )
        await app.close()
        await lib.close()
        return FeedRun(task: transfer.written, actor: transfer.actor, event: events.first)
    }

    /// Gives the event of one task update of a subscription with ``selection``. The response has its keys in sorted
    /// order.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - fields: The JSON list of the changed fields.
    ///   - names: The JSON list of the assignees of the task now.
    /// - Returns: The event JSON text.
    private static func updateEvent(of task: String, fields: String, assignees names: String) -> String {
        let update = #"{"fields":\#(fields),"id":"\#(task)","kind":"UPDATED","node":{"assignees":\#(names)}}"#
        return #"{"data":{"changes":{"updates":[\#(update)]}}}"#
    }

    @Test("A rename of a remote assignee actor gives an update event for the moved task on the target board")
    func renameOfRemoteAssigneeGivesUpdate() async throws {
        let run = try await Self.run(MutationName.updateActor, with: #"name: "\#(Self.newName)""#)
        let names = #"[{"name":"\#(Self.newName)"}]"#
        #expect(run.event == Self.updateEvent(of: run.task, fields: "[]", assignees: names))
    }

    @Test("A delete of a remote assignee actor gives an update event, and Task.assignees leaves the actor out")
    func deleteOfRemoteAssigneeGivesUpdate() async throws {
        let run = try await Self.run(MutationName.deleteActor)
        let fields = #"[{"name":"assignees","removed":["\#(run.actor)"]}]"#
        #expect(run.event == Self.updateEvent(of: run.task, fields: fields, assignees: "[]"))
    }
}
