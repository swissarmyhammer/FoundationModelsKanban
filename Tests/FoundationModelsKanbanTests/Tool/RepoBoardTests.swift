import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests where the engine finds the board of its working directory in a git repo (divergence.md §16, M9): the board is
/// in the `.kanban/` directory of the top folder of the worktree. ``BareFolderBoardTests`` tests the folders outside
/// git.
///
/// Each test makes real git repos in a ``GitSandbox`` and engines that read the worktree top and the board key from
/// git.
@Suite("Board at the worktree top", .watcherBudget)
struct RepoBoardTests {
    /// The name of the repo of the tests.
    static let repoName = "app"

    /// The name of the linked worktree of the worktree tests.
    static let worktreeName = "feature-worktree"

    /// The name of the subfolder of the working directory.
    static let subfolderName = "Sources"

    /// Makes a repo with ``BoardLocatorTests/appOrigin`` and a subfolder in it.
    ///
    /// - Parameter sandbox: The sandbox of the test.
    /// - Returns: The top folder of the repo, and its subfolder.
    /// - Throws: An error when a git command fails, or when the subfolder cannot be made.
    static func makeRepoWithSubfolder(in sandbox: GitSandbox) async throws -> (repo: URL, subfolder: URL) {
        let repo = try await sandbox.makeRepo(named: repoName, origin: BoardLocatorTests.appOrigin)
        return (repo, try GitSandbox.makeFolder(named: subfolderName, in: repo))
    }

    /// Runs one document on an engine of a working directory, and closes the engine.
    ///
    /// - Parameters:
    ///   - query: The GraphQL document.
    ///   - directory: The working directory of the engine.
    /// - Returns: The response JSON text.
    /// - Throws: An error when the engine cannot start or the call throws.
    static func respond(to query: String, inWorkingDirectory directory: URL) async throws -> String {
        let graph = try GitGraphFixture.makeGraph(at: directory)
        let response = try await KanbanGraphTests.execute(query, on: graph)
        await graph.close()
        return response
    }

    // MARK: - Subfolder

    @Test("A session in a subfolder of a repo writes to the board at the top folder of the repo")
    func subfolderUsesRepoBoard() async throws {
        let sandbox = try GitSandbox()
        let (repo, subfolder) = try await Self.makeRepoWithSubfolder(in: sandbox)
        let graph = try GitGraphFixture.makeGraph(at: subfolder)
        let task = try await CrossRepoFixture.addTask(with: "", on: graph)
        await graph.close()
        #expect(try NodeURI(parsing: task).boardKey == CrossRepoFixture.keyText(of: BoardLocatorTests.appOrigin))
        #expect(!(try CrossRepoWriteTests.events(ofTask: task, inRepoAt: repo).isEmpty))
        #expect(!CrossRepoWriteTests.hasBoardDirectory(inRepoAt: subfolder))
    }

    @Test("A subfolder .kanban/ of a repo is not read: the top folder board is read, and a warning names collectBoards")
    func subfolderBoardIsNotUsed() async throws {
        let sandbox = try GitSandbox()
        let (repo, subfolder) = try await Self.makeRepoWithSubfolder(in: sandbox)
        _ = try KanbanGraphTests.writeFixture(inRepoAt: subfolder)
        let response = try await Self.respond(to: "{ board { name } }", inWorkingDirectory: subfolder)
        let board = try KanbanGraphTests.object(named: "board", in: response)
        #expect(board["name"] as? String == Self.repoName)
        let warnings = try ResponseWarningsTests.warnings(of: response)
        #expect(warnings.map(\.code) == [SubfolderBoard.warningCode])
        let message = try #require(warnings.first?.message)
        let subfolderBoard = EventLog(repositoryAt: subfolder).directory.path
        #expect(message.contains(subfolderBoard) && message.contains(repo.path) && message.contains("collectBoards"))
    }

    // MARK: - Worktree

    @Test("A session in a linked worktree writes to the board of that worktree, with the key of the main clone")
    func worktreeUsesWorktreeBoard() async throws {
        let sandbox = try GitSandbox()
        let (repo, _) = try await Self.makeRepoWithSubfolder(in: sandbox)
        let worktree = try await sandbox.addWorktree(named: Self.worktreeName, to: repo)
        let worktreeSubfolder = try GitSandbox.makeFolder(named: Self.subfolderName, in: worktree)
        let graph = try GitGraphFixture.makeGraph(at: worktreeSubfolder)
        let task = try await CrossRepoFixture.addTask(with: "", on: graph)
        await graph.close()
        #expect(!(try CrossRepoWriteTests.events(ofTask: task, inRepoAt: worktree).isEmpty))
        #expect(!CrossRepoWriteTests.hasBoardDirectory(inRepoAt: repo))
        let worktreeKey = try await Self.respond(to: KanbanGraphTests.keyQuery, inWorkingDirectory: worktree)
        let mainCloneKey = try await Self.respond(to: KanbanGraphTests.keyQuery, inWorkingDirectory: repo)
        #expect(worktreeKey == mainCloneKey)
    }
}
