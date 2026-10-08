import Foundation
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests `Board.history` (plan.md §6.5, §6.7): the transactions of the board, newest first, each as a `Change`, with
/// the filters of the change feed.
///
/// Each test writes the fixture logs of ``KanbanGraphTests`` and runs ``ChangeBuilderTests/baseSetup`` in a commit
/// session of the board (``ChangeBuilderTests/baseSession(inRepoAt:writing:)``). The fixture writes three
/// transactions (the board, the column `todo`, and the task), and the base setup writes one more.
@Suite("History query")
struct HistoryTests {
    /// The number of transactions of the board after the base setup: the three fixture transactions and the base
    /// setup.
    static let baseTransactionCount = 4

    /// The number of transactions of the base board that change a column: the fixture column `todo`, and the column
    /// `Done` of the base setup.
    static let columnTransactionCount = 2

    /// The page size of the `first` test.
    static let pageSize = 2

    /// The selection of each change in most tests: the transaction and the id, the type, and the kind of each update.
    static let updateSelection = "txn updates { id type kind }"

    /// The selection of each change in the tests of the field changes: the transaction, and the id, the type, and the
    /// name and the values of each field change of each update.
    static let fieldSelection = "txn updates { id type fields { name before after } }"

    /// The arguments of a `history` call that keeps the updates of the tasks with the tag ``TagMutationTests/bug``.
    static let bugFilterArguments = ##"(filter: "#\##(TagMutationTests.bug)")"##

    /// The arguments of a `history` call that keeps the updates of the deleted tasks.
    static let deletedFilterArguments = ##"(filter: "#DELETED")"##

    /// The arguments of a `history` call that keeps the updates of the done tasks.
    static let doneFilterArguments = ##"(filter: "#DONE")"##

    // MARK: - Helpers

    /// Runs `board { history }` in a session, and expects that it gives no error.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the field, with their parentheses, or `""` for no arguments.
    ///   - selection: The selection of each change.
    ///   - session: The commit session. The query runs on a copy.
    /// - Returns: The changes, in the order of the response.
    static func history(
        with arguments: String = "",
        selecting selection: String = updateSelection,
        in session: CommitSession
    ) async throws -> [Map] {
        var copy = session
        let result = try await ChangeBuilderTests.run("{ board { history\(arguments) { \(selection) } } }", in: &copy)
        return try #require(result.data?["board"]["history"].array)
    }

    /// Runs mutation fields in a session, each one in its own call.
    ///
    /// - Parameters:
    ///   - fields: The mutation fields, in call order.
    ///   - session: The commit session.
    static func run(eachOf fields: [String], in session: inout CommitSession) async throws {
        for field in fields {
            try await ChangeBuilderTests.run(AddUpdateTaskTests.mutation(of: field), in: &session)
        }
    }

    /// Runs the base setup, and then runs mutation fields on the fixture task, each one in its own transaction. The
    /// other session helpers of this suite call this helper.
    ///
    /// - Parameters:
    ///   - directory: The temporary repo directory.
    ///   - fields: Gives the mutation fields from the refs of the fixture task after the base setup, in call order.
    /// - Returns: The session after the last field, and the ULID of the fixture task.
    static func session(
        inRepoAt directory: TemporaryDirectory,
        running fields: (ChangeBuilderTests.CaseRefs) -> [String]
    ) async throws -> (session: CommitSession, task: ULID) {
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        try await run(eachOf: fields(ChangeBuilderTests.refs(of: base.task, in: session)), in: &session)
        return (session, base.task)
    }

    /// Runs the base setup, and then completes the fixture task in one more transaction.
    ///
    /// - Parameter directory: The temporary repo directory.
    /// - Returns: The session after the completion, and the ULID of the fixture task.
    static func completedSession(inRepoAt directory: TemporaryDirectory) async throws -> (
        session: CommitSession,
        task: ULID
    ) {
        try await session(inRepoAt: directory) { refs in
            [TaskOperationTests.taskField(MutationName.completeTask, of: refs.task)]
        }
    }

    /// Runs the base setup, tags the fixture task with ``TagMutationTests/bug``, and then runs more mutation fields
    /// on the task, each one in its own transaction.
    ///
    /// - Parameters:
    ///   - directory: The temporary repo directory.
    ///   - fields: Gives the mutation fields from the refs of the fixture task after the base setup, in call order.
    /// - Returns: The session after the last field, and the ULID of the fixture task.
    static func taggedSession(
        inRepoAt directory: TemporaryDirectory,
        running fields: (ChangeBuilderTests.CaseRefs) -> [String]
    ) async throws -> (session: CommitSession, task: ULID) {
        try await session(inRepoAt: directory) { refs in [ChangeBuilderTests.tagField(of: refs)] + fields(refs) }
    }

    /// Gives the transaction ULID text of each change.
    ///
    /// - Parameter changes: The changes of a response.
    /// - Returns: The `txn` of each change, in the order of the changes.
    static func transactions(of changes: [Map]) -> [String] {
        changes.compactMap { change in change["txn"].string }
    }

    /// Runs `history` with no argument, and `history(since:)` with the second newest transaction.
    ///
    /// - Parameters:
    ///   - spelling: Gives the text of the `since` argument from the ULID text of the transaction.
    ///   - session: The commit session.
    /// - Returns: The transactions of the full history, and the transactions after the second newest one.
    static func transactionsSinceSecondNewest(
        spelledWith spelling: (String) -> String,
        in session: CommitSession
    ) async throws -> (all: [String], later: [String]) {
        let all = transactions(of: try await history(selecting: "txn", in: session))
        let since = spelling(try #require(all.dropFirst().first))
        let later = try await history(with: #"(since: "\#(since)")"#, selecting: "txn", in: session)
        return (all, transactions(of: later))
    }

    /// Gives the updates of all changes.
    ///
    /// - Parameter changes: The changes of a response.
    /// - Returns: The updates of each change, in the order of the changes.
    static func updates(of changes: [Map]) -> [Map] {
        changes.flatMap { change in change["updates"].array ?? [] }
    }

    /// Gives the text of each update of one change: the type, the kind, and the id, for example
    /// `TASK UPDATED kanban://…`.
    ///
    /// - Parameter change: The change of a response, or `nil`.
    /// - Returns: The text of each update, in the order of the change.
    static func updateTexts(of change: Map?) -> [String] {
        (change?["updates"].array ?? []).map { update in
            "\(update["type"].string ?? "") \(update["kind"].string ?? "") \(update["id"].string ?? "")"
        }
    }

    /// Gives the values of one field of each update.
    ///
    /// - Parameters:
    ///   - key: The field of the update, for example `type`.
    ///   - updates: The updates of a response.
    /// - Returns: The text of the field of each update.
    static func values(named key: String, of updates: [Map]) -> Set<String> {
        Set(updates.compactMap { update in update[key].string })
    }

    // MARK: - List

    @Test("history lists the transactions newest first, with ops, actor, and updates")
    func historyListsNewestFirst() async throws {
        let directory = try TemporaryDirectory()
        let completed = try await Self.completedSession(inRepoAt: directory)
        let selection = "txn ops actor { id } updates { id type kind }"
        let changes = try await Self.history(selecting: selection, in: completed.session)
        let txns = Self.transactions(of: changes)
        #expect(txns.count == Self.baseTransactionCount + 1)
        #expect(txns == txns.sorted(by: >))
        #expect(changes.first?["ops"].array?.compactMap(\.string) == [MutationName.completeTask])
        #expect(changes.last?["ops"].array?.compactMap(\.string) == [KanbanGraphTests.fixtureOperation])
        let actors = Set(changes.compactMap { change in change["actor"]["id"].string })
        #expect(actors == [ColumnActorTests.id(of: ReplayTests.actor)])
        let task = ColumnActorTests.id(of: .task(completed.task))
        #expect(Self.updateTexts(of: changes.first).contains("TASK UPDATED \(task)"))
        #expect(Self.updateTexts(of: changes.last) == ["BOARD CREATED \(ColumnActorTests.id(of: .board))"])
    }

    @Test("history(since: <txn>) returns only the later transactions")
    func historySinceGivesLaterTransactions() async throws {
        let directory = try TemporaryDirectory()
        let session = try await Self.completedSession(inRepoAt: directory).session
        let result = try await Self.transactionsSinceSecondNewest(spelledWith: { text in text }, in: session)
        #expect(result.later == Array(result.all.prefix(1)))
    }

    @Test("history(since:) accepts the transaction ULID in lowercase")
    func historySinceAcceptsLowercase() async throws {
        let directory = try TemporaryDirectory()
        let session = try await Self.completedSession(inRepoAt: directory).session
        let lowercase: (String) -> String = { text in text.lowercased() }
        let result = try await Self.transactionsSinceSecondNewest(spelledWith: lowercase, in: session)
        #expect(result.later == Array(result.all.prefix(1)))
    }

    @Test("history(first:) gives the newest transactions")
    func historyFirstGivesNewestTransactions() async throws {
        let directory = try TemporaryDirectory()
        let session = try await ChangeBuilderTests.baseSession(inRepoAt: directory).session
        let all = Self.transactions(of: try await Self.history(selecting: "txn", in: session))
        let page = try await Self.history(with: "(first: \(Self.pageSize))", selecting: "txn", in: session)
        #expect(page.count == Self.pageSize)
        #expect(Self.transactions(of: page) == Array(all.prefix(Self.pageSize)))
    }

    @Test("history marks a transaction undone when a later undo reverses it, and gives the undoes of the undo")
    func historyGivesUndoneState() async throws {
        let directory = try TemporaryDirectory()
        let original = try UndoneStateTests.transaction(atStep: UndoneStateTests.Step.original.rawValue)
        let undo = try UndoneStateTests.transaction(
            atStep: UndoneStateTests.Step.undo.rawValue,
            undoing: original.txn
        )
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory, writing: [original, undo])
        let changes = try await Self.history(selecting: "txn undone undoes", in: base.session)
        let byTransaction = Dictionary(uniqueKeysWithValues: changes.map { change in (change["txn"].string, change) })
        let originalChange = try #require(byTransaction[original.txn.ulidString])
        let undoChange = try #require(byTransaction[undo.txn.ulidString])
        #expect(originalChange["undone"] == .bool(true))
        #expect(undoChange["undone"] == .bool(false))
        #expect(undoChange["undoes"] == .string(original.txn.ulidString))
    }

    // MARK: - Filters

    @Test("history(filter: \"~column\") keeps only the updates of the node type, and leaves out a Change with none")
    func historyNodeTypeKeepsUpdatesOfType() async throws {
        let directory = try TemporaryDirectory()
        let session = try await ChangeBuilderTests.baseSession(inRepoAt: directory).session
        let changes = try await Self.history(with: #"(filter: "~column")"#, in: session)
        #expect(changes.count == Self.columnTransactionCount)
        #expect(Self.values(named: "type", of: Self.updates(of: changes)) == [NodeType.column.rawValue])
    }

    @Test("history(filter: \"~task\") keeps each update of a task, also the completion that makes the task done")
    func historyTaskTypeKeepsDoneTask() async throws {
        let directory = try TemporaryDirectory()
        let completed = try await Self.completedSession(inRepoAt: directory)
        let changes = try await Self.history(with: #"(filter: "~task")"#, in: completed.session)
        let task = ColumnActorTests.id(of: .task(completed.task))
        #expect(Self.values(named: "type", of: Self.updates(of: changes)) == [NodeType.task.rawValue])
        #expect(Self.updateTexts(of: changes.first) == ["TASK UPDATED \(task)"])
    }

    @Test("history(filter: \"^id\") keeps only the updates of the node, also when the task is done now")
    func historyRefKeepsUpdatesOfNode() async throws {
        let directory = try TemporaryDirectory()
        let completed = try await Self.completedSession(inRepoAt: directory)
        let node = AddUpdateTaskTests.sigilRef(of: completed.task)
        let changes = try await Self.history(with: #"(filter: "\#(node)")"#, in: completed.session)
        let task = ColumnActorTests.id(of: .task(completed.task))
        #expect(Self.values(named: "id", of: Self.updates(of: changes)) == [task])
        #expect(Self.updateTexts(of: changes.first) == ["TASK UPDATED \(task)"])
        #expect(Self.updateTexts(of: changes.last) == ["TASK CREATED \(task)"])
    }

    @Test("history(filter: \"^id\") with a ref that names no node gives no transaction")
    func historyUnknownRefGivesNoTransaction() async throws {
        let directory = try TemporaryDirectory()
        let session = try await ChangeBuilderTests.baseSession(inRepoAt: directory).session
        let changes = try await Self.history(with: #"(filter: "\#(AddUpdateTaskTests.unknownTask)")"#, in: session)
        #expect(changes.isEmpty)
    }

    @Test("Change.actor gives the actor of each transaction, so a client can select the changes of one actor")
    func historyGivesActorOfEachTransaction() async throws {
        let directory = try TemporaryDirectory()
        let alice = LocalRef.actor(slug: AddUpdateTaskTests.alice)
        let byAlice = try UndoneStateTests.transaction(atStep: UndoneStateTests.Step.original.rawValue, by: alice)
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory, writing: [byAlice])
        let changes = try await Self.history(selecting: "txn actor { id }", in: base.session)
        let aliceID = ColumnActorTests.id(of: alice)
        let byAliceChanges = changes.filter { change in change["actor"]["id"].string == aliceID }
        #expect(Self.transactions(of: byAliceChanges) == [byAlice.txn.ulidString])
        #expect(changes.count > byAliceChanges.count)
    }

    @Test("history(filter:) with a tag keeps only the task updates; a comment update needs ~comment in the filter")
    func historyFilterKeepsMatchingTasks() async throws {
        let directory = try TemporaryDirectory()
        let base = try await Self.taggedSession(inRepoAt: directory) { refs in
            [
                ChangeBuilderTests.addCommentField(refs),
                AddUpdateTaskTests.addTask(with: AddUpdateTaskTests.dependsOn(refs.task)),
            ]
        }
        let task = ColumnActorTests.id(of: .task(base.task))
        let tagged = Self.updates(of: try await Self.history(with: Self.bugFilterArguments, in: base.session))
        #expect(Self.values(named: "type", of: tagged) == [NodeType.task.rawValue])
        #expect(Self.values(named: "id", of: tagged) == [task])
        let withComments = try await Self.history(with: ##"(filter: "#bug || ~comment")"##, in: base.session)
        let types = Self.values(named: "type", of: Self.updates(of: withComments))
        #expect(types == [NodeType.task.rawValue, NodeType.comment.rawValue])
    }

    @Test("history(filter: \"#DELETED\") keeps the DELETED update of a deleted task")
    func historyDeletedFilterKeepsDeletedUpdate() async throws {
        let directory = try TemporaryDirectory()
        let base = try await Self.session(inRepoAt: directory) { refs in [ChangeBuilderTests.deleteTaskField(refs)] }
        let changes = try await Self.history(with: Self.deletedFilterArguments, in: base.session)
        let task = ColumnActorTests.id(of: .task(base.task))
        #expect(Self.updateTexts(of: changes.first) == ["TASK DELETED \(task)"])
    }

    @Test("history(filter:) with a tag leaves out the updates of a deleted task, the same as a task list")
    func historyTagFilterLeavesOutDeletedTask() async throws {
        let directory = try TemporaryDirectory()
        let session = try await Self.taggedSession(inRepoAt: directory) { refs in
            [ChangeBuilderTests.deleteTaskField(refs)]
        }.session
        let changes = try await Self.history(with: Self.bugFilterArguments, in: session)
        #expect(changes.isEmpty)
    }

    @Test("After undeleteTask, history(filter: \"#DELETED\") leaves out the task, and a tag filter keeps it again")
    func historyAfterUndeleteFollowsLiveTask() async throws {
        let directory = try TemporaryDirectory()
        let base = try await Self.taggedSession(inRepoAt: directory) { refs in
            [
                ChangeBuilderTests.deleteTaskField(refs),
                TaskOperationTests.taskField(MutationName.undeleteTask, of: refs.task),
            ]
        }
        let deleted = try await Self.history(with: Self.deletedFilterArguments, in: base.session)
        #expect(deleted.isEmpty)
        let tagged = try await Self.history(with: Self.bugFilterArguments, in: base.session)
        let task = ColumnActorTests.id(of: .task(base.task))
        #expect(Self.updateTexts(of: tagged.first) == ["TASK RESTORED \(task)"])
    }

    @Test("history(filter:) with a tag leaves out the updates of a done task, and #DONE keeps them")
    func historyDoneFilterKeepsDoneTask() async throws {
        let directory = try TemporaryDirectory()
        let completed = try await Self.taggedSession(
            inRepoAt: directory,
            running: { refs in [TaskOperationTests.taskField(MutationName.completeTask, of: refs.task)] }
        )
        #expect(try await Self.history(with: Self.bugFilterArguments, in: completed.session).isEmpty)
        let done = try await Self.history(with: Self.doneFilterArguments, in: completed.session)
        let task = ColumnActorTests.id(of: .task(completed.task))
        #expect(Self.updateTexts(of: done.first).contains("TASK UPDATED \(task)"))
    }

    @Test("After a move out of done, history(filter: \"#DONE\") leaves out the task, and a tag filter keeps it")
    func historyAfterMoveOutOfDoneFollowsOpenTask() async throws {
        let directory = try TemporaryDirectory()
        let reopened = try await Self.taggedSession(
            inRepoAt: directory,
            running: { refs in
                [
                    TaskOperationTests.taskField(MutationName.completeTask, of: refs.task),
                    TaskOperationTests.taskField(
                        MutationName.moveTask,
                        of: refs.task,
                        with: TaskOperationTests.moveInput()
                    ),
                ]
            }
        )
        #expect(try await Self.history(with: Self.doneFilterArguments, in: reopened.session).isEmpty)
        let tagged = try await Self.history(with: Self.bugFilterArguments, in: reopened.session)
        let task = ColumnActorTests.id(of: .task(reopened.task))
        #expect(Self.updateTexts(of: tagged.first).contains("TASK UPDATED \(task)"))
    }

    @Test("history keeps the update of a task that the completion of a different task makes ready, one per node")
    func historyKeepsUpdateOfDependentTask() async throws {
        let directory = try TemporaryDirectory()
        let base = try await Self.session(inRepoAt: directory) { refs in
            [
                AddUpdateTaskTests.addTask(with: AddUpdateTaskTests.dependsOn(refs.task)),
                TaskOperationTests.taskField(MutationName.completeTask, of: refs.task),
            ]
        }
        let changes = try await Self.history(selecting: Self.fieldSelection, in: base.session)
        let completion = try #require(changes.first)["updates"].array ?? []
        let completed = ColumnActorTests.id(of: .task(base.task))
        let dependents = completion.filter { update in
            update["type"].string == NodeType.task.rawValue && update["id"].string != completed
        }
        let ready = dependents.flatMap { update in update["fields"].array ?? [] }.filter { field in
            field["name"].string == "ready"
        }
        #expect(ready == [["name": "ready", "before": false, "after": true]])
        for change in changes {
            let ids = Self.updates(of: [change]).compactMap { update in update["id"].string }
            #expect(Set(ids).count == ids.count)
        }
    }

    // MARK: - Schema

    @Test("The Board type has the history field with only the filter and the paging arguments of plan.md §4.1")
    func schemaHasHistoryField() {
        #expect(KanbanGraph.schemaSDL.contains("  history(filter: String, since: ID, first: Int = 20): [Change!]"))
    }
}
