import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests `Task.unresolvedDependsOn` (divergence.md Q2, X2): the full URI of each dependency that no loaded board has as
/// a task. Such a dependency still blocks the task (plan.md §3.3, rule 4), and `blockedBy` does not list it. A
/// dependency on a tombstone is ignored, so it is not in the list.
///
/// Each test makes real git repos in a ``GitSandbox``. No test reads or changes the `.kanban/` directory of this repo.
@Suite("Cross-repo: dependencies that cannot resolve", .watcherBudget, .timeLimit(.minutes(1)))
struct UnresolvedDependsOnTests {
    /// The selection of the readiness fields of a task and of its unresolved dependencies.
    static let selection = "{ ready blockedBy { id } unresolvedDependsOn }"

    // MARK: - Helpers

    /// Reads the fields of ``selection`` for one task of the current board.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - graph: The engine.
    /// - Returns: The fields of the task, as the response gives them.
    /// - Throws: An error when the response has no task.
    static func fields(of task: String, on graph: KanbanGraph) async throws -> [String: Any] {
        let query = try CrossRepoReadTests.query(of: task, selecting: selection)
        let response = try await KanbanGraphTests.execute(query, on: graph)
        let board = try #require(NameRewriteTests.data(of: response)["board"] as? [String: Any], "\(response)")
        return try #require(board["task"] as? [String: Any], "\(response)")
    }

    /// Reads the fields of ``selection`` for one task of the current repo, on a new engine.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - repos: The repos.
    /// - Returns: The fields of the task.
    /// - Throws: An error when the engine cannot be made, or when the response has no task.
    static func fields(
        of task: String,
        onNewEngineIn repos: CrossRepoFixture.SideBySide
    ) async throws -> [String: Any] {
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let fields = try await fields(of: task, on: app)
        await app.close()
        return fields
    }

    /// Adds a task to the current repo with an `addTask` input, and reads the fields of ``selection`` for it.
    ///
    /// - Parameters:
    ///   - input: The fields of the input after the title, for example `dependsOn: [...]`.
    ///   - repos: The repos.
    /// - Returns: The fields of the new task.
    /// - Throws: An error when the call fails, or when the response has no task.
    static func fieldsOfTask(with input: String, in repos: CrossRepoFixture.SideBySide) async throws -> [String: Any] {
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await CrossRepoFixture.addTask(with: input, on: app)
        let fields = try await fields(of: task, on: app)
        await app.close()
        return fields
    }

    /// Adds a task to the current repo that depends on a target, and reads the fields of ``selection`` for it.
    ///
    /// - Parameters:
    ///   - target: The full URI of the target.
    ///   - repos: The repos.
    /// - Returns: The fields of the new task.
    /// - Throws: An error when the call fails, or when the response has no task.
    static func fieldsOfTask(
        dependingOn target: String,
        in repos: CrossRepoFixture.SideBySide
    ) async throws -> [String: Any] {
        try await fieldsOfTask(with: "dependsOn: \(AddUpdateTaskTests.list(of: [target]))", in: repos)
    }

    /// Adds a task to the current repo, writes a `dependsOn` edge to it with a raw log line, as a different process
    /// can, and reads the fields of ``selection`` for it on a new engine. The public write refuses some of these
    /// edges (divergence.md Q3).
    ///
    /// - Parameters:
    ///   - target: The stored ref of the target of the edge.
    ///   - repos: The repos.
    /// - Returns: The fields of the task.
    /// - Throws: An error when a call fails, when the append fails, or when the response has no task.
    static func fieldsOfTask(
        withLoggedEdgeTo target: StoredRef,
        in repos: CrossRepoFixture.SideBySide
    ) async throws -> [String: Any] {
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let task = try await CrossRepoFixture.addTask(with: "", on: app)
        await app.close()
        let patch = try PatchInput(
            node: .task(AddUpdateTaskTests.firstTask(in: task)),
            add: [PropertyName.dependsOn: [target]]
        )
        var ids = FixedULIDSource(at: ReplayTests.date(atStep: CommitTests.callStep))
        try KanbanGraphTests.append(patch, mintingFrom: &ids, to: EventLog(repositoryAt: repos.app))
        return try await fields(of: task, onNewEngineIn: repos)
    }

    /// Gives the ids of the `blockedBy` list of a task.
    ///
    /// - Parameter fields: The fields of the task.
    /// - Returns: The ids, or `nil` when the fields have no `blockedBy` list.
    static func blockerIDs(in fields: [String: Any]) -> [String]? {
        (fields["blockedBy"] as? [[String: Any]])?.compactMap { blocker in blocker["id"] as? String }
    }

    /// Checks that a task is blocked only by targets that cannot resolve: `ready` is `false`, `blockedBy` is empty,
    /// and `unresolvedDependsOn` lists the targets.
    ///
    /// - Parameters:
    ///   - targets: The full URIs that `unresolvedDependsOn` must list, in order.
    ///   - fields: The fields of the task.
    static func expectBlocked(onlyByUnresolved targets: [String], in fields: [String: Any]) {
        #expect(fields["ready"] as? Bool == false, "\(fields)")
        #expect(blockerIDs(in: fields) == [], "\(fields)")
        #expect(fields["unresolvedDependsOn"] as? [String] == targets, "\(fields)")
    }

    // MARK: - Targets that cannot resolve

    @Test("A dependsOn URI to a repo that the scan cannot find is in unresolvedDependsOn, and the task is blocked")
    func missingRepoIsUnresolved() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let target = NodeURI(boardKey: CrossRepoReadTests.missingKey, ref: .task(ULID())).description
        Self.expectBlocked(onlyByUnresolved: [target], in: try await Self.fieldsOfTask(dependingOn: target, in: repos))
    }

    @Test("A dependsOn URI with a typo in the board key is in unresolvedDependsOn")
    func typoInBoardKeyIsUnresolved() async throws {
        let dependency = try await UnreadableRelatedBoardTests.makeDependency()
        let uri = try NodeURI(parsing: dependency.target)
        let typo = NodeURI(boardKey: String(uri.boardKey.dropLast()), ref: uri.ref).description
        let fields = try await Self.fieldsOfTask(dependingOn: typo, in: dependency.repos)
        Self.expectBlocked(onlyByUnresolved: [typo], in: fields)
    }

    @Test("A dependsOn URI to a missing task of a loaded related board is in unresolvedDependsOn")
    func missingTaskOfLoadedBoardIsUnresolved() async throws {
        let dependency = try await UnreadableRelatedBoardTests.makeDependency()
        let missing = NodeURI(boardKey: try CrossRepoWriteTests.libKey(), ref: .task(ULID()))
        let fields = try await Self.fieldsOfTask(withLoggedEdgeTo: .remote(missing), in: dependency.repos)
        Self.expectBlocked(onlyByUnresolved: [missing.description], in: fields)
    }

    @Test("A body marker to a missing task of the current board is in unresolvedDependsOn")
    func bodyMarkerToMissingTaskIsUnresolved() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let appKey = try CrossRepoFixture.keyText(of: BoardLocatorTests.appOrigin)
        let marker = NodeURI(boardKey: appKey, ref: .task(ULID())).description
        let fields = try await Self.fieldsOfTask(with: #"body: "Needs \#(marker)""#, in: repos)
        Self.expectBlocked(onlyByUnresolved: [marker], in: fields)
    }

    @Test("A dependsOn edge to a node that is not a task is in unresolvedDependsOn")
    func edgeToNodeThatIsNotTaskIsUnresolved() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let column = LocalRef.column(slug: try #require(DefaultColumn.all.first).slug)
        let fields = try await Self.fieldsOfTask(withLoggedEdgeTo: .local(column), in: repos)
        let appKey = try CrossRepoFixture.keyText(of: BoardLocatorTests.appOrigin)
        Self.expectBlocked(onlyByUnresolved: [NodeURI(boardKey: appKey, ref: column).description], in: fields)
    }

    @Test(
        "A dependsOn URI to a task of a related board that cannot be read is in unresolvedDependsOn",
        arguments: UnreadableRelatedBoardTests.Breakage.allCases
    )
    func taskOfUnreadableBoardIsUnresolved(breakage: UnreadableRelatedBoardTests.Breakage) async throws {
        let dependency = try await UnreadableRelatedBoardTests.makeBrokenDependency(breakage)
        let fields = try await Self.fields(of: dependency.task, onNewEngineIn: dependency.repos)
        Self.expectBlocked(onlyByUnresolved: [dependency.target], in: fields)
    }

    // MARK: - Targets that resolve

    @Test("A task whose dependencies all resolve has an empty unresolvedDependsOn")
    func resolvedTargetsGiveEmptyList() async throws {
        let dependency = try await UnreadableRelatedBoardTests.makeDependency()
        let fields = try await Self.fields(of: dependency.task, onNewEngineIn: dependency.repos)
        #expect(Self.blockerIDs(in: fields) == [dependency.target], "\(fields)")
        #expect(fields["unresolvedDependsOn"] as? [String] == [], "\(fields)")
    }

    @Test("A dependency on a tombstoned task of a related board is not in unresolvedDependsOn")
    func tombstonedTargetIsNotUnresolved() async throws {
        let dependency = try await UnreadableRelatedBoardTests.makeDependency()
        let lib = try GitGraphFixture.makeGraph(at: dependency.repos.lib, mintingFrom: GitGraphFixture.secondEngineIDs)
        let delete = CommentTests.nodeField(MutationName.deleteTask, naming: dependency.target)
        _ = try await CommentTests.run(delete, on: lib)
        await lib.close()
        let fields = try await Self.fields(of: dependency.task, onNewEngineIn: dependency.repos)
        #expect(fields["ready"] as? Bool == true, "\(fields)")
        #expect(fields["unresolvedDependsOn"] as? [String] == [], "\(fields)")
    }

    // MARK: - Schema

    @Test("The schema gives unresolvedDependsOn a list of IDs with no null item")
    func unresolvedDependsOnFieldType() throws {
        #expect(try PublicSchema().sdl.contains("unresolvedDependsOn: [ID!]!\n"))
    }
}
