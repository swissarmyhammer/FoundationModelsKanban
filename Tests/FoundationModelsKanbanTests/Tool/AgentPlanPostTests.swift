import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing
import ULID

@testable import FoundationModelsKanban

/// Records each event that a tool call posts through its ``ToolContext``.
actor RecordingSink: OperationEventSink {
    /// The posted events, in post order.
    private(set) var events: [OperationEvent] = []

    /// Records one posted event.
    ///
    /// - Parameter event: The event.
    func post(event: OperationEvent) {
        events.append(event)
    }
}

/// Tests the post of the ACP agent plan after a `kanban` tool call that changes a task: the call posts one `.progress`
/// event with the plan of the board, and a query, a mutation that changes no task, and a call with no bound
/// ``ToolContext`` post nothing.
///
/// Each test runs in an empty repo, so the first mutation makes the board with the default columns.
@Suite("Agent plan: the post of a tool call")
struct AgentPlanPostTests {
    /// The title of the first task of a test.
    static let firstTitle = "Write the lexer"

    /// The title of the second task of a test.
    static let secondTitle = "Write the parser"

    /// The slug of the default column between the first column and the terminal column.
    static let doing = "doing"

    /// The detail line of a board with two live tasks and no done task.
    static let twoOpenTasks = "0 of 2 tasks done"

    /// The number of tool calls of the move test that change a task: two `addTask` calls and one `moveTask` call.
    static let moveCallCount = 3

    /// The number of live tasks after two `addTask` calls.
    static let twoTasks = 2

    /// Makes an `addTask` mutation that selects the id of the new task.
    ///
    /// - Parameter title: The title of the task.
    /// - Returns: The mutation document.
    static func addTask(titled title: String) -> String {
        AddUpdateTaskTests.mutation(of: #"addTask(input: { title: "\#(title)" }) { id }"#)
    }

    /// The tool, its engine, and the sink of the bound context of one test.
    struct Harness {
        /// The temporary repo directory. The value holds it, so that the repo stays on disk while the test runs.
        let directory: TemporaryDirectory

        /// The engine of the tool.
        let graph: KanbanGraph

        /// The tool.
        let tool: KanbanTool

        /// The sink of the bound context.
        let sink = RecordingSink()

        /// The key of the board of the repo: the id of its plan.
        var boardKey: String {
            KanbanGraphTests.fakeKey(ofRepoAt: directory.url).description
        }

        /// Makes the tool over a test engine in an empty repo.
        ///
        /// - Throws: An error when the directory or the engine cannot be made.
        init() throws {
            directory = try TemporaryDirectory()
            graph = try KanbanGraphTests.makeGraph(at: directory.url)
            tool = KanbanTool(graph: graph)
        }

        /// Makes a context that posts to the sink of the harness.
        var context: ToolContext {
            ToolContext(
                sessionID: ULID(),
                runPlane: RunPlane(),
                sink: sink,
                tool: tool.name,
                op: tool.name,
                completionToken: ToolContext.makeCompletionToken(),
                isCancelled: { false }
            )
        }

        /// Calls the tool with a document while the context of the harness is bound.
        ///
        /// - Parameter document: The GraphQL document.
        /// - Returns: The output of the tool.
        /// - Throws: An error when the arguments do not decode, or an I/O fault of the engine.
        @discardableResult
        func call(_ document: String) async throws -> String {
            let json = try KanbanArgumentsTests.argumentsJSON(query: document, variables: nil)
            let arguments = try KanbanArguments(GeneratedContent(json: json))
            return try await ToolContext.$current.withValue(context) {
                try await tool.call(arguments: arguments)
            }
        }

        /// Calls the tool to add a task, and gives the id of the new task.
        ///
        /// - Parameter title: The title of the task.
        /// - Returns: The full URI of the task.
        /// - Throws: An error when the response has no id.
        @discardableResult
        func addTask(titled title: String) async throws -> String {
            let response = try await call(AgentPlanPostTests.addTask(titled: title))
            let data = try #require(KanbanGraphTests.object(of: response)["data"] as? [String: Any])
            return try #require((data["addTask"] as? [String: Any])?["id"] as? String)
        }

        /// The plans of the posted events, in post order.
        var plans: [PlanSnapshot] {
            get async {
                await sink.events.compactMap(\.plan)
            }
        }
    }

    /// Makes a `moveTask` mutation of one task to a column.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - column: The slug of the column.
    /// - Returns: The mutation document.
    static func move(_ task: String, to column: String) -> String {
        let input = TaskOperationTests.moveInput(to: column)
        return AddUpdateTaskTests.mutation(of: CommentTests.nodeField("moveTask", naming: task, with: input))
    }

    @Test("addTask under a bound ToolContext posts one progress event with the plan of the board")
    func addTaskPostsThePlan() async throws {
        let harness = try Harness()
        try await harness.addTask(titled: Self.firstTitle)
        let event = try #require(await harness.sink.events.first)
        #expect(await harness.sink.events.count == 1)
        #expect(event.kind == .progress)
        #expect(event.detail == "0 of 1 tasks done")
        let expected = PlanSnapshot(
            id: harness.boardKey,
            entries: [PlanSnapshot.Entry(content: Self.firstTitle, priority: .high, status: .pending)]
        )
        #expect(event.plan == expected)
    }

    @Test("moveTask posts the full plan in board order, and a task that moves changes its tier and status")
    func moveTaskPostsTheNewOrder() async throws {
        let harness = try Harness()
        let first = try await harness.addTask(titled: Self.firstTitle)
        try await harness.addTask(titled: Self.secondTitle)
        try await harness.call(Self.move(first, to: Self.doing))
        let plans = await harness.plans
        let expected = [
            PlanSnapshot.Entry(content: Self.secondTitle, priority: .high, status: .pending),
            PlanSnapshot.Entry(content: Self.firstTitle, priority: .medium, status: .inProgress),
        ]
        #expect(plans.count == AgentPlanPostTests.moveCallCount)
        #expect(plans.last?.entries == expected)
        #expect(await harness.sink.events.last?.detail == Self.twoOpenTasks)
    }

    @Test("A query and a mutation that changes no task post nothing")
    func queryAndTagPostNothing() async throws {
        let harness = try Harness()
        try await harness.addTask(titled: Self.firstTitle)
        try await harness.call(AddUpdateTaskTests.mutation(of: TagMutationTests.addTag(named: TagMutationTests.bug)))
        try await harness.call("{ board { name tasks { totalCount } } }")
        #expect(await harness.sink.events.count == 1)
    }

    @Test("A direct execute of the engine posts nothing under a bound ToolContext, and the next tool call posts")
    func directExecutePostsNothing() async throws {
        let harness = try Harness()
        try await ToolContext.$current.withValue(harness.context) {
            _ = try await KanbanGraphTests.execute(Self.addTask(titled: Self.firstTitle), on: harness.graph)
        }
        #expect(await harness.sink.events.isEmpty)
        try await harness.addTask(titled: Self.secondTitle)
        #expect(await harness.plans.map(\.entries.count) == [AgentPlanPostTests.twoTasks])
    }
}
