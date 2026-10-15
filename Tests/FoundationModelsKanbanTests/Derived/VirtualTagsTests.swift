import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the virtual tags of a task: `READY`, `BLOCKED`, `CONFLICT`, `DELETED`, and `DONE` (plan.md §5.5, §6).
/// ``PriorityTagsTests`` tests the priority tags `HIGH`, `MEDIUM`, and `LOW`.
/// The tests in the "Rust" sections are the port of the tests of the Rust `virtual_tags.rs`. The Rust virtual tag
/// `BLOCKING` is not a virtual tag here (divergence.md Q1).
@Suite("Virtual tags")
struct VirtualTagsTests {
    /// The name of the Rust virtual tag `BLOCKING`, which is not a virtual tag here.
    static let blockingName = "BLOCKING"

    /// The color of the Rust virtual tag `READY`.
    static let rustReadyColor = "0e8a16"

    /// The color of the Rust virtual tag `BLOCKED`.
    static let rustBlockedColor = "e36209"

    /// The number of hex digits of a color.
    static let hexColorLength = 6

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

    @Test(
        "The virtual tags are READY, BLOCKED, CONFLICT, DELETED, DONE, HIGH, MEDIUM, and LOW, in this order"
    )
    func tagsInRegistryOrder() {
        let names = ["READY", "BLOCKED", "CONFLICT", "DELETED", "DONE", "HIGH", "MEDIUM", "LOW"]
        #expect(VirtualTag.allCases.map(\.rawValue) == names)
    }

    @Test("A virtual tag slug is upper case, and the match is case-sensitive (Rust test_is_virtual_slug)")
    func slugIsCaseSensitive() {
        #expect(VirtualTag(rawValue: "READY") == .ready)
        #expect(VirtualTag(rawValue: "BLOCKED") == .blocked)
        #expect(VirtualTag(rawValue: "ready") == nil)
        #expect(VirtualTag(rawValue: "NONEXISTENT") == nil)
    }

    // MARK: - Color and description

    @Test("READY and BLOCKED have the Rust colors (Rust ReadyStrategy and BlockedStrategy)")
    func readyAndBlockedHaveRustColors() {
        #expect(VirtualTag.ready.color == Self.rustReadyColor)
        #expect(VirtualTag.blocked.color == Self.rustBlockedColor)
    }

    @Test("Each virtual tag has its own color of 6 hex digits with no #")
    func eachTagHasDistinctHexColor() {
        let colors = VirtualTag.allCases.map(\.color)
        #expect(Set(colors).count == VirtualTag.allCases.count)
        for color in colors {
            #expect(color.count == Self.hexColorLength, "\(color)")
            let isHex = color.allSatisfy { character in character.isHexDigit }
            #expect(isHex, "\(color)")
        }
    }

    @Test("Each virtual tag has its own description of one sentence")
    func eachTagHasDistinctSentence() {
        let descriptions = VirtualTag.allCases.map(\.explanation)
        #expect(Set(descriptions).count == VirtualTag.allCases.count)
        for description in descriptions {
            #expect(description.hasSuffix("."), "\(description)")
            #expect(description.filter { character in character == "." }.count == 1, "\(description)")
        }
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

    // MARK: - No BLOCKING

    @Test("BLOCKING is not the name of a virtual tag, in any case")
    func blockingIsNotVirtualTag() {
        #expect(VirtualTag(named: Self.blockingName) == nil)
        #expect(VirtualTag(named: Self.blockingName.lowercased()) == nil)
    }

    @Test("A task that an open task depends on has no BLOCKING virtual tag")
    func dependedOnTaskHasNoBlockingTag() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.doing)
        try board.addTask(withULID: ReadinessFixture.second, dependingOn: [ReadinessFixture.first])
        let names = try Self.tags(ofTask: ReadinessFixture.first, on: board).map(\.rawValue)
        #expect(!names.contains(Self.blockingName))
    }

    // MARK: - CONFLICT

    @Test("A task with a conflict block has CONFLICT")
    func conflictBlockGivesConflict() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, fields: ReadinessFixture.fields(hasConflict: true))
        #expect(try Self.tags(ofTask: ReadinessFixture.first, on: board) == [.ready, .conflict, .high])
    }

    @Test("A task with no conflict block does not have CONFLICT")
    func noConflictBlockGivesNoConflict() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first)
        #expect(try !Self.tags(ofTask: ReadinessFixture.first, on: board).contains(.conflict))
    }

    // MARK: - DONE

    @Test("A live task in the terminal column that a task depends on has DONE, and not READY")
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
        #expect(try Self.tags(ofTask: ReadinessFixture.first, on: board) == [.blocked, .conflict, .high])
    }
}
