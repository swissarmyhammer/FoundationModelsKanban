import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the check of a cross-board dependency on write (divergence.md Q3 as P3 changed it, X3): a `dependsOn` URI
/// or a body task URL to a different board is always accepted and stored. When the board is found and has no task
/// for the URI, the response has a warning that names the URI. When the scan finds no board, the response has a
/// warning that says that the board is not found. A URI to a task that exists gives no warning.
///
/// Each test makes real git repos in a ``GitSandbox``. No test reads or changes the `.kanban/` directory of this repo.
@Suite("Cross-repo: the check of a dependency on a different board on write", .watcherBudget)
struct DependencyTargetWarningTests {
    /// The selection of a written task: its id, and its readiness fields.
    static let selection = "{ id ready blockedBy { id } unresolvedDependsOn }"

    // MARK: - Helpers

    /// Runs one mutation field on a new engine of the current repo.
    ///
    /// - Parameters:
    ///   - field: The mutation field, with its selection.
    ///   - repos: The repos.
    /// - Returns: The response JSON text.
    /// - Throws: An error when the engine cannot be made, or when the call fails.
    static func run(_ field: String, in repos: CrossRepoFixture.SideBySide) async throws -> String {
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let response = try await CommentTests.run(field, on: app)
        await app.close()
        return response
    }

    /// Adds a task to the current repo with an `addTask` input, and gives the response.
    ///
    /// - Parameters:
    ///   - input: The fields of the input after the title, for example `dependsOn: [...]`.
    ///   - repos: The repos.
    /// - Returns: The response JSON text.
    /// - Throws: An error when the engine cannot be made, or when the call fails.
    static func addTask(with input: String, in repos: CrossRepoFixture.SideBySide) async throws -> String {
        try await run(AddUpdateTaskTests.addTask(with: input, selecting: selection), in: repos)
    }

    /// Checks that a response has one warning with a code, and that its message names a URI.
    ///
    /// - Parameters:
    ///   - code: The code of the warning.
    ///   - uri: The full URI that the message must name.
    ///   - response: The response JSON text.
    /// - Throws: An error when the response has no warnings.
    static func expectWarning(coded code: String, naming uri: String, in response: String) throws {
        let warnings = try ResponseWarningsTests.warnings(of: response)
        #expect(warnings.map(\.code) == [code], "\(response)")
        let message = try #require(warnings.first?.message)
        #expect(message.contains(uri), "\(message)")
    }

    /// Gives the full URI of a task that the related board of the repos does not have.
    ///
    /// - Returns: The URI.
    /// - Throws: An error when the key of the related repo cannot be made.
    static func missingTaskOfRelatedBoard() throws -> String {
        NodeURI(boardKey: try CrossRepoWriteTests.libKey(), ref: .task(ULID())).description
    }

    // MARK: - A missing task on a found board

    @Test("addTask with a dependsOn URI to a missing task on a found board works, blocks the task, and warns")
    func dependsOnMissingTaskOfFoundBoardWarns() async throws {
        let dependency = try await UnreadableRelatedBoardTests.makeDependency()
        let missing = try Self.missingTaskOfRelatedBoard()
        let response = try await Self.addTask(
            with: "dependsOn: \(AddUpdateTaskTests.list(of: [missing]))",
            in: dependency.repos
        )
        UnresolvedDependsOnTests.expectBlocked(
            onlyByUnresolved: [missing],
            in: try KanbanGraphTests.object(named: MutationName.addTask, in: response)
        )
        try Self.expectWarning(coded: DependencyWarnings.taskNotFoundCode, naming: missing, in: response)
    }

    @Test("addTask with a body task URL to a missing task on a found board works, blocks the task, and warns")
    func bodyURLToMissingTaskOfFoundBoardWarns() async throws {
        let dependency = try await UnreadableRelatedBoardTests.makeDependency()
        let missing = try Self.missingTaskOfRelatedBoard()
        let response = try await Self.addTask(with: #"body: "Needs \#(missing)""#, in: dependency.repos)
        UnresolvedDependsOnTests.expectBlocked(
            onlyByUnresolved: [missing],
            in: try KanbanGraphTests.object(named: MutationName.addTask, in: response)
        )
        try Self.expectWarning(coded: DependencyWarnings.taskNotFoundCode, naming: missing, in: response)
    }

    @Test("updateTask with a dependsOn URI to a missing task on a found board works, blocks the task, and warns")
    func updateDependsOnMissingTaskOfFoundBoardWarns() async throws {
        let dependency = try await UnreadableRelatedBoardTests.makeDependency()
        let missing = try Self.missingTaskOfRelatedBoard()
        let update = AddUpdateTaskTests.updateTask(
            try AddUpdateTaskTests.firstTask(in: dependency.task),
            with: "dependsOn: \(AddUpdateTaskTests.list(of: [missing]))",
            selecting: Self.selection
        )
        let response = try await Self.run(update, in: dependency.repos)
        UnresolvedDependsOnTests.expectBlocked(
            onlyByUnresolved: [missing],
            in: try KanbanGraphTests.object(named: MutationName.updateTask, in: response)
        )
        try Self.expectWarning(coded: DependencyWarnings.taskNotFoundCode, naming: missing, in: response)
    }

    // MARK: - A board that is not found

    @Test("addTask with a dependsOn URI to a board that is not found works, and the URI is in unresolvedDependsOn")
    func dependsOnMissingBoardIsAccepted() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let target = NodeURI(boardKey: CrossRepoReadTests.missingKey, ref: .task(ULID())).description
        let response = try await Self.addTask(
            with: "dependsOn: \(AddUpdateTaskTests.list(of: [target]))",
            in: repos
        )
        UnresolvedDependsOnTests.expectBlocked(
            onlyByUnresolved: [target],
            in: try KanbanGraphTests.object(named: MutationName.addTask, in: response)
        )
        try Self.expectWarning(coded: DependencyWarnings.boardNotFoundCode, naming: target, in: response)
    }

    // MARK: - A task that exists

    @Test("addTask with a dependsOn URI to a task that exists on a different board works with no warning")
    func dependsOnExistingTaskGivesNoWarning() async throws {
        let dependency = try await UnreadableRelatedBoardTests.makeDependency()
        let input = "dependsOn: \(AddUpdateTaskTests.list(of: [dependency.target])), "
            + #"body: "Also \#(dependency.target)""#
        let response = try await Self.addTask(with: input, in: dependency.repos)
        let task = try KanbanGraphTests.object(named: MutationName.addTask, in: response)
        #expect(UnresolvedDependsOnTests.blockerIDs(in: task) == [dependency.target], "\(response)")
        #expect(task["unresolvedDependsOn"] as? [String] == [], "\(response)")
        #expect(try KanbanGraphTests.object(of: response)["extensions"] == nil, "\(response)")
    }
}
