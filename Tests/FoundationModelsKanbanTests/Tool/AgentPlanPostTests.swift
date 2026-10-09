import Foundation
import FoundationModels
import FoundationModelsExtras
import Synchronization
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

/// Tests the post of the ACP agent plan after a `kanban` tool call that changes a task (plan.md §7.3): the call posts
/// one `.progress` event with the plan of each changed board, in the sort order of the repo path. A query, a mutation
/// that changes no task, a call whose commit fails, a call with no bound ``ToolContext``, and a batch of the file
/// watcher post nothing. A successful call also posts the plan of a board that the commit check changed from a
/// different process.
///
/// Each test runs in an empty repo, so the first mutation makes the board with the default columns.
@Suite("Agent plan: the post of a tool call", .timeLimit(.minutes(1)))
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

    /// The number of posts after the first `addTask` call of a test: the plan of the new board.
    static let firstCallPosts = 1

    /// The key of the board of a test engine with the fake key reader: the id of its plan.
    static let boardKey = KanbanGraphTests.boardKey.description

    /// Makes an `addTask` mutation that selects the id of the new task.
    ///
    /// - Parameter title: The title of the task.
    /// - Returns: The mutation document.
    static func addTask(titled title: String) -> String {
        AddUpdateTaskTests.mutation(of: #"addTask(input: { title: "\#(title)" }) { id }"#)
    }

    /// The tool, its engine, and the sink of the bound context of one test.
    struct Harness {
        /// The owner of the repo directories on disk. The value holds it, so that the repos stay on disk while the
        /// test runs.
        let storage: AnyObject

        /// The engine of the tool.
        let graph: KanbanGraph

        /// The root directory of the repo of the engine.
        let root: URL

        /// The tool.
        let tool: KanbanTool

        /// The sink of the bound context.
        let sink = RecordingSink()

        /// Makes the tool over an engine.
        ///
        /// - Parameters:
        ///   - graph: The engine.
        ///   - root: The root directory of the repo of the engine.
        ///   - storage: The owner of the repo directories of the engine.
        init(graph: KanbanGraph, at root: URL, keeping storage: AnyObject) {
            self.storage = storage
            self.graph = graph
            self.root = root
            tool = KanbanTool(graph: graph)
        }

        /// Makes the tool over a test engine in an empty repo. This is the one place that makes the directory and the
        /// engine of a test in an empty repo.
        ///
        /// - Parameters:
        ///   - makeClock: Gives the clock of the engine from the event log of the board. The default clock always
        ///     gives ``KanbanGraphTests/time``.
        ///   - batchObserver: Gets a call when the file watcher applies a batch, or `nil` for no calls.
        /// - Throws: An error when the directory or the engine cannot be made.
        init(
            timedBy makeClock: (EventLog) -> @Sendable () -> DateTime = { _ in { KanbanGraphTests.time } },
            observingBatchesWith batchObserver: (any LiveGraphObserver)? = nil
        ) throws {
            let directory = try TemporaryDirectory()
            let graph = try KanbanGraphTests.makeGraph(
                at: directory.url,
                timedBy: makeClock(EventLog(repositoryAt: directory.url)),
                observingBatchesWith: batchObserver
            )
            self.init(graph: graph, at: directory.url, keeping: directory)
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

    /// Makes a harness over a test engine in an empty repo whose clock writes as a different process.
    ///
    /// - Returns: The harness, and the clock of its engine. The clock is idle.
    /// - Throws: An error when the directory or the engine cannot be made.
    static func makeHarnessWithOtherProcess() throws -> (harness: Harness, clock: OtherProcessClock) {
        var clock: OtherProcessClock?
        let harness = try Harness { log in
            let made = OtherProcessClock(writingTo: log)
            clock = made
            return made.now
        }
        return (harness, try #require(clock))
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
        #expect(await harness.sink.events.count == Self.firstCallPosts)
        #expect(event.kind == .progress)
        #expect(event.detail == "0 of 1 tasks done")
        let expected = PlanSnapshot(
            id: Self.boardKey,
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
        try await harness.call(KanbanGraphTests.nameQuery)
        #expect(await harness.sink.events.count == Self.firstCallPosts)
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

    @Test("A call that changes two boards posts one progress event for each board, in the sort order of the repo path")
    func twoBoardsPostInPathOrder() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let graph = try GitGraphFixture.makeGraph(at: repos.app)
        let harness = Harness(graph: graph, at: repos.app, keeping: repos.sandbox)
        try await harness.call(CrossRepoWriteTests.addTaskToEachBoard())
        let boards = [
            (path: repos.app.canonicalPath, key: try CrossRepoWriteTests.appKey()),
            (path: repos.lib.canonicalPath, key: try CrossRepoWriteTests.libKey()),
        ]
        let expected = boards.sorted { lhs, rhs in lhs.path < rhs.path }.map(\.key)
        let events = await harness.sink.events
        #expect(events.map(\.plan?.id) == expected)
        #expect(events.allSatisfy { event in event.kind == .progress })
    }

    @Test("A call whose commit fails with BOARD_BUSY posts no progress event")
    func boardBusyPostsNothing() async throws {
        let (harness, clock) = try Self.makeHarnessWithOtherProcess()
        try await harness.addTask(titled: Self.firstTitle)
        clock.arm(.writingAtEachRead)
        let response = try await harness.call(Self.addTask(titled: Self.secondTitle))
        clock.arm(.idle)
        #expect(try response == KanbanError.boardBusy(attempts: CommitSession.maximumRuns).responseJSON())
        #expect(await harness.sink.events.count == Self.firstCallPosts)
    }

    @Test("A successful call also posts the plan of a board that the commit check changed from a different process")
    func appliedChangeOfOtherProcessIsPosted() async throws {
        let (harness, clock) = try Self.makeHarnessWithOtherProcess()
        try await harness.addTask(titled: Self.firstTitle)
        clock.arm(.writingOnce)
        try await harness.call(AddUpdateTaskTests.mutation(of: TagMutationTests.addTag(named: TagMutationTests.bug)))
        let plans = await harness.plans
        #expect(plans.count == Self.firstCallPosts + 1)
        #expect(Set(plans.last?.entries.map(\.content) ?? []) == [Self.firstTitle, OtherProcessClock.title])
    }

    @Test("A batch of the file watcher posts nothing while a ToolContext is bound to the first call")
    func watcherBatchPostsNothing() async throws {
        let recorder = BatchRecorder()
        let harness = try Harness(observingBatchesWith: recorder)
        try await harness.addTask(titled: Self.firstTitle)
        let log = EventLog(repositoryAt: harness.root)
        var ids = GitGraphFixture.secondEngineIDs
        let task = try KanbanGraphTests.writeTask(titled: OtherProcessClock.title, mintingFrom: &ids, to: log)
        let taskFile = log.fileURL(for: .task(task))
        #expect(try await BoardWatcherTests.hasBatch(in: recorder.batches) { batch in
            BoardWatcherTests.batch(batch, holds: taskFile)
        })
        try await harness.call(KanbanGraphTests.nameQuery)
        #expect(await harness.sink.events.count == Self.firstCallPosts)
        await harness.graph.close()
    }
}

// MARK: - Clock of a different process

/// The clock of a test engine. When a test arms it, the clock also writes a new task to the board as a different
/// process. The engine reads the clock in each run of a call, so the write comes after the load of the board and
/// before the commit check of the run.
final class OtherProcessClock: Sendable {
    /// When the clock writes a task.
    enum Mode {
        /// The clock writes nothing.
        case idle

        /// The clock writes one task at the next read, and is then idle.
        case writingOnce

        /// The clock writes one task at each read.
        case writingAtEachRead
    }

    /// The state of the clock.
    private struct State {
        /// When the clock writes a task.
        var mode: Mode

        /// The ULID source of the writes of the different process.
        var ids: FixedULIDSource
    }

    /// The title of each task that the clock writes.
    static let title = "Written by a different process"

    /// The event log of the board.
    private let log: EventLog

    /// The state, behind a lock, because the engine can read the clock from a different thread.
    private let state = Mutex(State(mode: .idle, ids: GitGraphFixture.secondEngineIDs))

    /// Makes an idle clock.
    ///
    /// - Parameter log: The event log of the board that the clock writes to.
    init(writingTo log: EventLog) {
        self.log = log
    }

    /// Sets when the clock writes a task.
    ///
    /// - Parameter mode: The mode.
    func arm(_ mode: Mode) {
        state.withLock { state in state.mode = mode }
    }

    /// Gives ``KanbanGraphTests/time``, and writes a task first when the mode tells the clock to write.
    ///
    /// - Returns: The time.
    @Sendable
    func now() -> DateTime {
        state.withLock { state in
            switch state.mode {
            case .idle:
                return
            case .writingOnce:
                state.mode = .idle
            case .writingAtEachRead:
                break
            }
            do {
                _ = try KanbanGraphTests.writeTask(titled: Self.title, mintingFrom: &state.ids, to: log)
            } catch {
                Issue.record(error)
            }
        }
        return KanbanGraphTests.time
    }
}
