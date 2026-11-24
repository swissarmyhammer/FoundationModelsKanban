import Foundation
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the read of the board of a folder that opens no session: ``KanbanHost/readBoard(inFolder:)`` (TestudoApp
/// D214).
///
/// Each test uses a temporary folder. A test that needs a board writes it through a session of ``KanbanGraphTests``,
/// or writes the log files directly with the fixture writers of the loader tests. The read must give the same values
/// as the GraphQL query of a session, and it must write nothing.
@Suite("Board snapshot: the read of a board with no session", .watcherBudget)
struct BoardSnapshotTests {
    /// The slug of the actor that the session board adds.
    static let actorSlug = "alice"

    /// The name of the actor that the session board adds.
    static let actorName = "Alice"

    /// The tag of the first task of the session board.
    static let tagName = "bug"

    /// The title of the first task of the session board.
    static let firstTitle = "Port the parser"

    /// The body of the first task of the session board.
    static let firstBody = "Read the grammar."

    /// The title of the second task of the session board. The second task depends on the first task.
    static let secondTitle = "Write the tests"

    /// The body of the comment on the first task.
    static let commentBody = "Looks good."

    /// The slug of the terminal column of a new board. The session board moves the first task to it.
    static let doneColumn = "done"

    /// The step of the clock of the first write of the session board.
    static let firstWriteStep = 1

    /// The step of the clock of the second write of the session board.
    static let secondWriteStep = 2

    /// The title that the torn line of the torn-line test sets.
    static let tornTitle = "torn"

    /// The title that the whole line of the torn-line test sets.
    static let wholeTitle = "first"

    /// The title of the task whose body holds the markers in the marker test.
    static let markerTitle = "Check the markers"

    /// The tag that a `#tag` marker of the marker test names.
    static let markerTag = "ui"

    /// A default column that holds no task of the session board. The column test deletes it.
    static let emptyColumn = "review"

    /// The key of the errors of a GraphQL response, as JSON text.
    static let errorsKey = #""errors""#

    /// The largest number of tasks that the GraphQL query of a session reads in one page.
    static let pageSize = 100

    /// The mutation of the first write of the session board: the actor, and the first task with a body, a tag, and
    /// an assignee.
    static let firstWrite = """
        mutation {
          addActor(input: { id: "\(actorSlug)", name: "\(actorName)" }) { id }
          addTask(input: {
            title: "\(firstTitle)", body: "\(firstBody)", tags: ["\(tagName)"], assignees: ["\(actorSlug)"]
          }) { id }
        }
        """

    /// The mutation of the second write of the session board: the second task, which depends on the first task, a
    /// comment on the first task, and the move of the first task to the terminal column.
    static let secondWrite = """
        mutation($first: ID!) {
          addTask(input: { title: "\(secondTitle)", dependsOn: [$first] }) { id }
          addComment(input: { task: $first, body: "\(commentBody)" }) { id }
          moveTask(input: { id: $first, column: "\(doneColumn)" }) { id }
        }
        """

    /// The GraphQL query of a session that reads each field of the snapshot.
    static let boardQuery = """
        { board {
          columns { id name order }
          tasks(first: \(pageSize)) { edges { node {
            id shortId title body created updated virtualTags
            column { id } tags { name } assignees { id name } dependsOn { id }
            comments { id body created author { id name } }
          } } }
        } }
        """

    // MARK: - Fixture

    /// The session board of a folder, and the ULID of its first task.
    struct SessionBoard {
        /// The session. The test closes it before the read.
        let graph: KanbanGraph

        /// The ULID text of the first task.
        let firstTask: String
    }

    /// Writes the session board to a folder through a session of ``KanbanGraphTests``: two writes at two times of the
    /// clock.
    ///
    /// - Parameter folder: The folder of the board.
    /// - Returns: The session and the ULID of its first task.
    /// - Throws: An error when a write fails.
    static func writeSessionBoard(in folder: URL) async throws -> SessionBoard {
        let clock = TestClock(at: ReplayTests.date(atStep: firstWriteStep))
        let graph = try KanbanGraphTests.makeGraph(at: folder, timedBy: { DateTime(clock.now) })
        let first = try JSONDecoder().decode(
            AddTaskResponse.self,
            from: Data(try await KanbanGraphTests.execute(firstWrite, on: graph).utf8)
        )
        clock.move(to: ReplayTests.date(atStep: secondWriteStep))
        let variables: [String: Map] = ["first": .string(first.data.addTask.id)]
        let second = try await KanbanGraphTests.execute(secondWrite, variables: variables, on: graph)
        try #require(!second.contains(errorsKey), "\(second)")
        return SessionBoard(graph: graph, firstTask: try localID(of: first.data.addTask.id))
    }

    /// Gives the local id of a node from its full URI: the slug of a column or an actor, or the ULID of a task or a
    /// comment.
    ///
    /// - Parameter uri: The full URI of the node, as the GraphQL `id` field gives it.
    /// - Returns: The local id.
    /// - Throws: An error when the text is not a node URI with a local id.
    static func localID(of uri: String) throws -> String {
        try #require(try NodeURI(parsing: uri).ref.localID)
    }

    /// Gives the date of a GraphQL `DateTime` text.
    ///
    /// - Parameter text: The RFC 3339 text.
    /// - Returns: The date.
    /// - Throws: An error when the text is not an RFC 3339 time.
    static func date(of text: String) throws -> Date {
        try DateTime(rfc3339: text).date
    }

    /// Reads the board of a folder with the GraphQL query of a session, and makes the snapshot that the read must
    /// give.
    ///
    /// - Parameters:
    ///   - graph: The session.
    ///   - folder: The folder of the board. The expected snapshot holds the stamp of its board now.
    /// - Returns: The expected snapshot.
    /// - Throws: An error when the query fails, its response does not decode, or the folder gives no stamp.
    static func expectedSnapshot(from graph: KanbanGraph, in folder: URL) async throws -> BoardSnapshot {
        let response = try await KanbanGraphTests.execute(boardQuery, on: graph)
        let board = try JSONDecoder().decode(BoardResponse.self, from: Data(response.utf8)).data.board
        return BoardSnapshot(
            columns: try board.columns.map { column in
                BoardSnapshot.Column(id: try localID(of: column.id), name: column.name, order: column.order)
            },
            tasks: try board.tasks.edges.map { edge in try expectedTask(from: edge.node) },
            stamp: try #require(KanbanHost.shared.boardStamp(ofFolder: folder))
        )
    }

    /// Makes the snapshot task that the read must give for one task of the GraphQL response.
    ///
    /// - Parameter task: The task of the response.
    /// - Returns: The expected task.
    /// - Throws: An error when an id or a date of the response does not parse.
    static func expectedTask(from task: TaskResponse) throws -> BoardSnapshot.Task {
        BoardSnapshot.Task(
            id: try localID(of: task.id),
            shortID: task.shortId,
            title: task.title,
            description: task.body,
            column: try localID(of: task.column.id),
            tags: task.tags.map(\.name),
            assignees: try task.assignees.map(expectedActor(from:)),
            dependsOn: try task.dependsOn.map { dependency in try localID(of: dependency.id) },
            comments: try task.comments.map { comment in
                BoardSnapshot.Comment(
                    id: try localID(of: comment.id),
                    author: try expectedActor(from: comment.author),
                    text: comment.body,
                    created: try date(of: comment.created)
                )
            },
            created: try date(of: task.created),
            updated: try date(of: task.updated),
            isDone: task.virtualTags.contains(VirtualTag.done.rawValue)
        )
    }

    /// Makes the snapshot actor that the read must give for one actor of the GraphQL response.
    ///
    /// - Parameter actor: The actor of the response.
    /// - Returns: The expected actor.
    /// - Throws: An error when the id of the actor does not parse.
    static func expectedActor(from actor: ActorResponse) throws -> BoardSnapshot.Actor {
        BoardSnapshot.Actor(id: try localID(of: actor.id), name: actor.name)
    }

    /// Requires that the expected snapshot of the session board holds each value that the session wrote, so that a
    /// comparison with it examines each field.
    ///
    /// - Parameters:
    ///   - snapshot: The expected snapshot, from the GraphQL query of the session.
    ///   - firstTask: The ULID text of the first task.
    /// - Throws: An error when a value is missing.
    static func requireSessionValues(in snapshot: BoardSnapshot, firstTask: String) throws {
        let first = try #require(snapshot.tasks.first { task in task.id == firstTask })
        let second = try #require(snapshot.tasks.first { task in task.id != firstTask })
        try #require(first.tags == [tagName] && first.assignees.map(\.id) == [actorSlug])
        try #require(first.comments.map(\.text) == [commentBody] && first.isDone && first.column == doneColumn)
        try #require(second.dependsOn == [firstTask] && !second.isDone && first.updated > first.created)
    }

    /// Writes a board with one task that depends on one target, reads it, and gives the dependencies of the task.
    ///
    /// - Parameter target: The stored ref of the dependency.
    /// - Returns: The `dependsOn` value of the task in the snapshot.
    /// - Throws: An error when the write or the read fails.
    static func dependencies(ofTaskDependingOn target: StoredRef) async throws -> [String] {
        let directory = try TemporaryDirectory()
        let patch = try PatchInput(
            node: try ReplayTests.taskRef(),
            set: ["title": .json(.string(wholeTitle))],
            add: ["dependsOn": [target]]
        )
        try LoaderTests.append(patch, atStep: firstWriteStep, to: EventLog(repositoryAt: directory.url))
        let snapshot = try #require(try await KanbanHost.shared.readBoard(inFolder: directory.url).snapshot)
        return try #require(snapshot.tasks.first).dependsOn
    }

    /// Gives each path under a folder, also under `.git` and `.kanban`, with its modification date.
    ///
    /// - Parameter folder: The folder.
    /// - Returns: The modification date of each path, by the path relative to the folder.
    /// - Throws: An error when a path cannot be read.
    static func pathDates(under folder: URL) throws -> [String: Date] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys))
        let urls = enumerator.compactMap { item in item as? URL }
        let rootPath = folder.resolvingSymlinksInPath().path
        let pairs = try urls.map { url in
            let path = String(url.resolvingSymlinksInPath().path.dropFirst(rootPath.count))
            let date = try #require(try url.resourceValues(forKeys: Set(keys)).contentModificationDate)
            return (path, date)
        }
        return Dictionary(uniqueKeysWithValues: pairs)
    }

    /// Makes a folder that is a git repo with no commit, and writes the session board to it. The session reads a
    /// fake key, so it makes no commit. The session is closed at the return.
    ///
    /// - Parameter directory: The temporary directory of the test.
    /// - Returns: The folder.
    /// - Throws: An error when git or a write fails.
    static func makeRepoWithNoCommit(in directory: TemporaryDirectory) async throws -> URL {
        try await GitSandbox.initializeRepo(at: directory.url)
        let board = try await Self.writeSessionBoard(in: directory.url)
        await board.graph.close()
        return directory.url
    }

    /// Reads a folder with a host that records each engine load and each FSEvents stream start.
    ///
    /// - Parameters:
    ///   - folder: The folder of the board.
    ///   - loads: Records each engine load of the host.
    ///   - events: Records each FSEvents stream start of the host.
    /// - Throws: An error of the read.
    static func read(_ folder: URL, recordingLoadsIn loads: LoadRecorder, events: QuietFolderEvents) async throws {
        let host = HostFixture.makeHost(observingLoadsWith: loads, watchingWith: events)
        _ = try await host.readBoard(inFolder: folder)
        await host.close()
    }

    /// Writes the board fixture of the loader tests to a new temporary directory.
    ///
    /// - Returns: The temporary directory and the refs of the fixture nodes.
    /// - Throws: An error when a write fails.
    static func makeFixtureBoard() throws -> (directory: TemporaryDirectory, refs: [LocalRef]) {
        let directory = try TemporaryDirectory()
        let refs = try LoaderTests.writeBoard(to: EventLog(repositoryAt: directory.url))
        return (directory, refs)
    }

    // MARK: - No board

    @Test("A folder with no .kanban folder gives no board, not an error")
    func folderWithNoBoardGivesNoBoard() async throws {
        let directory = try TemporaryDirectory()
        #expect(try await KanbanHost.shared.readBoard(inFolder: directory.url) == .noBoard)
    }

    @Test("A .kanban folder of the old Rust kanban gives the error of a session")
    func rustBoardGivesIncompatibleBoard() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let rustDirectory = log.directory.appending(path: "boards", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rustDirectory, withIntermediateDirectories: true)
        await #expect(throws: KanbanError.incompatibleBoard(directory: log.directory.path)) {
            try await KanbanHost.shared.readBoard(inFolder: directory.url)
        }
    }

    @Test("A file with the name .kanban, not a folder, gives no board")
    func kanbanFileGivesNoBoard() async throws {
        let directory = try TemporaryDirectory()
        let file = EventLog(repositoryAt: directory.url).directory.path
        try #require(FileManager.default.createFile(atPath: file, contents: Data()))
        #expect(try await KanbanHost.shared.readBoard(inFolder: directory.url) == .noBoard)
    }

    // MARK: - Values

    @Test("A board that a session wrote gives the values of the GraphQL query of the session")
    func sessionBoardGivesQueryValues() async throws {
        let directory = try TemporaryDirectory()
        let board = try await Self.writeSessionBoard(in: directory.url)
        let expected = try await Self.expectedSnapshot(from: board.graph, in: directory.url)
        await board.graph.close()
        try Self.requireSessionValues(in: expected, firstTask: board.firstTask)
        #expect(try await KanbanHost.shared.readBoard(inFolder: directory.url) == .board(expected))
    }

    @Test("Tag markers and dependency markers in a body give the values of the GraphQL query of the session")
    func bodyMarkersGiveQueryValues() async throws {
        let directory = try TemporaryDirectory()
        let board = try await Self.writeSessionBoard(in: directory.url)
        let firstULID = try #require(ULID(ulidString: board.firstTask))
        let marker = NodeURI(boardKey: KanbanGraphTests.boardKey.description, ref: .task(firstULID)).description
        let body = "Needs \(marker) #\(Self.markerTag)"
        let field = #"addTask(input: { title: "\#(Self.markerTitle)", body: "\#(body)" }) { id }"#
        _ = try await CommentTests.run(field, on: board.graph)
        let expected = try await Self.expectedSnapshot(from: board.graph, in: directory.url)
        await board.graph.close()
        let markerTask = try #require(expected.tasks.first { task in task.title == Self.markerTitle })
        try #require(markerTask.tags == [Self.markerTag] && markerTask.dependsOn == [board.firstTask])
        #expect(try await KanbanHost.shared.readBoard(inFolder: directory.url) == .board(expected))
    }

    @Test("A deleted comment is not in the snapshot")
    func deletedCommentIsLeftOut() async throws {
        let directory = try TemporaryDirectory()
        let board = try await Self.writeSessionBoard(in: directory.url)
        let before = try #require(try await KanbanHost.shared.readBoard(inFolder: directory.url).snapshot)
        let comment = try #require(before.tasks.first { task in task.id == board.firstTask }?.comments.first)
        _ = try await CommentTests.run(CommentTests.nodeField("deleteComment", naming: comment.id), on: board.graph)
        await board.graph.close()
        let after = try #require(try await KanbanHost.shared.readBoard(inFolder: directory.url).snapshot)
        #expect(after.tasks.first { task in task.id == board.firstTask }?.comments == [])
    }

    @Test("A deleted column is not in the snapshot")
    func deletedColumnIsLeftOut() async throws {
        let directory = try TemporaryDirectory()
        let board = try await Self.writeSessionBoard(in: directory.url)
        let deletion = CommentTests.nodeField("deleteColumn", naming: Self.emptyColumn)
        _ = try await CommentTests.run(deletion, on: board.graph)
        await board.graph.close()
        let snapshot = try #require(try await KanbanHost.shared.readBoard(inFolder: directory.url).snapshot)
        let kept = DefaultColumn.all.map(\.slug).filter { slug in slug != Self.emptyColumn }
        #expect(snapshot.columns.map(\.id) == kept)
    }

    @Test("A dependency on a task of a different board gives the URI text of that task")
    func crossBoardDependencyGivesURI() async throws {
        let remote = LoaderTests.remoteTask()
        #expect(try await Self.dependencies(ofTaskDependingOn: remote) == [remote.description])
    }

    @Test("A dependency on a task that the board does not have is not in the snapshot")
    func danglingDependencyIsLeftOut() async throws {
        #expect(try await Self.dependencies(ofTaskDependingOn: .local(.task(ULID()))) == [])
    }

    @Test("A deleted task is not in the snapshot")
    func deletedTaskIsLeftOut() async throws {
        let directory = try TemporaryDirectory()
        let board = try await Self.writeSessionBoard(in: directory.url)
        let deletion = CommentTests.nodeField("deleteTask", naming: board.firstTask)
        _ = try await CommentTests.run(deletion, on: board.graph)
        await board.graph.close()
        let snapshot = try #require(try await KanbanHost.shared.readBoard(inFolder: directory.url).snapshot)
        #expect(snapshot.tasks.map(\.title) == [Self.secondTitle])
    }

    // MARK: - No write

    @Test("The read changes no path and no modification date under the folder, also under .git")
    func readWritesNoPath() async throws {
        let directory = try TemporaryDirectory()
        let folder = try await Self.makeRepoWithNoCommit(in: directory)
        let before = try Self.pathDates(under: folder)
        _ = try await KanbanHost.shared.readBoard(inFolder: folder)
        #expect(try Self.pathDates(under: folder) == before)
    }

    @Test("The read of a git repo with no commit makes no commit")
    func readMakesNoCommit() async throws {
        let directory = try TemporaryDirectory()
        let folder = try await Self.makeRepoWithNoCommit(in: directory)
        _ = try await KanbanHost.shared.readBoard(inFolder: folder)
        #expect(try await GitSandbox.output(ofGit: ["rev-list", "--count", "--all"], in: folder) == "0")
    }

    @Test("The read starts no FSEvents stream")
    func readStartsNoStream() async throws {
        let fixture = try Self.makeFixtureBoard()
        let events = QuietFolderEvents()
        try await Self.read(fixture.directory.url, recordingLoadsIn: LoadRecorder(), events: events)
        #expect(events.startCount == 0)
    }

    @Test("The read loads no engine in the host")
    func readLoadsNoEngine() async throws {
        let fixture = try Self.makeFixtureBoard()
        let loads = LoadRecorder()
        try await Self.read(fixture.directory.url, recordingLoadsIn: loads, events: QuietFolderEvents())
        #expect(loads.events.isEmpty)
    }

    // MARK: - Writes of a session at the same time

    @Test("A task log with a torn last line gives the state before that line")
    func tornLastLineGivesStateBefore() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let whole = try EventLogTests.titleEvent(atStep: Self.firstWriteStep, setting: Self.wholeTitle)
        let torn = try EventLogTests.titleEvent(atStep: Self.secondWriteStep, setting: Self.tornTitle)
        let text = "\(try whole.encodedLine())\n\(try torn.encodedLine())"
        try EventLogTests.writeLogFile(text, of: try ReplayTests.taskRef(), in: log)
        let snapshot = try #require(try await KanbanHost.shared.readBoard(inFolder: directory.url).snapshot)
        #expect(snapshot.tasks.map(\.title) == [Self.wholeTitle])
    }

    @Test("A transaction that is not complete in all its files does not show in the snapshot")
    func incompleteTransactionIsHeld() async throws {
        let fixture = try TransactionCheckTests.makeFixture()
        try TransactionCheckTests.write(fixture.events.prefix(1), to: fixture.log)
        let snapshot = try #require(try await KanbanHost.shared.readBoard(inFolder: fixture.directory.url).snapshot)
        let heldTask = try #require(fixture.tasks.first)
        let heldID = try #require(heldTask.localID)
        #expect(snapshot.tasks.first { task in task.id == heldID }?.title == heldTask.description)
    }
}

// MARK: - Test values

extension BoardRead {
    /// The snapshot of a read that found a board, or `nil` for no board. Only the tests read it.
    var snapshot: BoardSnapshot? {
        guard case .board(let snapshot) = self else {
            return nil
        }
        return snapshot
    }
}

// MARK: - Responses

extension BoardSnapshotTests {
    /// The response to ``firstWrite``: the id of the first task.
    struct AddTaskResponse: Decodable {
        /// The `data` field.
        struct Payload: Decodable {
            /// The `addTask` field.
            let addTask: NodeResponse
        }

        /// The `data` field.
        let data: Payload
    }

    /// The `id` of a node of a response.
    struct NodeResponse: Decodable {
        /// The full URI of the node.
        let id: String
    }

    /// The `name` of a tag of a response.
    struct NameResponse: Decodable {
        /// The name.
        let name: String
    }

    /// An actor of a response.
    struct ActorResponse: Decodable {
        /// The full URI of the actor.
        let id: String

        /// The name of the actor.
        let name: String
    }

    /// A comment of a response.
    struct CommentResponse: Decodable {
        /// The full URI of the comment.
        let id: String

        /// The body of the comment.
        let body: String

        /// The time of the comment, as RFC 3339 text.
        let created: String

        /// The author of the comment.
        let author: ActorResponse
    }

    /// A task of the response to ``boardQuery``. The names are the GraphQL field names.
    struct TaskResponse: Decodable {
        /// The full URI of the task.
        let id: String

        /// The short id of the task.
        let shortId: String

        /// The title of the task.
        let title: String

        /// The body of the task.
        let body: String

        /// The time of the first patch, as RFC 3339 text.
        let created: String

        /// The time of the last patch, as RFC 3339 text.
        let updated: String

        /// The virtual tags of the task, for example `DONE`.
        let virtualTags: [String]

        /// The column of the task.
        let column: NodeResponse

        /// The tags of the task.
        let tags: [NameResponse]

        /// The assignees of the task.
        let assignees: [ActorResponse]

        /// The tasks that the task depends on.
        let dependsOn: [NodeResponse]

        /// The comments of the task.
        let comments: [CommentResponse]
    }

    /// The response to ``boardQuery``.
    struct BoardResponse: Decodable {
        /// A column of the board.
        struct Column: Decodable {
            /// The full URI of the column.
            let id: String

            /// The name of the column.
            let name: String

            /// The sort key of the column.
            let order: Int
        }

        /// The edge of one task of the task list.
        struct Edge: Decodable {
            /// The task.
            let node: TaskResponse
        }

        /// The task list of the board.
        struct Tasks: Decodable {
            /// The edges of the tasks.
            let edges: [Edge]
        }

        /// The board.
        struct Board: Decodable {
            /// The columns of the board.
            let columns: [Column]

            /// The tasks of the board.
            let tasks: Tasks
        }

        /// The `data` field.
        struct Payload: Decodable {
            /// The board.
            let board: Board
        }

        /// The `data` field.
        let data: Payload
    }
}
