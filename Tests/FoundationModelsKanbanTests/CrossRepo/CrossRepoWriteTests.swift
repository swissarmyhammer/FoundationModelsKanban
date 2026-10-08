import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the writes across boards (plan.md §5.4, §6.6, §12 item 13): the `board` field of the mutations that make a
/// node, the board of a mutation on an existing node, the auto-init of a related repo, and one call that changes two
/// boards.
///
/// Each test makes two real git repos side by side in a ``GitSandbox``, and an engine of the current repo that reads
/// the board keys from git.
@Suite("Cross-repo: write related boards", .timeLimit(.minutes(1)))
struct CrossRepoWriteTests {
    /// A mutation field that makes a node of the related board with the `board` field.
    struct BoardFieldCase: Sendable, CustomTestStringConvertible {
        /// The name of the mutation.
        let name: String

        /// The mutation fields that the test runs first, or `nil` for no setup. Each field names the related board
        /// with ``boardMarker``.
        let setup: String?

        /// The fields of the `input` object after the `board` field.
        let input: String

        /// The local ref of the node that the field writes in the related board.
        let ref: LocalRef

        var testDescription: String {
            name
        }

        /// Makes the mutation field for a board ref.
        ///
        /// - Parameter reference: The board ref of the related board.
        /// - Returns: The field, with the selection `{ id }`.
        func field(naming reference: String) -> String {
            #"\#(name)(input: { \#(boardField(reference)), \#(input) }) { id }"#
        }
    }

    /// The text in a setup field that the test replaces with the board ref of the related board.
    static let boardMarker = "<board>"

    /// The name of a column that a test adds to the related board.
    static let columnName = "Blocked"

    /// The name of an actor that a test adds to the related board.
    static let actorName = "Lib Bot"

    /// The slug of ``actorName``.
    static let actorSlug = "lib-bot"

    /// The new name of the related board in the `initBoard` case.
    static let boardName = "Library"

    /// The new body of the related board in the `updateBoard` case.
    static let boardBody = "Notes"

    /// The new title of a task of the related board.
    static let newTitle = "Port the lexer"

    /// The slug of a default column that is not the first column.
    static let doingSlug = "doing"

    /// The mutation fields of the `board` field test.
    static let boardFieldCases = [
        BoardFieldCase(name: MutationName.initBoard, setup: nil, input: #"name: "\#(boardName)""#, ref: .board),
        BoardFieldCase(name: MutationName.updateBoard, setup: nil, input: #"body: "\#(boardBody)""#, ref: .board),
        BoardFieldCase(
            name: MutationName.addColumn,
            setup: nil,
            input: #"name: "\#(columnName)""#,
            ref: .column(slug: columnName.lowercased())
        ),
        BoardFieldCase(
            name: MutationName.addActor,
            setup: nil,
            input: #"name: "\#(actorName)""#,
            ref: .actor(slug: actorSlug)
        ),
        BoardFieldCase(
            name: MutationName.addTag,
            setup: nil,
            input: #"name: "\#(TagMutationTests.bug)""#,
            ref: .tag(slug: TagMutationTests.bug)
        ),
        BoardFieldCase(
            name: MutationName.renameTag,
            setup: #"addTag(input: { \#(boardField(boardMarker)), name: "\#(TagMutationTests.bug)" }) { id }"#,
            input: #"from: "\#(TagMutationTests.bug)", to: "\#(TagMutationTests.defect)""#,
            ref: .tag(slug: TagMutationTests.defect)
        ),
    ]

    // MARK: - Helpers

    /// Makes the `board` field of an `input` object.
    ///
    /// - Parameter reference: The board ref.
    /// - Returns: The `input` field.
    static func boardField(_ reference: String) -> String {
        #"board: "\#(reference)""#
    }

    /// Gives the key of the related repo as text.
    ///
    /// - Returns: The key.
    /// - Throws: An error when the remote URL is not valid.
    static func libKey() throws -> String {
        try CrossRepoFixture.keyText(of: BoardLocatorTests.libOrigin)
    }

    /// Gives the key of the current repo as text.
    ///
    /// - Returns: The key.
    /// - Throws: An error when the remote URL is not valid.
    static func appKey() throws -> String {
        try CrossRepoFixture.keyText(of: BoardLocatorTests.appOrigin)
    }

    /// Adds a task to the related board through the engine of the current repo, and gives its id.
    ///
    /// - Parameters:
    ///   - input: The other fields of the `input` object, or `""` for none.
    ///   - graph: The engine of the current repo.
    /// - Returns: The full URI of the task.
    static func addLibTask(with input: String = "", on graph: KanbanGraph) async throws -> String {
        try await CrossRepoFixture.addTask(with: "\(boardField(libKey())), \(input)", on: graph)
    }

    /// Tells if a response has no `errors` list.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: `true` when the response has no error.
    /// - Throws: An error when the response is not a JSON object.
    static func hasNoErrors(_ response: String) throws -> Bool {
        try KanbanGraphTests.object(of: response)["errors"] == nil
    }

    /// Tells if a repo has a `.kanban/` directory.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: `true` when the directory is there.
    static func hasBoardDirectory(inRepoAt root: URL) -> Bool {
        FileManager.default.fileExists(atPath: EventLog(repositoryAt: root).directory.path)
    }

    /// Reads the events of each node log of a repo.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The events of all logs.
    /// - Throws: An error when a log cannot be read.
    static func events(inRepoAt root: URL) throws -> [Event] {
        let refs = try EventLog(repositoryAt: root).nodeFileSignatures().keys
        return try refs.flatMap { ref in try BoardMutationTests.events(of: ref, inRepoAt: root) }
    }

    /// Reads the events of the log of one task.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - root: The root directory of the repo of the task.
    /// - Returns: The events of the task log.
    /// - Throws: An error when the URI holds no ULID, or the log cannot be read.
    static func events(ofTask task: String, inRepoAt root: URL) throws -> [Event] {
        try BoardMutationTests.events(of: .task(AddUpdateTaskTests.firstTask(in: task)), inRepoAt: root)
    }

    // MARK: - Board field

    @Test("addTask with the board field writes the task to the log of the related board, and nothing to the current")
    func addTaskWritesRelatedLog() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await Self.addLibTask(on: app)
        #expect(try NodeURI(parsing: task).boardKey == Self.libKey())
        let patch = try #require(try Self.events(ofTask: task, inRepoAt: repos.lib).first?.patch)
        #expect(patch.set[PropertyName.title] == .string(AddUpdateTaskTests.title))
        #expect(!Self.hasBoardDirectory(inRepoAt: repos.app))
    }

    @Test("The first mutation on a related repo with no .kanban/ makes its board with default columns and the actor")
    func firstMutationEnablesRelatedRepo() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        _ = try await Self.addLibTask(on: GitGraphFixture.makeGraph(at: repos.app))
        let log = EventLog(repositoryAt: repos.lib)
        let refs = Set(try log.nodeFileSignatures().keys)
        let columns = DefaultColumn.all.map { column in LocalRef.column(slug: column.slug) }
        #expect(refs.isSuperset(of: [.board, KanbanGraphTests.sessionActor.ref] + columns))
        let name = try #require(log.readLog(of: .board).node?.state as? BoardNode).name
        #expect(name == BoardLocatorTests.libName)
    }

    @Test("A query on a related repo with no .kanban/ writes nothing")
    func queryOnRelatedRepoWritesNothing() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        _ = try await CrossRepoReadTests.board("name", of: Self.libKey(), on: app)
        #expect(!Self.hasBoardDirectory(inRepoAt: repos.lib))
    }

    @Test("Each mutation with the board field writes its node to the related board", arguments: boardFieldCases)
    func boardFieldWritesRelatedBoard(mutation: BoardFieldCase) async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let reference = try Self.libKey()
        if let setup = mutation.setup {
            _ = try await CommentTests.run(setup.replacingOccurrences(of: Self.boardMarker, with: reference), on: app)
        }
        let response = try await CommentTests.run(mutation.field(naming: reference), on: app)
        #expect(try Self.hasNoErrors(response), "\(response)")
        #expect(try !BoardMutationTests.events(of: mutation.ref, inRepoAt: repos.lib).isEmpty)
        #expect(!Self.hasBoardDirectory(inRepoAt: repos.app))
    }

    @Test("The session actor is the assignee of a new task in a related board that knew the actor before the call")
    func knownActorOfRelatedBoardIsAssignee() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        _ = try await Self.addLibTask(on: app)
        let task = try await Self.addLibTask(on: app)
        let patch = try #require(try Self.events(ofTask: task, inRepoAt: repos.lib).first?.patch)
        #expect(patch.add[PropertyName.assignees] == [.local(KanbanGraphTests.sessionActor.ref)])
    }

    @Test(
        "A mutation with a board field or a node URI of a board that the scan cannot find gives NOT_FOUND",
        arguments: [
            #"addTask(input: { title: "x", board: "\#(CrossRepoReadTests.missingKey)" }) { id }"#,
            #"updateTask(input: { id: "kanban://\#(CrossRepoReadTests.missingKey)/task/\#(ULID())", title: "x" }) "#
                + "{ id }",
        ]
    )
    func missingBoardGivesNotFound(field: String) async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let response = try await CommentTests.run(field, on: GitGraphFixture.makeGraph(at: repos.app))
        let name = try #require(field.split(separator: "(").first).description
        let expected = KanbanError.boardNotFound(
            reference: CrossRepoReadTests.missingKey,
            searchRoots: [repos.sandbox.root.path]
        )
        try ErrorCoverageTests.expectFailure(of: name, in: response, giving: expected, coded: "NOT_FOUND")
    }

    // MARK: - Existing nodes

    @Test("A mutation on a node of a related board writes to that board, and its short refs resolve there")
    func mutationOnRelatedNodeWritesRelatedLog() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await Self.addLibTask(on: app)
        let column = #", column: "\#(Self.doingSlug)""#
        let response = try await CommentTests.run(
            CommentTests.nodeField(MutationName.moveTask, naming: task, with: column),
            on: app
        )
        #expect(try Self.hasNoErrors(response), "\(response)")
        let patch = try #require(try Self.events(ofTask: task, inRepoAt: repos.lib).last?.patch)
        #expect(patch.set[PropertyName.column] == .ref(.local(.column(slug: Self.doingSlug))))
        #expect(!Self.hasBoardDirectory(inRepoAt: repos.app))
    }

    @Test("updateTask on a task of a related board writes the new title to the related log")
    func updateTaskOnRelatedNode() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await Self.addLibTask(on: app)
        let update = CommentTests.nodeField(
            MutationName.updateTask,
            naming: task,
            with: #", title: "\#(Self.newTitle)""#
        )
        _ = try await CommentTests.run(update, on: app)
        let patch = try #require(try Self.events(ofTask: task, inRepoAt: repos.lib).last?.patch)
        #expect(patch.set[PropertyName.title] == .string(Self.newTitle))
    }

    @Test("addComment on a task of a related board writes the comment to the related log")
    func addCommentOnRelatedTask() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await Self.addLibTask(on: app)
        let comment = try await Design.PortabilityTests.id(
            runningField: CommentTests.addComment(to: task),
            named: MutationName.addComment,
            on: app
        )
        let ref = try NodeURI(parsing: comment).ref
        #expect(try !BoardMutationTests.events(of: ref, inRepoAt: repos.lib).isEmpty)
        #expect(!Self.hasBoardDirectory(inRepoAt: repos.app))
    }

    // MARK: - One call, many boards

    @Test("One call that changes two boards writes one txn to both, with the key of the other board in boards")
    func oneCallWritesOneTransactionToBothBoards() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let (appKey, libKey) = (try Self.appKey(), try Self.libKey())
        let mutation = AddUpdateTaskTests.mutation(
            of: "a: " + AddUpdateTaskTests.addTask(with: ""),
            "b: " + AddUpdateTaskTests.addTask(with: Self.boardField(libKey))
        )
        let response = try await KanbanGraphTests.execute(mutation, on: app)
        #expect(try Self.hasNoErrors(response), "\(response)")
        let appEvents = try Self.events(inRepoAt: repos.app)
        let libEvents = try Self.events(inRepoAt: repos.lib)
        #expect(!appEvents.isEmpty && !libEvents.isEmpty)
        #expect(Set((appEvents + libEvents).map(\.txn)).count == 1)
        #expect(appEvents.allSatisfy { event in event.boards == [libKey] })
        #expect(libEvents.allSatisfy { event in event.boards == [appKey] })
        #expect(Set((appEvents + libEvents).map(\.ops)) == [[MutationName.addTask]])
    }

    @Test("A dependsOn edge from the current board to a related board is stored as the full URI of the target")
    func crossBoardEdgeIsFullURI() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let target = try await Self.addLibTask(on: app)
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        let patch = try #require(try Self.events(ofTask: task, inRepoAt: repos.app).first?.patch)
        #expect(patch.add[PropertyName.dependsOn] == [.remote(try NodeURI(parsing: target))])
    }

    @Test("After writes across two boards, no log line holds the key of its own board")
    func noLogLineHoldsKeyOfItsOwnBoard() async throws {
        let repos = try await CrossRepoFixture.SideBySide()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let appTask = try await CrossRepoFixture.addTask(with: "", on: app)
        let libTask = try await Self.addLibTask(with: "dependsOn: \(AddUpdateTaskTests.list(of: [appTask]))", on: app)
        _ = try await CrossRepoFixture.addTask(dependingOn: libTask, on: app)
        let (appKey, libKey) = (try Self.appKey(), try Self.libKey())
        let appTexts = try Design.PortabilityTests.logTexts(inRepoAt: repos.app).values
        let libTexts = try Design.PortabilityTests.logTexts(inRepoAt: repos.lib).values
        #expect(!appTexts.contains { text in text.contains(appKey) })
        #expect(!libTexts.contains { text in text.contains(libKey) })
        #expect(appTexts.contains { text in text.contains(libKey) })
        #expect(libTexts.contains { text in text.contains(appKey) })
    }
}
