import Foundation
import Synchronization
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the engine actor: `execute`, the serial gate, and the board load (plan.md §5.4 steps 1 to 3, §7.2).
///
/// Each test uses a temporary repo directory, a fake board key, a fixed clock, and a fixed ULID source, so that each
/// response is deterministic (plan.md §11).
@Suite("KanbanGraph: execute, serial gate, and board load")
struct KanbanGraphTests {
    /// The fake key of the board. No test runs git.
    static let boardKey = BoardKey(localDirectoryName: "kanban")

    /// The time of the fixed clock and of each fixture event.
    static let time = ReplayTests.time(atStep: .zero)

    /// The name of the board of the fixture logs.
    static let boardName = "Kanban"

    /// The ref of the column of the fixture task.
    static let todoColumn = LocalRef.column(slug: "todo")

    /// The name of the column of the fixture task.
    static let todoName = "Todo"

    /// The title of the fixture task.
    static let taskTitle = "Port the parser"

    /// The title of the task that a test writes after the first query.
    static let laterTitle = "Write the tests"

    /// The name of the repo directory of the empty-repo test.
    static let emptyRepoName = "empty-repo"

    /// The public mutation name that each fixture event records.
    static let fixtureOperation = "addTask"

    /// The time that the first call of the gate test waits after it starts. Without the gate, the second call starts
    /// in this time.
    static let firstCallDelay = Duration.milliseconds(100)

    /// A query that reads the board, its tasks, and the column of each task. The one column of the fixture is the
    /// terminal column, so its tasks are done, and the query gives `excludeDone: false` to list them.
    static let boardQuery = """
        { board { name key tasks(excludeDone: false) {
            totalCount edges { node { id shortId title column { name } } } } } }
        """

    /// A query that reads the name of the board.
    static let nameQuery = "{ board { name } }"

    /// The response to ``nameQuery`` on the fixture logs.
    static let nameResponse = #"{"data":{"board":{"name":"\#(boardName)"}}}"#

    // MARK: - Fixture

    /// The fake key reader: it gives ``boardKey`` for each repo, and does not run git.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: ``boardKey``.
    @Sendable
    static func fakeKey(ofRepoAt root: URL) -> BoardKey {
        boardKey
    }

    /// Makes an engine for a repo, with the fixed clock.
    ///
    /// - Parameters:
    ///   - root: The root directory of the repo.
    ///   - keyReader: Gives the key of the board. The default is ``fakeKey(ofRepoAt:)``.
    ///   - observer: Gets a call when each call starts and ends, or `nil` for no calls.
    /// - Returns: The engine.
    static func makeGraph(
        at root: URL,
        readingKeyWith keyReader: @escaping @Sendable (URL) throws(BoardKeyError) -> BoardKey = fakeKey,
        reportingTo observer: (any KanbanCallObserver)? = nil
    ) throws -> KanbanGraph {
        try KanbanGraph(root: root, readingKeyWith: keyReader, timedBy: { time }, reportingTo: observer)
    }

    /// Runs one document with no variables and no operation name.
    ///
    /// - Parameters:
    ///   - query: The GraphQL document.
    ///   - graph: The engine.
    /// - Returns: The response JSON text.
    static func execute(_ query: String, on graph: KanbanGraph) async throws -> String {
        try await graph.execute(query: query, variables: [:], operationName: nil)
    }

    /// Writes one patch as an event to the log of its node. The event ids come from the ULID source.
    ///
    /// - Parameters:
    ///   - patch: The patch.
    ///   - ids: The ULID source of the event id and the transaction id.
    ///   - log: The event log of the board.
    static func append(_ patch: PatchInput, mintingFrom ids: inout FixedULIDSource, to log: EventLog) throws {
        let event = Event(
            id: ids.makeULID(),
            txn: ids.makeULID(),
            ops: [fixtureOperation],
            at: time,
            actor: ReplayTests.actor,
            patch: patch
        )
        try log.append(contentsOf: [event], toLogOf: patch.node)
    }

    /// Writes a task in the `todo` column.
    ///
    /// - Parameters:
    ///   - title: The title of the task.
    ///   - ids: The ULID source of the task id and the event ids.
    ///   - log: The event log of the board.
    /// - Returns: The ULID of the task.
    static func writeTask(
        titled title: String,
        mintingFrom ids: inout FixedULIDSource,
        to log: EventLog
    ) throws -> ULID {
        let task = ids.makeULID()
        let patch = try PatchInput(
            node: .task(task),
            set: ["title": .json(.string(title)), "column": .ref(.local(todoColumn))]
        )
        try append(patch, mintingFrom: &ids, to: log)
        return task
    }

    /// Writes the fixture logs: the board, one column, and one task in the column.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The ULID of the task, and the ULID source after the fixture, for more writes.
    static func writeFixture(inRepoAt root: URL) throws -> (task: ULID, ids: FixedULIDSource) {
        let log = EventLog(repositoryAt: root)
        var ids = FixedULIDSource(at: ReplayTests.date(atStep: .zero))
        try append(PatchInput(node: .board, set: ["name": .json(.string(boardName))]), mintingFrom: &ids, to: log)
        let column = try PatchInput(node: todoColumn, set: ["name": .json(.string(todoName)), "order": .json(0)])
        try append(column, mintingFrom: &ids, to: log)
        let task = try writeTask(titled: taskTitle, mintingFrom: &ids, to: log)
        return (task, ids)
    }

    /// Gives the JSON text of one task in the response to ``boardQuery``.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task.
    ///   - title: The title of the task.
    /// - Returns: The JSON object of the edge of the task, with sorted keys.
    static func edgeJSON(of task: ULID, titled title: String) -> String {
        let id = NodeURI(boardKey: boardKey.description, ref: .task(task)).description
        let node = #"{"column":{"name":"\#(todoName)"},"id":"\#(id)","shortId":"\#(ShortID(of: task).value)","#
        return #"{"node":\#(node)"title":"\#(title)"}}"#
    }

    /// Reads a response as a JSON object.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The response as a JSON object.
    static func object(of response: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
    }

    // MARK: - Tests

    @Test("A query on fixture logs returns the expected JSON with sorted keys")
    func queryOnFixtureLogs() async throws {
        let directory = try TemporaryDirectory()
        let task = try Self.writeFixture(inRepoAt: directory.url).task
        let response = try await Self.execute(Self.boardQuery, on: Self.makeGraph(at: directory.url))
        let tasks = #"{"edges":[\#(Self.edgeJSON(of: task, titled: Self.taskTitle))],"totalCount":1}"#
        let board = #"{"key":"\#(Self.boardKey)","name":"\#(Self.boardName)","tasks":\#(tasks)}"#
        #expect(response == #"{"data":{"board":\#(board)}}"#)
    }

    @Test("A query on a repo with no .kanban/ returns an empty board with the repo directory name and writes no file")
    func queryOnEmptyRepo() async throws {
        let directory = try TemporaryDirectory()
        let root = directory.url.appending(path: Self.emptyRepoName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let query = "{ board { name created tasks { totalCount } } }"
        let response = try await Self.execute(query, on: Self.makeGraph(at: root))
        let board = #"{"created":"\#(Self.time.rfc3339)","name":"\#(Self.emptyRepoName)","tasks":{"totalCount":0}}"#
        #expect(response == #"{"data":{"board":\#(board)}}"#)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test("Two concurrent execute calls on one KanbanGraph run one at a time")
    func concurrentCallsRunOneAtATime() async throws {
        let directory = try TemporaryDirectory()
        _ = try Self.writeFixture(inRepoAt: directory.url)
        let recorder = CallRecorder(delayingFirstCallBy: Self.firstCallDelay)
        let graph = try Self.makeGraph(at: directory.url, reportingTo: recorder)
        async let first = Self.execute(Self.nameQuery, on: graph)
        async let second = Self.execute(Self.nameQuery, on: graph)
        let responses = try await [first, second]
        #expect(responses == [Self.nameResponse, Self.nameResponse])
        #expect(recorder.events == [.start, .finish, .start, .finish])
    }

    @Test("The first call loads the board, and a later call reads the same graph from memory")
    func boardStaysInMemory() async throws {
        let directory = try TemporaryDirectory()
        var (_, ids) = try Self.writeFixture(inRepoAt: directory.url)
        let graph = try Self.makeGraph(at: directory.url)
        let first = try await Self.execute(Self.boardQuery, on: graph)
        _ = try Self.writeTask(titled: Self.laterTitle, mintingFrom: &ids, to: EventLog(repositoryAt: directory.url))
        let second = try await Self.execute(Self.boardQuery, on: graph)
        #expect(second == first)
    }

    @Test("A document with a syntax error gives a response with one error and no data, and execute does not throw")
    func syntaxErrorDoesNotThrow() async throws {
        let directory = try TemporaryDirectory()
        let response = try await Self.execute("{ board {", on: Self.makeGraph(at: directory.url))
        let object = try Self.object(of: response)
        let errors = try #require(object["errors"] as? [Any])
        #expect(errors.count == 1)
        #expect(object["data"] == nil)
    }

    @Test("The operation name selects one operation of a document, and the variables reach it")
    func operationNameSelectsOperation() async throws {
        let directory = try TemporaryDirectory()
        _ = try Self.writeFixture(inRepoAt: directory.url)
        let document = """
            query Names { board { name } }
            query Page($first: Int) {
                board { tasks(first: $first, excludeDone: false) { edges { node { title } } totalCount } }
            }
            """
        let response = try await Self.makeGraph(at: directory.url).execute(
            query: document,
            variables: ["first": 0],
            operationName: "Page"
        )
        #expect(response == #"{"data":{"board":{"tasks":{"edges":[],"totalCount":1}}}}"#)
    }

    @Test("A call that fails to read the key throws, and the next call runs and loads the board")
    func failedCallReleasesGate() async throws {
        let directory = try TemporaryDirectory()
        _ = try Self.writeFixture(inRepoAt: directory.url)
        let reader = FailOnceKeyReader(giving: Self.boardKey)
        let graph = try Self.makeGraph(at: directory.url) { root throws(BoardKeyError) in
            try reader.key(ofRepoAt: root)
        }
        await #expect(throws: FailOnceKeyReader.failure) {
            try await Self.execute(Self.nameQuery, on: graph)
        }
        #expect(try await Self.execute(Self.nameQuery, on: graph) == Self.nameResponse)
    }

    @Test("The schema SDL has the board query and no patch mutation")
    func schemaSDLIsPublicSchema() {
        #expect(KanbanGraph.schemaSDL.contains("board(id: String): Board"))
        #expect(!KanbanGraph.schemaSDL.contains("patch"))
    }
}

// MARK: - Call recorder

/// Records the start and the end of each call of a ``KanbanGraph``. The first call waits after it starts, so that a
/// second call that does not wait for the gate starts before the first call ends.
final class CallRecorder: KanbanCallObserver {
    /// One recorded event.
    enum CallEvent: Equatable {
        /// A call started.
        case start

        /// A call ended.
        case finish
    }

    /// The time that the first call waits after it starts.
    private let delay: Duration

    /// The recorded events, behind a lock, because the calls can run on different threads.
    private let recorded = Mutex<[CallEvent]>([])

    /// Makes a recorder.
    ///
    /// - Parameter delay: The time that the first call waits after it starts.
    init(delayingFirstCallBy delay: Duration) {
        self.delay = delay
    }

    /// The recorded events, in the order that they occurred.
    var events: [CallEvent] {
        recorded.withLock { events in events }
    }

    /// Records a start. The first start waits for the delay.
    func callDidStart() async {
        let isFirst = recorded.withLock { events in
            events.append(.start)
            return events.count == 1
        }
        guard isFirst else {
            return
        }
        do {
            try await Task.sleep(for: delay)
        } catch {
            Issue.record(error)
        }
    }

    /// Records an end.
    func callDidFinish() {
        recorded.withLock { events in events.append(.finish) }
    }
}

// MARK: - Key reader

/// A fake key reader whose first read fails, as when git cannot start. Each later read gives the key.
final class FailOnceKeyReader: Sendable {
    /// The error of the first read.
    static let failure = BoardKeyError.gitUnavailable(message: "git is not installed")

    /// The key of each read after the first.
    private let key: BoardKey

    /// `true` after the first read.
    private let didRead = Mutex(false)

    /// Makes a reader.
    ///
    /// - Parameter key: The key of each read after the first.
    init(giving key: BoardKey) {
        self.key = key
    }

    /// Reads the key of a repo.
    ///
    /// - Parameter root: The root directory of the repo. The reader does not read it.
    /// - Returns: The key.
    /// - Throws: ``failure`` on the first read.
    func key(ofRepoAt root: URL) throws(BoardKeyError) -> BoardKey {
        let isFirst = didRead.withLock { didRead in
            defer { didRead = true }
            return !didRead
        }
        guard !isFirst else {
            throw Self.failure
        }
        return key
    }
}
