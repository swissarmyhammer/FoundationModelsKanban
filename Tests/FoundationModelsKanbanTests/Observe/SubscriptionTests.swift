import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// The number of minutes of the time limit of each test of ``SubscriptionTests``. The constant is at file scope,
/// because the `@Suite` attribute of a type cannot read a member of the same type.
private let subscriptionSuiteMinutes = 1

/// Tests the change feed of the engine: `Subscription.changes` and `KanbanGraph.subscribe` (plan.md §6.7, §12 item
/// 17).
///
/// Each test reads the events of a subscription with ``StreamWait``, so a test that waits for an event that does not
/// come stops at the time limit. A test that must show that a change sends only one event makes a second change, and
/// expects the event of the second change next. Each test closes each engine that it makes.
@Suite("Subscriptions: the change feed", .timeLimit(.minutes(subscriptionSuiteMinutes)))
struct SubscriptionTests {
    /// The number of events that a test reads when it expects the event of one change.
    static let oneEvent = 1

    /// The number of events that a test reads when it expects the events of two changes.
    private static let twoEvents = 2

    /// The number of lines of the log file of the task before the line of the branch in the merged file: the line of
    /// the fixture.
    private static let linesBeforeBranchLine = 1

    /// The selection of each event of the tests: the transaction, the operations, and the id and the kind of each
    /// update.
    static let selection = "{ txn ops updates { id kind } }"

    /// The arguments of a subscription to the task updates only. A mutation also writes the session actor, and this
    /// filter leaves out that update.
    static let taskArguments = #"(filter: "~task")"#

    /// The query of the newest transaction of the current board.
    static let latestTxnQuery = "{ board { history(first: 1) { txn } } }"

    /// The name of the public mutation of a title change.
    static let updateTask = "updateTask"

    // MARK: - Helpers

    /// Makes a subscription document with ``selection``.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the `changes` field, for example `(filter: "~task")`, or `""` for none.
    ///   - selection: The selection of each event. The default is ``selection``.
    /// - Returns: The document.
    static func subscription(_ arguments: String, selecting selection: String = selection) -> String {
        "subscription { changes\(arguments) \(selection) }"
    }

    /// Subscribes to a document with no variables and no operation name.
    ///
    /// - Parameters:
    ///   - document: The subscription document.
    ///   - graph: The engine.
    /// - Returns: The stream of the responses, one for each event.
    static func subscribe(
        _ document: String,
        on graph: KanbanGraph
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await graph.subscribe(query: document, variables: [:], operationName: nil)
    }

    /// Reads the next events of a stream, and stops at the time limit.
    ///
    /// - Parameters:
    ///   - count: The number of events to read.
    ///   - stream: The stream of a subscription.
    /// - Returns: The events, in the order of the stream. The list is shorter when the stream ends or the time limit
    ///   ends first.
    static func events(_ count: Int, of stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        let events = try await StreamWait.value {
            try await stream.prefix(count).reduce(into: [String]()) { events, event in events.append(event) }
        }
        return events ?? []
    }

    /// Reads each event of a stream until the stream ends, and stops at the time limit.
    ///
    /// - Parameter stream: The stream of a subscription.
    /// - Returns: The events, or `nil` when the stream does not end before the time limit.
    static func allEvents(of stream: AsyncThrowingStream<String, Error>) async throws -> [String]? {
        try await StreamWait.value {
            try await stream.reduce(into: [String]()) { events, event in events.append(event) }
        }
    }

    /// Reads each event of a subscription that cannot start, and gives the code of the first error of its first
    /// event.
    ///
    /// - Parameter stream: The stream of the subscription.
    /// - Returns: The number of events before the stream ends, and the `extensions.code` of the first error of the
    ///   first event.
    /// - Throws: An error when the stream does not end before the time limit, or when the first event has no error
    ///   with `extensions`.
    private static func errorCode(
        of stream: AsyncThrowingStream<String, Error>
    ) async throws -> (eventCount: Int, code: String?) {
        let events = try #require(try await allEvents(of: stream))
        let errors = try NameRewriteTests.errors(of: try #require(events.first))
        let extensions = try #require(errors.first?["extensions"] as? [String: Any])
        return (events.count, extensions["code"] as? String)
    }

    /// Gives the response of one event with ``selection``.
    ///
    /// - Parameters:
    ///   - txn: The transaction ULID text.
    ///   - operation: The one public mutation of the transaction.
    ///   - updates: The JSON objects of the updates, in order.
    /// - Returns: The response JSON text, with sorted keys.
    static func event(txn: String, operation: String, updates: [String]) -> String {
        let updateList = updates.joined(separator: ",")
        return #"{"data":{"changes":{"ops":["\#(operation)"],"txn":"\#(txn)","updates":[\#(updateList)]}}}"#
    }

    /// Gives the JSON object of one update of a task with ``selection``.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - kind: The kind of the update.
    /// - Returns: The JSON object, with sorted keys.
    static func update(ofTask task: String, kind: UpdateKind) -> String {
        #"{"id":"\#(task)","kind":"\#(kind.rawValue)"}"#
    }

    /// Gives the full URI of a task of the fixture board.
    ///
    /// - Parameter task: The ULID of the task.
    /// - Returns: The URI text.
    static func id(of task: ULID) -> String {
        NodeURI(boardKey: KanbanGraphTests.boardKey.description, ref: .task(task)).description
    }

    /// Gives the response of the event of a title change of the fixture task.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task.
    ///   - txn: The transaction ULID text.
    ///   - operation: The one public mutation of the transaction.
    /// - Returns: The response JSON text.
    static func titleEvent(of task: ULID, txn: String, operation: String) -> String {
        patchEvent(of: task, kind: .updated, txn: txn, operation: operation)
    }

    /// Gives the response of an event with one update of a task from a patch line.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task.
    ///   - kind: The kind of the update.
    ///   - txn: The transaction ULID text.
    ///   - operation: The one public mutation of the transaction.
    /// - Returns: The response JSON text.
    private static func patchEvent(of task: ULID, kind: UpdateKind, txn: String, operation: String) -> String {
        event(txn: txn, operation: operation, updates: [update(ofTask: id(of: task), kind: kind)])
    }

    /// Gives the newest transaction of the current board.
    ///
    /// - Parameter graph: The engine.
    /// - Returns: The transaction ULID text.
    /// - Throws: An error when the response has no transaction.
    static func latestTxn(on graph: KanbanGraph) async throws -> String {
        let response = try await KanbanGraphTests.execute(latestTxnQuery, on: graph)
        let board = try #require(NameRewriteTests.data(of: response)["board"] as? [String: Any], "\(response)")
        let history = try #require(board["history"] as? [[String: Any]], "\(response)")
        return try #require(history.first?["txn"] as? String, "\(response)")
    }

    /// Changes the title of a task with an `updateTask` call, and gives the event that the call sends.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task.
    ///   - title: The new title.
    ///   - graph: The engine.
    /// - Returns: The response JSON text of the event, with the transaction of the call.
    static func changeTitle(of task: ULID, to title: String, on graph: KanbanGraph) async throws -> String {
        let field = UndoTests.titleField(title, of: task)
        return try await runMutation(field, operation: updateTask, of: task, kind: .updated, on: graph)
    }

    /// Deletes a task with a `deleteTask` call, and gives the event that the call sends.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task.
    ///   - graph: The engine.
    /// - Returns: The response JSON text of the event, with the transaction of the call.
    static func deleteTask(_ task: ULID, on graph: KanbanGraph) async throws -> String {
        let field = TaskOperationTests.taskField(MutationName.deleteTask, of: task)
        return try await runMutation(field, operation: MutationName.deleteTask, of: task, kind: .deleted, on: graph)
    }

    /// Runs one mutation field that changes one task, and gives the event that the call sends.
    ///
    /// - Parameters:
    ///   - field: The mutation field.
    ///   - operation: The public mutation of the field.
    ///   - task: The ULID of the task that the mutation changes.
    ///   - kind: The kind of the update of the task.
    ///   - graph: The engine.
    /// - Returns: The response JSON text of the event, with the transaction of the call.
    private static func runMutation(
        _ field: String,
        operation: String,
        of task: ULID,
        kind: UpdateKind,
        on graph: KanbanGraph
    ) async throws -> String {
        _ = try await CommentTests.run(field, on: graph)
        return patchEvent(of: task, kind: kind, txn: try await latestTxn(on: graph), operation: operation)
    }

    /// Gives the transaction ULID of the next event that ``KanbanGraphTests/append(_:mintingFrom:to:)`` writes with a
    /// ULID source. The append mints the event id first, and then the transaction ULID.
    ///
    /// - Parameter ids: The ULID source of the append.
    /// - Returns: The transaction ULID text.
    static func nextTxn(of ids: FixedULIDSource) -> String {
        var probe = ids
        _ = probe.makeULID()
        return probe.makeULID().ulidString
    }

    // MARK: - Changes from this process

    @Test("A commit in this process sends one Change to a matching subscriber")
    func commitSendsOneChange() async throws {
        let directory = try TemporaryDirectory()
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let stream = try await Self.subscribe(Self.subscription(Self.taskArguments), on: graph)
        let first = try await Self.changeTitle(of: task, to: KanbanGraphTests.laterTitle, on: graph)
        let second = try await Self.changeTitle(of: task, to: KanbanGraphTests.taskTitle, on: graph)
        #expect(try await Self.events(Self.twoEvents, of: stream) == [first, second])
        await graph.close()
    }

    @Test("A change with no update that matches the ^id filter is not sent")
    func changeWithNoMatchingUpdateIsNotSent() async throws {
        let directory = try TemporaryDirectory()
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let arguments = #"(filter: "\#(AddUpdateTaskTests.sigilRef(of: task))")"#
        let stream = try await Self.subscribe(Self.subscription(arguments), on: graph)
        _ = try await CrossRepoFixture.addTask(with: "", on: graph)
        let expected = try await Self.changeTitle(of: task, to: KanbanGraphTests.laterTitle, on: graph)
        #expect(try await Self.events(Self.oneEvent, of: stream) == [expected])
        await graph.close()
    }

    @Test("A #DELETED subscription sends the change of a deleteTask, and not the change of an undeleteTask")
    func deletedFilterLeavesOutUndelete() async throws {
        let directory = try TemporaryDirectory()
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let stream = try await Self.subscribe(Self.subscription(HistoryTests.deletedFilterArguments), on: graph)
        let firstDelete = try await Self.deleteTask(task, on: graph)
        _ = try await CommentTests.run(TaskOperationTests.taskField(MutationName.undeleteTask, of: task), on: graph)
        let secondDelete = try await Self.deleteTask(task, on: graph)
        #expect(try await Self.events(Self.twoEvents, of: stream) == [firstDelete, secondDelete])
        await graph.close()
    }

    @Test("A subscription with a filter that does not name DONE sends the change of a done task")
    func filterWithNoDoneAtomSendsDoneTask() async throws {
        let directory = try TemporaryDirectory()
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let stream = try await Self.subscribe(Self.subscription(#"(filter: "!~actor")"#), on: graph)
        let expected = try await Self.changeTitle(of: task, to: KanbanGraphTests.laterTitle, on: graph)
        #expect(try await Self.events(Self.oneEvent, of: stream) == [expected])
        await graph.close()
    }

    // MARK: - Changes from other processes

    @Test("A log line that a different process appends sends one Change")
    func appendedLineSendsOneChange() async throws {
        let directory = try TemporaryDirectory()
        var (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let stream = try await Self.subscribe(Self.subscription(Self.taskArguments), on: graph)
        let lineTxn = Self.nextTxn(of: ids)
        try BoardWatcherTests.writeLaterTitle(to: task, mintingFrom: &ids, in: EventLog(repositoryAt: directory.url))
        let lineEvent = Self.titleEvent(of: task, txn: lineTxn, operation: KanbanGraphTests.fixtureOperation)
        #expect(try await Self.events(Self.oneEvent, of: stream) == [lineEvent])
        let laterEvent = try await Self.changeTitle(of: task, to: KanbanGraphTests.taskTitle, on: graph)
        #expect(try await Self.events(Self.oneEvent, of: stream) == [laterEvent])
        await graph.close()
    }

    @Test("A union merge that rewrites a log file sends only the new transactions")
    func rewrittenFileSendsOnlyNewTransactions() async throws {
        let directory = try TemporaryDirectory()
        var (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let stream = try await Self.subscribe(Self.subscription(Self.taskArguments), on: graph)
        let ownEvent = try await Self.changeTitle(of: task, to: KanbanGraphTests.laterTitle, on: graph)
        #expect(try await Self.events(Self.oneEvent, of: stream) == [ownEvent])
        let branch = try TemporaryDirectory()
        let branchTxn = Self.nextTxn(of: ids)
        try BoardWatcherTests.writeLaterTitle(to: task, mintingFrom: &ids, in: EventLog(repositoryAt: branch.url))
        let file = EventLog(repositoryAt: directory.url).fileURL(for: .task(task))
        let branchFile = EventLog(repositoryAt: branch.url).fileURL(for: .task(task))
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        let branchLine = try String(contentsOf: branchFile, encoding: .utf8).split(separator: "\n")
        let mergedLines = lines.prefix(Self.linesBeforeBranchLine) + branchLine
            + lines.dropFirst(Self.linesBeforeBranchLine)
        let merged = mergedLines.map { line in "\(line)\n" }.joined()
        try merged.write(to: file, atomically: true, encoding: .utf8)
        let branchEvent = Self.titleEvent(of: task, txn: branchTxn, operation: KanbanGraphTests.fixtureOperation)
        #expect(try await Self.events(Self.oneEvent, of: stream) == [branchEvent])
        let laterEvent = try await Self.changeTitle(of: task, to: KanbanGraphTests.taskTitle, on: graph)
        #expect(try await Self.events(Self.oneEvent, of: stream) == [laterEvent])
        await graph.close()
    }

    // MARK: - Related boards

    @Test("A task of a related board that becomes done sends a ready update to a subscriber on the dependent board")
    func doneTaskOfRelatedBoardSendsReadyUpdate() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let lib = try GitGraphFixture.makeGraph(at: repos.lib)
        let target = try await CrossRepoFixture.addTask(with: "", on: lib)
        await lib.close()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        await app.close()
        let watcher = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        let fieldSelection = "{ txn ops updates { id kind fields { name before after } } }"
        let document = Self.subscription(Self.taskArguments, selecting: fieldSelection)
        let stream = try await Self.subscribe(document, on: watcher)
        let done = try #require(DefaultColumn.all.last).slug
        let patch = try PatchInput(
            node: .task(AddUpdateTaskTests.firstTask(in: target)),
            set: [PropertyName.column: .ref(.local(.column(slug: done)))]
        )
        var ids = GitGraphFixture.thirdEngineIDs
        let txn = Self.nextTxn(of: ids)
        try KanbanGraphTests.append(patch, mintingFrom: &ids, to: EventLog(repositoryAt: repos.lib))
        let event = try #require(try await Self.events(Self.oneEvent, of: stream).first)
        #expect(event.contains(#""txn":"\#(txn)""#))
        #expect(event.contains(#""id":"\#(task)","kind":"\#(UpdateKind.updated.rawValue)""#))
        #expect(event.contains(#"{"after":true,"before":false,"name":"ready"}"#))
        await watcher.close()
    }

    // MARK: - Errors and close

    @Test("A subscription with a filter that does not parse gives one response with INVALID_FILTER, and ends")
    func invalidFilterGivesOneErrorAndEnds() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let stream = try await Self.subscribe(Self.subscription(#"(filter: "&&")"#), on: graph)
        let (eventCount, code) = try await Self.errorCode(of: stream)
        #expect(eventCount == Self.oneEvent)
        #expect(code == "INVALID_FILTER")
        await graph.close()
    }

    @Test("A subscription on a board with no repo directory gives one response with NOT_FOUND, and ends")
    func boardWithNoDirectoryGivesOneErrorAndEnds() async throws {
        let stream = try await PublicSchema().subscribe(
            to: Self.subscription(""),
            variables: [:],
            operationName: nil,
            formattedWith: .sortedKeys,
            context: GraphQLEngineTests.makeContext()
        )
        let (eventCount, code) = try await Self.errorCode(of: stream)
        #expect(eventCount == Self.oneEvent)
        #expect(code == "NOT_FOUND")
    }

    @Test("close() ends each subscription stream")
    func closeEndsStreams() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let stream = try await Self.subscribe(Self.subscription(""), on: graph)
        await graph.close()
        #expect(try await Self.allEvents(of: stream) == [])
    }
}
