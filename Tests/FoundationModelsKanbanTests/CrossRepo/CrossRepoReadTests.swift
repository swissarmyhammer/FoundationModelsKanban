import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the reads across boards (plan.md §6.6, §12 items 13 and 26): the board refs of `Query.board(id:)`, the list
/// of `Query.boards(enabled:)`, `node(id:)` with a URI of a related board, and the readiness of a cross-board
/// `dependsOn` edge.
///
/// Each test makes real git repos in a ``GitSandbox`` and engines that read the board keys from git. A test that
/// waits for a change of a related board waits for a batch that the engine applies, with no fixed sleep.
@Suite("Cross-repo: read related boards", .timeLimit(.minutes(1)))
struct CrossRepoReadTests {
    /// The key of a board that no scan finds.
    static let missingKey = "github.com/example/missing"

    /// The selection of the `ready` field of a task.
    static let readySelection = "{ ready }"

    // MARK: - Helpers

    /// Makes the query of one task of the current board.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - selection: The selection of the task field.
    /// - Returns: The query document.
    /// - Throws: An error when the URI holds no ULID.
    static func query(of task: String, selecting selection: String) throws -> String {
        CommentTests.taskQuery(of: try AddUpdateTaskTests.firstTask(in: task), selecting: selection)
    }

    /// Gives the response to the query of the `ready` field of a task.
    ///
    /// - Parameter isReady: The expected value of `ready`.
    /// - Returns: The response JSON text.
    static func readyResponse(_ isReady: Bool) -> String {
        #"{"data":{"board":{"task":{"ready":\#(isReady)}}}}"#
    }

    /// Waits until the query of the `ready` field of a task gives `true`. The query runs again after each batch that
    /// the engine applies.
    ///
    /// - Parameters:
    ///   - query: The query of the `ready` field of the task.
    ///   - graph: The engine.
    ///   - recorder: The batch recorder of the engine.
    /// - Returns: `true` when the task is ready before the time limit ends.
    static func becomesReady(
        _ query: String,
        on graph: KanbanGraph,
        recordedBy recorder: BatchRecorder
    ) async throws -> Bool {
        try await BoardWatcherTests.query(query, reaches: readyResponse(true), on: graph, recordedBy: recorder)
    }

    /// Reads one field of the board that a board ref names.
    ///
    /// - Parameters:
    ///   - field: The name of the field, for example `path`.
    ///   - reference: The board ref.
    ///   - graph: The engine.
    /// - Returns: The text of the field.
    /// - Throws: An error when the response has no board.
    static func board(_ field: String, of reference: String, on graph: KanbanGraph) async throws -> String? {
        let response = try await KanbanGraphTests.execute(#"{ board(id: "\#(reference)") { \#(field) } }"#, on: graph)
        let board = try #require(NameRewriteTests.data(of: response)["board"] as? [String: Any], "\(response)")
        return board[field] as? String
    }

    /// Reads the path of each board of `Query.boards`.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the field, for example `(enabled: true)`, or the empty text.
    ///   - graph: The engine.
    /// - Returns: The paths, in the order of the list.
    /// - Throws: An error when the response has no list.
    static func boardPaths(with arguments: String = "", on graph: KanbanGraph) async throws -> [String] {
        let response = try await KanbanGraphTests.execute("{ boards\(arguments) { path } }", on: graph)
        let boards = try #require(NameRewriteTests.data(of: response)["boards"] as? [[String: Any]], "\(response)")
        return boards.compactMap { board in board["path"] as? String }
    }

    // MARK: - Dependencies across boards

    @Test("A task that depends on a task of a related board becomes ready after a second engine completes that task")
    func readyAfterCompleteInSameProcess() async throws {
        let repos = try CrossRepoFixture.SideBySide()
        let recorder = BatchRecorder()
        let app = try CrossRepoFixture.makeGraph(at: repos.app, recordedBy: recorder)
        let lib = try CrossRepoFixture.makeGraph(at: repos.lib)
        let target = try await CrossRepoFixture.addTask(with: "", on: lib)
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        let query = try Self.query(of: task, selecting: Self.readySelection)
        #expect(try await KanbanGraphTests.execute(query, on: app) == Self.readyResponse(false))
        _ = try await CommentTests.run(CommentTests.nodeField(MutationName.completeTask, naming: target), on: lib)
        #expect(try await Self.becomesReady(query, on: app, recordedBy: recorder))
        await app.close()
        await lib.close()
    }

    @Test("A task that depends on a task of a related board becomes ready after a different process completes it")
    func readyAfterWriteOfDifferentProcess() async throws {
        let repos = try CrossRepoFixture.SideBySide()
        let recorder = BatchRecorder()
        let app = try CrossRepoFixture.makeGraph(at: repos.app, recordedBy: recorder)
        let lib = try CrossRepoFixture.makeGraph(at: repos.lib)
        let target = try await CrossRepoFixture.addTask(with: "", on: lib)
        await lib.close()
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        let query = try Self.query(of: task, selecting: Self.readySelection)
        #expect(try await KanbanGraphTests.execute(query, on: app) == Self.readyResponse(false))
        let done = try #require(DefaultColumn.all.last).slug
        let patch = try PatchInput(
            node: .task(AddUpdateTaskTests.firstTask(in: target)),
            set: [PropertyName.column: .ref(.local(.column(slug: done)))]
        )
        var ids = FixedULIDSource(at: ReplayTests.date(atStep: CommitTests.callStep))
        try KanbanGraphTests.append(patch, mintingFrom: &ids, to: EventLog(repositoryAt: repos.lib))
        #expect(try await Self.becomesReady(query, on: app, recordedBy: recorder))
        await app.close()
    }

    @Test("dependsOn and blockedBy of a task list the task of the related board that it depends on")
    func dependsOnListsTaskOfRelatedBoard() async throws {
        let repos = try CrossRepoFixture.SideBySide()
        let app = try CrossRepoFixture.makeGraph(at: repos.app)
        let target = try await CrossRepoFixture.addTask(with: "", on: CrossRepoFixture.makeGraph(at: repos.lib))
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        let response = try await KanbanGraphTests.execute(
            Self.query(of: task, selecting: "{ dependsOn { id } blockedBy { id } }"),
            on: app
        )
        let edge = #"[{"id":"\#(target)"}]"#
        #expect(response == #"{"data":{"board":{"task":{"blockedBy":\#(edge),"dependsOn":\#(edge)}}}}"#)
    }

    @Test("node(id:) with the URI of a node of a related board gives that node")
    func nodeReadsRelatedBoard() async throws {
        let repos = try CrossRepoFixture.SideBySide()
        let target = try await CrossRepoFixture.addTask(with: "", on: CrossRepoFixture.makeGraph(at: repos.lib))
        let query = #"{ node(id: "\#(target)") { id ... on Task { title } } }"#
        let response = try await KanbanGraphTests.execute(query, on: CrossRepoFixture.makeGraph(at: repos.app))
        #expect(response == #"{"data":{"node":{"id":"\#(target)","title":"\#(AddUpdateTaskTests.title)"}}}"#)
    }

    @Test("A dependency on a task of a board that the scan cannot find counts as not done, with no error")
    func missingBoardDependencyIsNotDone() async throws {
        let repos = try CrossRepoFixture.SideBySide()
        let app = try CrossRepoFixture.makeGraph(at: repos.app)
        let target = NodeURI(boardKey: Self.missingKey, ref: .task(ULID())).description
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        let response = try await KanbanGraphTests.execute(Self.query(of: task, selecting: Self.readySelection), on: app)
        #expect(response == Self.readyResponse(false))
    }

    // MARK: - Board refs

    @Test("board(id:) with the current key gives the current directory, also when a different copy comes first")
    func currentKeyGivesCurrentDirectory() async throws {
        let sandbox = try GitSandbox()
        let repos = try BoardLocatorTests.TwoCopies(in: sandbox)
        let graph = try CrossRepoFixture.makeGraph(at: repos.current)
        let key = try CrossRepoFixture.keyText(of: BoardLocatorTests.appOrigin)
        #expect(try await Self.board("path", of: key, on: graph) == repos.current.path)
    }

    @Test("board(id:) with a related key gives the first copy in scan order on each call")
    func relatedKeyGivesFirstCopyOnEachCall() async throws {
        let sandbox = try GitSandbox()
        let repos = try BoardLocatorTests.TwoCopies(in: sandbox)
        let graph = try CrossRepoFixture.makeGraph(at: repos.current)
        let key = try CrossRepoFixture.keyText(of: BoardLocatorTests.libOrigin)
        #expect(try await Self.board("path", of: key, on: graph) == repos.firstCopy.path)
        #expect(try await Self.board("path", of: key, on: graph) == repos.firstCopy.path)
    }

    @Test("board(id:) with a path selects that copy")
    func pathSelectsCopy() async throws {
        let sandbox = try GitSandbox()
        let repos = try BoardLocatorTests.TwoCopies(in: sandbox)
        let graph = try CrossRepoFixture.makeGraph(at: repos.current)
        #expect(try await Self.board("path", of: repos.secondCopy.path, on: graph) == repos.secondCopy.path)
    }

    @Test("board(id:) with a unique repo directory name selects that copy")
    func directoryNameSelectsCopy() async throws {
        let sandbox = try GitSandbox()
        let repos = try BoardLocatorTests.TwoCopies(in: sandbox)
        let graph = try CrossRepoFixture.makeGraph(at: repos.current)
        let path = try await Self.board("path", of: BoardLocatorTests.secondCopyName, on: graph)
        #expect(path == repos.secondCopy.path)
    }

    @Test("A board that is not enabled shows the repo directory name as its name")
    func boardThatIsNotEnabledShowsDirectoryName() async throws {
        let sandbox = try GitSandbox()
        let repos = try BoardLocatorTests.TwoCopies(in: sandbox)
        let graph = try CrossRepoFixture.makeGraph(at: repos.current)
        let key = try CrossRepoFixture.keyText(of: BoardLocatorTests.libOrigin)
        #expect(try await Self.board("name", of: key, on: graph) == BoardLocatorTests.firstCopyName)
    }

    @Test("A key that the first scan did not find makes the engine scan one more time")
    func unknownKeyScansAgain() async throws {
        let sandbox = try GitSandbox()
        let repos = try BoardLocatorTests.TwoCopies(in: sandbox)
        let graph = try CrossRepoFixture.makeGraph(at: repos.current)
        let key = try CrossRepoFixture.keyText(of: BoardLocatorTests.libOrigin)
        #expect(try await Self.board("path", of: key, on: graph) == repos.firstCopy.path)
        let newRepo = try sandbox.makeRepo(named: "e-new-lib", origin: BoardLocatorTests.newOrigin)
        let newKey = try CrossRepoFixture.keyText(of: BoardLocatorTests.newOrigin)
        #expect(try await Self.board("path", of: newKey, on: graph) == newRepo.path)
    }

    @Test("A board that the scan cannot find gives NOT_FOUND with the search roots in the message")
    func missingBoardGivesNotFoundWithSearchRoots() async throws {
        let repos = try CrossRepoFixture.SideBySide()
        let root = repos.sandbox.root.appending(path: "src", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let graph = try CrossRepoFixture.makeGraph(at: repos.app, locatedBy: BoardLocator(searchRoots: [root]))
        let query = #"{ board(id: "\#(Self.missingKey)") { name } }"#
        let response = try await KanbanGraphTests.execute(query, on: graph)
        let roots = [repos.sandbox.root.path, root.path]
        let expected = KanbanError.boardNotFound(reference: Self.missingKey, searchRoots: roots)
        try ErrorCoverageTests.expectFailure(of: "board", in: response, giving: expected, coded: "NOT_FOUND")
    }

    // MARK: - Board list

    @Test("boards lists each copy of each repo with its path, in scan order")
    func boardsListsEachCopy() async throws {
        let sandbox = try GitSandbox()
        let repos = try BoardLocatorTests.TwoCopies(in: sandbox)
        let graph = try CrossRepoFixture.makeGraph(at: repos.current)
        let expected = [repos.worktree, repos.current, repos.firstCopy, repos.secondCopy].map(\.path)
        #expect(try await Self.boardPaths(on: graph) == expected)
    }

    @Test("boards(enabled:) lists only the copies with the enabled state")
    func boardsFiltersByEnabledState() async throws {
        let sandbox = try GitSandbox()
        let repos = try BoardLocatorTests.TwoCopies(in: sandbox)
        _ = try KanbanGraphTests.writeFixture(inRepoAt: repos.secondCopy)
        let graph = try CrossRepoFixture.makeGraph(at: repos.current)
        #expect(try await Self.boardPaths(with: "(enabled: true)", on: graph) == [repos.secondCopy.path])
        let notEnabled = [repos.worktree, repos.current, repos.firstCopy].map(\.path)
        #expect(try await Self.boardPaths(with: "(enabled: false)", on: graph) == notEnabled)
    }
}
