import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests `Board.nextTask` (plan.md §6): from the tasks that are not done, are ready, and match the filter, the first
/// task in column order and then in ordinal order, or `null`.
///
/// These are the behavior tests of the Rust file `swissarmyhammer-kanban/src/task/next.rs`, written again as GraphQL
/// documents. The Rust archive maps to a delete (plan.md §12, item 21). The Rust `$project` filters now give
/// `INVALID_FILTER` (plan.md §6.3).
@Suite("Next task")
struct NextTaskTests {
    /// The ULID text of the first task. The ULIDs of the fixture are in this order: first, second, third, fourth.
    static let first = ReadinessFixture.first

    /// The ULID text of the second task.
    static let second = ReadinessFixture.second

    /// The ULID text of the third task.
    static let third = ReadinessFixture.third

    /// The slug of the test actor.
    static let alice = "alice"

    /// The slug of the test tag.
    static let bug = "bug"

    /// The Rust `next task` project filters, each of which now gives `INVALID_FILTER`.
    static let projectFilters = ["$myproj", "$other", "$task-card-field-polish"]

    /// The slug of a column that a test adds with the same order as the first column. It sorts before
    /// ``ReadinessFixture/todo`` by slug.
    static let alpha = "alpha"

    /// The slug of a tombstoned column that a test adds.
    static let parked = "parked"

    /// The order of ``parked``: after the column ``ReadinessFixture/doing``, so that a live column with this order
    /// would sort after it.
    static let parkedOrder = 2

    /// Each filter of a board where the first task depends on the second task, with the task that is next. The first
    /// task is blocked and the second task is ready. A `^` atom matches the task and each task that depends on it.
    static let readinessFilterCases: [(filter: String, next: String?)] = [
        ("#READY", second),
        ("#BLOCKED", nil),
        (QueryFixture.sigilRef(of: first), nil),
        (QueryFixture.sigilRef(of: second), second),
    ]

    /// The columns of three tasks (the first, the second, and the third task), each with the task that is next.
    /// This is the Rust test that moves the tasks to `done` one at a time.
    static let columnCases: [(columns: [String], next: String?)] = [
        ([ReadinessFixture.todo, ReadinessFixture.doing, ReadinessFixture.done], first),
        ([ReadinessFixture.done, ReadinessFixture.doing, ReadinessFixture.done], second),
        ([ReadinessFixture.done, ReadinessFixture.done, ReadinessFixture.done], nil),
    ]

    @Test("A board with no task has no next task")
    func emptyBoard() async throws {
        #expect(try await TaskQueryFixture().nextTaskULID() == nil)
    }

    @Test("The next task is the first task of the first column")
    func returnsFirst() async throws {
        var fixture = TaskQueryFixture()
        try fixture.board.addTask(withULID: Self.first)
        try fixture.board.addTask(withULID: Self.second)
        #expect(try await fixture.nextTaskULID() == Self.first)
    }

    @Test("A blocked task is not next")
    func skipsBlocked() async throws {
        var fixture = TaskQueryFixture()
        try fixture.board.addTask(withULID: Self.first, dependingOn: [Self.second])
        try fixture.board.addTask(withULID: Self.second)
        #expect(try await fixture.nextTaskULID() == Self.second)
    }

    @Test("A filter by tag skips the tasks without the tag, and a filter that matches nothing gives null")
    func filterByTag() async throws {
        var fixture = TaskQueryFixture()
        fixture.board.addTag(withSlug: Self.bug)
        try fixture.board.addTask(withULID: Self.first)
        try fixture.board.addTask(withULID: Self.second, fields: ReadinessFixture.fields(body: "#\(Self.bug)"))
        #expect(try await fixture.nextTaskULID() == Self.first)
        #expect(try await fixture.nextTaskULID(withFilter: "#bug") == Self.second)
        #expect(try await fixture.nextTaskULID(withFilter: "#feature") == nil)
    }

    @Test("A Rust project filter gives INVALID_FILTER", arguments: projectFilters)
    func projectFilter(filter: String) async throws {
        var fixture = TaskQueryFixture()
        try fixture.board.addTask(withULID: Self.first)
        let error = try await fixture.kanbanError(of: #"{ board { nextTask(filter: "\#(filter)") { id } } }"#)
        #expect(error.code == "INVALID_FILTER")
    }

    @Test("A done task is not next")
    func ignoresDone() async throws {
        var fixture = TaskQueryFixture()
        try fixture.board.addTask(withULID: Self.first, inColumn: ReadinessFixture.done)
        try fixture.board.addTask(withULID: Self.second)
        #expect(try await fixture.nextTaskULID() == Self.second)
    }

    @Test("The next task comes from all the columns that are not done", arguments: columnCases)
    func searchesAllOpenColumns(columns: [String], next: String?) async throws {
        var fixture = TaskQueryFixture()
        for (task, column) in zip([Self.first, Self.second, Self.third], columns) {
            try fixture.board.addTask(withULID: task, inColumn: column)
        }
        #expect(try await fixture.nextTaskULID() == next)
    }

    @Test("A task of an earlier column comes before a task of a later column")
    func prefersEarlierColumn() async throws {
        var fixture = TaskQueryFixture()
        try fixture.board.addTask(withULID: Self.first, inColumn: ReadinessFixture.doing)
        try fixture.board.addTask(withULID: Self.second)
        #expect(try await fixture.nextTaskULID() == Self.second)
    }

    @Test("In one column, the task with the lower ordinal is next")
    func prefersLowerOrdinal() async throws {
        var fixture = TaskQueryFixture()
        try fixture.board.addTask(withULID: Self.first)
        let early = TaskNode(
            id: try DependencyMarkersTests.ulid(of: Self.second),
            fields: ReadinessFixture.fields(),
            column: QueryFixture.edge(to: .column(slug: ReadinessFixture.todo)),
            ordinal: Ordinal(before: .first)
        )
        fixture.board.graph.update(with: .task(early))
        #expect(try await fixture.nextTaskULID() == Self.second)
    }

    @Test("A deleted task is not next")
    func skipsDeleted() async throws {
        var fixture = TaskQueryFixture()
        try fixture.board.addTask(withULID: Self.first, fields: ReadinessFixture.fields(isDeleted: true))
        try fixture.board.addTask(withULID: Self.second)
        #expect(try await fixture.nextTaskULID() == Self.second)
    }

    /// Each filter that names `#DELETED`, with the next task when the first task is deleted and the second task is
    /// assigned to ``alice``.
    static let deletedFilterCases: [(filter: String, next: String?)] = [
        ("#DELETED", nil),
        ("#DELETED || @alice", second),
    ]

    @Test("A filter that names #DELETED gives no deleted task as next", arguments: deletedFilterCases)
    func deletedFilterGivesNoTombstone(filter: String, next: String?) async throws {
        var fixture = TaskQueryFixture()
        fixture.board.addActor(withSlug: Self.alice, named: "Alice")
        try fixture.board.addTask(withULID: Self.first, fields: ReadinessFixture.fields(isDeleted: true))
        try fixture.board.addTask(withULID: Self.second, assignedTo: [Self.alice])
        #expect(try await fixture.nextTaskULID(withFilter: filter) == next)
    }

    @Test("A board where each task is deleted has no next task")
    func allDeleted() async throws {
        var fixture = TaskQueryFixture()
        for task in [Self.first, Self.second] {
            try fixture.board.addTask(withULID: task, fields: ReadinessFixture.fields(isDeleted: true))
        }
        #expect(try await fixture.nextTaskULID() == nil)
    }

    @Test("A filter by assignee gives the task of the actor")
    func filterByAssignee() async throws {
        var fixture = TaskQueryFixture()
        fixture.board.addActor(withSlug: Self.alice, named: "Alice")
        try fixture.board.addTask(withULID: Self.first)
        try fixture.board.addTask(withULID: Self.second, assignedTo: [Self.alice])
        #expect(try await fixture.nextTaskULID(withFilter: "@alice") == Self.second)
    }

    // MARK: - Dependencies

    @Test("A task whose only dependency is a tombstone is next")
    func tombstonedDependencyDoesNotBlock() async throws {
        var fixture = TaskQueryFixture()
        try fixture.board.addTask(withULID: Self.second, fields: ReadinessFixture.fields(isDeleted: true))
        try fixture.board.addTask(withULID: Self.first, dependingOn: [Self.second])
        #expect(try await fixture.nextTaskULID() == Self.first)
    }

    @Test("No task of a dependency cycle in one board is next")
    func cycleGivesNoNextTask() async throws {
        var fixture = TaskQueryFixture()
        try fixture.board.addTask(withULID: Self.first, dependingOn: [Self.second])
        try fixture.board.addTask(withULID: Self.second, dependingOn: [Self.first])
        #expect(try await fixture.nextTaskULID() == nil)
    }

    @Test("A task that depends on a task of a board that is not loaded is not next")
    func dependencyOnBoardThatIsNotLoadedBlocks() async throws {
        var fixture = TaskQueryFixture()
        let uri = try DependencyMarkersTests.uri(ofTask: Self.third, inBoard: DependencyMarkersTests.otherBoardKey)
        try fixture.board.addTask(withULID: Self.first, dependingOnRemote: [uri])
        try fixture.board.addTask(withULID: Self.second)
        #expect(try await fixture.nextTaskULID() == Self.second)
    }

    @Test("A board where each task is blocked has no next task")
    func allBlocked() async throws {
        var fixture = TaskQueryFixture()
        try fixture.board.addTask(withULID: Self.first, dependingOn: [ReadinessFixture.ghost])
        try fixture.board.addTask(withULID: Self.second, dependingOn: [Self.first])
        #expect(try await fixture.nextTaskULID() == nil)
    }

    @Test("A task with a conflict block can be next")
    func conflictTaskCanBeNext() async throws {
        var fixture = TaskQueryFixture()
        try fixture.board.addTask(withULID: Self.first, fields: ReadinessFixture.fields(hasConflict: true))
        try fixture.board.addTask(withULID: Self.second)
        #expect(try await fixture.nextTaskULID() == Self.first)
    }

    // MARK: - Order

    @Test("Two tasks of one column with the same ordinal sort by ULID, not by the order that they were added")
    func sameOrdinalSortsByULID() async throws {
        var fixture = TaskQueryFixture()
        try fixture.board.addTask(withULID: Self.second)
        try fixture.board.addTask(withULID: Self.first)
        #expect(try await fixture.nextTaskULID() == Self.first)
    }

    @Test("Two columns with the same order sort by slug")
    func sameColumnOrderSortsBySlug() async throws {
        var fixture = TaskQueryFixture()
        fixture.board.addColumn(withSlug: Self.alpha, order: .zero)
        try fixture.board.addTask(withULID: Self.first)
        try fixture.board.addTask(withULID: Self.second, inColumn: Self.alpha)
        #expect(try await fixture.nextTaskULID() == Self.second)
    }

    @Test("A task in a tombstoned column shows in the first column, so it comes before a task of a later column")
    func taskOfTombstonedColumnIsInFirstColumn() async throws {
        var fixture = TaskQueryFixture()
        fixture.board.addColumn(withSlug: Self.parked, order: Self.parkedOrder, isDeleted: true)
        try fixture.board.addTask(withULID: Self.first, inColumn: ReadinessFixture.doing)
        try fixture.board.addTask(withULID: Self.second, inColumn: Self.parked)
        #expect(try await fixture.nextTaskULID() == Self.second)
    }

    @Test("A board with one column has no next task, because that column is the terminal column")
    func oneColumnBoardHasNoNextTask() async throws {
        var fixture = TaskQueryFixture()
        for (order, slug) in ReadinessFixture.defaultColumns.enumerated().dropFirst() {
            fixture.board.addColumn(withSlug: slug, order: order, isDeleted: true)
        }
        try fixture.board.addTask(withULID: Self.first)
        #expect(try await fixture.nextTaskULID() == nil)
    }

    // MARK: - Readiness filters

    @Test(
        "The filters #READY, #BLOCKED, and ^ give the next task of the tasks that they match",
        arguments: readinessFilterCases
    )
    func readinessFilter(filter: String, next: String?) async throws {
        var fixture = TaskQueryFixture()
        try fixture.board.addTask(withULID: Self.first, dependingOn: [Self.second])
        try fixture.board.addTask(withULID: Self.second)
        #expect(try await fixture.nextTaskULID(withFilter: filter) == next)
    }
}
