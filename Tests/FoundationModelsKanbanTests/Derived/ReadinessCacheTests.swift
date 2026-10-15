import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the readiness cache of a board (divergence.md §2 "Performance", §16 Gap 3, K9): a read with no change does
/// not walk the dependency graph again, and a change walks again only for the tasks that the change can affect.
///
/// Each test uses a graph in memory, or a temporary repo of its own. No test reads or changes the `.kanban/`
/// directory of this repo.
@Suite("Readiness cache: no walk again when nothing changed", .watcherBudget)
struct ReadinessCacheTests {
    /// The number of chains of the two-chain board: each chain is a done task and a task that depends on it.
    static let chainCount = 2

    /// The number of tasks that depend on the task that a test changes in the two-chain board.
    static let dependentCount = 1

    /// The title that a test gives to a task to change it.
    static let changedTitle = "Changed title"

    /// The number of steps of the property test after the calls of each random sequence. Each step is a random
    /// public call or a watcher apply of a raw log line.
    static let stepCount = 12

    /// One kind of raw log line that a different process, a merge, or a manual edit can write. The file watcher
    /// then applies it to the live graph.
    enum RawEdit: CaseIterable {
        /// A `dependsOn` edge from one task to a task, also to itself or to a task that depends on it: the raw line
        /// can close a cycle that the public write refuses.
        case dependency

        /// A delete or an undelete of a task.
        case delete

        /// A move of a task to a column, done or not done.
        case column
    }

    // MARK: - Helpers

    /// Makes a board with two chains: the second task depends on the first task, and the fourth task depends on the
    /// third task. The first task and the third task are done, so the readiness of each dependent walks one time.
    ///
    /// - Returns: The board.
    /// - Throws: An error when a ULID text is not valid.
    static func twoChains() throws -> ReadinessFixture {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.done)
        try board.addTask(withULID: ReadinessFixture.second, dependingOn: [ReadinessFixture.first])
        try board.addTask(withULID: ReadinessFixture.third, inColumn: ReadinessFixture.done)
        try board.addTask(withULID: ReadinessFixture.fourth, dependingOn: [ReadinessFixture.third])
        return board
    }

    /// Reads the readiness of each task of a graph through a cache.
    ///
    /// - Parameters:
    ///   - graph: The graph of the board.
    ///   - cache: The readiness cache of the board.
    /// - Returns: The slots of the ready tasks.
    @discardableResult
    static func readyTasks(of graph: Graph, cachedIn cache: ReadinessCache) -> Set<Int> {
        let readiness = Readiness(of: graph, inBoard: DependencyMarkersTests.boardKey, cachedIn: cache)
        return Set(readiness.taskOrder.filter(readiness.isReady(taskAt:)))
    }

    /// Gives the readiness of the live graph of a session as a read view gives it: through the readiness cache of
    /// the board.
    ///
    /// - Parameter session: The commit session.
    /// - Returns: The cached readiness.
    static func cachedReadiness(of session: CommitSession) -> Readiness {
        session.snapshot.view(reading: .unavailable).readiness
    }

    /// Expects that the cached readiness of each task of a session, live or tombstoned, is the same as a full walk:
    /// the same blockers in the same order.
    ///
    /// - Parameter session: The commit session.
    static func expectCachedReadinessEqualsFullWalk(of session: CommitSession) {
        let cached = cachedReadiness(of: session)
        let full = Readiness(of: cached.graph, inBoard: session.key.description)
        for slot in full.taskOrder {
            #expect(cached.blockers(ofTaskAt: slot) == full.blockers(ofTaskAt: slot), "task at slot \(slot)")
        }
    }

    /// Writes a raw log line of a patch, as a different process, a merge, or a manual edit can, and applies the
    /// changed file to the live graph, as the file watcher does.
    ///
    /// - Parameters:
    ///   - patch: The patch of the line.
    ///   - session: The commit session.
    ///   - step: The step of the line in its sequence. Each step gets a later time, so that its event id is larger
    ///     than each id of the session.
    /// - Throws: An error when the append or the apply fails.
    static func applyRawEdit(_ patch: PatchInput, to session: inout CommitSession, atStep step: Int) async throws {
        var ids = FixedULIDSource(at: ReplayTests.date(atStep: CommitTests.callStep + step + 1))
        let log = session.live.log
        try KanbanGraphTests.append(patch, mintingFrom: &ids, to: log)
        _ = try await session.apply(watchedPaths: [log.fileURL(for: patch.node)])
    }

    /// Makes the patch of a random raw log line on a random task of a session.
    ///
    /// - Parameters:
    ///   - session: The commit session.
    ///   - generator: The source of random numbers.
    /// - Returns: The patch.
    /// - Throws: An error when the patch is not valid.
    static func randomRawEdit(in session: CommitSession, using generator: inout SplitMix64) throws -> PatchInput {
        typealias Replay = Design.ReplayPropertyTests
        let tasks = Replay.tasks(of: session)
        let task = Replay.pick(from: tasks, using: &generator)
        switch Replay.pick(from: RawEdit.allCases, using: &generator) {
        case .dependency:
            let target = Replay.pick(from: tasks, using: &generator)
            return try PatchInput(node: .task(task), add: [PropertyName.dependsOn: [.local(.task(target))]])
        case .delete:
            let graph = session.live.graph
            let state = graph.slot(for: .task(task)).flatMap { slot in graph.node(at: slot, as: TaskNode.self) }
            return try PatchInput(node: .task(task), delete: state?.fields.isDeleted != true)
        case .column:
            let column = Replay.pick(from: Replay.columns, using: &generator)
            return try PatchInput(node: .task(task), set: [PropertyName.column: .ref(.local(.column(slug: column)))])
        }
    }

    // MARK: - Tests

    @Test("A second nextTask with no change between the calls does no walk")
    func secondNextTaskDoesNoWalk() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = fixture.session
        let dependent = AddUpdateTaskTests.addTask(with: AddUpdateTaskTests.dependsOn(fixture.task))
        try await ChangeBuilderTests.run(AddUpdateTaskTests.mutation(of: dependent), in: &session)
        let complete = TaskOperationTests.taskField(MutationName.completeTask, of: fixture.task)
        try await ChangeBuilderTests.run(AddUpdateTaskTests.mutation(of: complete), in: &session)
        try await ChangeBuilderTests.run(CrossRepoCycleReadinessTests.nextTaskQuery, in: &session)
        let walks = session.live.readiness.walkCount
        try await ChangeBuilderTests.run(CrossRepoCycleReadinessTests.nextTaskQuery, in: &session)
        #expect(walks > .zero)
        #expect(session.live.readiness.walkCount == walks)
    }

    @Test("A read with no change walks nothing, and a change of one task walks again only for its dependents")
    func changeWalksOnlyForDependents() throws {
        var board = try Self.twoChains()
        let cache = ReadinessCache()
        Self.readyTasks(of: board.graph, cachedIn: cache)
        #expect(cache.walkCount == Self.chainCount)
        Self.readyTasks(of: board.graph, cachedIn: cache)
        #expect(cache.walkCount == Self.chainCount)
        try board.addTask(
            withULID: ReadinessFixture.third,
            titled: Self.changedTitle,
            inColumn: ReadinessFixture.done
        )
        Self.readyTasks(of: board.graph, cachedIn: cache)
        #expect(cache.walkCount == Self.chainCount + Self.dependentCount)
    }

    @Test("After random writes, deletes, dependency changes, and watcher applies, the cache equals a full walk")
    func cachedReadinessEqualsFullWalk() async throws {
        typealias Replay = Design.ReplayPropertyTests
        _ = try await Replay.runSequences { start, generator in
            var session = start
            Self.expectCachedReadinessEqualsFullWalk(of: session)
            for step in 0..<Self.stepCount {
                if Bool.random(using: &generator) {
                    let call = Replay.pick(from: Replay.RandomCall.allCases, using: &generator)
                    let field = call.field(choosingFrom: Replay.tasks(of: session), using: &generator)
                    _ = try await ColumnActorTests.result(of: AddUpdateTaskTests.mutation(of: field), in: &session)
                } else {
                    let edit = try Self.randomRawEdit(in: session, using: &generator)
                    try await Self.applyRawEdit(edit, to: &session, atStep: step)
                }
                Self.expectCachedReadinessEqualsFullWalk(of: session)
            }
        }
    }

    @Test("A cycle in one board that a watcher apply closes blocks each task in it, also a task whose dependency is done")
    func cycleFromWatcherApplyBlocksEachTask() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = fixture.session
        let addDependent = AddUpdateTaskTests.addTask(with: AddUpdateTaskTests.dependsOn(fixture.task))
        try await ChangeBuilderTests.run(AddUpdateTaskTests.mutation(of: addDependent), in: &session)
        let complete = TaskOperationTests.taskField(MutationName.completeTask, of: fixture.task)
        try await ChangeBuilderTests.run(AddUpdateTaskTests.mutation(of: complete), in: &session)
        let tasks = Design.ReplayPropertyTests.tasks(of: session)
        let dependent = try #require(tasks.first { task in task != fixture.task })
        let graph = session.live.graph
        let doneSlot = try #require(graph.slot(for: .task(fixture.task)))
        let dependentSlot = try #require(graph.slot(for: .task(dependent)))
        #expect(Self.cachedReadiness(of: session).isReady(taskAt: dependentSlot))
        let edge = try PatchInput(node: .task(fixture.task), add: [PropertyName.dependsOn: [.local(.task(dependent))]])
        try await Self.applyRawEdit(edge, to: &session, atStep: .zero)
        let readiness = Self.cachedReadiness(of: session)
        #expect(readiness.blockers(ofTaskAt: dependentSlot) == [.slot(doneSlot)])
        #expect(readiness.blockers(ofTaskAt: doneSlot) == [.slot(dependentSlot)])
        Self.expectCachedReadinessEqualsFullWalk(of: session)
    }
}
