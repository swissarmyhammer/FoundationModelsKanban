import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests `Task.timeline` (divergence.md §23, TestudoApp KANBAN-13): the history of one task, newest first, with
/// paging. Each entry is a column move, a change of one stored field, or a change of one comment, with the time, the
/// actor, the transaction, and the undone state of its transaction.
///
/// Each engine test uses the fixture logs of ``KanbanGraphTests``: one task in the column `todo`. The fixture writes
/// the task in one transaction that sets its title and its column.
@Suite("Task.timeline", .watcherBudget)
struct TaskTimelineTests {
    /// The selection of each entry in most tests: the transaction, the kind, the actor, and each value of a kind.
    private static let entrySelection = """
        txn kind actor { id } from { id } to { id } field { name before after } comment { id } commentUpdate
        """

    /// The selection of each entry in the paging tests: the cursor and the kind.
    private static let pageSelection = "cursor kind"

    /// The page size of the tests that read the two newest entries.
    private static let pageSize = 2

    /// The number of tasks that the read test adds beside the fixture task.
    private static let otherTaskCount = 10

    /// The new body of the comment in the comment test.
    private static let changedCommentBody = "Looks better."

    // MARK: - Helpers

    /// Gives the transaction of the fixture task: the transaction of the first event of its log.
    ///
    /// - Parameters:
    ///   - task: The ULID of the fixture task.
    ///   - directory: The temporary repo directory.
    /// - Returns: The ULID text of the transaction.
    private static func fixtureTransaction(of task: ULID, in directory: TemporaryDirectory) throws -> String {
        let log = try EventLog(repositoryAt: directory.url).readLog(of: .task(task))
        return try #require(log.events.first).txn.ulidString
    }

    /// Runs one mutation field on an engine, and gives the transaction of the call.
    ///
    /// - Parameters:
    ///   - field: The mutation field, with its selection.
    ///   - graph: The engine.
    /// - Returns: The response JSON text, and the ULID text of the transaction in `extensions.txn`.
    private static func write(_ field: String, on graph: KanbanGraph) async throws -> (response: String, txn: String) {
        let response = try await CommentTests.run(field, on: graph)
        return (response, try ResponseTransactionTests.transaction(of: response))
    }

    /// Runs a query of the timeline of a task on an engine.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task.
    ///   - arguments: The arguments of the field, with their parentheses, or `""` for no arguments.
    ///   - selection: The selection of each entry.
    ///   - graph: The engine.
    /// - Returns: The response JSON text.
    private static func timeline(
        of task: ULID,
        with arguments: String = "",
        selecting selection: String = entrySelection,
        on graph: KanbanGraph
    ) async throws -> String {
        let field = "{ timeline\(arguments) { \(selection) } }"
        return try await CommentTests.respond(toQueryOf: task, selecting: field, on: graph)
    }

    /// Gives the response of a query of the timeline of a task.
    ///
    /// - Parameter entries: The JSON object text of each entry, in the order of the list.
    /// - Returns: The response JSON text.
    private static func timelineResponse(_ entries: [String]) -> String {
        #"{"data":{"board":{"task":{"timeline":[\#(entries.joined(separator: ","))]}}}}"#
    }

    /// Gives the JSON object that ``entrySelection`` gives for one entry of the session actor.
    ///
    /// - Parameters:
    ///   - txn: The ULID text of the transaction of the entry.
    ///   - kind: The kind of the entry.
    ///   - from: The JSON of `from`. The default is `null`.
    ///   - to: The JSON of `to`. The default is `null`.
    ///   - field: The JSON of `field`. The default is `null`.
    ///   - comment: The JSON of `comment`. The default is `null`.
    ///   - update: The kind of the comment change, or `nil` for `null`.
    /// - Returns: The JSON object text, with sorted keys.
    private static func entryJSON(
        txn: String,
        kind: TimelineKind,
        from: String = "null",
        to: String = "null",
        field: String = "null",
        comment: String = "null",
        update: UpdateKind? = nil
    ) -> String {
        let actor = AddUpdateTaskTests.idJSON(of: KanbanGraphTests.sessionActor.ref)
        let commentUpdate = update.map { kind in #""\#(kind.rawValue)""# } ?? "null"
        return #"{"actor":\#(actor),"comment":\#(comment),"commentUpdate":\#(commentUpdate),"field":\#(field),"#
            + #""from":\#(from),"kind":"\#(kind.rawValue)","to":\#(to),"txn":"\#(txn)"}"#
    }

    /// Gives the JSON object of a field change of a single value, with the selection `{ name before after }`.
    ///
    /// - Parameters:
    ///   - name: The name of the field.
    ///   - before: The text value before the change, or `nil` for `null`.
    ///   - after: The text value after the change.
    /// - Returns: The JSON object text, with sorted keys.
    private static func fieldJSON(named name: String, from before: String?, to after: String) -> String {
        let beforeJSON = before.map { text in #""\#(text)""# } ?? "null"
        return #"{"after":"\#(after)","before":\#(beforeJSON),"name":"\#(name)"}"#
    }

    /// Gives the JSON object of a column, with the selection `{ id }`.
    ///
    /// - Parameter slug: The slug of the column.
    /// - Returns: The JSON object text.
    private static func columnJSON(_ slug: String) -> String {
        AddUpdateTaskTests.idJSON(of: .column(slug: slug))
    }

    /// Gives the JSON object that ``pageSelection`` gives for one entry.
    ///
    /// - Parameters:
    ///   - txn: The ULID text of the transaction of the entry.
    ///   - index: The place of the entry among the entries of its transaction.
    ///   - kind: The kind of the entry.
    /// - Returns: The JSON object text, with sorted keys.
    private static func pageEntryJSON(txn: String, index: Int, kind: TimelineKind) throws -> String {
        let cursor = TimelineCursor(txn: try #require(ULID(ulidString: txn)), index: index).text
        return #"{"cursor":"\#(cursor)","kind":"\#(kind.rawValue)"}"#
    }

    /// Makes an `updateTask` field that gives the fixture task the title ``ChangeBuilderTests/newTitle``.
    ///
    /// - Parameter task: The ULID of the task.
    /// - Returns: The field.
    private static func rename(_ task: ULID) -> String {
        AddUpdateTaskTests.updateTask(task, with: #"title: "\#(ChangeBuilderTests.newTitle)""#)
    }

    /// Makes a new engine of the fixture repo, renames the fixture task, and then moves it to `done`, each in its own
    /// call.
    ///
    /// - Parameter directory: The temporary repo directory.
    /// - Returns: The engine, the ULID of the fixture task, and the transactions of the add, the rename, and the move.
    private static func renamedAndMoved(
        in directory: TemporaryDirectory
    ) async throws -> (graph: KanbanGraph, task: ULID, created: String, renamed: String, moved: String) {
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let created = try fixtureTransaction(of: fixture.task, in: directory)
        let renamed = try await write(rename(fixture.task), on: fixture.graph).txn
        let moved = try await write(TaskOperationTests.doneMove(of: fixture.task), on: fixture.graph).txn
        return (fixture.graph, fixture.task, created, renamed, moved)
    }

    // MARK: - Entries

    @Test("timeline gives the moves, the field changes, and the comments of a task, newest first, with each actor")
    func timelineGivesMovesFieldsAndComments() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try await Self.renamedAndMoved(in: directory)
        let added = try await Self.write(
            CommentTests.addComment(to: AddUpdateTaskTests.sigilRef(of: fixture.task)),
            on: fixture.graph
        )
        let comment = try #require(KanbanGraphTests.object(named: "addComment", in: added.response)["id"] as? String)
        let response = try await Self.timeline(of: fixture.task, on: fixture.graph)
        let parser = KanbanGraphTests.taskTitle
        let expected = Self.timelineResponse([
            Self.entryJSON(txn: added.txn, kind: .comment, comment: #"{"id":"\#(comment)"}"#, update: .created),
            Self.entryJSON(
                txn: fixture.moved,
                kind: .move,
                from: Self.columnJSON(TaskOperationTests.todoSlug),
                to: Self.columnJSON(TaskOperationTests.doneSlug)
            ),
            Self.entryJSON(
                txn: fixture.renamed,
                kind: .field,
                field: Self.fieldJSON(named: "title", from: parser, to: ChangeBuilderTests.newTitle)
            ),
            Self.entryJSON(txn: fixture.created, kind: .move, to: Self.columnJSON(TaskOperationTests.todoSlug)),
            Self.entryJSON(
                txn: fixture.created,
                kind: .field,
                field: Self.fieldJSON(named: "title", from: nil, to: parser)
            ),
        ])
        #expect(response == expected)
    }

    @Test("timeline gives the added and the removed members of a list field")
    func timelineGivesListMembers() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let input = TaskOperationTests.tagsInput(TagMutationTests.bug)
        for mutation in [MutationName.tagTask, MutationName.untagTask] {
            _ = try await Self.write(
                TaskOperationTests.taskField(mutation, of: fixture.task, with: input),
                on: fixture.graph
            )
        }
        let response = try await Self.timeline(
            of: fixture.task,
            with: "(first: \(Self.pageSize))",
            selecting: "kind field { name added removed }",
            on: fixture.graph
        )
        let tagList = #"["\#(ColumnActorTests.id(of: .tag(slug: TagMutationTests.bug)))"]"#
        let removed = #"{"added":[],"name":"\#(PropertyName.tags)","removed":\#(tagList)}"#
        let added = #"{"added":\#(tagList),"name":"\#(PropertyName.tags)","removed":[]}"#
        let expected = Self.timelineResponse([
            #"{"field":\#(removed),"kind":"FIELD"}"#,
            #"{"field":\#(added),"kind":"FIELD"}"#,
        ])
        #expect(response == expected)
    }

    @Test("timeline gives the add, the body change with its diff, and the delete of a comment")
    func timelineGivesCommentChanges() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let added = try await Self.write(
            CommentTests.addComment(to: AddUpdateTaskTests.sigilRef(of: fixture.task)),
            on: fixture.graph
        )
        let comment = try #require(KanbanGraphTests.object(named: "addComment", in: added.response)["id"] as? String)
        let body = #"body: "\#(Self.changedCommentBody)""#
        let update = CommentTests.nodeField(MutationName.updateComment, naming: comment, with: body)
        _ = try await Self.write(update, on: fixture.graph)
        _ = try await Self.write(CommentTests.nodeField(MutationName.deleteComment, naming: comment), on: fixture.graph)
        let response = try await Self.timeline(
            of: fixture.task,
            with: "(first: 3)",
            selecting: "kind commentUpdate field { name diff }",
            on: fixture.graph
        )
        let diffText = UnifiedDiff(from: CommentTests.body, to: Self.changedCommentBody).text
        // The JSON string of the diff, with its quotes. The diff holds a backslash line, so a plain escape of the
        // line ends is not sufficient.
        let diffData = try JSONSerialization.data(
            withJSONObject: diffText,
            options: [.fragmentsAllowed, .withoutEscapingSlashes]
        )
        let diff = String(decoding: diffData, as: UTF8.self)
        let expected = Self.timelineResponse([
            #"{"commentUpdate":"DELETED","field":null,"kind":"COMMENT"}"#,
            #"{"commentUpdate":"UPDATED","field":{"diff":\#(diff),"name":"body"},"kind":"COMMENT"}"#,
            #"{"commentUpdate":"CREATED","field":null,"kind":"COMMENT"}"#,
        ])
        #expect(response == expected)
    }

    @Test("timeline marks the entries of an undone transaction undone, and the undo itself not undone")
    func timelineMarksUndoneTransaction() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let renamed = try await Self.write(Self.rename(fixture.task), on: fixture.graph).txn
        let undo = UndoTests.reverseField(MutationName.undoChange, with: #"txn: "\#(renamed)""#)
        let undone = try await Self.write(undo, on: fixture.graph).txn
        let response = try await Self.timeline(
            of: fixture.task,
            with: "(first: \(Self.pageSize))",
            selecting: "txn undone field { name before after }",
            on: fixture.graph
        )
        let parser = KanbanGraphTests.taskTitle
        let newTitle = ChangeBuilderTests.newTitle
        let back = Self.fieldJSON(named: "title", from: newTitle, to: parser)
        let forward = Self.fieldJSON(named: "title", from: parser, to: newTitle)
        let expected = Self.timelineResponse([
            #"{"field":\#(back),"txn":"\#(undone)","undone":false}"#,
            #"{"field":\#(forward),"txn":"\#(renamed)","undone":true}"#,
        ])
        #expect(response == expected)
    }

    // MARK: - Paging

    @Test("timeline(first:) gives the newest entries, and after: with the cursor of the last gives the next page")
    func timelinePagesWithFirstAndAfter() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try await Self.renamedAndMoved(in: directory)
        let firstPage = try await Self.timeline(
            of: fixture.task,
            with: "(first: \(Self.pageSize))",
            selecting: Self.pageSelection,
            on: fixture.graph
        )
        let lastCursor = TimelineCursor(txn: try #require(ULID(ulidString: fixture.renamed)), index: .zero).text
        let nextPage = try await Self.timeline(
            of: fixture.task,
            with: #"(first: \#(Self.pageSize), after: "\#(lastCursor)")"#,
            selecting: Self.pageSelection,
            on: fixture.graph
        )
        let expectedFirst = Self.timelineResponse([
            try Self.pageEntryJSON(txn: fixture.moved, index: .zero, kind: .move),
            try Self.pageEntryJSON(txn: fixture.renamed, index: .zero, kind: .field),
        ])
        let expectedNext = Self.timelineResponse([
            try Self.pageEntryJSON(txn: fixture.created, index: .zero, kind: .move),
            try Self.pageEntryJSON(txn: fixture.created, index: 1, kind: .field),
        ])
        #expect(firstPage == expectedFirst)
        #expect(nextPage == expectedNext)
    }

    @Test("timeline(after:) takes the txn of a transaction in lowercase, and starts after each entry of it")
    func timelineAfterTakesTransaction() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try await Self.renamedAndMoved(in: directory)
        let response = try await Self.timeline(
            of: fixture.task,
            with: #"(after: "\#(fixture.moved.lowercased())")"#,
            selecting: Self.pageSelection,
            on: fixture.graph
        )
        let expected = Self.timelineResponse([
            try Self.pageEntryJSON(txn: fixture.renamed, index: .zero, kind: .field),
            try Self.pageEntryJSON(txn: fixture.created, index: .zero, kind: .move),
            try Self.pageEntryJSON(txn: fixture.created, index: 1, kind: .field),
        ])
        #expect(response == expected)
    }

    @Test("timeline(first:) with a negative value gives no entries")
    func timelineNegativeFirstGivesNoEntries() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let response = try await Self.timeline(
            of: fixture.task,
            with: "(first: -1)",
            selecting: Self.pageSelection,
            on: fixture.graph
        )
        #expect(response == Self.timelineResponse([]))
    }

    // MARK: - Reads

    @Test("timeline reads only the logs of the task and of its comments, on a board with many tasks")
    func timelineReadsOnlyLogsOfTaskAndComments() async throws {
        let directory = try TemporaryDirectory()
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let refs = ChangeBuilderTests.refs(of: base.task, in: session)
        let otherTasks = (0..<Self.otherTaskCount).map { _ in AddUpdateTaskTests.addTask(with: "") }
        try await HistoryTests.run(eachOf: otherTasks + [ChangeBuilderTests.addCommentField(refs)], in: &session)
        let view = BoardView(of: session.live.graph, inBoard: ChangeBuilderTests.boardKey, from: session.source)
        let task = try view.task(for: AddUpdateTaskTests.sigilRef(of: base.task))
        let comment = try #require(task.comments.first).state.ref
        let reader = CountingLogReader(reading: session.source.logs)
        _ = task.timelineEntries(reading: reader)
        #expect(reader.reads == [.task(base.task), comment])
    }
}

/// A reader of the node logs of a board that records each node whose log it reads.
private final class CountingLogReader: NodeLogReading {
    /// The node logs that the reader reads.
    private let logs: NodeLogs

    /// The local ref of each node whose log the reader read, in the order of the reads.
    private(set) var reads: [LocalRef] = []

    /// Makes a reader of some node logs.
    ///
    /// - Parameter logs: The node logs.
    init(reading logs: NodeLogs) {
        self.logs = logs
    }

    /// The undone state of the transactions of the board.
    var undoneState: UndoneState {
        logs.undoneState
    }

    /// Gives the events of the log of one node, and records the read.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The events of the node, in the order of their ids.
    func events(of ref: LocalRef) -> [Event] {
        reads.append(ref)
        return logs.events(of: ref)
    }
}
