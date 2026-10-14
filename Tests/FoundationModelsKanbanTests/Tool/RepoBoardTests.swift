import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests where the engine finds the board of its working directory (divergence.md §16): the board is in the
/// `.kanban/` directory of the top folder of the worktree, and a folder that is not in a git repo has no board.
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

    /// The name of the folder that is not in a git repo.
    static let plainFolderName = "plain-folder"

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

    @Test("A .kanban/ in a subfolder of a repo is not read: the session reads the board at the top folder")
    func subfolderBoardIsNotUsed() async throws {
        let sandbox = try GitSandbox()
        let (_, subfolder) = try await Self.makeRepoWithSubfolder(in: sandbox)
        _ = try KanbanGraphTests.writeFixture(inRepoAt: subfolder)
        let response = try await Self.respond(to: "{ board { name } }", inWorkingDirectory: subfolder)
        #expect(response == #"{"data":{"board":{"name":"\#(Self.repoName)"}}}"#)
    }

    // MARK: - Outside git

    @Test("Each call in a folder that is not in a git repo gives NOT_A_REPO, and writes no .kanban/")
    func folderOutsideRepoGivesNotARepo() async throws {
        let sandbox = try GitSandbox()
        let folder = try GitSandbox.makeFolder(named: Self.plainFolderName, in: sandbox.root)
        let graph = try GitGraphFixture.makeGraph(at: folder)
        let expected = try KanbanError.notARepo(path: folder.path).responseJSON()
        #expect(try await KanbanGraphTests.execute(KanbanGraphTests.keyQuery, on: graph) == expected)
        let mutation = AddUpdateTaskTests.mutation(of: AddUpdateTaskTests.addTask(with: ""))
        #expect(try await KanbanGraphTests.execute(mutation, on: graph) == expected)
        await graph.close()
        #expect(!CrossRepoWriteTests.hasBoardDirectory(inRepoAt: folder))
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
