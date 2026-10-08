import Foundation
import FoundationModelsKanban
import Testing

/// The smoke test of the integration package: the package builds, and the engine reads a board in a real git repo.
///
/// The test uses only the public API of the library, and runs the real `git` to read the board key.
@Suite("Integration smoke: KanbanGraph reads a board in a git repo")
struct BoardSmokeTests {
    /// The name of the repo directory. A repo with no `.kanban/` directory gives a board with this name.
    static let repoName = "smoke-repo"

    /// The name of the session actor of the engine.
    static let actorName = "Integration Smoke"

    /// A query that reads the name of the board.
    static let nameQuery = "{ board { name } }"

    /// The response to ``nameQuery``: the name of the board is ``repoName``.
    static let nameResponse = #"{"data":{"board":{"name":"\#(repoName)"}}}"#

    /// A `KanbanGraph` on a new git repo with no `.kanban/` directory reads an empty board with the name of the repo
    /// directory.
    @Test("{ board { name } } gives the name of the repo directory")
    func boardNameIsTheRepoDirectoryName() async throws {
        let response = try await TemporaryGitRepo.withRepo(named: Self.repoName) { root in
            let graph = try KanbanGraph(root: root, actor: Self.actorName)
            let response = try await graph.execute(query: Self.nameQuery, variables: [:], operationName: nil)
            await graph.close()
            return response
        }

        #expect(response == Self.nameResponse)
    }
}
