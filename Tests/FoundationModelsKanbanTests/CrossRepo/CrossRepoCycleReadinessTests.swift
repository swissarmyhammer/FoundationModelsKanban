import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the readiness of a `dependsOn` cycle across boards that a merge makes (plan.md §5.3 step 5, divergence.md
/// X8): each task in the cycle is blocked, also when its dependency is done, and `nextTask` does not give it. A chain
/// across boards with no cycle keeps its readiness.
///
/// The write path refuses an edge that closes a cycle, so each test writes the last edge of a cycle with a raw log
/// line, as a merge or a different process can. Each test makes real git repos side by side in a ``GitSandbox``. No
/// test reads or changes the `.kanban/` directory of this repo.
@Suite("Cross-repo: readiness of dependency cycles across boards", .watcherBudget)
struct CrossRepoCycleReadinessTests {
    /// The name of the third repo of a test with three boards.
    static let toolsName = "tools"

    /// The `origin` of the third repo of a test with three boards.
    static let toolsOrigin = "https://github.com/example/tools.git"

    /// The query of the next task of the current board.
    static let nextTaskQuery = "{ board { nextTask { id } } }"

    /// The response to ``nextTaskQuery`` when no task is next.
    static let noNextTask = #"{"data":{"board":{"nextTask":null}}}"#

    // MARK: - Helpers

    /// Gives the key of the third repo as text.
    ///
    /// - Returns: The key.
    /// - Throws: An error when the remote URL is not valid.
    static func toolsKey() throws -> String {
        try CrossRepoFixture.keyText(of: toolsOrigin)
    }

    /// Completes a task through an engine, and checks that the call has no error.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - graph: The engine.
    /// - Throws: An error when the call fails.
    static func complete(_ task: String, on graph: KanbanGraph) async throws {
        let field = CommentTests.nodeField(MutationName.completeTask, naming: task)
        let response = try await CommentTests.run(field, on: graph)
        #expect(try CrossRepoWriteTests.hasNoErrors(response), "\(response)")
    }

    /// Writes a `dependsOn` edge from a task to a task of a different board with a raw log line, as a merge or a
    /// different process can. The public write refuses an edge that closes a cycle.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task that gets the edge.
    ///   - target: The full URI of the target of the edge.
    ///   - repo: The repo of the board of the task.
    /// - Throws: An error when a URI holds no ULID, or when the append fails.
    static func logEdge(from task: String, to target: String, inRepoAt repo: URL) throws {
        let patch = try PatchInput(
            node: .task(AddUpdateTaskTests.firstTask(in: task)),
            add: [PropertyName.dependsOn: [.remote(NodeURI(parsing: target))]]
        )
        var ids = FixedULIDSource(at: ReplayTests.date(atStep: CommitTests.callStep))
        try KanbanGraphTests.append(patch, mintingFrom: &ids, to: EventLog(repositoryAt: repo))
    }

    /// Reads the readiness fields of one task of the board of a repo, on a new engine.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - repo: The repo of the board of the task.
    /// - Returns: The fields of ``UnresolvedDependsOnTests/selection``.
    /// - Throws: An error when the engine cannot be made, or when the response has no task.
    static func fields(of task: String, inRepoAt repo: URL) async throws -> [String: Any] {
        let graph = try GitGraphFixture.makeGraph(at: repo)
        let fields = try await UnresolvedDependsOnTests.fields(of: task, on: graph)
        await graph.close()
        return fields
    }

    /// Reads `nextTask` of the board of a repo, on a new engine.
    ///
    /// - Parameter repo: The repo of the board.
    /// - Returns: The response JSON text.
    /// - Throws: An error when the engine cannot be made, or when the call fails.
    static func nextTask(inRepoAt repo: URL) async throws -> String {
        let graph = try GitGraphFixture.makeGraph(at: repo)
        let response = try await KanbanGraphTests.execute(nextTaskQuery, on: graph)
        await graph.close()
        return response
    }

    /// Checks that a task is blocked by one dependency: `ready` is `false`, and `blockedBy` lists only that
    /// dependency.
    ///
    /// - Parameters:
    ///   - blocker: The full URI of the dependency that blocks the task.
    ///   - fields: The fields of the task.
    static func expectBlocked(by blocker: String, in fields: [String: Any]) {
        #expect(fields["ready"] as? Bool == false, "\(fields)")
        #expect(UnresolvedDependsOnTests.blockerIDs(in: fields) == [blocker], "\(fields)")
    }

    /// The tasks of the two-board example of divergence.md X8.
    struct TwoBoardCycle {
        /// The current repo and the related repo.
        let repos: CrossRepoFixture.SideBySide

        /// The full URI of `a`, the task of the current board. It is not done, and it depends on `b`.
        let task: String

        /// The full URI of `b`, the task of the related board. It is done, and it depends on `a`.
        let dependency: String
    }

    /// Makes the two-board example: `a` depends on `B#b`, and `b` is done and depends on `A#a`.
    ///
    /// - Returns: The repos and the two tasks.
    /// - Throws: An error when a call fails, or when the append fails.
    static func makeTwoBoardCycle() async throws -> TwoBoardCycle {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let dependency = try await CrossRepoWriteTests.addLibTask(on: app)
        let task = try await CrossRepoFixture.addTask(dependingOn: dependency, on: app)
        try await complete(dependency, on: app)
        await app.close()
        try logEdge(from: dependency, to: task, inRepoAt: repos.lib)
        return TwoBoardCycle(repos: repos, task: task, dependency: dependency)
    }

    /// The tasks of a chain across three boards: `a` in the current board depends on `b` in the related board, and
    /// `b` depends on `c` in the third board. `b` and `c` are done.
    struct ThreeBoardChain {
        /// The three repos. The third repo is ``toolsName``.
        let repos: CrossRepoFixture.ThreeRepos

        /// The full URI of `a`, the task of the current board. It is not done.
        let first: String

        /// The full URI of `b`, the task of the related board.
        let second: String

        /// The full URI of `c`, the task of the third board.
        let third: String
    }

    /// Makes the chain of ``ThreeBoardChain``, with no cycle.
    ///
    /// - Returns: The repos and the three tasks.
    /// - Throws: An error when a call fails.
    static func makeThreeBoardChain() async throws -> ThreeBoardChain {
        let repos = try await CrossRepoFixture.ThreeRepos.make(toolsNamed: toolsName, origin: toolsOrigin)
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let third = try await CrossRepoFixture.addTask(with: CrossRepoWriteTests.boardField(toolsKey()), on: app)
        let second = try await CrossRepoWriteTests.addLibTask(
            with: "dependsOn: \(AddUpdateTaskTests.list(of: [third]))",
            on: app
        )
        let first = try await CrossRepoFixture.addTask(dependingOn: second, on: app)
        try await complete(second, on: app)
        try await complete(third, on: app)
        await app.close()
        return ThreeBoardChain(repos: repos, first: first, second: second, third: third)
    }

    // MARK: - Cycles across boards

    @Test("In a cycle across two boards, the task is blocked by its done dependency and is not READY")
    func twoBoardCycleBlocksTask() async throws {
        let cycle = try await Self.makeTwoBoardCycle()
        let fields = try await Self.fields(of: cycle.task, inRepoAt: cycle.repos.app)
        Self.expectBlocked(by: cycle.dependency, in: fields)
    }

    @Test("nextTask does not give a task in a cycle across two boards")
    func nextTaskSkipsTaskInCrossBoardCycle() async throws {
        let cycle = try await Self.makeTwoBoardCycle()
        #expect(try await Self.nextTask(inRepoAt: cycle.repos.app) == Self.noNextTask)
    }

    @Test("A cycle across three boards blocks each task in it")
    func threeBoardCycleBlocksEachTask() async throws {
        let chain = try await Self.makeThreeBoardChain()
        try Self.logEdge(from: chain.third, to: chain.first, inRepoAt: chain.repos.tools)
        let first = try await Self.fields(of: chain.first, inRepoAt: chain.repos.app)
        let second = try await Self.fields(of: chain.second, inRepoAt: chain.repos.lib)
        let third = try await Self.fields(of: chain.third, inRepoAt: chain.repos.tools)
        Self.expectBlocked(by: chain.second, in: first)
        Self.expectBlocked(by: chain.third, in: second)
        Self.expectBlocked(by: chain.first, in: third)
    }

    // MARK: - Chains with no cycle

    @Test("A chain across three boards with no cycle keeps its readiness: the task is READY and nextTask gives it")
    func threeBoardChainWithNoCycleIsReady() async throws {
        let chain = try await Self.makeThreeBoardChain()
        let fields = try await Self.fields(of: chain.first, inRepoAt: chain.repos.app)
        #expect(fields["ready"] as? Bool == true, "\(fields)")
        #expect(UnresolvedDependsOnTests.blockerIDs(in: fields) == [], "\(fields)")
        let next = #"{"data":{"board":{"nextTask":{"id":"\#(chain.first)"}}}}"#
        #expect(try await Self.nextTask(inRepoAt: chain.repos.app) == next)
    }

    @Test("A cycle across boards behind a done dependency does not block a task outside the cycle, and the walk ends")
    func crossBoardCycleBehindDoneDependencyDoesNotBlock() async throws {
        let chain = try await Self.makeThreeBoardChain()
        try Self.logEdge(from: chain.third, to: chain.second, inRepoAt: chain.repos.tools)
        let fields = try await Self.fields(of: chain.first, inRepoAt: chain.repos.app)
        #expect(fields["ready"] as? Bool == true, "\(fields)")
    }
}
