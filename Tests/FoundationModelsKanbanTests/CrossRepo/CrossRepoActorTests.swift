import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests `Change.actor` for a change of a related board (plan.md §6.5, §6.6, §6.7): the actor resolves in the board of
/// the change, not in the board of the call.
///
/// Each test makes real git repos in a ``GitSandbox``. The related repo has an actor that the current repo does not
/// have: the session actor of the engine that writes the related board. Each test closes each engine that it makes.
@Suite("Cross-repo: the actor of a change of a related board", .timeLimit(.minutes(1)))
struct CrossRepoActorTests {
    /// The name of the session actor that writes the related board. The current board has no actor with this name.
    private static let libActorName = "Lib Owner"

    /// The selection of the name of the actor of a change.
    private static let actorSelection = "{ actor { name } }"

    /// The JSON object of a change with ``actorSelection`` whose actor is the actor of the related board.
    private static let libActorChange = #"{"actor":{"name":"\#(libActorName)"}}"#

    /// Makes an engine for the related repo with the session actor ``libActorName``.
    ///
    /// - Parameter repos: The repos of the sandbox.
    /// - Returns: The engine.
    /// - Throws: An error when the actor name gives an empty slug.
    private static func makeLibGraph(in repos: CrossRepoFixture.SideBySide) throws -> KanbanGraph {
        try GitGraphFixture.makeGraph(at: repos.lib, actingAs: try KanbanGraph.sessionActor(named: libActorName))
    }

    @Test("history of a related board gives the actor of that board")
    func historyOfRelatedBoardGivesItsActor() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let lib = try Self.makeLibGraph(in: repos)
        _ = try await CrossRepoFixture.addTask(with: "", on: lib)
        await lib.close()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let libKey = try CrossRepoFixture.keyText(of: BoardLocatorTests.libOrigin)
        let query = #"{ board(id: "\#(libKey)") { history(first: 1) \#(Self.actorSelection) } }"#
        let response = try await KanbanGraphTests.execute(query, on: app)
        #expect(response == #"{"data":{"board":{"history":[\#(Self.libActorChange)]}}}"#)
        await app.close()
    }

    @Test("A DERIVED-only change of a subscription gives the actor of the board of the transaction")
    func derivedChangeGivesActorOfTransactionBoard() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let lib = try Self.makeLibGraph(in: repos)
        let target = try await CrossRepoFixture.addTask(with: "", on: lib)
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        _ = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        await app.close()
        let watcher = try GitGraphFixture.makeGraph(at: repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        let document = "subscription { changes\(SubscriptionTests.taskArguments) \(Self.actorSelection) }"
        let stream = try await SubscriptionTests.subscribe(document, on: watcher)
        _ = try await CommentTests.run(CommentTests.nodeField(MutationName.completeTask, naming: target), on: lib)
        let expected = #"{"data":{"changes":\#(Self.libActorChange)}}"#
        #expect(try await SubscriptionTests.events(SubscriptionTests.oneEvent, of: stream) == [expected])
        await lib.close()
        await watcher.close()
    }
}
