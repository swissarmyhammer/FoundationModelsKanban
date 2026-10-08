import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests how the projection shows a merged state that breaks a graph rule, with no error (plan.md §3.3 rule 7, §5.3
/// step 5): a task in a tombstoned or missing column, a comment on a tombstoned task, two columns with the same
/// `order`, and a tombstoned actor as a comment author or a `Change` actor.
@Suite("Broken merge display")
struct BrokenMergeDisplayTests {
    /// The slug of a column that the tests delete.
    static let archive = "archive"

    /// The slug of a column that sorts before `doing` by slug.
    static let alpha = "alpha"

    /// The order of the `doing` column of the default columns.
    static let doingOrder = 1

    /// The ULID text of a tombstoned comment.
    static let deletedComment = "01KT71J5F6AT2W4Y6Z8A0B2C4D"

    /// The ULID text of a comment on a different task.
    static let otherTaskComment = "01KT72K6G7BV3X5Z7A9B1C3D5E"

    // MARK: - Column of a task

    @Test("A task in a tombstoned column shows in the first column")
    func tombstonedColumnShowsFirst() throws {
        var board = ReadinessFixture()
        board.addColumn(withSlug: Self.archive, order: Int.max, isDeleted: true)
        let slot = try board.addTask(withULID: ReadinessFixture.first, inColumn: Self.archive)
        #expect(board.readiness.column(ofTaskAt: slot) == (try board.slot(ofColumn: ReadinessFixture.todo)))
    }

    @Test("A task with no column shows in the first column")
    func noColumnShowsFirst() throws {
        var board = ReadinessFixture()
        let slot = try board.addTask(withULID: ReadinessFixture.first, inColumn: nil)
        #expect(board.readiness.column(ofTaskAt: slot) == (try board.slot(ofColumn: ReadinessFixture.todo)))
    }

    @Test("A task whose column the graph does not have shows in the first column")
    func missingColumnShowsFirst() throws {
        var board = ReadinessFixture()
        let slot = try board.addTask(withULID: ReadinessFixture.first, inColumn: Self.archive)
        #expect(board.readiness.column(ofTaskAt: slot) == (try board.slot(ofColumn: ReadinessFixture.todo)))
    }

    @Test("A task in a live column shows in that column")
    func liveColumnShowsItself() throws {
        var board = ReadinessFixture()
        let slot = try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.doing)
        #expect(board.readiness.column(ofTaskAt: slot) == (try board.slot(ofColumn: ReadinessFixture.doing)))
    }

    @Test("A task in a tombstoned column is not done when the first column is not the terminal column")
    func tombstonedColumnIsNotDone() throws {
        var board = ReadinessFixture()
        board.addColumn(withSlug: Self.archive, order: .zero, isDeleted: true)
        let slot = try board.addTask(withULID: ReadinessFixture.first, inColumn: Self.archive)
        #expect(!board.readiness.isDone(taskAt: slot))
    }

    @Test("A slot that holds no task has no column")
    func notATaskHasNoColumn() throws {
        let board = ReadinessFixture()
        #expect(board.readiness.column(ofTaskAt: try board.slot(ofColumn: ReadinessFixture.todo)) == nil)
    }

    // MARK: - A board with one column

    @Test("On a board with one column, a task with no column shows in it and is done")
    func oneColumnBoardTaskWithNoColumnIsDone() throws {
        var board = ReadinessFixture()
        board.graph = Graph()
        board.addColumn(withSlug: ReadinessFixture.todo, order: .zero)
        let slot = try board.addTask(withULID: ReadinessFixture.first, inColumn: nil)
        let readiness = board.readiness
        #expect(readiness.column(ofTaskAt: slot) == (try board.slot(ofColumn: ReadinessFixture.todo)))
        #expect(readiness.isDone(taskAt: slot))
        #expect(readiness.virtualTags(ofTaskAt: slot) == [.done])
        #expect(readiness.summary == BoardSummary(total: 1, ready: 1, done: 1))
    }

    @Test("On a board with one column, a task in a tombstoned column is done")
    func oneColumnBoardTombstonedColumnIsDone() throws {
        var board = ReadinessFixture()
        board.graph = Graph()
        board.addColumn(withSlug: ReadinessFixture.todo, order: .zero)
        board.addColumn(withSlug: Self.archive, order: Int.max, isDeleted: true)
        let slot = try board.addTask(withULID: ReadinessFixture.first, inColumn: Self.archive)
        #expect(board.readiness.isDone(taskAt: slot))
    }

    @Test("A board with no live column shows a task in no column")
    func noLiveColumnShowsNoColumn() throws {
        var board = ReadinessFixture()
        board.graph = Graph()
        let slot = try board.addTask(withULID: ReadinessFixture.first, inColumn: nil)
        #expect(board.readiness.column(ofTaskAt: slot) == nil)
        #expect(!board.readiness.isDone(taskAt: slot))
    }

    // MARK: - Column order

    @Test("Two columns with the same order sort by slug")
    func sameOrderSortsBySlug() throws {
        var board = ReadinessFixture()
        board.addColumn(withSlug: Self.alpha, order: Self.doingOrder)
        let expected = try [ReadinessFixture.todo, Self.alpha, ReadinessFixture.doing, "review", ReadinessFixture.done]
            .map(board.slot(ofColumn:))
        #expect(ColumnOrder(of: board.graph).slots == expected)
    }

    @Test("Of two columns with the minimum order, the first slug is the first column")
    func firstColumnTieSortsBySlug() throws {
        var board = ReadinessFixture()
        board.addColumn(withSlug: Self.alpha, order: .zero)
        let slot = try board.addTask(withULID: ReadinessFixture.first, inColumn: nil)
        #expect(board.readiness.column(ofTaskAt: slot) == (try board.slot(ofColumn: Self.alpha)))
    }

    @Test("A tombstoned column is not in the column order")
    func tombstonedColumnIsNotInOrder() throws {
        var board = ReadinessFixture()
        board.addColumn(withSlug: Self.archive, order: .zero, isDeleted: true)
        let archive = try board.slot(ofColumn: Self.archive)
        #expect(!ColumnOrder(of: board.graph).slots.contains(archive))
    }

    // MARK: - Comments

    @Test("The comments of a task are its live comments, in ULID order")
    func commentsOfLiveTask() throws {
        var board = ReadinessFixture()
        let task = try board.addTask(withULID: ReadinessFixture.first)
        let second = try board.addComment(withULID: ReadinessFixture.secondComment, onTask: ReadinessFixture.first)
        let first = try board.addComment(withULID: ReadinessFixture.firstComment, onTask: ReadinessFixture.first)
        try board.addComment(withULID: Self.deletedComment, onTask: ReadinessFixture.first, isDeleted: true)
        try board.addTask(withULID: ReadinessFixture.second)
        try board.addComment(withULID: Self.otherTaskComment, onTask: ReadinessFixture.second)
        #expect(board.graph.comments(ofTaskAt: task) == [first, second])
    }

    @Test("A comment on a tombstoned task is hidden")
    func commentOnTombstonedTaskIsHidden() throws {
        var board = ReadinessFixture()
        let task = try board.addTask(withULID: ReadinessFixture.first, fields: ReadinessFixture.fields(isDeleted: true))
        try board.addComment(withULID: ReadinessFixture.firstComment, onTask: ReadinessFixture.first)
        #expect(board.graph.comments(ofTaskAt: task).isEmpty)
    }

    // MARK: - Tombstoned actors

    @Test("A comment author that is a tombstoned actor resolves to the tombstone")
    func tombstonedAuthorResolvesToTombstone() throws {
        var board = ReadinessFixture()
        board.addActor(withSlug: ReadinessFixture.author, isDeleted: true)
        try board.addTask(withULID: ReadinessFixture.first)
        let comment = try board.addComment(withULID: ReadinessFixture.firstComment, onTask: ReadinessFixture.first)
        let author = try #require(board.graph.author(ofCommentAt: comment))
        #expect(author.slug == ReadinessFixture.author)
        #expect(author.fields.isDeleted)
    }

    @Test("A live comment author resolves to the actor")
    func liveAuthorResolves() throws {
        var board = ReadinessFixture()
        board.addActor(withSlug: ReadinessFixture.author)
        try board.addTask(withULID: ReadinessFixture.first)
        let comment = try board.addComment(withULID: ReadinessFixture.firstComment, onTask: ReadinessFixture.first)
        let author = try #require(board.graph.author(ofCommentAt: comment))
        #expect(!author.fields.isDeleted)
    }

    @Test("A comment author that the graph does not have resolves to nothing")
    func missingAuthorResolvesToNothing() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first)
        let comment = try board.addComment(withULID: ReadinessFixture.firstComment, onTask: ReadinessFixture.first)
        #expect(board.graph.author(ofCommentAt: comment) == nil)
    }

    @Test("A Change actor that is a tombstoned actor resolves to the tombstone")
    func tombstonedChangeActorResolvesToTombstone() throws {
        var board = ReadinessFixture()
        board.addActor(withSlug: ReadinessFixture.author, isDeleted: true)
        let actor = try #require(board.graph.actor(for: .actor(slug: ReadinessFixture.author)))
        #expect(actor.fields.isDeleted)
    }

    @Test("A Change actor that the graph does not have, or a ref that is not an actor, resolves to nothing")
    func missingChangeActorResolvesToNothing() {
        let board = ReadinessFixture()
        #expect(board.graph.actor(for: .actor(slug: ReadinessFixture.author)) == nil)
        #expect(board.graph.actor(for: .column(slug: ReadinessFixture.todo)) == nil)
    }
}
