import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the readiness cache across boards (divergence.md §16 Gap 3, X8): after the engine keeps the readiness of a
/// task of the current board, a change of a related board on its own changes that readiness. The file watcher of the
/// related board brings the change into memory, and the next read of the current board computes again the task that
/// depends on the changed task.
///
/// Each test makes real git repos side by side in a ``GitSandbox``. No test reads or changes the `.kanban/` directory
/// of this repo.
@Suite("Cross-repo: the readiness cache follows a related board", .watcherBudget)
struct CrossRepoReadinessCacheTests {
    /// Waits until a batch of a file watcher gives a task the expected `ready` value.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - ready: The expected `ready` value.
    ///   - graph: The engine of the board of the task.
    ///   - recorder: Records each batch that the file watchers of the engine apply.
    /// - Returns: `true` when a batch gave the task the value, `false` when the time limit ended first.
    /// - Throws: An error when a read fails.
    static func task(
        _ task: String,
        becomesReady ready: Bool,
        on graph: KanbanGraph,
        recordedBy recorder: BatchRecorder
    ) async throws -> Bool {
        try await BoardWatcherTests.hasBatch(in: recorder.batches) { _ in
            try await UnresolvedDependsOnTests.fields(of: task, on: graph)["ready"] as? Bool == ready
        }
    }

    @Test("A related board that completes a dependency on its own makes the dependent task of the current board ready")
    func relatedChangeMakesDependentReady() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let recorder = BatchRecorder()
        let app = try GitGraphFixture.makeGraph(at: repos.app, recordedBy: recorder)
        let dependency = try await CrossRepoWriteTests.addLibTask(on: app)
        let task = try await CrossRepoFixture.addTask(dependingOn: dependency, on: app)
        CrossRepoCycleReadinessTests.expectBlocked(
            by: dependency,
            in: try await UnresolvedDependsOnTests.fields(of: task, on: app)
        )
        let lib = try GitGraphFixture.makeGraph(at: repos.lib, mintingFrom: GitGraphFixture.secondEngineIDs)
        try await CrossRepoCycleReadinessTests.complete(dependency, on: lib)
        await lib.close()
        #expect(try await Self.task(task, becomesReady: true, on: app, recordedBy: recorder))
        await app.close()
    }

    @Test("A related board that closes a cycle on its own blocks the task that the engine kept as ready")
    func relatedChangeClosesCycle() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let recorder = BatchRecorder()
        let app = try GitGraphFixture.makeGraph(at: repos.app, recordedBy: recorder)
        let dependency = try await CrossRepoWriteTests.addLibTask(on: app)
        let task = try await CrossRepoFixture.addTask(dependingOn: dependency, on: app)
        try await CrossRepoCycleReadinessTests.complete(dependency, on: app)
        let before = try await UnresolvedDependsOnTests.fields(of: task, on: app)
        #expect(before["ready"] as? Bool == true, "\(before)")
        try CrossRepoCycleReadinessTests.logEdge(from: dependency, to: task, inRepoAt: repos.lib)
        #expect(try await Self.task(task, becomesReady: false, on: app, recordedBy: recorder))
        CrossRepoCycleReadinessTests.expectBlocked(
            by: dependency,
            in: try await UnresolvedDependsOnTests.fields(of: task, on: app)
        )
        await app.close()
    }
}
