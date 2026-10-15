import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests dependencies between boards end to end (plan.md §3.3, §6.1, §6.6, divergence.md §1.1 and §2): a body marker
/// to a task of a related board, the cycle check of a write across two and three boards, the removal of a dropped
/// cross-board target from the body, and `nextTask` with a dependency on a different board.
///
/// Each test makes real git repos side by side in a ``GitSandbox``. No test reads or changes the `.kanban/` directory
/// of this repo.
@Suite("Cross-repo: dependencies between boards end to end", .watcherBudget, .timeLimit(.minutes(1)))
struct CrossRepoDependencyTests {
    /// The code of the error of a write that closes a dependency cycle.
    static let cycleCode = "DEPENDENCY_CYCLE"

    /// The selection of the `updateTask` field that drops a dependency: the body and the dependencies.
    static let bodySelection = "{ body dependsOn { id } }"

    /// The text before the task URL in a body.
    static let bodyPrefix = "Needs"

    // MARK: - Helpers

    /// Makes the `body` field of an `input` object that names a task URL as a dependency marker, with a new line at
    /// the end.
    ///
    /// - Parameter task: The full URI of the task.
    /// - Returns: The `input` field.
    static func markerBody(naming task: String) -> String {
        #"body: "\#(bodyPrefix) \#(task)\n""#
    }

    /// Reads the `ready` field of a task of the current board.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - graph: The engine of the current repo.
    /// - Returns: The response JSON text.
    /// - Throws: An error when the URI holds no ULID, or when the call fails.
    static func readyResponse(of task: String, on graph: KanbanGraph) async throws -> String {
        let query = try CrossRepoReadTests.query(of: task, selecting: CrossRepoReadTests.readySelection)
        return try await KanbanGraphTests.execute(query, on: graph)
    }

    // MARK: - Body markers

    @Test("A body marker that closes a cycle through a related board gives DEPENDENCY_CYCLE and writes nothing")
    func bodyMarkerCycleThroughRelatedBoardIsRefused() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let appTask = try await CrossRepoFixture.addTask(with: "", on: app)
        let libTask = try await CrossRepoWriteTests.addLibTask(
            with: "dependsOn: \(AddUpdateTaskTests.list(of: [appTask]))",
            on: app
        )
        let before = try Design.PortabilityTests.logTexts(inRepoAt: repos.app)
        let field = CommentTests.nodeField(
            MutationName.updateTask,
            naming: appTask,
            with: Self.markerBody(naming: libTask)
        )
        let response = try await CommentTests.run(field, on: app)
        try ErrorCoverageTests.expectFailure(
            of: MutationName.updateTask,
            in: response,
            giving: try CrossRepoCycleTests.cycle(from: appTask, through: libTask),
            coded: Self.cycleCode
        )
        #expect(try Design.PortabilityTests.logTexts(inRepoAt: repos.app) == before)
        await app.close()
    }

    @Test("A body marker to a task of a related board blocks the task until that task is done")
    func bodyMarkerToRelatedBoardChangesReady() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let target = try await CrossRepoWriteTests.addLibTask(on: app)
        let task = try await CrossRepoFixture.addTask(with: Self.markerBody(naming: target), on: app)
        #expect(try await Self.readyResponse(of: task, on: app) == CrossRepoReadTests.readyResponse(false))
        try await CrossRepoCycleReadinessTests.complete(target, on: app)
        #expect(try await Self.readyResponse(of: task, on: app) == CrossRepoReadTests.readyResponse(true))
        await app.close()
    }

    @Test("updateTask with dependsOn that drops a target of a related board also removes its URL from the body")
    func droppedRelatedTargetLeavesBody() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let target = try await CrossRepoWriteTests.addLibTask(on: app)
        let input = "dependsOn: \(AddUpdateTaskTests.list(of: [target])), \(Self.markerBody(naming: target))"
        let task = try await CrossRepoFixture.addTask(with: input, on: app)
        let clear = CommentTests.nodeField(
            MutationName.updateTask,
            naming: task,
            with: "dependsOn: []",
            selecting: Self.bodySelection
        )
        let response = try await CommentTests.run(clear, on: app)
        let updated = try KanbanGraphTests.object(named: MutationName.updateTask, in: response)
        #expect(updated["body"] as? String == "\(Self.bodyPrefix)\n", "\(response)")
        #expect((updated["dependsOn"] as? [Any])?.isEmpty == true, "\(response)")
        await app.close()
    }

    // MARK: - Cycles across three boards

    @Test("A dependsOn edge that closes a cycle across three boards gives DEPENDENCY_CYCLE and writes nothing")
    func threeBoardCycleIsRefused() async throws {
        let chain = try await CrossRepoCycleReadinessTests.makeThreeBoardChain()
        let app = try GitGraphFixture.makeGraph(at: chain.repos.app, mintingFrom: GitGraphFixture.secondEngineIDs)
        let before = try Design.PortabilityTests.logTexts(inRepoAt: chain.repos.tools)
        let field = CrossRepoCycleTests.dependencyField(from: chain.third, to: chain.first)
        let response = try await CommentTests.run(field, on: app)
        let start = try AddUpdateTaskTests.firstTaskRef(in: chain.third)
        try ErrorCoverageTests.expectFailure(
            of: MutationName.updateTask,
            in: response,
            giving: .dependencyCycle(path: [start, chain.first, chain.second, start]),
            coded: Self.cycleCode
        )
        #expect(try Design.PortabilityTests.logTexts(inRepoAt: chain.repos.tools) == before)
        await app.close()
    }

    // MARK: - nextTask

    @Test(
        "nextTask gives a task that depends on a task of a related board only when that task is done",
        arguments: [false, true]
    )
    func nextTaskFollowsRelatedDependency(isDone: Bool) async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let target = try await CrossRepoWriteTests.addLibTask(on: app)
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        if isDone {
            try await CrossRepoCycleReadinessTests.complete(target, on: app)
        }
        await app.close()
        let next = isDone
            ? #"{"data":{"board":{"nextTask":{"id":"\#(task)"}}}}"#
            : CrossRepoCycleReadinessTests.noNextTask
        #expect(try await CrossRepoCycleReadinessTests.nextTask(inRepoAt: repos.app) == next)
    }

    @Test("nextTask does not give a task that depends on a task of a board that the scan cannot find")
    func nextTaskSkipsDependencyOnMissingBoard() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let target = NodeURI(boardKey: CrossRepoReadTests.missingKey, ref: .task(ULID())).description
        _ = try await CrossRepoFixture.addTask(dependingOn: target, on: app)
        await app.close()
        let response = try await CrossRepoCycleReadinessTests.nextTask(inRepoAt: repos.app)
        #expect(response == CrossRepoCycleReadinessTests.noNextTask)
    }
}
