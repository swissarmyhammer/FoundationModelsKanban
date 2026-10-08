import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the virtual tags of a task: `READY`, `BLOCKED`, `BLOCKING`, `CONFLICT`, `DELETED`, and `DONE` (plan.md §5.5,
/// §6).
/// The tests in the "Rust" sections are the port of the tests of the Rust `virtual_tags.rs`.
@Suite("Virtual tags")
struct VirtualTagsTests {
    /// Gives the virtual tags of one task of a board.
    ///
    /// - Parameters:
    ///   - text: The ULID text of the task.
    ///   - board: The board that holds the task.
    /// - Returns: The virtual tags of the task.
    /// - Throws: An error when the graph does not have the task.
    static func tags(ofTask text: String, on board: ReadinessFixture) throws -> [VirtualTag] {
        board.readiness.virtualTags(ofTaskAt: try board.slot(ofTask: text))
    }

    // MARK: - Rust: registry

    @Test("The virtual tags are READY, BLOCKED, BLOCKING, CONFLICT, DELETED, and DONE, in this order")
    func tagsInRegistryOrder() {
        let names = ["READY", "BLOCKED", "BLOCKING", "CONFLICT", "DELETED", "DONE"]
        #expect(VirtualTag.allCases.map(\.rawValue) == names)
    }

    @Test("A virtual tag slug is upper case, and the match is case-sensitive (Rust test_is_virtual_slug)")
    func slugIsCaseSensitive() {
        #expect(VirtualTag(rawValue: "READY") == .ready)
        #expect(VirtualTag(rawValue: "BLOCKED") == .blocked)
        #expect(VirtualTag(rawValue: "ready") == nil)
        #expect(VirtualTag(rawValue: "NONEXISTENT") == nil)
    }

    // MARK: - Rust: READY

    @Test("A task with no dependencies is READY (Rust ready_no_deps)")
    func readyNoDependencies() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first)
        #expect(try Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.ready))
    }

    @Test("A task whose dependencies are all done is READY (Rust ready_all_deps_complete)")
    func readyAllDependenciesDone() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.second, inColumn: ReadinessFixture.done)
        try board.addTask(withULID: ReadinessFixture.first, dependingOn: [ReadinessFixture.second])
        #expect(try Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.ready))
    }

    @Test("A task with a dependency that is not done is not READY (Rust ready_incomplete_dep)")
    func notReadyIncompleteDependency() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.second, inColumn: ReadinessFixture.doing)
        try board.addTask(withULID: ReadinessFixture.first, dependingOn: [ReadinessFixture.second])
        #expect(try !Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.ready))
    }

    @Test("A done task is not READY (Rust ready_completed_task)")
    func doneTaskIsNotReady() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.done)
        #expect(try !Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.ready))
    }

    @Test("A task with an unknown dependency is not READY (Rust ready_missing_dep_is_not_ready)")
    func unknownDependencyIsNotReady() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, dependingOn: [ReadinessFixture.ghost])
        #expect(try !Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.ready))
    }

    // MARK: - Rust: BLOCKED

    @Test("A task with an unknown dependency is BLOCKED (Rust blocked_missing_dep_is_blocked)")
    func unknownDependencyIsBlocked() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, dependingOn: [ReadinessFixture.ghost])
        #expect(try Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.blocked))
    }

    @Test("A task with a dependency that is not done is BLOCKED (Rust blocked_incomplete_dep)")
    func incompleteDependencyIsBlocked() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.second)
        try board.addTask(withULID: ReadinessFixture.first, dependingOn: [ReadinessFixture.second])
        #expect(try Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.blocked))
    }

    @Test("A task with no dependencies is not BLOCKED (Rust blocked_no_deps)")
    func noDependenciesIsNotBlocked() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first)
        #expect(try !Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.blocked))
    }

    @Test("A task whose dependencies are all done is not BLOCKED (Rust blocked_all_deps_complete)")
    func allDependenciesDoneIsNotBlocked() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.second, inColumn: ReadinessFixture.done)
        try board.addTask(withULID: ReadinessFixture.first, dependingOn: [ReadinessFixture.second])
        #expect(try !Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.blocked))
    }

    // MARK: - Rust: BLOCKING

    @Test("A task that another task depends on is BLOCKING (Rust blocking_has_dependents)")
    func dependedOnIsBlocking() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.doing)
        try board.addTask(withULID: ReadinessFixture.second, dependingOn: [ReadinessFixture.first])
        #expect(try Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.blocking))
    }

    @Test("A done task that another task depends on is not BLOCKING (Rust blocking_completed)")
    func doneTaskIsNotBlocking() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.done)
        try board.addTask(withULID: ReadinessFixture.second, dependingOn: [ReadinessFixture.first])
        #expect(try !Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.blocking))
    }

    @Test("A task that no task depends on is not BLOCKING (Rust blocking_no_dependents)")
    func noDependentsIsNotBlocking() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.doing)
        try board.addTask(withULID: ReadinessFixture.second)
        #expect(try !Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.blocking))
    }

    // MARK: - CONFLICT

    @Test("A task with a conflict block has CONFLICT")
    func conflictBlockGivesConflict() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, fields: ReadinessFixture.fields(hasConflict: true))
        #expect(try Self.tags(ofTask: ReadinessFixture.first, on: board) == [.ready, .conflict])
    }

    @Test("A task with no conflict block does not have CONFLICT")
    func noConflictBlockGivesNoConflict() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first)
        #expect(try !Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.conflict))
    }

    // MARK: - DONE

    @Test("A live task in the terminal column has DONE, and not READY or BLOCKING")
    func doneTaskHasDone() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.done)
        try board.addTask(withULID: ReadinessFixture.second, dependingOn: [ReadinessFixture.first])
        #expect(try Self.tags(ofTask: ReadinessFixture.first, on: board) == [.done])
    }

    @Test(
        "A task that is not in the terminal column does not have DONE",
        arguments: ReadinessFixture.defaultColumns.dropLast()
    )
    func openTaskHasNoDone(column: String) throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, inColumn: column)
        #expect(try !Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.done))
    }

    @Test("A tombstone in the terminal column has DELETED, and not DONE")
    func doneTombstoneHasNoDone() throws {
        var board = ReadinessFixture()
        let fields = ReadinessFixture.fields(isDeleted: true)
        try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.done, fields: fields)
        #expect(try Self.tags(ofTask: ReadinessFixture.first, on: board) == [.deleted])
    }

    @Test("A done task with a dependency that is not done keeps BLOCKED, as in Rust, and has DONE")
    func doneTaskWithOpenDependencyIsBlocked() throws {
        var board = ReadinessFixture()
        try board.addTask(
            withULID: ReadinessFixture.first,
            inColumn: ReadinessFixture.done,
            dependingOn: [ReadinessFixture.ghost]
        )
        #expect(try Self.tags(ofTask: ReadinessFixture.first, on: board) == [.blocked, .done])
    }

    @Test("A node that is not a task has no virtual tags")
    func otherNodeHasNoTags() throws {
        let board = ReadinessFixture()
        let column = try #require(board.graph.slot(for: .column(slug: ReadinessFixture.todo)))
        #expect(board.readiness.virtualTags(ofTaskAt: column).isEmpty)
    }

    // MARK: - Order

    @Test("The virtual tags of a task are in registry order")
    func tagsOfTaskInOrder() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.second, dependingOn: [ReadinessFixture.first])
        try board.addTask(
            withULID: ReadinessFixture.first,
            dependingOn: [ReadinessFixture.ghost],
            fields: ReadinessFixture.fields(hasConflict: true)
        )
        #expect(try Self.tags(ofTask: ReadinessFixture.first, on: board) == [.blocked, .blocking, .conflict])
    }
}
