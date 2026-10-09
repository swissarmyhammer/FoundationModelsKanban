import Foundation
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests `undo` and `redo` in one board (plan.md §6.5, §11): an undo appends the inverse patches of a transaction, a
/// redo reverses an undo, a later change to the same property is a conflict, and `force` writes the inverse anyway.
///
/// Most tests write the fixture logs of ``KanbanGraphTests`` and run ``ChangeBuilderTests/baseSetup`` in a commit
/// session of the board (``ChangeBuilderTests/baseSession(inRepoAt:writing:)``). Then a test runs some calls, each in
/// its own transaction, and an undo or a redo.
@Suite("Undo and redo in one board")
struct UndoTests {
    /// The selection of the `Change` that `undo` and `redo` give.
    static let changeSelection = "txn undoes ops"

    /// The tracked field that the projection compare leaves out. `started` is the time of the first move out of the
    /// first column (plan.md §5.3 step 4). An undo of a move appends the move back, and the log keeps the first move,
    /// so the undo does not clear `started`.
    static let movedField = "started"

    /// The title of the fixture task after the first of two title calls.
    static let firstTitle = "Port the lexer"

    /// The title of the fixture task after the second of two title calls.
    static let secondTitle = "Port the evaluator"

    /// The lines of the body of the fixture task in the body tests.
    static let bodyLines = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]

    /// The text of a line that a body test changes.
    static let changedLine = "changed"

    /// The text of a line that a later call of a body test changes.
    static let laterChangedLine = "changed later"

    /// The slug of a tag that the fixture board does not have, beside ``TaskOperationTests/feature``.
    static let chore = "chore"

    // MARK: - Helpers

    /// Makes an `undo` or a `redo` field.
    ///
    /// - Parameters:
    ///   - name: The name of the mutation.
    ///   - input: The fields of the `input` object, or `""` for no `input` argument.
    /// - Returns: The field, with ``changeSelection``.
    static func reverseField(_ name: String, with input: String) -> String {
        let argument = input.isEmpty ? "" : "(input: { \(input) })"
        return "\(name)\(argument) { \(changeSelection) }"
    }

    /// Makes the `input` fields that name a transaction.
    ///
    /// - Parameters:
    ///   - txn: The transaction ULID.
    ///   - isForced: `true` to add `force: true`.
    /// - Returns: The `input` fields.
    static func txnInput(_ txn: ULID, forcing isForced: Bool = false) -> String {
        #"txn: "\#(txn.ulidString)""# + (isForced ? ", force: true" : "")
    }

    /// Runs an `undo` or a `redo` call in a session, and expects that it gives no error.
    ///
    /// - Parameters:
    ///   - name: The name of the mutation. The default is `undo`.
    ///   - input: The fields of the `input` object, or `""` for no `input` argument.
    ///   - session: The commit session.
    /// - Returns: The `Change` that the call gives.
    @discardableResult
    static func reverse(
        _ name: String = MutationName.undo,
        with input: String = "",
        in session: inout CommitSession
    ) async throws -> Map {
        let document = AddUpdateTaskTests.mutation(of: reverseField(name, with: input))
        let result = try await ChangeBuilderTests.run(document, in: &session)
        return result.data?[name] ?? .null
    }

    /// Runs an `undo` or a `redo` call that fails in a session, and gives its error.
    ///
    /// - Parameters:
    ///   - name: The name of the mutation. The default is `undo`.
    ///   - input: The fields of the `input` object, or `""` for no `input` argument.
    ///   - session: The commit session.
    /// - Returns: The error of the first GraphQL error of the response.
    static func failure(
        of name: String = MutationName.undo,
        with input: String = "",
        in session: inout CommitSession
    ) async throws -> KanbanError {
        let document = AddUpdateTaskTests.mutation(of: reverseField(name, with: input))
        let result = try await ColumnActorTests.result(of: document, in: &session)
        return try #require(result.errors.first?.originalError as? KanbanError)
    }

    /// Runs one mutation field in its own call in a session, and gives the transaction of the call.
    ///
    /// - Parameters:
    ///   - field: The mutation field.
    ///   - session: The commit session.
    /// - Returns: The transaction ULID of the call.
    static func transaction(running field: String, in session: inout CommitSession) async throws -> ULID {
        try await HistoryTests.run(eachOf: [field], in: &session)
        return try newestTransaction(of: session)
    }

    /// Gives the newest transaction of the log of a session.
    ///
    /// - Parameter session: The commit session.
    /// - Returns: The largest transaction ULID of the log.
    static func newestTransaction(of session: CommitSession) throws -> ULID {
        try #require(session.live.events.map(\.txn).max())
    }

    /// Gives the projection of the live graph of a session: the tracked fields of each node, live or tombstoned,
    /// without ``movedField``.
    ///
    /// - Parameter session: The commit session.
    /// - Returns: The tracked fields of each node, by its local ref.
    static func projection(of session: CommitSession) -> [LocalRef: TrackedFields] {
        let view = ChangeBuilderTests.view(of: session)
        let pairs = view.graph.allSlots.compactMap { slot -> (LocalRef, TrackedFields)? in
            guard let node = view.graph.node(at: slot), let object = view.nodeObject(at: slot) else {
                return nil
            }
            var fields = object.trackedFields
            fields.removeValue(forKey: movedField)
            return (node.ref, fields)
        }
        return Dictionary(uniqueKeysWithValues: pairs)
    }

    /// Tells if the tracked fields of a node are the fields of a tombstone.
    ///
    /// - Parameter fields: The tracked fields of the node.
    /// - Returns: `true` when `deleted` has a value.
    static func isTombstone(_ fields: TrackedFields) -> Bool {
        fields["deleted"] != .single(.null)
    }

    /// Gives the nodes of a session that are not in an earlier projection.
    ///
    /// - Parameters:
    ///   - session: The commit session.
    ///   - earlier: The earlier projection.
    /// - Returns: The tracked fields of each node that the earlier projection does not have, by its local ref.
    static func addedNodes(
        of session: CommitSession,
        since earlier: [LocalRef: TrackedFields]
    ) -> [LocalRef: TrackedFields] {
        projection(of: session).filter { ref, _ in earlier[ref] == nil }
    }

    /// Expects that the projection of a session equals an earlier projection, except the nodes that are not in the
    /// earlier projection. Each such node must be a tombstone (plan.md §6.5).
    ///
    /// - Parameters:
    ///   - session: The commit session after the undo.
    ///   - earlier: The projection before the call that the undo reversed.
    static func expectProjection(of session: CommitSession, restoring earlier: [LocalRef: TrackedFields]) {
        let undone = projection(of: session)
        for (ref, fields) in earlier {
            #expect(undone[ref] == fields, "\(ref)")
        }
        for (ref, fields) in addedNodes(of: session, since: earlier) {
            #expect(isTombstone(fields), "\(ref)")
        }
    }

    /// Expects that each node of a list is in the projection of a session, and is not a tombstone.
    ///
    /// - Parameters:
    ///   - refs: The local refs of the nodes.
    ///   - session: The commit session.
    static func expectLive(_ refs: Set<LocalRef>, in session: CommitSession) {
        let current = projection(of: session)
        for ref in refs {
            #expect(current[ref].map { fields in !isTombstone(fields) } == true, "\(ref)")
        }
    }

    /// Makes an `addTask` field with one tag.
    ///
    /// - Parameter tag: The tag name.
    /// - Returns: The field.
    static func addTaskTagged(_ tag: String) -> String {
        AddUpdateTaskTests.addTask(with: TaskOperationTests.tagsInput(tag))
    }

    /// Makes an `addTask` field whose body has one `#marker`.
    ///
    /// - Parameter tag: The tag name of the marker.
    /// - Returns: The field.
    static func addTaskMarking(_ tag: String) -> String {
        AddUpdateTaskTests.addTask(with: ##"body: "#\##(tag)""##)
    }

    /// Makes an `updateTask` field that sets the title of a task.
    ///
    /// - Parameters:
    ///   - title: The new title.
    ///   - task: The ULID of the task.
    /// - Returns: The field.
    static func titleField(_ title: String, of task: ULID) -> String {
        AddUpdateTaskTests.updateTask(task, with: #"title: "\#(title)""#)
    }

    /// Makes an `updateTask` field that sets the body of a task.
    ///
    /// - Parameters:
    ///   - lines: The lines of the new body. Each line ends with a line break.
    ///   - task: The ULID of the task.
    /// - Returns: The field.
    static func bodyField(_ lines: [String], of task: ULID) -> String {
        AddUpdateTaskTests.updateTask(task, with: #"body: ""# + lines.map { line in #"\#(line)\n"# }.joined() + #"""#)
    }

    /// Gives the text of a body.
    ///
    /// - Parameter lines: The lines of the body. Each line ends with a line break.
    /// - Returns: The text.
    static func text(of lines: [String]) -> String {
        lines.map { line in "\(line)\n" }.joined()
    }

    /// Gives lines with one line changed.
    ///
    /// - Parameters:
    ///   - lines: The lines.
    ///   - index: The index of the line to change.
    ///   - line: The new text of the line.
    /// - Returns: The changed lines.
    static func lines(_ lines: [String], changing index: Int, to line: String) -> [String] {
        var changed = lines
        changed[index] = line
        return changed
    }

    /// Runs the base setup, and then two calls that set the title of the fixture task: first ``firstTitle``, then
    /// ``secondTitle``.
    ///
    /// - Parameter directory: The temporary repo directory.
    /// - Returns: The session, the ULID of the fixture task, and the transactions of the two calls.
    static func twoTitleCalls(inRepoAt directory: TemporaryDirectory) async throws -> (
        session: CommitSession,
        task: ULID,
        first: ULID,
        second: ULID
    ) {
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let first = try await transaction(running: titleField(firstTitle, of: base.task), in: &session)
        let second = try await transaction(running: titleField(secondTitle, of: base.task), in: &session)
        return (session, base.task, first, second)
    }

    /// Runs the base setup, a call that sets the body of the fixture task to ``bodyLines``, and two calls that change
    /// the second line: first to ``changedLine``, then to ``laterChangedLine``.
    ///
    /// - Parameter directory: The temporary repo directory.
    /// - Returns: The session, the ULID of the fixture task, and the transactions of the two changes.
    static func twoChangesOfOneLine(inRepoAt directory: TemporaryDirectory) async throws -> (
        session: CommitSession,
        task: ULID,
        first: ULID,
        second: ULID
    ) {
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let task = base.task
        try await HistoryTests.run(eachOf: [bodyField(bodyLines, of: task)], in: &session)
        let firstLines = lines(bodyLines, changing: 1, to: changedLine)
        let first = try await transaction(running: bodyField(firstLines, of: task), in: &session)
        let laterLines = lines(bodyLines, changing: 1, to: laterChangedLine)
        let second = try await transaction(running: bodyField(laterLines, of: task), in: &session)
        return (session, task, first, second)
    }

    // MARK: - Each public mutation

    @Test(
        "undo of each public mutation restores the projection before the call, and each node it made is a tombstone",
        arguments: ChangeBuilderTests.mutationCases
    )
    func undoRestoresProjectionBeforeCall(mutationCase: ChangeBuilderTests.MutationCase) async throws {
        let recorded = try await ChangeBuilderTests.record(mutationCase)
        var session = recorded.after
        try await Self.reverse(in: &session)
        Self.expectProjection(of: session, restoring: Self.projection(of: recorded.before))
    }

    @Test(
        "redo after the undo of each public mutation gives the projection from after the call",
        arguments: ChangeBuilderTests.mutationCases
    )
    func redoRestoresProjectionAfterCall(mutationCase: ChangeBuilderTests.MutationCase) async throws {
        let recorded = try await ChangeBuilderTests.record(mutationCase)
        var session = recorded.after
        try await Self.reverse(in: &session)
        try await Self.reverse(MutationName.redo, in: &session)
        #expect(Self.projection(of: session) == Self.projection(of: recorded.after))
    }

    @Test("undo of a call with many mutation fields reverses all of them")
    func undoReversesAllFieldsOfCall() async throws {
        let directory = try TemporaryDirectory()
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let earlier = Self.projection(of: session)
        let refs = ChangeBuilderTests.refs(of: base.task, in: session)
        let fields = [
            Self.titleField(Self.firstTitle, of: base.task),
            ChangeBuilderTests.tagField(of: refs),
            ColumnActorTests.addQA,
        ]
        try await ChangeBuilderTests.run("mutation { \(fields.joined(separator: " ")) }", in: &session)
        try await Self.reverse(in: &session)
        Self.expectProjection(of: session, restoring: earlier)
    }

    // MARK: - Result

    @Test("undo gives the Change that it wrote, and its patches have undoes = the reversed transaction")
    func undoGivesWrittenChange() async throws {
        let directory = try TemporaryDirectory()
        let calls = try await Self.twoTitleCalls(inRepoAt: directory)
        var session = calls.session
        let change = try await Self.reverse(in: &session)
        let undo = try Self.newestTransaction(of: session)
        #expect(change["txn"] == .string(undo.ulidString))
        #expect(change["undoes"] == .string(calls.second.ulidString))
        #expect(change["ops"] == .array([.string(MutationName.undo)]))
        let written = session.live.events.filter { event in event.txn == undo }
        #expect(!written.isEmpty)
        #expect(written.allSatisfy { event in event.undoes == calls.second })
    }

    // MARK: - Target

    @Test("Two undo calls in a row reverse the two newest calls, and do not act as a redo")
    func twoUndosReverseTwoNewestCalls() async throws {
        let directory = try TemporaryDirectory()
        let calls = try await Self.twoTitleCalls(inRepoAt: directory)
        var session = calls.session
        let firstUndo = try await Self.reverse(in: &session)
        let secondUndo = try await Self.reverse(in: &session)
        #expect(firstUndo["undoes"] == .string(calls.second.ulidString))
        #expect(secondUndo["undoes"] == .string(calls.first.ulidString))
        #expect(try CommitTests.title(of: .task(calls.task), in: session) == KanbanGraphTests.taskTitle)
    }

    @Test("deleteTask, then undo, then redo gives the projection after deleteTask, and the undo clears deleted")
    func deleteTaskUndoRedoGivesProjectionAfterDelete() async throws {
        let directory = try TemporaryDirectory()
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let refs = ChangeBuilderTests.refs(of: base.task, in: session)
        try await HistoryTests.run(eachOf: [ChangeBuilderTests.deleteTaskField(refs)], in: &session)
        let deleted = Self.projection(of: session)
        try await Self.reverse(in: &session)
        let restored = try #require(Self.projection(of: session)[.task(base.task)])
        #expect(!Self.isTombstone(restored))
        try await Self.reverse(MutationName.redo, in: &session)
        #expect(Self.projection(of: session) == deleted)
    }

    @Test("undo with no txn takes the newest transaction of the session actor, not a newer one of a different actor")
    func undoTakesNewestTransactionOfSessionActor() async throws {
        let directory = try TemporaryDirectory()
        let step = UndoneStateTests.Step.original.rawValue
        let own = try UndoneStateTests.transaction(atStep: step)
        let other = try UndoneStateTests.transaction(atStep: step + 1, by: .actor(slug: AddUpdateTaskTests.alice))
        var session = try await ChangeBuilderTests.fixtureSession(inRepoAt: directory, writing: [own, other]).session
        let error = try await Self.failure(in: &session)
        #expect(error == .undoConflict(transaction: own.txn.ulidString, laterTransactions: [other.txn.ulidString]))
    }

    @Test("After a union merge of two branches, undo and redo with no txn take their targets from both branches")
    func undoAfterMergeTakesTargetsOfBothBranches() async throws {
        let directory = try TemporaryDirectory()
        typealias Step = UndoneStateTests.MergeStep
        let mainOriginal = try UndoneStateTests.transaction(atStep: Step.mainOriginal.rawValue)
        let branchOriginal = try UndoneStateTests.transaction(atStep: Step.branchOriginal.rawValue)
        let mainUndo = try UndoneStateTests.transaction(atStep: Step.mainUndo.rawValue, undoing: mainOriginal.txn)
        let branchUndo = try UndoneStateTests.transaction(
            atStep: Step.branchUndo.rawValue,
            undoing: branchOriginal.txn
        )
        let branchRedo = try UndoneStateTests.transaction(atStep: Step.branchRedo.rawValue, undoing: branchUndo.txn)
        let merged = [branchOriginal, branchUndo, branchRedo, mainOriginal, mainUndo]
        var session = try await ChangeBuilderTests.fixtureSession(inRepoAt: directory, writing: merged).session
        let error = try await Self.failure(in: &session)
        let expected = KanbanError.undoConflict(
            transaction: branchOriginal.txn.ulidString,
            laterTransactions: [mainUndo.txn.ulidString]
        )
        #expect(error == expected)
        let redo = try await Self.reverse(MutationName.redo, in: &session)
        #expect(redo["undoes"] == .string(mainUndo.txn.ulidString))
    }

    // MARK: - Side effects

    @Test("undo of addTask that made a tag as a side effect makes a tombstone of the task and of the tag")
    func undoAddTaskRemovesSideEffectTag() async throws {
        let directory = try TemporaryDirectory()
        var session = try await ChangeBuilderTests.baseSession(inRepoAt: directory).session
        let earlier = Self.projection(of: session)
        try await HistoryTests.run(eachOf: [Self.addTaskTagged(TaskOperationTests.feature)], in: &session)
        try await Self.reverse(in: &session)
        let added = Self.addedNodes(of: session, since: earlier)
        #expect(Set(added.keys.map(\.nodeType)) == [.task, .tag])
        Self.expectProjection(of: session, restoring: earlier)
    }

    @Test("undo of a call with addTask that made a tag and addTag makes a tombstone of both tags")
    func undoAddTaskAndAddTagRemovesBothTags() async throws {
        let directory = try TemporaryDirectory()
        var session = try await ChangeBuilderTests.baseSession(inRepoAt: directory).session
        let earlier = Self.projection(of: session)
        let fields = [Self.addTaskTagged(TaskOperationTests.feature), TagMutationTests.addTag(named: Self.chore)]
        try await ChangeBuilderTests.run("mutation { \(fields.joined(separator: " ")) }", in: &session)
        try await Self.reverse(in: &session)
        let tags = Self.addedNodes(of: session, since: earlier).keys.filter { ref in ref.nodeType == .tag }
        #expect(Set(tags) == [.tag(slug: TaskOperationTests.feature), .tag(slug: Self.chore)])
        Self.expectProjection(of: session, restoring: earlier)
    }

    @Test("undo of moveTask to a new column moves the task back and makes a tombstone of the column")
    func undoMoveToNewColumnRemovesColumn() async throws {
        let directory = try TemporaryDirectory()
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let earlier = Self.projection(of: session)
        let refs = ChangeBuilderTests.refs(of: base.task, in: session)
        let move = ChangeBuilderTests.moveField(of: refs, to: TaskOperationTests.newColumnSlug)
        try await HistoryTests.run(eachOf: [move], in: &session)
        try await Self.reverse(in: &session)
        let added = Self.addedNodes(of: session, since: earlier)
        #expect(Set(added.keys) == [.column(slug: TaskOperationTests.newColumnSlug)])
        Self.expectProjection(of: session, restoring: earlier)
    }

    @Test("undo of addTask whose #marker made a deleted tag live again makes a tombstone of the tag again")
    func undoAddTaskDeletesRestoredTag() async throws {
        let directory = try TemporaryDirectory()
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let refs = ChangeBuilderTests.refs(of: base.task, in: session)
        try await HistoryTests.run(eachOf: [ChangeBuilderTests.deleteBugField(refs)], in: &session)
        let earlier = Self.projection(of: session)
        try await HistoryTests.run(eachOf: [Self.addTaskMarking(TagMutationTests.bug)], in: &session)
        let restored = try #require(Self.projection(of: session)[.tag(slug: TagMutationTests.bug)])
        #expect(!Self.isTombstone(restored))
        try await Self.reverse(in: &session)
        Self.expectProjection(of: session, restoring: earlier)
    }

    // MARK: - New board

    @Test("undo of the first call on a new board keeps the board, the default columns, and the session actor")
    func undoFirstCallKeepsAutoInitNodes() async throws {
        let directory = try TemporaryDirectory()
        var session = try await CommitTests.makeSession(of: EventLog(repositoryAt: directory.url))
        try await HistoryTests.run(eachOf: [Self.addTaskTagged(TaskOperationTests.feature)], in: &session)
        try await Self.reverse(in: &session)
        Self.expectLive(BoardMutationTests.initializedRefs, in: session)
        let removed = Self.projection(of: session).filter { _, fields in Self.isTombstone(fields) }
        #expect(Set(removed.keys.map(\.nodeType)) == [.task, .tag])
    }

    @Test("undo of the first call after a later call by the same session actor gives no UNDO_CONFLICT")
    func undoFirstCallAfterLaterCallBySameActor() async throws {
        let directory = try TemporaryDirectory()
        var session = try await CommitTests.makeSession(of: EventLog(repositoryAt: directory.url))
        let first = try await Self.transaction(running: Self.addTaskTagged(TaskOperationTests.feature), in: &session)
        try await HistoryTests.run(eachOf: [Self.addTaskTagged(Self.chore)], in: &session)
        try await Self.reverse(with: Self.txnInput(first), in: &session)
        Self.expectLive(BoardMutationTests.initializedRefs, in: session)
    }

    // MARK: - Conflicts

    @Test("undo of addTag after a later task used the tag gives UNDO_CONFLICT with the later transaction")
    func undoAddTagAfterLaterUseConflicts() async throws {
        let directory = try TemporaryDirectory()
        var session = try await ChangeBuilderTests.baseSession(inRepoAt: directory).session
        let addTag = try await Self.transaction(
            running: TagMutationTests.addTag(named: TaskOperationTests.feature),
            in: &session
        )
        let addTask = AddUpdateTaskTests.addTask(with: TaskOperationTests.tagsInput(TaskOperationTests.feature))
        let use = try await Self.transaction(running: addTask, in: &session)
        let error = try await Self.failure(with: Self.txnInput(addTag), in: &session)
        #expect(error == .undoConflict(transaction: addTag.ulidString, laterTransactions: [use.ulidString]))
    }

    @Test("undo of addTask that made a tag, after a later task used the tag, gives UNDO_CONFLICT")
    func undoAddTaskAfterLaterUseOfSideEffectTagConflicts() async throws {
        let directory = try TemporaryDirectory()
        var session = try await ChangeBuilderTests.baseSession(inRepoAt: directory).session
        let addTask = Self.addTaskTagged(TaskOperationTests.feature)
        let first = try await Self.transaction(running: addTask, in: &session)
        let use = try await Self.transaction(running: addTask, in: &session)
        let error = try await Self.failure(with: Self.txnInput(first), in: &session)
        #expect(error == .undoConflict(transaction: first.ulidString, laterTransactions: [use.ulidString]))
    }

    @Test("undo of addTask that made a deleted tag live again, after a later task used the tag, gives UNDO_CONFLICT")
    func undoAddTaskAfterLaterUseOfRestoredTagConflicts() async throws {
        let directory = try TemporaryDirectory()
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let refs = ChangeBuilderTests.refs(of: base.task, in: session)
        try await HistoryTests.run(eachOf: [ChangeBuilderTests.deleteBugField(refs)], in: &session)
        let restore = try await Self.transaction(running: Self.addTaskMarking(TagMutationTests.bug), in: &session)
        let use = try await Self.transaction(running: Self.addTaskTagged(TagMutationTests.bug), in: &session)
        let error = try await Self.failure(with: Self.txnInput(restore), in: &session)
        #expect(error == .undoConflict(transaction: restore.ulidString, laterTransactions: [use.ulidString]))
    }

    @Test("undo after a later change to the same property gives UNDO_CONFLICT with the later transaction")
    func undoAfterLaterChangeOfPropertyConflicts() async throws {
        let directory = try TemporaryDirectory()
        let calls = try await Self.twoTitleCalls(inRepoAt: directory)
        var session = calls.session
        let error = try await Self.failure(with: Self.txnInput(calls.first), in: &session)
        let expected = KanbanError.undoConflict(
            transaction: calls.first.ulidString,
            laterTransactions: [calls.second.ulidString]
        )
        #expect(error == expected)
    }

    @Test("undo that gives UNDO_CONFLICT writes nothing")
    func undoConflictWritesNothing() async throws {
        let directory = try TemporaryDirectory()
        let calls = try await Self.twoTitleCalls(inRepoAt: directory)
        var session = calls.session
        let events = session.live.events
        _ = try await Self.failure(with: Self.txnInput(calls.first), in: &session)
        #expect(session.live.events == events)
    }

    @Test("undo with force after a later change to the same property writes the inverse anyway")
    func forcedUndoWritesInverse() async throws {
        let directory = try TemporaryDirectory()
        let calls = try await Self.twoTitleCalls(inRepoAt: directory)
        var session = calls.session
        try await Self.reverse(with: Self.txnInput(calls.first, forcing: true), in: &session)
        #expect(try CommitTests.title(of: .task(calls.task), in: session) == KanbanGraphTests.taskTitle)
    }

    @Test("undo of addColumn after a task moved into the column gives UNDO_CONFLICT with the later transaction")
    func undoAddColumnAfterLaterEdgeConflicts() async throws {
        let directory = try TemporaryDirectory()
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let setup = try Self.newestTransaction(of: session)
        let refs = ChangeBuilderTests.refs(of: base.task, in: session)
        let move = ChangeBuilderTests.moveField(of: refs, to: TaskOperationTests.doneSlug)
        let moved = try await Self.transaction(running: move, in: &session)
        let error = try await Self.failure(with: Self.txnInput(setup), in: &session)
        #expect(error == .undoConflict(transaction: setup.ulidString, laterTransactions: [moved.ulidString]))
    }

    @Test("undo of addColumn with force, after a task moved into the column, gives COLUMN_NOT_EMPTY")
    func forcedUndoOfAddColumnWithTaskGivesColumnNotEmpty() async throws {
        let directory = try TemporaryDirectory()
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let setup = try Self.newestTransaction(of: session)
        let refs = ChangeBuilderTests.refs(of: base.task, in: session)
        let move = ChangeBuilderTests.moveField(of: refs, to: TaskOperationTests.doneSlug)
        try await HistoryTests.run(eachOf: [move], in: &session)
        let error = try await Self.failure(with: Self.txnInput(setup, forcing: true), in: &session)
        #expect(error == .columnNotEmpty(column: TaskOperationTests.doneSlug, liveTaskCount: 1))
    }

    // MARK: - Body

    @Test("undo of a body change after a later change to other lines reverses only the first change")
    func undoBodyAfterLaterChangeToOtherLines() async throws {
        let directory = try TemporaryDirectory()
        let base = try await ChangeBuilderTests.baseSession(inRepoAt: directory)
        var session = base.session
        let task = base.task
        try await HistoryTests.run(eachOf: [Self.bodyField(Self.bodyLines, of: task)], in: &session)
        let firstLines = Self.lines(Self.bodyLines, changing: .zero, to: Self.changedLine)
        let first = try await Self.transaction(running: Self.bodyField(firstLines, of: task), in: &session)
        let lastIndex = Self.bodyLines.count - 1
        let bothLines = Self.lines(firstLines, changing: lastIndex, to: Self.laterChangedLine)
        try await HistoryTests.run(eachOf: [Self.bodyField(bothLines, of: task)], in: &session)
        try await Self.reverse(with: Self.txnInput(first), in: &session)
        let expected = Self.lines(Self.bodyLines, changing: lastIndex, to: Self.laterChangedLine)
        #expect(try CommitTests.field(\.fields.body, of: .task(task), in: session) == Self.text(of: expected))
    }

    @Test("undo of a body change whose reversed diff does not apply gives UNDO_CONFLICT with the later transaction")
    func undoBodyThatDoesNotApplyConflicts() async throws {
        let directory = try TemporaryDirectory()
        let calls = try await Self.twoChangesOfOneLine(inRepoAt: directory)
        var session = calls.session
        let error = try await Self.failure(with: Self.txnInput(calls.first), in: &session)
        let expected = KanbanError.undoConflict(
            transaction: calls.first.ulidString,
            laterTransactions: [calls.second.ulidString]
        )
        #expect(error == expected)
    }

    @Test("undo with force of a body change whose reversed diff does not apply gives the body before the change")
    func forcedUndoOfBodyGivesBodyBeforeChange() async throws {
        let directory = try TemporaryDirectory()
        let calls = try await Self.twoChangesOfOneLine(inRepoAt: directory)
        var session = calls.session
        try await Self.reverse(with: Self.txnInput(calls.first, forcing: true), in: &session)
        let body = try CommitTests.field(\.fields.body, of: .task(calls.task), in: session)
        #expect(body == Self.text(of: Self.bodyLines))
    }

    // MARK: - Nothing to undo

    @Test("undo on a board with no transaction gives NOTHING_TO_UNDO")
    func undoWithNoTransactionGivesNothingToUndo() async throws {
        let directory = try TemporaryDirectory()
        var session = try await CommitTests.makeSession(of: EventLog(repositoryAt: directory.url))
        #expect(try await Self.failure(in: &session) == .nothingToUndo)
    }

    @Test("redo on a board with no undo transaction gives NOTHING_TO_UNDO")
    func redoWithNoUndoGivesNothingToUndo() async throws {
        let directory = try TemporaryDirectory()
        var session = try await ChangeBuilderTests.baseSession(inRepoAt: directory).session
        #expect(try await Self.failure(of: MutationName.redo, in: &session) == .nothingToUndo)
    }

    @Test(
        "undo(txn:) of a transaction that is already undone gives NOTHING_TO_UNDO and writes nothing, also with force",
        arguments: [false, true]
    )
    func undoOfUndoneTransactionGivesNothingToUndo(isForced: Bool) async throws {
        let directory = try TemporaryDirectory()
        let calls = try await Self.twoTitleCalls(inRepoAt: directory)
        var session = calls.session
        try await Self.reverse(with: Self.txnInput(calls.second), in: &session)
        // A later call changes the title again, so a second inverse of the second call would change the title.
        try await HistoryTests.run(eachOf: [Self.titleField(KanbanGraphTests.taskTitle, of: calls.task)], in: &session)
        let events = session.live.events
        let error = try await Self.failure(with: Self.txnInput(calls.second, forcing: isForced), in: &session)
        #expect(error == .nothingToUndo)
        #expect(session.live.events == events)
    }

    @Test(
        "redo(txn:) of a transaction that is not undone gives NOTHING_TO_UNDO and writes nothing, also with force",
        arguments: [false, true]
    )
    func redoOfTransactionNotUndoneGivesNothingToUndo(isForced: Bool) async throws {
        let directory = try TemporaryDirectory()
        let calls = try await Self.twoTitleCalls(inRepoAt: directory)
        var session = calls.session
        let events = session.live.events
        let input = Self.txnInput(calls.second, forcing: isForced)
        let error = try await Self.failure(of: MutationName.redo, with: input, in: &session)
        #expect(error == .nothingToUndo)
        #expect(session.live.events == events)
    }

    @Test("redo(txn:) takes the original transaction, and reverses the undo of that transaction")
    func redoOfUndoneTransactionReversesItsUndo() async throws {
        let directory = try TemporaryDirectory()
        let calls = try await Self.twoTitleCalls(inRepoAt: directory)
        var session = calls.session
        let undo = try await Self.reverse(with: Self.txnInput(calls.second), in: &session)
        let redo = try await Self.reverse(MutationName.redo, with: Self.txnInput(calls.second), in: &session)
        #expect(redo["undoes"] == undo["txn"])
        #expect(try CommitTests.title(of: .task(calls.task), in: session) == Self.secondTitle)
    }

    // MARK: - Schema

    @Test("The Mutation type has undo and redo, with the UndoInput input and the Change result")
    func schemaHasUndoAndRedo() {
        let sdl = KanbanGraph.schemaSDL
        let lines = [
            "  undo(input: UndoInput): Change",
            "  redo(input: UndoInput): Change",
            "input UndoInput {",
            "  txn: ID",
            "  force: Boolean",
        ]
        for line in lines {
            #expect(sdl.contains(line), "\(line)")
        }
    }
}
