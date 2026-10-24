import Foundation
import FoundationModelsExtras
import GraphQL
import Testing

@testable import FoundationModelsKanban

/// Tests the `kanban` endpoint against the test kit of the GraphQL toolkit (EXTRAS-9 rule 11): the SDL is the SDL of
/// the golden file, each part of the schema has a description, and the endpoint passes the conformance check with a
/// mutation alias probe and a subscription alias probe. The test that the tool gives the endpoint is
/// ``KanbanEndpointTests/toolGivesEndpoint()``.
@Suite("Kanban endpoint: the conventions of the GraphQL toolkit", .watcherBudget)
struct EndpointConventionTests {
    /// The golden file of the SDL of the endpoint, relative to the repository root. It is outside the test target, so
    /// the package needs no resource rule for it.
    static let goldenPath = "Tests/Fixtures/kanban.graphql"

    /// The alias of the probe: the verb synonym `create` of the canonical mutation `addTask`.
    static let probeAlias = "createTask"

    /// The canonical name that the rewrite of the probe gives.
    static let probeCanonicalName = "addTask"

    /// The alias probe of the conformance check: a mutation that names `addTask` by its synonym `createTask`.
    static let mutationProbe = GraphQLAliasProbe(
        query: #"mutation { \#(probeAlias)(input: { title: "\#(KanbanGraphTests.laterTitle)" }) { id } }"#,
        from: probeAlias,
        to: probeCanonicalName
    )

    /// The alias of the subscription probe: the `<noun>Changes` alias of the canonical subscription `changes`.
    static let changesAlias = "kanbanChanges"

    /// The canonical name that the rewrite of the subscription probe gives.
    static let changesCanonicalName = "changes"

    /// The alias probe of the subscription: `changes` by its alias `kanbanChanges`, after the cursor of a read.
    ///
    /// - Parameter cursor: The cursor of the root `cursor` query.
    /// - Returns: The probe.
    static func changesProbe(after cursor: String) -> GraphQLAliasProbe {
        GraphQLAliasProbe(
            query: "subscription($after: String) { \(changesAlias)(after: $after) { cursor } }",
            variables: ["after": .string(cursor)],
            from: changesAlias,
            to: changesCanonicalName,
            kind: .subscription
        )
    }

    /// The board ref of the errors that name a board.
    static let boardReference = BoardLocatorTests.libName

    /// The transaction of the error of a transaction whose board is not loaded.
    static let transaction = "01KTXN0001"

    /// The field of the error of a field that reads other boards.
    static let boardsField = "boards"

    /// One error of each case of ``KanbanError``: the cases of ``KanbanErrorTests``, and the cases that it does not
    /// list because they share a code.
    static let errors: [KanbanError] =
        (KanbanErrorTests.codes + KanbanErrorTests.reservedSlugCodes).map { error, _ in error } + [
            .nodesNotFound(type: .task, references: KanbanErrorTests.missingTaskRefs),
            .boardNotFound(reference: boardReference, searchRoots: []),
            .transactionBoardNotLoaded(transaction: transaction, board: boardReference),
            .unreachableBoard(reference: boardReference),
            .unreachableBoards(field: boardsField),
        ]

    /// Each code of a warning that the endpoint can give, in `extensions.warnings`.
    static let warningCodes = [
        UnreadableBoard.warningCode,
        UnreadableBoard.incompatibleWarningCode,
        SubfolderBoard.warningCode,
        SharedBoardID.warningCode,
        OldBoardName.warningCode,
        IgnoredNull.warningCode,
        DependencyWarnings.taskNotFoundCode,
        DependencyWarnings.boardNotFoundCode,
        Placement.neighborNotFoundWarningCode,
        PriorityMove.warningCode,
        PriorityMove.ordinalIgnoredCode,
        RefResolver.sharedShortIDWarningCode,
        RefResolver.sharedTitleSlugWarningCode,
        GraphQLRemovedParameter.warningCode,
    ]

    /// Each code of the toolkit that the endpoint can give: `RESYNC_REQUIRED` ends a `changes` subscription that
    /// cannot resume after its cursor.
    static let toolkitCodes = [GraphQLToolkitError.resyncRequired(reason: "").code]

    /// Each error code and each warning code that the endpoint can give, for rule 8, with no repeat.
    static var codes: [String] {
        Array(Set(errors.map(\.code) + warningCodes + toolkitCodes)).sorted()
    }

    // MARK: - Helpers

    /// Runs the conformance check on an engine of a fixture board, with no exception: the endpoint obeys each rule.
    ///
    /// - Returns: The problems of the check.
    /// - Throws: An error when the fixture cannot be written or the engine cannot start.
    static func conformanceProblems() async throws -> [String] {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let read = try await KanbanGraphTests.execute("{ cursor }", on: graph)
        let cursor = try #require(KanbanGraphTests.data(of: read)["cursor"] as? String, "\(read)")
        let problems = await GraphQLEndpointConformance.problems(
            of: graph,
            scope: .sessionFolder,
            probes: [mutationProbe, changesProbe(after: cursor)],
            codes: codes,
            exceptions: []
        )
        await graph.close()
        return problems
    }

    // MARK: - Tests

    @Test("The SDL of the endpoint is the SDL of the golden file")
    func schemaMatchesGoldenFile() {
        let goldenFile = RepositoryFile.root.appendingPathComponent(Self.goldenPath)
        #expect(GraphQLSchemaGolden.problems(of: KanbanGraph.schemaSDL, against: goldenFile) == [])
    }

    @Test("Each type, field, argument, input field and enum value of the SDL has a description")
    func eachPartOfSchemaIsDescribed() throws {
        let undescribed = try GraphQLSchemaDescriptions.undescribed(in: buildSchema(source: KanbanGraph.schemaSDL))
        #expect(undescribed == [])
    }

    @Test("The endpoint passes the conformance check with the alias probes createTask and kanbanChanges, no exception")
    func endpointConforms() async throws {
        #expect(try await Self.conformanceProblems() == [])
    }
}
