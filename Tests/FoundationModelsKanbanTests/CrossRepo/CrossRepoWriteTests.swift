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

    /// The name of a file that a test makes in a folder before a write through a path ref.
    static let folderFileName = "README.md"

    /// The text of ``folderFileName``.
    static let folderFileText = "A file of the folder, outside .kanban/.\n"

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

    /// Makes a mutation with two `addTask` fields: one field adds a task to the current board, and one field adds a
    /// task to the related board.
    ///
    /// - Returns: The mutation document.
    /// - Throws: An error when the remote URL of the related repo is not valid.
    static func addTaskToEachBoard() throws -> String {
        AddUpdateTaskTests.mutation(
            of: "a: " + AddUpdateTaskTests.addTask(with: ""),
            "b: " + AddUpdateTaskTests.addTask(with: boardField(try libKey()))
        )
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

    /// Makes a folder at ``BoardLocatorTests/outsidePath`` in the sandbox of two repos. The scan does not look there.
    ///
    /// - Parameters:
    ///   - kind: The kind of the folder. A git repo gets ``BoardLocatorTests/newOrigin``.
    ///   - repos: The repos of the sandbox.
    /// - Returns: The folder.
    /// - Throws: An error when the folder cannot be made, or when a git command fails.
    static func makeOutsideFolder(
        as kind: CrossRepoFixture.FolderKind,
        in repos: CrossRepoFixture.SideBySide
    ) async throws -> URL {
        try await kind.makeFolder(
            named: BoardLocatorTests.outsidePath,
            origin: BoardLocatorTests.newOrigin,
            in: repos.sandbox
        )
    }

    /// Makes a folder with ``makeOutsideFolder(as:in:)``, adds a task to it through a path ref, and checks the key of
    /// the task and the log of the task in the folder.
    ///
    /// - Parameters:
    ///   - kind: The kind of the folder.
    ///   - reference: Gives the path ref from the folder.
    /// - Throws: An error when the folder cannot be made, when a git command fails, or when the log cannot be read.
    static func expectAddTaskWritesOutsideFolder(
        as kind: CrossRepoFixture.FolderKind,
        namedBy reference: (URL) -> String
    ) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let other = try await makeOutsideFolder(as: kind, in: repos)
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await CrossRepoFixture.addTask(with: boardField(reference(other)), on: app)
        let key = try kind.key(ofFolderNamed: BoardLocatorTests.outsideName, origin: BoardLocatorTests.newOrigin)
        #expect(try NodeURI(parsing: task).boardKey == key.description)
        let patch = try #require(try events(ofTask: task, inRepoAt: other).first?.patch)
        #expect(patch.set[PropertyName.title] == .string(AddUpdateTaskTests.title))
    }

    /// Reads each file of a folder and of its subfolders.
    ///
    /// - Parameter folder: The folder.
    /// - Returns: The contents of each file, by the path of the file.
    /// - Throws: An error when the folder or a file cannot be read.
    static func files(inFolderAt folder: URL) throws -> [String: Data] {
        let files = try FileManager.default.subpathsOfDirectory(atPath: folder.path)
            .map { path in folder.appending(path: path, directoryHint: .notDirectory) }
            .filter(isFile(_:))
        return Dictionary(uniqueKeysWithValues: try files.map { file in (file.path, try Data(contentsOf: file)) })
    }

    /// Tells if a URL names a file that exists, and not a folder.
    ///
    /// - Parameter url: The file URL.
    /// - Returns: `true` when a file has the path. A folder, or a path with nothing at it, gives `false`.
    private static func isFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    // MARK: - Board field

    @Test("addTask with the board field writes the task to the log of the related board, and nothing to the current")
    func addTaskWritesRelatedLog() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await Self.addLibTask(on: app)
        #expect(try NodeURI(parsing: task).boardKey == Self.libKey())
        let patch = try #require(try Self.events(ofTask: task, inRepoAt: repos.lib).first?.patch)
        #expect(patch.set[PropertyName.title] == .string(AddUpdateTaskTests.title))
        #expect(!Self.hasBoardDirectory(inRepoAt: repos.app))
    }

    @Test("The first mutation on a related repo with no .kanban/ makes its board with default columns and the actor")
    func firstMutationEnablesRelatedRepo() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
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
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        _ = try await CrossRepoReadTests.board("name", of: Self.libKey(), on: app)
        #expect(!Self.hasBoardDirectory(inRepoAt: repos.lib))
    }

    @Test("Each mutation with the board field writes its node to the related board", arguments: boardFieldCases)
    func boardFieldWritesRelatedBoard(mutation: BoardFieldCase) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
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
        let repos = try await CrossRepoFixture.SideBySide.make()
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
        let repos = try await CrossRepoFixture.SideBySide.make()
        let response = try await CommentTests.run(field, on: GitGraphFixture.makeGraph(at: repos.app))
        let name = try #require(field.split(separator: "(").first).description
        let expected = KanbanError.boardNotFound(
            reference: CrossRepoReadTests.missingKey,
            searchRoots: [repos.sandbox.root.path]
        )
        try ErrorCoverageTests.expectFailure(of: name, in: response, giving: expected, coded: "NOT_FOUND")
    }

    // MARK: - Path refs

    @Test(
        "addTask with the board field set to the path of a folder that the scan does not find writes to that folder",
        arguments: CrossRepoFixture.FolderKind.allCases
    )
    func pathOutsidePlacesWritesFolder(kind: CrossRepoFixture.FolderKind) async throws {
        try await Self.expectAddTaskWritesOutsideFolder(as: kind) { folder in folder.path }
    }

    @Test(
        "addTask with the board field set to a path that starts with ../ writes to the folder from the current root",
        arguments: CrossRepoFixture.FolderKind.allCases
    )
    func relativePathWritesFolderFromRoot(kind: CrossRepoFixture.FolderKind) async throws {
        try await Self.expectAddTaskWritesOutsideFolder(as: kind) { _ in BoardLocatorTests.outsideReferenceFromRoot }
    }

    @Test(
        "addTask through a path ref changes no file of the folder outside .kanban/ (plan.md §6.6, trust)",
        arguments: CrossRepoFixture.FolderKind.allCases
    )
    func pathRefWritesOnlyBoardDirectory(kind: CrossRepoFixture.FolderKind) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let other = try await Self.makeOutsideFolder(as: kind, in: repos)
        let folderFile = other.appending(path: Self.folderFileName, directoryHint: .notDirectory)
        try Data(Self.folderFileText.utf8).write(to: folderFile)
        let before = try Self.files(inFolderAt: other)
        let task = try await CrossRepoFixture.addTask(
            with: Self.boardField(BoardLocatorTests.outsideReferenceFromRoot),
            on: GitGraphFixture.makeGraph(at: repos.app)
        )
        let after = try Self.files(inFolderAt: other)
        let boardLog = EventLog(repositoryAt: other)
        let boardPrefix = boardLog.directory.path + "/"
        #expect(after.filter { path, _ in !path.hasPrefix(boardPrefix) } == before)
        let taskLog = boardLog.fileURL(for: .task(try AddUpdateTaskTests.firstTask(in: task)))
        #expect(after.keys.contains(taskLog.path))
    }

    @Test("addTask with the board field set to the path of a folder that does not exist gives NOT_FOUND")
    func missingFolderPathGivesNotFound() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let missing = repos.sandbox.root.appending(path: BoardLocatorTests.missingName, directoryHint: .isDirectory)
        let field = AddUpdateTaskTests.addTask(with: Self.boardField(missing.path))
        let response = try await CommentTests.run(field, on: GitGraphFixture.makeGraph(at: repos.app))
        let expected = KanbanError.boardNotFound(reference: missing.path, searchRoots: [repos.sandbox.root.path])
        try ErrorCoverageTests.expectFailure(of: MutationName.addTask, in: response, giving: expected, coded: "NOT_FOUND")
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    // MARK: - Existing nodes

    @Test("A mutation on a node of a related board writes to that board, and its short refs resolve there")
    func mutationOnRelatedNodeWritesRelatedLog() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
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
        let repos = try await CrossRepoFixture.SideBySide.make()
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
        let repos = try await CrossRepoFixture.SideBySide.make()
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
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let (appKey, libKey) = (try Self.appKey(), try Self.libKey())
        let response = try await KanbanGraphTests.execute(Self.addTaskToEachBoard(), on: app)
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
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let target = try await Self.addLibTask(on: app)
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        let patch = try #require(try Self.events(ofTask: task, inRepoAt: repos.app).first?.patch)
        #expect(patch.add[PropertyName.dependsOn] == [.remote(try NodeURI(parsing: target))])
    }

    @Test("After writes across two boards, no log line holds the key of its own board")
    func noLogLineHoldsKeyOfItsOwnBoard() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
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
