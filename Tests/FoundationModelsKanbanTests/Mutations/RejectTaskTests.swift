import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the `rejectTask` mutation (divergence.md §21): the user moves a task back with a comment to the agent, in one
/// transaction (TestudoApp D92).
///
/// The call adds the comment to the task, with the session actor as the author, and moves the task. With no `column`,
/// the task goes to the column before the column where it shows, in board order. Each test uses the fixture logs of
/// ``KanbanGraphTests``. Most tests add the columns `doing`, `review`, and `done` after `todo`, and move the fixture
/// task to `done` (``columnsSetup(movingToDone:)``).
@Suite("rejectTask mutation", .watcherBudget)
struct RejectTaskTests {
    /// The comment of the reject in the tests: the reason that the task goes back.
    private static let comment = "The build fails on main."

    /// The slug of the column that the setup adds after `todo`.
    private static let doingSlug = "doing"

    /// The slug of the column that the setup adds between `doing` and `done`: the column before `done`.
    private static let reviewSlug = "review"

    /// The selection of a `rejectTask` field: the task, its column, and the body and the author of each comment.
    private static let resultSelection = "{ id column { id } comments { body author { id } } }"

    /// The comments that are empty or hold only white space.
    private static let emptyComments = ["", "   "]

    /// The filter of the subscription of the changes test: it leaves out the session actor and the board summary.
    private static let taskAndCommentFilter = #"(filter: "!~actor && !~board")"#

    // MARK: - Helpers

    /// Makes the setup document: it adds the columns `doing`, `review`, and `done` after `todo`, in this board order,
    /// and can move a task to `done`.
    ///
    /// - Parameter task: The ULID of the task to move to `done`, or `nil` for no move.
    /// - Returns: The document.
    private static func columnsSetup(movingToDone task: ULID? = nil) -> String {
        let columns = [doingSlug, reviewSlug, TaskOperationTests.doneSlug].map { slug in
            ColumnActorTests.addColumnField(named: slug)
        }
        let move = task.map { task in [TaskOperationTests.doneMove(of: task)] } ?? []
        return AddUpdateTaskTests.mutation(of: (columns + move).joined(separator: " "))
    }

    /// Makes a new engine of the fixture repo, and runs ``columnsSetup(movingToDone:)`` with the fixture task.
    ///
    /// - Parameter directory: The temporary repo directory. The result holds it, so that the repo stays on disk while
    ///   the test uses the engine.
    /// - Returns: The directory, the engine, and the ULID of the fixture task in `done`.
    private static func taskInDone(
        in directory: TemporaryDirectory
    ) async throws -> (directory: TemporaryDirectory, graph: KanbanGraph, task: ULID) {
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        _ = try await KanbanGraphTests.execute(columnsSetup(movingToDone: fixture.task), on: fixture.graph)
        return (directory, fixture.graph, fixture.task)
    }

    /// Makes a `rejectTask` field.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task. The field names it by `^` and the short id.
    ///   - comment: The text of the `comment` field.
    ///   - input: The other fields of the `input` object, or `""` for none.
    ///   - selection: The selection of the field.
    /// - Returns: The field.
    private static func rejectField(
        of task: ULID,
        saying comment: String = comment,
        with input: String = "",
        selecting selection: String = resultSelection
    ) -> String {
        TaskOperationTests.taskField(
            "rejectTask",
            of: task,
            with: #"comment: "\#(comment)" \#(input)"#,
            selecting: selection
        )
    }

    /// Gives the JSON object that ``resultSelection`` gives for a task with the one comment of the reject.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task.
    ///   - slug: The slug of the column of the task.
    /// - Returns: The JSON object text, with sorted keys.
    private static func rejectedJSON(of task: ULID, inColumn slug: String) -> String {
        let author = AddUpdateTaskTests.idJSON(of: KanbanGraphTests.sessionActor.ref)
        let comments = #"[{"author":\#(author),"body":"\#(comment)"}]"#
        let column = AddUpdateTaskTests.idJSON(of: .column(slug: slug))
        return #"{"column":\#(column),"comments":\#(comments),"id":"\#(ColumnActorTests.id(of: .task(task)))"}"#
    }

    /// Gives the response of a document with one `rejectTask` field that selects ``resultSelection``: the task is in a
    /// column, and it has the one comment of the reject.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task.
    ///   - slug: The slug of the column of the task.
    /// - Returns: The response JSON text, with no `extensions.txn`.
    private static func rejectedResponse(of task: ULID, inColumn slug: String) -> String {
        TaskOperationTests.dataResponse(of: #""rejectTask":\#(rejectedJSON(of: task, inColumn: slug))"#)
    }

    /// Makes the three tasks of ``TaskOperationTests/threeTasks(in:)`` in `todo`, adds the column `done` after `todo`,
    /// and moves the first task to `done`. Then `todo` is the column before `done`, and it holds the second task and
    /// the third task, in this order.
    ///
    /// - Parameter directory: The temporary repo directory.
    /// - Returns: The directory, the engine, and the ULIDs of the three tasks.
    private static func threeTasksWithFirstInDone(
        in directory: TemporaryDirectory
    ) async throws -> (directory: TemporaryDirectory, graph: KanbanGraph, first: ULID, second: ULID, third: ULID) {
        let tasks = try await TaskOperationTests.threeTasks(in: directory)
        _ = try await KanbanGraphTests.execute(
            AddUpdateTaskTests.mutation(
                of: AddUpdateTaskTests.doneColumn,
                TaskOperationTests.doneMove(of: tasks.first)
            ),
            on: tasks.graph
        )
        return tasks
    }

    // MARK: - The move and the comment

    @Test("rejectTask with no column adds the comment and moves a task in done to the column before done")
    func rejectTaskMovesToColumnBeforeDone() async throws {
        let fixture = try await Self.taskInDone(in: try TemporaryDirectory())
        let response = try await KanbanGraphTests.runWithoutTransaction(
            Self.rejectField(of: fixture.task),
            on: fixture.graph
        )
        #expect(response == Self.rejectedResponse(of: fixture.task, inColumn: Self.reviewSlug))
    }

    @Test("rejectTask with the column doing adds the comment and moves the task to doing")
    func rejectTaskMovesToNamedColumn() async throws {
        let fixture = try await Self.taskInDone(in: try TemporaryDirectory())
        let input = TaskOperationTests.moveInput(to: Self.doingSlug)
        let response = try await KanbanGraphTests.runWithoutTransaction(
            Self.rejectField(of: fixture.task, with: input),
            on: fixture.graph
        )
        #expect(response == Self.rejectedResponse(of: fixture.task, inColumn: Self.doingSlug))
    }

    @Test("rejectTask with no column and before puts the task before the neighbor in the column before done")
    func rejectTaskPlacesTaskBeforeNeighbor() async throws {
        let tasks = try await Self.threeTasksWithFirstInDone(in: try TemporaryDirectory())
        let reject = Self.rejectField(of: tasks.first, with: TaskOperationTests.neighbor("before", of: tasks.third))
        let response = try await KanbanGraphTests.runWithoutTransaction(reject, on: tasks.graph)
        #expect(response == Self.rejectedResponse(of: tasks.first, inColumn: TaskOperationTests.todoSlug))
        #expect(try await TaskOperationTests.listedTasks(on: tasks.graph) == [tasks.second, tasks.first, tasks.third])
    }

    @Test("rejectTask with no column and after puts the task after the neighbor in the column before done")
    func rejectTaskPlacesTaskAfterNeighbor() async throws {
        let tasks = try await Self.threeTasksWithFirstInDone(in: try TemporaryDirectory())
        let reject = Self.rejectField(of: tasks.first, with: TaskOperationTests.neighbor("after", of: tasks.second))
        let response = try await KanbanGraphTests.runWithoutTransaction(reject, on: tasks.graph)
        #expect(response == Self.rejectedResponse(of: tasks.first, inColumn: TaskOperationTests.todoSlug))
        #expect(try await TaskOperationTests.listedTasks(on: tasks.graph) == [tasks.second, tasks.first, tasks.third])
    }

    @Test("rejectReview names rejectTask")
    func rejectReviewNamesRejectTask() async throws {
        let fixture = try await Self.taskInDone(in: try TemporaryDirectory())
        let field = CommentTests.nodeField(
            "rejectReview",
            naming: AddUpdateTaskTests.sigilRef(of: fixture.task),
            with: #"comment: "\#(Self.comment)""#,
            selecting: Self.resultSelection
        )
        let response = try await KanbanGraphTests.runWithoutTransaction(field, on: fixture.graph)
        let data = #""rejectReview":\#(Self.rejectedJSON(of: fixture.task, inColumn: Self.reviewSlug))"#
        let rewrite = #"{"from":"rejectReview","path":["rejectReview"],"to":"rejectTask"}"#
        #expect(response == #"{"data":{\#(data)},"extensions":{"rewrites":[\#(rewrite)]}}"#)
    }

    // MARK: - One transaction

    @Test("rejectTask writes one transaction, and one undoChange of it removes the comment and moves the task back")
    func undoOfRejectTaskRemovesCommentAndMovesTaskBack() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try await Self.taskInDone(in: directory)
        let document = AddUpdateTaskTests.mutation(of: Self.rejectField(of: fixture.task))
        let call = try await ResponseTransactionTests.run(document, on: fixture.graph, in: directory)
        let txn = try ResponseTransactionTests.transaction(of: call.response)
        #expect(call.written == [txn], "\(call.response)")
        let undo = UndoTests.reverseField(MutationName.undoChange, with: #"txn: "\#(txn)""#)
        _ = try await CommentTests.run(undo, on: fixture.graph)
        let task = try await CommentTests.respond(
            toQueryOf: fixture.task,
            selecting: "{ column { id } comments { body } }",
            on: fixture.graph
        )
        let column = AddUpdateTaskTests.idJSON(of: .column(slug: TaskOperationTests.doneSlug))
        #expect(task == #"{"data":{"board":{"task":{"column":\#(column),"comments":[]}}}}"#)
    }

    @Test("The changes event of rejectTask holds the new comment and the moved task")
    func changesEventHoldsCommentAndTask() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try await Self.taskInDone(in: directory)
        let stream = try await SubscriptionTests.subscribe(
            SubscriptionTests.subscription(Self.taskAndCommentFilter),
            on: fixture.graph
        )
        let response = try await CommentTests.run(
            Self.rejectField(of: fixture.task, selecting: "{ comments { id } }"),
            on: fixture.graph
        )
        let comments = try KanbanGraphTests.object(named: "rejectTask", in: response)["comments"] as? [[String: Any]]
        let comment = try #require(comments?.first?["id"] as? String, "\(response)")
        let expected = SubscriptionTests.event(
            txn: try ResponseTransactionTests.transaction(of: response),
            operation: "rejectTask",
            updates: [
                SubscriptionTests.update(ofNode: comment, kind: .created),
                SubscriptionTests.update(ofNode: SubscriptionTests.id(of: fixture.task), kind: .updated),
            ]
        )
        let events = try await SubscriptionTests.events(
            SubscriptionTests.oneEvent,
            of: stream,
            afterChangeAt: directory.url
        )
        #expect(events == [expected])
        await fixture.graph.close()
    }

    // MARK: - Errors

    @Test("rejectTask with an empty comment gives EMPTY_COMMENT and writes nothing", arguments: emptyComments)
    func emptyCommentWritesNothing(comment: String) async throws {
        let task = try AddUpdateTaskTests.fixtureTask()
        let error = try await ColumnActorTests.failure(
            of: AddUpdateTaskTests.mutation(of: Self.rejectField(of: task, saying: comment)),
            after: Self.columnsSetup(movingToDone: task),
            in: try TemporaryDirectory()
        )
        #expect(error == .emptyComment)
    }

    @Test("rejectTask with no comment gives GRAPHQL_VALIDATION_FAILED and writes nothing")
    func missingCommentWritesNothing() async throws {
        let task = try AddUpdateTaskTests.fixtureTask()
        let document = AddUpdateTaskTests.mutation(
            of: TaskOperationTests.taskField("rejectTask", of: task, selecting: Self.resultSelection)
        )
        let response = try await ColumnActorTests.respondWritingNothing(
            to: document,
            after: Self.columnsSetup(movingToDone: task),
            in: try TemporaryDirectory()
        )
        let inputColumn = try #require(document.range(of: "{ id:")).lowerBound.utf16Offset(in: document) + 1
        let message = #"Field \"RejectTaskInput.comment\" of required type \"String!\" was not provided."#
        let location = #"{"column":\#(inputColumn),"line":1}"#
        let error = #"{"extensions":{"code":"GRAPHQL_VALIDATION_FAILED"},"locations":[\#(location)],"#
            + #""message":"\#(message)","path":[]}"#
        #expect(response == #"{"errors":[\#(error)]}"#)
    }

    @Test("rejectTask with no column on a task in the first column gives NO_PREVIOUS_COLUMN and writes nothing")
    func taskInFirstColumnWritesNothing() async throws {
        let task = try AddUpdateTaskTests.fixtureTask()
        let error = try await ColumnActorTests.failure(
            of: AddUpdateTaskTests.mutation(of: Self.rejectField(of: task)),
            after: Self.columnsSetup(),
            in: try TemporaryDirectory()
        )
        let expected = KanbanError.noPreviousColumn(
            task: AddUpdateTaskTests.sigilRef(of: task),
            column: TaskOperationTests.todoSlug
        )
        #expect(error == expected)
    }

    @Test("rejectTask with before and after gives CONFLICTING_PLACEMENT with the two fields and writes nothing")
    func beforeAndAfterGiveConflictingPlacement() async throws {
        let task = try AddUpdateTaskTests.fixtureTask()
        let placement = [
            TaskOperationTests.neighbor("before", of: task),
            TaskOperationTests.neighbor("after", of: task),
        ]
        let error = try await ColumnActorTests.failure(
            of: AddUpdateTaskTests.mutation(of: Self.rejectField(of: task, with: placement.joined(separator: " "))),
            after: Self.columnsSetup(movingToDone: task),
            in: try TemporaryDirectory()
        )
        #expect(error == .conflictingPlacement(fields: ["before", "after"]))
    }
}
