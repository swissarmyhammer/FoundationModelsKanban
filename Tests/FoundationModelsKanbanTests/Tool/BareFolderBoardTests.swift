import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the boards in folders that are not in a git repo (divergence.md M9, where the board is). Outside git, the board
/// is in the nearest folder, from the working directory up, that has a `.kanban/`. When no folder has one, the board is
/// `<working dir>/.kanban/`, and the first write makes it. The key of such a board is its board ID.
///
/// Each test makes its folders in a ``GitSandbox``, which is not in a git repo. The engines read the worktree tops and
/// the board keys from git.
@Suite("Boards in folders outside git", .watcherBudget)
struct BareFolderBoardTests {
    /// The name of the bare folder of the tests.
    static let bareFolderName = "notes"

    /// The path of the subfolder of the bare folder, below the bare folder.
    static let subfolderPath = "Sources/Deep"

    /// Makes a bare folder in a sandbox.
    ///
    /// - Parameter sandbox: The sandbox of the test.
    /// - Returns: The bare folder.
    /// - Throws: An error from `FileManager` when the folder cannot be made.
    static func makeBareFolder(in sandbox: GitSandbox) throws -> URL {
        try GitSandbox.makeFolder(named: bareFolderName, in: sandbox.root)
    }

    /// Makes the subfolder ``subfolderPath`` in a folder.
    ///
    /// - Parameter folder: The folder.
    /// - Returns: The subfolder.
    /// - Throws: An error from `FileManager` when the folder cannot be made.
    static func makeSubfolder(in folder: URL) throws -> URL {
        try GitSandbox.makeFolder(named: subfolderPath, in: folder)
    }

    // MARK: - Where the board is

    @Test("A session in a bare folder with no .kanban/ above makes the board in the working directory on the first write")
    func firstWriteMakesBoardInWorkingDirectory() async throws {
        let sandbox = try GitSandbox()
        let folder = try Self.makeBareFolder(in: sandbox)
        let graph = try GitGraphFixture.makeGraph(at: folder)
        #expect(!CrossRepoWriteTests.hasBoardDirectory(inRepoAt: folder))
        let task = try await CrossRepoFixture.addTask(with: "", on: graph)
        await graph.close()
        #expect(!(try CrossRepoWriteTests.events(ofTask: task, inRepoAt: folder).isEmpty))
        #expect(try NodeURI(parsing: task).boardKey == (try BoardIDTests.boardID(inRepoAt: folder)))
        withExtendedLifetime(sandbox) {}
    }

    @Test("A session in a bare folder and in a subfolder of it use the .kanban/ of the bare folder")
    func sessionUsesNearestBoardAbove() async throws {
        let sandbox = try GitSandbox()
        let folder = try Self.makeBareFolder(in: sandbox)
        _ = try KanbanGraphTests.writeFixture(inRepoAt: folder)
        let subfolder = try Self.makeSubfolder(in: folder)
        for directory in [folder, subfolder] {
            let response = try await RepoBoardTests.respond(to: KanbanGraphTests.nameQuery, inWorkingDirectory: directory)
            #expect(response == KanbanGraphTests.nameResponse)
        }
        let graph = try GitGraphFixture.makeGraph(at: subfolder)
        let task = try await CrossRepoFixture.addTask(with: "", on: graph)
        await graph.close()
        #expect(!(try CrossRepoWriteTests.events(ofTask: task, inRepoAt: folder).isEmpty))
        #expect(!CrossRepoWriteTests.hasBoardDirectory(inRepoAt: subfolder))
        withExtendedLifetime(sandbox) {}
    }

    // MARK: - Scan

    /// Makes a bare folder with a board in a sandbox: an engine of the folder writes the board one time, so the board
    /// gets its board ID.
    ///
    /// - Parameter sandbox: The sandbox of the test.
    /// - Returns: The bare folder, and its board ID.
    /// - Throws: An error when the folder or the board cannot be made.
    static func makeBareBoard(in sandbox: GitSandbox) async throws -> (folder: URL, id: String) {
        let folder = try makeBareFolder(in: sandbox)
        let graph = try GitGraphFixture.makeGraph(at: folder)
        try await CrossRepoUndoTests.runWithNoErrors(BoardIDTests.writeField, on: graph)
        await graph.close()
        return (folder, try BoardIDTests.boardID(inRepoAt: folder))
    }

    @Test("Query.boards of a repo lists a sibling bare folder that has a .kanban/, with its board ID as its key")
    func boardsListsSiblingBareFolder() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: BoardLocatorTests.appName, origin: BoardLocatorTests.appOrigin)
        let bare = try await Self.makeBareBoard(in: sandbox)
        let graph = try GitGraphFixture.makeGraph(at: repo)
        #expect(try await CrossRepoReadTests.boardPaths(on: graph).contains(bare.folder.path))
        #expect(try await CrossRepoReadTests.board("path", of: bare.id, on: graph) == bare.folder.path)
        await graph.close()
        withExtendedLifetime(sandbox) {}
    }

    @Test("Query.boards of a bare folder lists a sibling repo and the bare folder itself")
    func boardsOfBareFolderListsSiblingRepo() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: BoardLocatorTests.appName, origin: BoardLocatorTests.appOrigin)
        let bare = try await Self.makeBareBoard(in: sandbox)
        let graph = try GitGraphFixture.makeGraph(at: bare.folder)
        let paths = try await CrossRepoReadTests.boardPaths(on: graph)
        #expect(Set(paths) == [repo.path, bare.folder.path])
        await graph.close()
        withExtendedLifetime(sandbox) {}
    }

    // MARK: - Shared board ID

    /// The name of the copy of the bare folder in the shared board ID test.
    static let copiedFolderName = "notes-copy"

    @Test("A scan that finds a copied bare folder with the same board ID gives a warning that names both paths")
    func copiedFolderGivesSharedIDWarning() async throws {
        let sandbox = try GitSandbox()
        let bare = try await Self.makeBareBoard(in: sandbox)
        let copy = sandbox.root.appending(path: Self.copiedFolderName, directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: bare.folder, to: copy)
        let graph = try GitGraphFixture.makeGraph(at: bare.folder)
        let response = try await KanbanGraphTests.execute(ScanCacheTests.boardsQuery, on: graph)
        await graph.close()
        #expect(try CrossRepoWriteTests.hasNoErrors(response), "\(response)")
        let shared = try ResponseWarningsTests.warnings(of: response).filter { warning in
            warning.code == SharedBoardID.warningCode
        }
        #expect(shared.count == 1)
        let message = try #require(shared.first?.message)
        #expect(message.contains(bare.folder.path) && message.contains(copy.path) && message.contains(bare.id))
        withExtendedLifetime(sandbox) {}
    }
}
