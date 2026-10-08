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

    /// The selection of each change in most tests: the transaction and the id, the type, the kind, and the source of
    /// each update.
    static let updateSelection = "txn updates { id type kind source }"

    /// The arguments of a `history` call that keeps the updates of the tasks with the tag ``TagMutationTests/bug``.
    static let bugFilterArguments = ##"(filter: "#\##(TagMutationTests.bug)")"##

    /// The arguments of a `history` call that keeps the updates of the deleted tasks.
    static let deletedFilterArguments = ##"(filter: "#DELETED")"##

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

    /// Runs the base setup, and then completes the fixture task in one more transaction.
    ///
    /// - Parameter directory: The temporary repo directory.
    /// - Returns: The session after the completion, and the ULID of the fixture task.
    static func completedSession(inRepoAt directory: TemporaryDirectory) async throws -> (
        session: CommitSession,
        task: ULID
    ) {
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        try await run(eachOf: [TaskOperationTests.taskField(MutationName.completeTask, of: base.task)], in: &session)
        return (session, base.task)
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

    @Test("history(type:) keeps only the updates of the types, and leaves out a Change with no update left")
    func historyTypeKeepsUpdatesOfTypes() async throws {
        let directory = try TemporaryDirectory()
        let session = try await ChangeBuilderTests.baseSession(inRepoAt: directory).session
        let changes = try await Self.history(with: "(type: [COLUMN])", in: session)
        #expect(changes.count == Self.columnTransactionCount)
        #expect(Self.values(named: "type", of: Self.updates(of: changes)) == [NodeType.column.rawValue])
    }

    @Test("history(node:) keeps only the updates of the node")
    func historyNodeKeepsUpdatesOfNode() async throws {
        let directory = try TemporaryDirectory()
        let completed = try await Self.completedSession(inRepoAt: directory)
        let node = AddUpdateTaskTests.sigilRef(of: completed.task)
        let changes = try await Self.history(with: #"(node: "\#(node)")"#, in: completed.session)
        let task = ColumnActorTests.id(of: .task(completed.task))
        #expect(Self.values(named: "id", of: Self.updates(of: changes)) == [task])
        #expect(Self.updateTexts(of: changes.first) == ["TASK UPDATED \(task)"])
        #expect(Self.updateTexts(of: changes.last) == ["TASK CREATED \(task)"])
    }

    @Test("history(node:) with a ref that names no node gives no transaction")
    func historyUnknownNodeGivesNoTransaction() async throws {
        let directory = try TemporaryDirectory()
        let session = try await ChangeBuilderTests.baseSession(inRepoAt: directory).session
        let changes = try await Self.history(with: #"(node: "\#(AddUpdateTaskTests.unknownTask)")"#, in: session)
        #expect(changes.isEmpty)
    }

    @Test("history(actor:) keeps only the transactions of the actor")
    func historyActorKeepsTransactionsOfActor() async throws {
        let directory = try TemporaryDirectory()
        let alice = LocalRef.actor(slug: AddUpdateTaskTests.alice)
        let byAlice = try UndoneStateTests.transaction(atStep: UndoneStateTests.Step.original.rawValue, by: alice)
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory, writing: [byAlice])
        let changes = try await Self.history(
            with: #"(actor: "\#(AddUpdateTaskTests.alice)")"#,
            selecting: "txn actor { id }",
            in: base.session
        )
        #expect(Self.transactions(of: changes) == [byAlice.txn.ulidString])
        #expect(changes.first?["actor"]["id"].string == ColumnActorTests.id(of: alice))
    }

    @Test("history(filter:) keeps only the updates of the tasks that match, and of the comments on those tasks")
    func historyFilterKeepsMatchingTasksAndComments() async throws {
        let directory = try TemporaryDirectory()
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let refs = ChangeBuilderTests.refs(of: base.task, in: session)
        let otherTask = AddUpdateTaskTests.addTask(with: AddUpdateTaskTests.dependsOn(base.task))
        try await Self.run(
            eachOf: [ChangeBuilderTests.tagField(of: refs), ChangeBuilderTests.addCommentField(refs), otherTask],
            in: &session
        )
        let changes = try await Self.history(with: Self.bugFilterArguments, in: session)
        let updates = Self.updates(of: changes)
        #expect(Self.values(named: "type", of: updates) == [NodeType.task.rawValue, NodeType.comment.rawValue])
        let taskUpdates = updates.filter { update in update["type"].string == NodeType.task.rawValue }
        #expect(Self.values(named: "id", of: taskUpdates) == [ColumnActorTests.id(of: .task(base.task))])
    }

    @Test("history(filter: \"#DELETED\") keeps the DELETED update of a deleted task")
    func historyDeletedFilterKeepsDeletedUpdate() async throws {
        let directory = try TemporaryDirectory()
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let refs = ChangeBuilderTests.refs(of: base.task, in: session)
        try await Self.run(eachOf: [ChangeBuilderTests.deleteTaskField(refs)], in: &session)
        let changes = try await Self.history(with: Self.deletedFilterArguments, in: session)
        let task = ColumnActorTests.id(of: .task(base.task))
        #expect(Self.updateTexts(of: changes.first) == ["TASK DELETED \(task)"])
    }

    @Test("history(filter:) with a tag leaves out the updates of a deleted task, the same as a task list")
    func historyTagFilterLeavesOutDeletedTask() async throws {
        let directory = try TemporaryDirectory()
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let refs = ChangeBuilderTests.refs(of: base.task, in: session)
        try await Self.run(
            eachOf: [ChangeBuilderTests.tagField(of: refs), ChangeBuilderTests.deleteTaskField(refs)],
            in: &session
        )
        let changes = try await Self.history(with: Self.bugFilterArguments, in: session)
        #expect(changes.isEmpty)
    }

    @Test("After undeleteTask, history(filter: \"#DELETED\") leaves out the task, and a tag filter keeps it again")
    func historyAfterUndeleteFollowsLiveTask() async throws {
        let directory = try TemporaryDirectory()
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let refs = ChangeBuilderTests.refs(of: base.task, in: session)
        try await Self.run(
            eachOf: [
                ChangeBuilderTests.tagField(of: refs),
                ChangeBuilderTests.deleteTaskField(refs),
                TaskOperationTests.taskField(MutationName.undeleteTask, of: base.task),
            ],
            in: &session
        )
        let deleted = try await Self.history(with: Self.deletedFilterArguments, in: session)
        #expect(deleted.isEmpty)
        let tagged = try await Self.history(with: Self.bugFilterArguments, in: session)
        let task = ColumnActorTests.id(of: .task(base.task))
        #expect(Self.updateTexts(of: tagged.first) == ["TASK RESTORED \(task)"])
    }

    @Test("history(derived: false) leaves out the DERIVED updates")
    func historyWithoutDerivedLeavesOutDerivedUpdates() async throws {
        let directory = try TemporaryDirectory()
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let dependent = AddUpdateTaskTests.addTask(with: AddUpdateTaskTests.dependsOn(base.task))
        let complete = TaskOperationTests.taskField(MutationName.completeTask, of: base.task)
        try await Self.run(eachOf: [dependent, complete], in: &session)
        let derived = UpdateSource.derived.rawValue
        let withDerived = try await Self.history(in: session)
        #expect(Self.values(named: "source", of: Self.updates(of: withDerived)).contains(derived))
        let withoutDerived = try await Self.history(with: "(derived: false)", in: session)
        #expect(!Self.values(named: "source", of: Self.updates(of: withoutDerived)).contains(derived))
        #expect(Self.transactions(of: withoutDerived) == Self.transactions(of: withDerived))
    }

    // MARK: - Schema

    @Test("The Board type has the history field with the arguments and the defaults of plan.md §4.1")
    func schemaHasHistoryField() {
        let field = "  history(type: [NodeType!], node: ID, actor: ID, filter: String, derived: Boolean = true, "
            + "since: ID, first: Int = 20): [Change!]"
        #expect(KanbanGraph.schemaSDL.contains(field))
    }
}
