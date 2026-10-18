import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the key index of a board that a call reached by a path to a folder outside the scan places (divergence.md
/// X4): after that call, a URI with the key of that board resolves to it, also in a later call.
///
/// Each test makes real git repos in a ``GitSandbox``: the current repo and a related repo side by side, and a repo
/// at ``BoardLocatorTests/outsidePath``, where the scan does not look. The engines read the worktree tops and the
/// board keys from git.
@Suite("Cross-repo: a board that a call reached by a path is in the key index", .watcherBudget)
struct PathBoardKeyTests {
    /// The response key of the field that adds a task to the current board.
    static let currentField = "current"

    /// The response key of the field that adds a task to the board outside the scan places.
    static let outsideField = "outside"

    /// The path in the sandbox of a second repo outside the scan places, with the same key as the first. Its path
    /// sorts before the path of the first repo.
    static let earlierOutsidePath = "outside/a-other"

    /// The `origin` that a test gives to the repo outside the scan places after a call reached it by a path.
    static let movedOrigin = "https://github.com/example/moved-lib.git"

    // MARK: - Helpers

    /// Gives the key of the repo outside the scan places as text.
    ///
    /// - Returns: The key.
    /// - Throws: An error when the remote URL is not valid.
    static func outsideKey() throws -> String {
        try CrossRepoFixture.keyText(of: BoardLocatorTests.newOrigin)
    }

    /// Makes the repos of a test: the current repo and the related repo side by side, and a git repo outside the scan
    /// places.
    ///
    /// - Returns: The repos, and the repo outside the scan places.
    /// - Throws: An error when a directory cannot be made, or when a git command fails.
    static func makeRepos() async throws -> (repos: CrossRepoFixture.SideBySide, outside: URL) {
        let repos = try await CrossRepoFixture.SideBySide.make()
        return (repos, try await CrossRepoWriteTests.makeOutsideFolder(as: .gitRepo, in: repos))
    }

    /// Adds a task to the board of a folder through a path ref, and gives its id.
    ///
    /// - Parameters:
    ///   - input: The fields of the input after the board field, or the empty text.
    ///   - folder: The folder that the path ref names.
    ///   - graph: The engine of the current repo.
    /// - Returns: The full URI of the task.
    /// - Throws: An error when the response has no id.
    static func addTask(with input: String = "", inFolderAt folder: URL, on graph: KanbanGraph) async throws -> String {
        try await CrossRepoFixture.addTask(with: CrossRepoWriteTests.boardField(folder.path) + input, on: graph)
    }

    // MARK: - Key index

    @Test("After a call with a path outside the scan places, a URI with the key of that board resolves to it")
    func keyResolvesAfterPathCall() async throws {
        let (repos, outside) = try await Self.makeRepos()
        let graph = try GitGraphFixture.makeGraph(at: repos.app)
        #expect(try await CrossRepoReadTests.board("path", of: outside.path, on: graph) == outside.path)
        let uri = NodeURI(boardKey: try Self.outsideKey(), ref: .board).description
        #expect(try await CrossRepoReadTests.board("path", of: uri, on: graph) == outside.path)
        await graph.close()
    }

    @Test("A key that a copy of the scan has resolves to that copy, also after a call reached a copy by a path")
    func scanCopyComesBeforePathCopy() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let outside = try await repos.sandbox.makeRepo(
            named: BoardLocatorTests.outsidePath,
            origin: BoardLocatorTests.libOrigin
        )
        let graph = try GitGraphFixture.makeGraph(at: repos.app)
        #expect(try await CrossRepoReadTests.board("path", of: outside.path, on: graph) == outside.path)
        let key = try CrossRepoWriteTests.libKey()
        #expect(try await CrossRepoReadTests.board("path", of: key, on: graph) == repos.lib.path)
        await graph.close()
    }

    @Test("Two copies that calls reached by a path, with one key: the key resolves to the first path in sort order")
    func pathCopiesResolveInSortOrder() async throws {
        let (repos, outside) = try await Self.makeRepos()
        let earlier = try await repos.sandbox.makeRepo(
            named: Self.earlierOutsidePath,
            origin: BoardLocatorTests.newOrigin
        )
        let graph = try GitGraphFixture.makeGraph(at: repos.app)
        #expect(try await CrossRepoReadTests.board("path", of: outside.path, on: graph) == outside.path)
        #expect(try await CrossRepoReadTests.board("path", of: earlier.path, on: graph) == earlier.path)
        #expect(try await CrossRepoReadTests.board("path", of: Self.outsideKey(), on: graph) == earlier.path)
        await graph.close()
    }

    // MARK: - Invalidation

    @Test("A new origin of a repo that a call reached by a path makes its old key resolve to that repo no more")
    func changedOriginForgetsOldKey() async throws {
        let (repos, outside) = try await Self.makeRepos()
        let recorder = ScanRecorder()
        let host = Self.makeHost(recordedBy: recorder)
        let graph = try await host.session(workingDirectory: repos.app, actor: KanbanHostTests.firstActor)
        let key = try Self.outsideKey()
        #expect(try await CrossRepoReadTests.board("path", of: outside.path, on: graph) == outside.path)
        #expect(try await ScanCacheTests.hasBoard(of: key, on: graph))
        try await GitSandbox.runGit(withArguments: ["remote", "set-url", "origin", Self.movedOrigin], in: outside)
        try await recorder.waitForChange(.repo(outside.canonicalPath)) {
            try await !ScanCacheTests.hasBoard(of: key, on: graph)
        }
        #expect(try await !ScanCacheTests.hasBoard(of: key, on: graph))
        await host.close()
    }

    @Test("A closed host keeps no board that a call reached by a path")
    func closedHostForgetsPathCopies() async throws {
        let (repos, outside) = try await Self.makeRepos()
        let host = Self.makeHost(recordedBy: ScanRecorder())
        let graph = try await host.session(workingDirectory: repos.app, actor: KanbanHostTests.firstActor)
        #expect(try await CrossRepoReadTests.board("path", of: outside.path, on: graph) == outside.path)
        await host.close()
        #expect(try await !ScanCacheTests.hasBoard(of: Self.outsideKey(), on: graph))
    }

    /// Makes a host that reads the worktree tops and the board keys from git, and whose scans and watched changes a
    /// recorder records.
    ///
    /// - Parameter recorder: Records each scan, and each change that a file watcher of the host sees.
    /// - Returns: The host.
    static func makeHost(recordedBy recorder: ScanRecorder) -> KanbanHost {
        HostFixture.makeHost(
            readingKeyWith: BoardKey.read(fromRepoAt:),
            findingTopWith: BoardKey.worktreeTop(of:),
            observingScansWith: recorder
        )
    }

    // MARK: - Reads by key

    @Test("A task that depends on a done task of a board that a call reached by a path is READY")
    func dependencyOnDoneTaskIsReady() async throws {
        let (repos, outside) = try await Self.makeRepos()
        let graph = try GitGraphFixture.makeGraph(at: repos.app)
        let done = try #require(DefaultColumn.all.last).slug
        let target = try await Self.addTask(with: #", column: "\#(done)""#, inFolderAt: outside, on: graph)
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: graph)
        let query = try CrossRepoReadTests.query(of: task, selecting: CrossRepoReadTests.readySelection)
        #expect(try await KanbanGraphTests.execute(query, on: graph) == CrossRepoReadTests.readyResponse(true))
        await graph.close()
    }

    @Test("node(id:) with the URI of a task of a board that a call reached by a path gives the task")
    func nodeReadsPathBoard() async throws {
        let (repos, outside) = try await Self.makeRepos()
        let graph = try GitGraphFixture.makeGraph(at: repos.app)
        let target = try await Self.addTask(inFolderAt: outside, on: graph)
        let query = #"{ node(id: "\#(target)") { id ... on Task { title } } }"#
        let response = try await KanbanGraphTests.execute(query, on: graph)
        #expect(response == #"{"data":{"node":{"id":"\#(target)","title":"\#(AddUpdateTaskTests.title)"}}}"#)
        await graph.close()
    }

    // MARK: - Undo

    @Test("undo with no board field reverses a call that changed the current board and a board reached by a path")
    func undoReversesPathBoard() async throws {
        let (repos, outside) = try await Self.makeRepos()
        let graph = try GitGraphFixture.makeGraph(at: repos.app)
        let mutation = AddUpdateTaskTests.mutation(
            of: "\(Self.currentField): " + AddUpdateTaskTests.addTask(with: ""),
            "\(Self.outsideField): " + AddUpdateTaskTests.addTask(with: CrossRepoWriteTests.boardField(outside.path))
        )
        let data = try KanbanGraphTests.data(of: try await KanbanGraphTests.execute(mutation, on: graph))
        let current = try CrossRepoUndoTests.id(of: Self.currentField, in: data)
        let other = try CrossRepoUndoTests.id(of: Self.outsideField, in: data)
        try await CrossRepoUndoTests.runWithNoErrors(CrossRepoUndoTests.undoField, on: graph)
        #expect(try CrossRepoUndoTests.lastEvent(ofTask: current, inRepoAt: repos.app).patch.delete == true)
        #expect(try CrossRepoUndoTests.lastEvent(ofTask: other, inRepoAt: outside).patch.delete == true)
        await graph.close()
    }
}
