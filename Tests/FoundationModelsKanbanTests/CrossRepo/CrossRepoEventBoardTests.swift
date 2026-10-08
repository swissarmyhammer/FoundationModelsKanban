import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the board that the resolvers of a change of a related board read (plan.md §6.5, §6.6, §6.7): the key of the
/// current board of the engine names that board, and the node of an update is a node of the board of the update.
///
/// Each test makes real git repos in a ``GitSandbox``. Each test closes each engine that it makes.
@Suite("Cross-repo: the board of a change of a related board", .timeLimit(.minutes(1)))
struct CrossRepoEventBoardTests {
    /// The name of the session actor of the engine on the current repo. The related board has no actor with this
    /// name.
    private static let appActorName = "App Owner"

    /// The selection of the name of the actor of a change.
    private static let actorSelection = "{ actor { name } }"

    /// The selection of the `ready` value of the task of each update.
    private static let readySelection = "{ updates { node { ... on Task { ready } } } }"

    /// Subscribes, on the engine of the current repo, to the task changes of the related board. A task of the related
    /// board depends on a task of the current board. Then the engine completes the task of the current board, and the
    /// task of the related board gets a `DERIVED`-only change.
    ///
    /// - Parameter selection: The selection of each change.
    /// - Returns: The response of the first event, in a list. The list is empty when no event comes before the time
    ///   limit.
    /// - Throws: An error when a repo, an engine, or a call fails.
    private static func eventOfRelatedBoard(selecting selection: String) async throws -> [String] {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let appActor = try KanbanGraph.sessionActor(named: appActorName)
        let app = try GitGraphFixture.makeGraph(at: repos.app, actingAs: appActor)
        let target = try await CrossRepoFixture.addTask(with: "", on: app)
        let lib = try GitGraphFixture.makeGraph(at: repos.lib, mintingFrom: GitGraphFixture.secondEngineIDs)
        _ = try await CrossRepoFixture.addTask(dependingOn: target, on: lib)
        await lib.close()
        let libKey = try CrossRepoFixture.keyText(of: BoardLocatorTests.libOrigin)
        let document = #"subscription { changes(board: "\#(libKey)", type: [TASK]) \#(selection) }"#
        let stream = try await SubscriptionTests.subscribe(document, on: app)
        _ = try await CommentTests.run(CommentTests.nodeField(MutationName.completeTask, naming: target), on: app)
        let events = try await SubscriptionTests.events(SubscriptionTests.oneEvent, of: stream)
        await app.close()
        return events
    }

    @Test("A change of a related board for a transaction of the current board gives the actor of the current board")
    func relatedBoardChangeGivesActorOfCurrentBoard() async throws {
        let expected = #"{"data":{"changes":{"actor":{"name":"\#(Self.appActorName)"}}}}"#
        let events = try await Self.eventOfRelatedBoard(selecting: Self.actorSelection)
        #expect(events == [expected])
    }

    @Test("A task of a related board that depends on a done task of the current board is ready in the change")
    func relatedBoardTaskIsReadyInChange() async throws {
        let expected = #"{"data":{"changes":{"updates":[{"node":{"ready":true}}]}}}"#
        let events = try await Self.eventOfRelatedBoard(selecting: Self.readySelection)
        #expect(events == [expected])
    }

    @Test("history of a related board gives the nodes of that board")
    func historyOfRelatedBoardGivesItsNodes() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let lib = try GitGraphFixture.makeGraph(at: repos.lib)
        let target = try await CrossRepoFixture.addTask(with: "", on: lib)
        await lib.close()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let libKey = try CrossRepoFixture.keyText(of: BoardLocatorTests.libOrigin)
        let query = #"{ board(id: "\#(libKey)") { history(first: 1) { updates(type: [TASK]) { node { id } } } } }"#
        let response = try await KanbanGraphTests.execute(query, on: app)
        #expect(response == #"{"data":{"board":{"history":[{"updates":[{"node":{"id":"\#(target)"}}]}]}}}"#)
        await app.close()
    }
}
