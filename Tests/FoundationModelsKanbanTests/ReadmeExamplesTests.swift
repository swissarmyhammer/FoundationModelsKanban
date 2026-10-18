import Foundation
import FoundationModels
import FoundationModelsMultitool
import GraphQL
import Testing

@testable import FoundationModelsKanban

/// Tests the "Get started" examples of `README.md` (^n1yhb0x).
///
/// Each test runs an example with the same code and the same GraphQL documents as the README, on a board in a
/// temporary git repo with no remote. The repo has one empty first commit with a new UUID in its message (see
/// ``ExampleBoard``). The folder of the repo has the name ``folderName``. The board key is `local/<root commit>` of
/// that commit, and each test has its own key. Each response must
/// have no `errors`. A response with no minted id and no transaction ULID must be the same text as a
/// ```` ```json ```` block of the README.
@Suite("README: the Get started examples", .watcherBudget)
struct ReadmeExamplesTests {
    /// The README, relative to the repository root.
    private static let readmePath = DocumentationTests.readmePath

    /// The name of the folder of the board of each test.
    private static let folderName = "my-project"

    /// The title of the task that example 2 adds.
    private static let taskTitle = "Fix the login bug"

    /// The mutation of example 2. It adds the actor `alice`, and a task with the tag `bug` that `alice` does.
    private static let addTaskMutation = """
        mutation($title: String!) {
          addActor(input: { id: "alice", name: "Alice" }) { name }
          addTask(input: { title: $title, tags: ["bug"], assignees: ["alice"] }) {
            title column { name } tags { name } assignees { name }
          }
        }
        """

    /// The variables of ``addTaskMutation``.
    private static let addTaskVariables: [String: Map] = ["title": .string(taskTitle)]

    /// The Swift text of ``addTaskVariables`` in the README.
    private static let addTaskVariablesText = #"variables: ["title": "\#(taskTitle)"]"#

    /// The query of example 2 that reads the columns of the board.
    private static let columnsQuery = "{ board { columns { name } } }"

    /// The mutation of example 5. It adds a second task with the tag `bug`, so the subscription gets one event.
    private static let secondBugMutation = """
        mutation { addTask(input: { title: "Fix the logout bug", tags: ["bug"] }) { title } }
        """

    /// The instructions of the session of example 3.
    private static let sessionInstructions = "Use the kanban tool to read and change the task board."

    /// The name of the tool of example 3.
    private static let toolName = "kanban"

    /// The response to ``DocumentationTests/nodeHistoryQuery`` on a board with no node whose short id is `01jabcd`.
    private static let noChangesResponse = #"{"data":{"board":{"history":[]}}}"#

    /// The operations of the first transaction of the board: the two mutation fields of ``addTaskMutation``.
    private static let firstOperations = ["addActor", "addTask"]

    /// The operations of the transaction of ``secondBugMutation``.
    private static let secondBugOperations = ["addTask"]

    /// The kind of the update of a new node.
    private static let createdKind = UpdateKind.created.rawValue

    /// Each GraphQL document of a Swift code block of the README.
    private static let swiftDocuments: Set = [
        addTaskMutation,
        columnsQuery,
        DocumentationTests.bugsOfAliceQuery,
        DocumentationTests.columnHistoryQuery,
        DocumentationTests.nodeHistoryQuery,
        DocumentationTests.bugOrCommentSubscription,
        secondBugMutation,
    ]

    /// The entries of `.kanban/` that the board can have: the log of the board, one directory for each other node
    /// type, the two git files, and the lock file (plan.md §5.2).
    private static let boardEntries = Set(
        [EventLog.boardFileName]
            + PatchNodeType.allCases.compactMap(\.logDirectoryName)
            + EventLog.gitFiles.keys
            + [EventLog.lockFileName]
    )

    // MARK: - Board

    /// A board of the examples, as example 1 opens it: a git repo with no remote in a folder with the name
    /// ``folderName``, and the engine of the folder. The tests of the kanban skill examples use the same board.
    struct ExampleBoard {
        /// The temporary directory that holds the folder. It removes the folder when the value ends.
        let directory: TemporaryDirectory

        /// The folder of the board.
        let root: URL

        /// The engine, as example 1 makes it.
        let graph: KanbanGraph

        /// Makes the folder, runs `git init` in it with ``GitSandbox/initializeRepo(at:withIdentity:)``, makes the first
        /// commit of the repo, and makes the engine of example 1. The repo gets the local config
        /// ``GitSandbox/identityConfig``: a name and an email of the author, and no commit signatures. The message of the
        /// first commit has a new UUID. Thus the board of each value has its own key: the key is the hash of the first
        /// commit, and an empty commit with the same message, the same author, and the same second gives the same hash.
        /// When two boards have one key, the engine of each test sees the other board as a copy of its own board, and an
        /// `undo` or a `redo` of one test can reverse the transaction of the other test.
        ///
        /// - Throws: An error when the folder cannot be made, when `git init`, `git config`, or `git commit` fails, or
        ///   when the engine cannot be made.
        init() async throws {
            directory = try TemporaryDirectory()
            root = try GitSandbox.makeFolder(named: ReadmeExamplesTests.folderName, in: directory.url)
            try await GitSandbox.initializeRepo(at: root)
            try await GitSandbox.runGit(
                withArguments: ["commit", "--quiet", "--allow-empty", "-m", "Example board \(UUID().uuidString)"],
                in: root
            )
            graph = try await KanbanHost.shared.session(workingDirectory: root, actor: nil)
        }

        /// The `.kanban/` directory of the board.
        var boardDirectory: URL {
            EventLog(repositoryAt: root).directory
        }
    }

    // MARK: - Helpers

    /// Reads each code block of one language of the README.
    ///
    /// - Parameter language: The language of the blocks.
    /// - Returns: The text of each block, in README order.
    /// - Throws: An error when the README cannot be read.
    private static func readmeBlocks(of language: CodeLanguage) throws -> [String] {
        try RepositoryFile.codeBlocks(of: language, at: readmePath)
    }

    /// Gives the value of each multi-line string literal of a Swift text, as Swift reads it: without the indent of the
    /// closing delimiter.
    ///
    /// - Parameter swift: The Swift text.
    /// - Returns: The value of each literal, in text order.
    private static func multilineStrings(in swift: String) -> [String] {
        swift.matches(of: #/"""\n(?<body>[\s\S]*?)\n(?<indent> *)"""/#).map { literal in
            literal.body
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line in line.dropFirst(literal.indent.count) }
                .joined(separator: "\n")
        }
    }

    /// Checks that a response has no `errors`.
    ///
    /// - Parameter response: The response JSON text.
    /// - Throws: An error when the response is not a JSON object.
    private static func expectNoErrors(_ response: String) throws {
        #expect(try KanbanGraphTests.object(of: response)["errors"] == nil, "\(response)")
    }

    /// Checks that the README shows a response as the full text of one ```` ```json ```` block.
    ///
    /// - Parameter response: The response JSON text, with sorted keys.
    /// - Throws: An error when the README cannot be read.
    private static func expectReadmeShows(_ response: String) throws {
        let blocks = try readmeBlocks(of: .json)
        #expect(blocks.contains(response), "README.md must have the json block \(response); found \(blocks)")
    }

    /// Runs the mutation of example 2.
    ///
    /// - Parameter graph: The engine.
    /// - Returns: The response JSON text.
    private static func addFirstTask(on graph: KanbanGraph) async throws -> String {
        try await KanbanGraphTests.execute(addTaskMutation, variables: addTaskVariables, on: graph)
    }

    /// Runs one query of the README on a board that has the task of example 2.
    ///
    /// - Parameter query: The query.
    /// - Returns: The example board, which keeps its folder until the value ends, and the `board` object of the
    ///   response.
    /// - Throws: An error when a response has `errors`, or no `board` object.
    private static func boardAfterFirstTask(
        answering query: String
    ) async throws -> (example: ExampleBoard, board: [String: Any]) {
        let example = try await ExampleBoard()
        try expectNoErrors(try await addFirstTask(on: example.graph))
        let response = try await KanbanGraphTests.execute(query, on: example.graph)
        await example.graph.close()
        try expectNoErrors(response)
        let board = try KanbanGraphTests.object(named: "board", in: response)
        return (example, board)
    }

    /// Gives the prefix of the id of each task of a board: the scheme, the board key, and the `task` type.
    ///
    /// - Parameter root: The folder of the board. The repo of the folder must have its first commit.
    /// - Returns: The prefix, for example `kanban://local/c83fae4e58ce/task/`.
    /// - Throws: A ``BoardKeyError`` when the key of the board cannot be read.
    private static func taskIDPrefix(inBoardAt root: URL) async throws -> String {
        "kanban://\(try await BoardKey.read(fromRepoAt: root))/task/"
    }

    /// Reads the `updates` of one change as their `id` and `kind`.
    ///
    /// - Parameter change: The change object of a response.
    /// - Returns: The id and the kind of each update, in order.
    private static func idsAndKinds(of change: [String: Any]) -> [[String]] {
        let updates = change["updates"] as? [[String: Any]] ?? []
        return updates.map { update in [update["id"] as? String ?? "", update["kind"] as? String ?? ""] }
    }

    /// Reads the names of the tools of one entry of a session transcript.
    ///
    /// - Parameter entry: The entry.
    /// - Returns: The name of each tool of an instructions entry, or `nil` for each other entry.
    private static func toolNames(of entry: Transcript.Entry) -> [String]? {
        guard case .instructions(let instructions) = entry else {
            return nil
        }
        return instructions.toolDefinitions.map(\.name)
    }

    /// Writes a JSON value as JSON text with sorted keys, the form of each ```` ```json ```` block of the README and
    /// of the kanban skill.
    ///
    /// - Parameter text: The JSON text.
    /// - Returns: The same value as JSON text with sorted keys and no white space.
    /// - Throws: An error when the text is not JSON.
    static func sortedJSON(_ text: String) throws -> String {
        let value = try JSONSerialization.jsonObject(with: Data(text.utf8))
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Example 1: open a board in a folder

    @Test("The README names the default columns of DefaultColumn.all")
    func readmeNamesDefaultColumns() throws {
        let names = DefaultColumn.all.map { column in "`\(column.slug)` (\(column.name))" }
        let phrase = names.dropLast().joined(separator: ", ") + ", and " + (names.last ?? "")
        #expect(try RepositoryFile.text(at: Self.readmePath).contains(phrase), "README.md must name \(phrase)")
    }

    @Test("A query writes no file, and the first mutation makes .kanban/ with the default columns")
    func firstMutationMakesBoard() async throws {
        let board = try await ExampleBoard()
        try Self.expectNoErrors(try await KanbanGraphTests.execute(Self.columnsQuery, on: board.graph))
        let madeByQuery = FileManager.default.fileExists(atPath: board.boardDirectory.path)
        try Self.expectNoErrors(try await Self.addFirstTask(on: board.graph))
        let columns = try await KanbanGraphTests.execute(Self.columnsQuery, on: board.graph)
        await board.graph.close()
        let names = DefaultColumn.all.map { column in #"{"name":"\#(column.name)"}"# }.joined(separator: ",")
        #expect(!madeByQuery)
        #expect(FileManager.default.fileExists(atPath: board.boardDirectory.path))
        #expect(columns == #"{"data":{"board":{"columns":[\#(names)]}}}"#)
        try Self.expectReadmeShows(columns)
    }

    // MARK: - Example 2: add and list tasks

    @Test("The addTask mutation with variables gives the response that the README shows")
    func addTaskGivesReadmeResponse() async throws {
        let board = try await ExampleBoard()
        let response = try await Self.addFirstTask(on: board.graph)
        await board.graph.close()
        let task = try KanbanGraphTests.object(named: "addTask", in: response)
        #expect(task["title"] as? String == Self.taskTitle)
        #expect(try RepositoryFile.text(at: Self.readmePath).contains(Self.addTaskVariablesText))
        try Self.expectReadmeShows(response)
    }

    @Test("The tasks filter #bug && @alice lists the task of example 2")
    func bugsOfAliceListTask() async throws {
        let (example, board) = try await Self.boardAfterFirstTask(answering: DocumentationTests.bugsOfAliceQuery)
        let prefix = try await Self.taskIDPrefix(inBoardAt: example.root)
        let edges = (board["tasks"] as? [String: Any])?["edges"] as? [[String: Any]] ?? []
        let nodes = edges.compactMap { edge in edge["node"] as? [String: Any] }
        #expect(nodes.map { node in node["title"] as? String } == [Self.taskTitle])
        #expect(nodes.allSatisfy { node in (node["id"] as? String)?.hasPrefix(prefix) == true })
    }

    @Test("The history filter ~column gives the column updates of the first mutation")
    func columnHistoryHasDefaultColumns() async throws {
        let (example, board) = try await Self.boardAfterFirstTask(answering: DocumentationTests.columnHistoryQuery)
        let key = try await BoardKey.read(fromRepoAt: example.root)
        let changes = board["history"] as? [[String: Any]] ?? []
        let columns = DefaultColumn.all.map { column in
            ["kanban://\(key)/column/\(column.slug)", Self.createdKind]
        }
        #expect(changes.map { change in change["ops"] as? [String] } == [Self.firstOperations])
        #expect(changes.map(Self.idsAndKinds(of:)) == [columns])
    }

    @Test("The history filter of a node that the board does not have gives no change")
    func nodeHistoryOfUnknownNodeIsEmpty() async throws {
        let board = try await ExampleBoard()
        try Self.expectNoErrors(try await Self.addFirstTask(on: board.graph))
        let response = try await KanbanGraphTests.execute(DocumentationTests.nodeHistoryQuery, on: board.graph)
        await board.graph.close()
        #expect(response == Self.noChangesResponse)
    }

    // MARK: - Example 3: give the tool to a model

    @Test("A LanguageModelSession takes the kanban tool")
    func sessionTakesKanbanTool() async throws {
        let board = try await ExampleBoard()
        let session = LanguageModelSession(
            tools: [KanbanTool(graph: board.graph)],
            instructions: Self.sessionInstructions
        )
        #expect(session.transcript.compactMap(Self.toolNames(of:)) == [[Self.toolName]])
        #expect(try RepositoryFile.text(at: Self.readmePath).contains(Self.sessionInstructions))
    }

    // MARK: - Example 4: code mode

    @Test("The code mode script of the README adds a task, reads nextTask, and moves the task")
    func codeModeScriptMovesTask() async throws {
        let script = try #require(try Self.readmeBlocks(of: .js).first, "README.md must have a js block")
        let board = try await ExampleBoard()
        let output = try await CodeModeTests.run(script, on: board.graph)
        await board.graph.close()
        try Self.expectReadmeShows(try Self.sortedJSON(output))
    }

    // MARK: - Example 5: watch changes

    @Test("The subscription gets the change of a second bug task, and close() ends the stream")
    func subscriptionGetsSecondBug() async throws {
        let board = try await ExampleBoard()
        try Self.expectNoErrors(try await Self.addFirstTask(on: board.graph))
        let subscription = DocumentationTests.bugOrCommentSubscription
        let stream = try await SubscriptionTests.subscribe(subscription, on: board.graph)
        try Self.expectNoErrors(try await KanbanGraphTests.execute(Self.secondBugMutation, on: board.graph))
        let events = try await SubscriptionTests.events(
            SubscriptionTests.oneEvent, of: stream, afterChangeAt: board.boardDirectory
        )
        await board.graph.close()
        let rest = try await SubscriptionTests.allEvents(of: stream)
        let prefix = try await Self.taskIDPrefix(inBoardAt: board.root)
        let event = try #require(events.first, "the subscription must send one event")
        try Self.expectNoErrors(event)
        let change = try KanbanGraphTests.object(named: "changes", in: event)
        let updates = change["updates"] as? [[String: Any]] ?? []
        #expect(change["ops"] as? [String] == Self.secondBugOperations)
        #expect(updates.map { update in update["kind"] as? String } == [Self.createdKind])
        #expect(updates.allSatisfy { update in (update["id"] as? String)?.hasPrefix(prefix) == true })
        #expect(rest == [])
    }

    // MARK: - Example 6: the layout of .kanban/

    @Test("The README layout of .kanban/ names each entry that a board can have")
    func readmeLayoutNamesBoardEntries() throws {
        let layout = try #require(try Self.readmeBlocks(of: .text).first, "README.md must have a text block")
        let lines = layout.split(separator: "\n").dropFirst()
        let entries = lines.compactMap { line in
            line.split(separator: " ").first?.split(separator: "/").first.map(String.init)
        }
        let unionLine = try #require(EventLog.gitFiles[EventLog.gitattributesFileName])
        #expect(Set(entries) == Self.boardEntries)
        #expect(layout.contains(unionLine.trimmingCharacters(in: .newlines)))
    }

    @Test("After the examples, each entry of .kanban/ is in the README layout")
    func boardEntriesAreInLayout() async throws {
        let board = try await ExampleBoard()
        try Self.expectNoErrors(try await Self.addFirstTask(on: board.graph))
        try Self.expectNoErrors(try await KanbanGraphTests.execute(Self.secondBugMutation, on: board.graph))
        await board.graph.close()
        let entries = try FileManager.default.contentsOfDirectory(atPath: board.boardDirectory.path)
        #expect(Set(entries).isSubset(of: Self.boardEntries), "\(entries)")
    }

    // MARK: - Each GraphQL document of the README

    @Test("Each Swift code block of the README runs only documents that this suite runs")
    func eachSwiftDocumentIsRun() throws {
        let documents = try Self.readmeBlocks(of: .swift).flatMap(Self.multilineStrings(in:))
        #expect(Set(documents) == Self.swiftDocuments)
    }

    @Test("Each graphql code block of the README runs with no errors on a board in a git repo with no remote")
    func eachGraphQLBlockRuns() async throws {
        let blocks = try Self.readmeBlocks(of: .graphql)
        let board = try await ExampleBoard()
        try Self.expectNoErrors(try await Self.addFirstTask(on: board.graph))
        for block in blocks {
            try Self.expectNoErrors(try await Self.response(to: block, on: board.graph, boardAt: board.boardDirectory))
        }
        await board.graph.close()
        #expect(!blocks.isEmpty)
        #expect(FileManager.default.fileExists(atPath: board.boardDirectory.path))
    }

    /// Runs one GraphQL document: a subscription with `subscribe`, and each other document with `execute`.
    ///
    /// A subscription gets one event: the change of ``secondBugMutation``.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - graph: The engine.
    ///   - board: The board folder of the engine. The failure message at the time limit of ``FolderEventWait`` names
    ///     it.
    /// - Returns: The response, or the first event of a subscription.
    /// - Throws: An error when a subscription sends no event, or ``FolderEventTimeout`` when the event does not come
    ///   before the time limit.
    private static func response(
        to document: String,
        on graph: KanbanGraph,
        boardAt board: URL
    ) async throws -> String {
        let operation = try #require(try parse(source: document).definitions.first as? OperationDefinition)
        guard operation.operation == .subscription else {
            return try await KanbanGraphTests.execute(document, on: graph)
        }
        let stream = try await SubscriptionTests.subscribe(document, on: graph)
        try expectNoErrors(try await KanbanGraphTests.execute(secondBugMutation, on: graph))
        let events = try await SubscriptionTests.events(SubscriptionTests.oneEvent, of: stream, afterChangeAt: board)
        return try #require(events.first, "the subscription \(document) must send one event")
    }
}
