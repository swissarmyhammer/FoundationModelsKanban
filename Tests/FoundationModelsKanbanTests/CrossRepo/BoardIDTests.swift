import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the board ID of each board and the names of a board (divergence.md M9): the ID event in the board log, the
/// resolve of a board by each of its names, and the old git key after a remote change.
///
/// Each test makes real git repos in a ``GitSandbox``. The engines read the worktree tops and the board keys from git.
@Suite("Board ID: the ID event, and the names of a board", .watcherBudget)
struct BoardIDTests {
    /// The `updateBoard` field that a test runs as a write of the board.
    static let writeField = #"updateBoard(input: { body: "Plan" }) { name }"#

    // MARK: - Helpers

    /// Gives the events of the board log of a repo that add a board ID.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The ID events, in the order of their ids.
    /// - Throws: An error when the board log cannot be read.
    static func idEvents(inRepoAt root: URL) throws -> [Event] {
        try BoardMutationTests.events(of: .board, inRepoAt: root).filter { event in
            !(event.patch.add[PropertyName.boardIDs] ?? []).isEmpty
        }
    }

    /// Makes one git repo with ``BoardLocatorTests/appOrigin`` in a new sandbox.
    ///
    /// - Returns: The sandbox, and the root directory of the repo.
    /// - Throws: An error when the directory cannot be made, or when a git command fails.
    static func makeRepo() async throws -> (sandbox: GitSandbox, repo: URL) {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: BoardLocatorTests.appName, origin: BoardLocatorTests.appOrigin)
        return (sandbox, repo)
    }

    // MARK: - ID event

    @Test("initBoard on a new board in a git repo writes one board ID event")
    func newBoardHasOneIDEvent() async throws {
        let (sandbox, repo) = try await Self.makeRepo()
        let graph = try GitGraphFixture.makeGraph(at: repo)
        try await CrossRepoUndoTests.runWithNoErrors("initBoard { name }", on: graph)
        #expect(try Self.idEvents(inRepoAt: repo).count == 1)
        await graph.close()
        withExtendedLifetime(sandbox) {}
    }

    @Test("A board with no ID gets no ID when it loads, and gets one ID event on its next write")
    func oldBoardGetsIDOnNextWrite() async throws {
        let (sandbox, repo) = try await Self.makeRepo()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: repo)
        let graph = try GitGraphFixture.makeGraph(at: repo)
        _ = try await KanbanGraphTests.execute("{ board { name } }", on: graph)
        #expect(try Self.idEvents(inRepoAt: repo).isEmpty)
        try await CrossRepoUndoTests.runWithNoErrors(Self.writeField, on: graph)
        try await CrossRepoUndoTests.runWithNoErrors(Self.writeField, on: graph)
        #expect(try Self.idEvents(inRepoAt: repo).count == 1)
        await graph.close()
        withExtendedLifetime(sandbox) {}
    }

    @Test("undo of the write that gave an old board its ID keeps the ID")
    func undoKeepsBoardID() async throws {
        let (sandbox, repo) = try await Self.makeRepo()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: repo)
        let graph = try GitGraphFixture.makeGraph(at: repo)
        try await CrossRepoUndoTests.runWithNoErrors(Self.writeField, on: graph)
        try await CrossRepoUndoTests.runWithNoErrors(CrossRepoUndoTests.undoField, on: graph)
        let board = try Self.boardNode(inRepoAt: repo)
        #expect(board.ids.count == 1)
        #expect(board.fields.body.isEmpty)
        await graph.close()
        withExtendedLifetime(sandbox) {}
    }

    // MARK: - Names

    /// A board ID that is lower than each ID that a session mints: the second ID of a merged board log.
    static let lowestID = "00000000000000000000000001"

    /// Gives the board node of a repo, as its board log has it now.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The board node.
    /// - Throws: An error when the board log cannot be read, or has no board node.
    static func boardNode(inRepoAt root: URL) throws -> BoardNode {
        try #require(try EventLog(repositoryAt: root).readLog(of: .board).node?.state as? BoardNode)
    }

    /// Gives the primary board ID of a repo, as its board log has it now.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The text of the lowest board ID.
    /// - Throws: An error when the board log has no board ID.
    static func boardID(inRepoAt root: URL) throws -> String {
        try #require(try boardNode(inRepoAt: root).ids.first).ulidString
    }

    /// Gives the URI of a board by one of its names.
    ///
    /// - Parameter name: The name: a board ID or a git key.
    /// - Returns: The text of the URI `kanban://<name>/board`.
    static func boardURI(named name: String) -> String {
        NodeURI(boardKey: name, ref: .board).description
    }

    /// Initializes the board of a repo with its own engine, and closes the engine.
    ///
    /// - Parameter repo: The root directory of the repo.
    /// - Returns: The primary board ID of the new board.
    /// - Throws: An error when the call fails.
    static func initBoard(inRepoAt repo: URL) async throws -> String {
        let graph = try GitGraphFixture.makeGraph(at: repo)
        try await CrossRepoUndoTests.runWithNoErrors("initBoard { name }", on: graph)
        await graph.close()
        return try boardID(inRepoAt: repo)
    }

    @Test("A URI with the bare board ID and a URI with the git key resolve to the same board")
    func boardIDAndGitKeyResolveToOneBoard() async throws {
        let (sandbox, repo) = try await Self.makeRepo()
        let id = try await Self.initBoard(inRepoAt: repo)
        let graph = try GitGraphFixture.makeGraph(at: repo)
        let key = try CrossRepoFixture.keyText(of: BoardLocatorTests.appOrigin)
        for name in [id, id.lowercased(), key] {
            #expect(try await CrossRepoReadTests.board("path", of: Self.boardURI(named: name), on: graph) == repo.path)
        }
        #expect(try await CrossRepoReadTests.board("path", of: id, on: graph) == repo.path)
        await graph.close()
        withExtendedLifetime(sandbox) {}
    }

    @Test("node(id:) with a task URI that has the bare board ID gives the task with the git key URI")
    func taskURIWithBoardIDResolves() async throws {
        let (sandbox, repo) = try await Self.makeRepo()
        let graph = try GitGraphFixture.makeGraph(at: repo)
        let task = try NodeURI(parsing: try await CrossRepoFixture.addTask(with: "", on: graph))
        let byID = NodeURI(boardKey: try Self.boardID(inRepoAt: repo), ref: task.ref)
        let response = try await KanbanGraphTests.execute(#"{ node(id: "\#(byID)") { id } }"#, on: graph)
        #expect(response == #"{"data":{"node":{"id":"\#(task)"}}}"#)
        await graph.close()
        withExtendedLifetime(sandbox) {}
    }

    @Test("A related board resolves by its bare board ID")
    func relatedBoardResolvesByBoardID() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let libID = try await Self.initBoard(inRepoAt: repos.lib)
        let graph = try GitGraphFixture.makeGraph(at: repos.app)
        #expect(try await CrossRepoReadTests.board("path", of: libID, on: graph) == repos.lib.path)
        #expect(try await CrossRepoReadTests.board("path", of: Self.boardURI(named: libID), on: graph) == repos.lib.path)
        await graph.close()
    }

    @Test("A board log with two ID events after a merge: each ID resolves, and the lowest ID is the primary ID")
    func mergedBoardLogKeepsEachID() async throws {
        let (sandbox, repo) = try await Self.makeRepo()
        let firstID = try await Self.initBoard(inRepoAt: repo)
        var ids = FixedULIDSource(at: ReplayTests.date(atStep: .zero))
        let patch = try PatchInput(
            node: .board,
            add: [PropertyName.boardIDs: [StoredRef.board(named: Self.lowestID)]]
        )
        try KanbanGraphTests.append(patch, mintingFrom: &ids, to: EventLog(repositoryAt: repo))
        let graph = try GitGraphFixture.makeGraph(at: repo, mintingFrom: GitGraphFixture.secondEngineIDs)
        for name in [firstID, Self.lowestID] {
            #expect(try await CrossRepoReadTests.board("path", of: Self.boardURI(named: name), on: graph) == repo.path)
        }
        #expect(try await CrossRepoReadTests.board("boardId", of: firstID, on: graph) == Self.lowestID)
        await graph.close()
        withExtendedLifetime(sandbox) {}
    }

    @Test("Board.names lists the git key, each board ID, and each old name")
    func boardNamesListEachName() async throws {
        let (sandbox, repo) = try await Self.makeRepo()
        let id = try await Self.initBoard(inRepoAt: repo)
        let graph = try GitGraphFixture.makeGraph(at: repo)
        let response = try await KanbanGraphTests.execute("{ board { names } }", on: graph)
        let key = try CrossRepoFixture.keyText(of: BoardLocatorTests.appOrigin)
        #expect(response == #"{"data":{"board":{"names":["\#(key)","\#(id)"]}}}"#)
        await graph.close()
        withExtendedLifetime(sandbox) {}
    }

    // MARK: - Old git key

    /// Gives a repo whose board was made with ``BoardLocatorTests/appOrigin``, and whose `origin` is then
    /// ``BoardLocatorTests/newOrigin``.
    ///
    /// - Parameter repos: The repos of the sandbox.
    /// - Returns: The old git key of the board of ``CrossRepoFixture/SideBySide/app``.
    /// - Throws: An error when a call or a git command fails.
    static func moveAppToNewRemote(in repos: CrossRepoFixture.SideBySide) async throws -> String {
        _ = try await Self.initBoard(inRepoAt: repos.app)
        let arguments = ["remote", "set-url", "origin", BoardLocatorTests.newOrigin]
        try await GitSandbox.runGit(withArguments: arguments, in: repos.app)
        return try CrossRepoFixture.keyText(of: BoardLocatorTests.appOrigin)
    }

    @Test("A write after a remote change records the old git key, and a URI with the old key still resolves")
    func remoteChangeRecordsOldKey() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let oldKey = try await Self.moveAppToNewRemote(in: repos)
        let graph = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        try await CrossRepoUndoTests.runWithNoErrors(Self.writeField, on: graph)
        let board = try Self.boardNode(inRepoAt: repos.app)
        #expect(board.oldNames == [oldKey])
        #expect(board.gitKey == (try CrossRepoFixture.keyText(of: BoardLocatorTests.newOrigin)))
        #expect(try await CrossRepoReadTests.board("path", of: Self.boardURI(named: oldKey), on: graph) == repos.app.path)
        await graph.close()
        let lib = try GitGraphFixture.makeGraph(at: repos.lib)
        #expect(try await CrossRepoReadTests.board("path", of: oldKey, on: lib) == repos.app.path)
        await lib.close()
    }

    // MARK: - Stored refs

    @Test("A dependsOn URI with the board ID of a related board is stored with the git key of that board")
    func dependencyOnBoardIDStoresGitKey() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let lib = try GitGraphFixture.makeGraph(at: repos.lib)
        let target = try NodeURI(parsing: try await CrossRepoFixture.addTask(with: "", on: lib))
        await lib.close()
        let byID = NodeURI(boardKey: try Self.boardID(inRepoAt: repos.lib), ref: target.ref)
        let app = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        let task = try await CrossRepoFixture.addTask(dependingOn: byID.description, on: app)
        let added = try #require(try CrossRepoWriteTests.events(ofTask: task, inRepoAt: repos.app).first)
        #expect(added.patch.add[PropertyName.dependsOn] == [.remote(target)])
        await app.close()
    }

    @Test("A dependsOn URI with the board ID of the current board is stored as a local ref")
    func dependencyOnOwnBoardIDIsLocal() async throws {
        let (sandbox, repo) = try await Self.makeRepo()
        let graph = try GitGraphFixture.makeGraph(at: repo)
        let target = try NodeURI(parsing: try await CrossRepoFixture.addTask(with: "", on: graph))
        let byID = NodeURI(boardKey: try Self.boardID(inRepoAt: repo), ref: target.ref)
        let task = try await CrossRepoFixture.addTask(dependingOn: byID.description, on: graph)
        let added = try #require(try CrossRepoWriteTests.events(ofTask: task, inRepoAt: repo).first)
        #expect(added.patch.add[PropertyName.dependsOn] == [.local(target.ref)])
        await graph.close()
        withExtendedLifetime(sandbox) {}
    }

    // MARK: - Index

    @Test("The scan index of a host gets the new board ID of a related board when its board log changes")
    func scanIndexGetsNewBoardID() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: repos.lib)
        let recorder = ScanRecorder()
        let host = PathBoardKeyTests.makeHost(recordedBy: recorder)
        let graph = try await host.session(workingDirectory: repos.app, actor: KanbanHostTests.firstActor)
        let libKey = try CrossRepoWriteTests.libKey()
        #expect(try await ScanCacheTests.hasBoard(of: libKey, on: graph))
        let lib = try GitGraphFixture.makeGraph(at: repos.lib)
        try await CrossRepoUndoTests.runWithNoErrors(Self.writeField, on: lib)
        await lib.close()
        let libID = try Self.boardID(inRepoAt: repos.lib)
        try await recorder.waitForChange(waitingFor: "the board ID of the related board", at: repos.lib) {
            try await ScanCacheTests.hasBoard(of: libID, on: graph)
        }
        #expect(try await CrossRepoReadTests.board("path", of: libID, on: graph) == repos.lib.path)
        await host.close()
    }
}
