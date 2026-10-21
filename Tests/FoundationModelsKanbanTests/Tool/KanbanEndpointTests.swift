import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing

@testable import FoundationModelsKanban

/// Tests the `kanban` GraphQL endpoint (KANBAN-5, EXTRAS-9 rules 1, 3 and 11): ``KanbanGraph`` conforms to
/// ``GraphQLEndpoint``, and ``KanbanTool`` gives that same engine in ``GraphQLEndpointTool/graphQLEndpoints``.
///
/// Each test uses the fixture repo of ``KanbanGraphTests``: one board, one terminal column, and one task.
@Suite("Kanban endpoint: the engine as a GraphQLEndpoint of the tool", .watcherBudget)
struct KanbanEndpointTests {
    /// The name of the endpoint: the noun of the tool (EXTRAS-9 rule 1).
    static let endpointName = "kanban"

    /// The version of the schema of the endpoint (EXTRAS-9 rule 1).
    static let endpointVersion = "1"

    /// A query whose response does not change between two calls on one board.
    static let boardQuery = "{ board { name columns { id name } tasks { edges { node { id title } } } } }"

    /// A subscription that cannot start: its filter does not parse, so its stream has one response with the error.
    static let failingSubscription = #"subscription { changes(filter: "&&") { txn } }"#

    // MARK: - Tool

    @Test("The tool gives one endpoint with the name kanban, the version 1, and the session-folder scope")
    func toolGivesEndpoint() async throws {
        let directory = try TemporaryDirectory()
        let tool = try KanbanToolTests.makeTool(inRepoAt: directory.url)
        let endpoint = try #require(tool.graphQLEndpoints.only)
        #expect(endpoint.name == Self.endpointName)
        #expect(endpoint.version == Self.endpointVersion)
        #expect(endpoint.scope == .sessionFolder)
        #expect(endpoint.schema == KanbanGraph.schemaSDL)
        try await Self.close(tool)
    }

    @Test("The tool is found as a GraphQLEndpointTool through an any Tool value")
    func toolIsFoundAsEndpointTool() async throws {
        let directory = try TemporaryDirectory()
        let tool: any Tool = try KanbanToolTests.makeTool(inRepoAt: directory.url)
        let endpointTool = try #require(tool as? any GraphQLEndpointTool)
        #expect(endpointTool.graphQLEndpoints.count == 1)
        try await Self.close(try #require(tool as? KanbanTool))
    }

    @Test("The endpoint of the tool and of each copy of the tool is the engine of the tool, not a copy")
    func endpointIsEngineOfTool() async throws {
        let directory = try TemporaryDirectory()
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let tool = KanbanTool(graph: graph)
        let copy = tool
        for endpoints in [tool.graphQLEndpoints, copy.graphQLEndpoints] {
            let endpoint = try #require(endpoints.only as? KanbanGraph)
            #expect(endpoint === graph)
        }
        await graph.close()
    }

    // MARK: - Execute and subscribe

    @Test(
        "execute through the protocol gives the same JSON as the direct call, for each viewer of the user",
        arguments: [nil, KanbanViewerFixture.userDevice]
    )
    func executeMatchesDirectCall(viewer: GraphQLViewer?) async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let direct = try await KanbanGraphTests.execute(Self.boardQuery, on: graph)
        let endpoint: any GraphQLEndpoint = graph
        let viaEndpoint = try await endpoint.execute(
            query: Self.boardQuery,
            variables: [:],
            operationName: nil,
            viewer: viewer
        )
        #expect(viaEndpoint == direct)
        await graph.close()
    }

    @Test("subscribe through the protocol gives the same JSON as the direct call for a change")
    func subscribeMatchesDirectCall() async throws {
        let directory = try TemporaryDirectory()
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let document = SubscriptionTests.subscription(SubscriptionTests.taskArguments)
        let direct = try await SubscriptionTests.subscribe(document, on: graph)
        let endpoint: any GraphQLEndpoint = graph
        let viaEndpoint = try await endpoint.subscribe(query: document, variables: [:], operationName: nil, viewer: nil)
        let expected = try await SubscriptionTests.changeTitle(of: task, to: KanbanGraphTests.laterTitle, on: graph)
        let oneEvent = SubscriptionTests.oneEvent
        #expect(try await SubscriptionTests.events(oneEvent, of: direct, afterChangeAt: directory.url) == [expected])
        #expect(try await SubscriptionTests.events(oneEvent, of: viaEndpoint, afterChangeAt: directory.url) == [expected])
        await graph.close()
    }

    @Test("subscribe through the protocol gives the same error stream as the direct call for a document that fails")
    func failingSubscribeMatchesDirectCall() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let direct = try await SubscriptionTests.subscribe(Self.failingSubscription, on: graph)
        let endpoint: any GraphQLEndpoint = graph
        let viaEndpoint = try await endpoint.subscribe(
            query: Self.failingSubscription,
            variables: [:],
            operationName: nil,
            viewer: nil
        )
        let directEvents = try await SubscriptionTests.allEvents(of: direct)
        #expect(!directEvents.isEmpty)
        #expect(try await SubscriptionTests.allEvents(of: viaEndpoint) == directEvents)
        await graph.close()
    }

    // MARK: - Helpers

    /// Closes the engine of a tool.
    ///
    /// - Parameter tool: The tool.
    /// - Throws: An error when the tool gives no engine.
    static func close(_ tool: KanbanTool) async throws {
        await (try #require(tool.graphQLEndpoints.only as? KanbanGraph)).close()
    }
}

extension Array {
    /// The one element of the array, or `nil` when the array has no element or more than one.
    fileprivate var only: Element? {
        count == 1 ? first : nil
    }
}
