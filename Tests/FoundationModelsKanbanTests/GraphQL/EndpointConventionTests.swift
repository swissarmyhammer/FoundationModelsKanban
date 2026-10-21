import Foundation
import FoundationModelsExtras
import GraphQL
import Testing

@testable import FoundationModelsKanban

/// Tests the `kanban` endpoint against the test kit of the GraphQL toolkit (EXTRAS-9 rule 11): the SDL is the SDL of
/// the golden file, each part of the schema has a description, and the endpoint passes the conformance check with an
/// alias probe. The test that the tool gives the endpoint is ``KanbanEndpointTests/toolGivesEndpoint()``.
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
    static let probe = GraphQLAliasProbe(
        query: #"mutation { \#(probeAlias)(input: { title: "\#(KanbanGraphTests.laterTitle)" }) { id } }"#,
        from: probeAlias,
        to: probeCanonicalName
    )

    /// The id of the task that adds the opaque change cursor, `changes(after:)` and the root query `cursor`
    /// (KANBAN-7). It removes the exception of rule 9.
    static let changeCursorTask = "e60e9sx"

    /// The id of the task that gives each mutation the form `verbNoun(input: VerbNounInput!)`. It removes the
    /// exception of rule 7.
    ///
    /// The exception stands because no mutation that breaks rule 7 can change and keep its old form as an alias: the
    /// rewrite of the toolkit does not rename a type name in a variable definition, cannot move top-level arguments
    /// into an `input` object, and cannot give a default for a missing required `input` (plan.md §4 makes `input`
    /// optional when it has no required field).
    static let mutationFormTask = "gnn5vz8"

    /// The rules that the endpoint does not obey yet, each with the task that removes it.
    static let exceptions = [
        GraphQLConventionException(rule: .changes, removedBy: changeCursorTask),
        GraphQLConventionException(rule: .mutations, removedBy: mutationFormTask),
    ]

    /// The mutations that break rule 7 under its exception, in the order of the schema. A new mutation must have the
    /// form of rule 7, so this list only gets shorter.
    static let mutationsOutsideRule7 = [
        "initBoard", "updateBoard", "deleteColumn", "undeleteColumn", "addActor", "deleteActor", "undeleteActor",
        "completeTask", "unassignTask", "untagTask", "deleteTask", "undeleteTask", "deleteComment", "undeleteComment",
        "addTag", "deleteTag", "undeleteTag", "undo", "redo", "repairLinks", "collectBoards",
    ]

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

    /// Each error code and each warning code that the endpoint can give, for rule 8, with no repeat.
    static var codes: [String] {
        Array(Set(errors.map(\.code) + warningCodes)).sorted()
    }

    // MARK: - Helpers

    /// Runs the conformance check on an engine of a fixture board.
    ///
    /// - Parameter exceptions: The rules that the check does not report.
    /// - Returns: The problems of the check.
    /// - Throws: An error when the fixture cannot be written or the engine cannot start.
    static func conformanceProblems(excepting exceptions: [GraphQLConventionException]) async throws -> [String] {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let problems = await GraphQLEndpointConformance.problems(
            of: graph,
            scope: .sessionFolder,
            probe: probe,
            codes: codes,
            exceptions: exceptions
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

    @Test("The endpoint passes the conformance check with the alias probe createTask, under the exceptions")
    func endpointConforms() async throws {
        #expect(try await Self.conformanceProblems(excepting: Self.exceptions) == [])
    }

    @Test("Under the rule-9 exception alone, rule 7 reports only the mutations of the rule-7 exception")
    func onlyKnownMutationsBreakRule7() async throws {
        let rule7 = GraphQLConventionRule.mutations.name
        let problems = try await Self.conformanceProblems(excepting: [Self.exceptions[0]])
        let reported = problems.filter { problem in problem.hasPrefix(rule7) }
        let named = Self.mutationsOutsideRule7.filter { mutation in
            reported.contains { problem in problem.contains("mutation \(mutation)(") }
        }
        #expect(named == Self.mutationsOutsideRule7, "\(reported)")
        #expect(reported.count == Self.mutationsOutsideRule7.count, "\(reported)")
        #expect(problems.filter { problem in !problem.hasPrefix(rule7) } == [])
    }
}
