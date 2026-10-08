import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the `dependsOn` cycle rule across boards (plan.md §3.3 rule 6, §5.4, §6.6): the check reads each board on
/// the cycle path, and the commit check covers each board that the check read.
///
/// Each test makes two real git repos side by side in a ``GitSandbox``. The engines read the board keys from git.
@Suite("Cross-repo: dependency cycles across boards", .timeLimit(.minutes(1)))
struct CrossRepoCycleTests {
    // MARK: - Helpers

    /// Makes the `updateTask` field that gives a task one dependency.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - target: The full URI of the task that the task depends on.
    /// - Returns: The field, with the selection `{ id }`.
    static func dependencyField(from task: String, to target: String) -> String {
        CommentTests.nodeField(
            MutationName.updateTask,
            naming: task,
            with: "dependsOn: \(AddUpdateTaskTests.list(of: [target]))"
        )
    }

    /// Gives the error of a cycle that goes from a task of the board of the field to a task of a different board,
    /// and back.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task of the field.
    ///   - other: The full URI of the task of the different board.
    /// - Returns: The error. A task of the board of the field shows as its short id, and a task of a different
    ///   board shows as its full URI.
    /// - Throws: An error when the URI of the task holds no ULID.
    static func cycle(from task: String, through other: String) throws -> KanbanError {
        let start = AddUpdateTaskTests.sigilRef(of: try AddUpdateTaskTests.firstTask(in: task))
        return .dependencyCycle(path: [start, other, start])
    }

    // MARK: - Tests

    @Test("A dependsOn edge that closes a cycle through a related board gives DEPENDENCY_CYCLE and writes nothing")
    func crossBoardCycleIsRefused() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let app = try GitGraphFixture.makeGraph(at: repos.app)
        let appTask = try await CrossRepoFixture.addTask(with: "", on: app)
        let libTask = try await CrossRepoWriteTests.addLibTask(
            with: "dependsOn: \(AddUpdateTaskTests.list(of: [appTask]))",
            on: app
        )
        let before = try Design.PortabilityTests.logTexts(inRepoAt: repos.app)
        let response = try await CommentTests.run(Self.dependencyField(from: appTask, to: libTask), on: app)
        let expected = try Self.cycle(from: appTask, through: libTask)
        try ErrorCoverageTests.expectFailure(
            of: MutationName.updateTask,
            in: response,
            giving: expected,
            coded: "DEPENDENCY_CYCLE"
        )
        #expect(try Design.PortabilityTests.logTexts(inRepoAt: repos.app) == before)
        await app.close()
    }

    @Test("Two engines add the two halves of a cross-board cycle: the second one gets DEPENDENCY_CYCLE at its commit")
    func concurrentHalvesOfCycleAreRefusedAtCommit() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let first = try GitGraphFixture.makeGraph(at: repos.app)
        let appTask = try await CrossRepoFixture.addTask(with: "", on: first)
        let libTask = try await CrossRepoWriteTests.addLibTask(on: first)
        // The second engine is a different process: it loads both boards, and then its file watchers stop. Thus its
        // live graphs do not see the write of the first engine, the same as before an FSEvents event comes in. Only
        // the commit check under the locks (plan.md §5.4 step 5.2) can find the write.
        let second = try GitGraphFixture.makeGraph(at: repos.lib, mintingFrom: GitGraphFixture.secondEngineIDs)
        _ = try await CrossRepoReadTests.board("name", of: CrossRepoWriteTests.appKey(), on: second)
        await second.close()
        let firstHalf = try await CommentTests.run(Self.dependencyField(from: appTask, to: libTask), on: first)
        #expect(try CrossRepoWriteTests.hasNoErrors(firstHalf), "\(firstHalf)")
        let before = try Design.PortabilityTests.logTexts(inRepoAt: repos.lib)
        let secondHalf = try await CommentTests.run(Self.dependencyField(from: libTask, to: appTask), on: second)
        try ErrorCoverageTests.expectFailure(
            of: MutationName.updateTask,
            in: secondHalf,
            giving: try Self.cycle(from: libTask, through: appTask),
            coded: "DEPENDENCY_CYCLE"
        )
        #expect(try Design.PortabilityTests.logTexts(inRepoAt: repos.lib) == before)
        await first.close()
    }
}
