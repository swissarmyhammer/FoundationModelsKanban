import Foundation
import GraphQL
import Graphiti
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the change model (plan.md §4.1, §5.3 step 5, §6.7): the `Change` of one transaction, with one `NodeUpdate`
/// for each node that the transaction changed, and the `FieldChange` values of each update.
///
/// Each test writes the fixture logs of ``KanbanGraphTests`` (the board, the column `todo`, and one task in `todo`),
/// and runs ``baseSetup`` in a commit session of the board. Then a test runs the setup of its case, and one
/// transaction. The test keeps a copy of the session from before the transaction, so that it can query the board
/// before and after the transaction.
@Suite("Change model: NodeUpdate and FieldChange")
struct ChangeBuilderTests {
    /// The refs that the fields of a mutation case name: the fixture task, and the first comment of the board.
    struct CaseRefs: Sendable {
        /// The ULID of the fixture task.
        let task: ULID

        /// The `^` ref of the first comment of the board, live or tombstoned, or `""` when the board has no comment.
        let comment: String
    }

    /// One public mutation of the change test: the setup fields, the field of the transaction, and the updates of the
    /// patched nodes that the transaction must give.
    struct MutationCase: Sendable, CustomTestStringConvertible {
        /// The name of the case: the name of the mutation, and the variant.
        let testDescription: String

        /// The mutation fields that run before the transaction, each one in its own call, in order.
        let setup: [@Sendable (CaseRefs) -> String]

        /// The mutation field of the transaction.
        let field: @Sendable (CaseRefs) -> String

        /// The type and the kind of each update of a patched node of the transaction, in sorted order.
        let updates: [String]

        /// Makes a case.
        ///
        /// - Parameters:
        ///   - name: The name of the case.
        ///   - setup: The mutation fields that run before the transaction.
        ///   - field: The mutation field of the transaction.
        ///   - updates: The type and the kind of each update of a patched node of the transaction.
        init(
            _ name: String,
            after setup: [@Sendable (CaseRefs) -> String] = [],
            running field: @escaping @Sendable (CaseRefs) -> String,
            changing updates: [(NodeType, UpdateKind)]
        ) {
            testDescription = name
            self.setup = setup
            self.field = field
            self.updates = updates.map(ChangeBuilderTests.signature).sorted()
        }
    }

    /// One transaction of a test: the session before it and after it, its events, and its change.
    struct Recorded {
        /// The temporary repo directory. The value holds it, so that the repo stays on disk while the test runs.
        let directory: TemporaryDirectory

        /// The commit session before the transaction.
        let before: CommitSession

        /// The commit session after the transaction.
        let after: CommitSession

        /// The events of the transaction, in the order of their ids.
        let events: [Event]

        /// The change of the transaction.
        let change: Change
    }

    /// The current key of the fixture board.
    static let boardKey = KanbanGraphTests.boardKey.description

    /// The mutation that each test runs before its case: a terminal column after `todo`, so that the fixture task is
    /// not done, the actors `alice` and `bob`, and the tag `bug`. The call also writes the session actor.
    static let baseSetup = AddUpdateTaskTests.mutation(
        of: AddUpdateTaskTests.doneColumn,
        AddUpdateTaskTests.addActors,
        TagMutationTests.addTag(named: TagMutationTests.bug)
    )

    /// The name of an actor that only the `addActor` case adds.
    static let carol = "Carol"

    /// The new title of the fixture task in the `updateTask` case.
    static let newTitle = "Port the lexer"

    /// The new body of the fixture task in the `updateTask` case: one checked item.
    static let checkedBody = #"- [x] read the grammar\n"#

    /// The fields of a task whose value is one node, a list of nodes, or an object. A query selects these sub fields,
    /// so that the response has the same values as a field change.
    static let selections = [
        "column": "column { id }",
        "task": "task { id }",
        "author": "author { id }",
        "assignees": "assignees { id }",
        "tags": "tags { id }",
        "dependsOn": "dependsOn { id }",
        "blockedBy": "blockedBy { id }",
        "blocks": "blocks { id }",
        "progress": "progress { completed fraction total }",
        "summary": "summary { blocked done percent ready total }",
    ]

    /// The fields whose value is a list: a field change gives `added` and `removed`.
    static let listFields: Set<String> = ["assignees", "tags", "dependsOn", "blockedBy", "blocks", "virtualTags"]

    /// The name of the body field: a field change gives only `diff`.
    static let bodyField = "body"

    // MARK: - Cases

    /// Each public mutation of plan.md §4.2, with the updates of the patched nodes that it gives on the fixture board.
    static let mutationCases: [MutationCase] = taskCases + columnActorCases + tagCases + commentCases

    /// The board and the task mutations.
    static let taskCases: [MutationCase] = [
        MutationCase(
            "initBoard",
            running: { _ in #"initBoard(input: { name: "\#(newTitle)" }) { id }"# },
            changing: [(.board, .updated)]
        ),
        MutationCase(
            "updateBoard",
            running: { _ in #"updateBoard(input: { body: "\#(checkedBody)" }) { id }"# },
            changing: [(.board, .updated)]
        ),
        MutationCase(
            "addTask",
            running: { refs in AddUpdateTaskTests.addTask(with: AddUpdateTaskTests.dependsOn(refs.task)) },
            changing: [(.task, .created)]
        ),
        MutationCase(
            "updateTask",
            running: { refs in
                AddUpdateTaskTests.updateTask(refs.task, with: #"title: "\#(newTitle)", body: "\#(checkedBody)""#)
            },
            changing: [(.task, .updated)]
        ),
        MutationCase(
            "moveTask",
            running: { refs in moveField(of: refs, to: TaskOperationTests.doneSlug) },
            changing: [(.task, .updated)]
        ),
        MutationCase(
            "moveTask to a new column",
            running: { refs in moveField(of: refs, to: TaskOperationTests.newColumnSlug) },
            changing: [(.column, .created), (.task, .updated)]
        ),
        MutationCase(
            "completeTask",
            running: { refs in TaskOperationTests.taskField("completeTask", of: refs.task) },
            changing: [(.task, .updated)]
        ),
        MutationCase("assignTask", running: assignField, changing: [(.task, .updated)]),
        MutationCase(
            "unassignTask",
            after: [assignField],
            running: { refs in
                TaskOperationTests.taskField("unassignTask", of: refs.task, with: TaskOperationTests.aliceInput)
            },
            changing: [(.task, .updated)]
        ),
        MutationCase("tagTask", running: { refs in tagField(of: refs) }, changing: [(.task, .updated)]),
        MutationCase(
            "tagTask with a new tag",
            running: { refs in tagField(of: refs, naming: TaskOperationTests.feature) },
            changing: [(.tag, .created), (.task, .updated)]
        ),
        MutationCase(
            "untagTask",
            after: [{ refs in tagField(of: refs) }],
            running: { refs in tagField(of: refs, as: "untagTask") },
            changing: [(.task, .updated)]
        ),
        MutationCase("deleteTask", running: deleteTaskField, changing: [(.task, .deleted)]),
        MutationCase(
            "undeleteTask",
            after: [deleteTaskField],
            running: { refs in TaskOperationTests.taskField("undeleteTask", of: refs.task) },
            changing: [(.task, .restored)]
        ),
    ]

    /// The column and the actor mutations.
    static let columnActorCases: [MutationCase] = [
        MutationCase("addColumn", running: { _ in ColumnActorTests.addQA }, changing: [(.column, .created)]),
        MutationCase(
            "updateColumn",
            running: { _ in
                CommentTests.nodeField("updateColumn", naming: TaskOperationTests.todoSlug, with: #"name: "Backlog""#)
            },
            changing: [(.column, .updated)]
        ),
        MutationCase("deleteColumn", running: deleteDoneField, changing: [(.column, .deleted)]),
        MutationCase(
            "undeleteColumn",
            after: [deleteDoneField],
            running: { _ in CommentTests.nodeField("undeleteColumn", naming: TaskOperationTests.doneSlug) },
            changing: [(.column, .restored)]
        ),
        MutationCase(
            "addActor",
            running: { _ in #"addActor(input: { name: "\#(carol)" }) { id }"# },
            changing: [(.actor, .created)]
        ),
        MutationCase(
            "updateActor",
            running: { _ in
                let color = #"color: "\#(ColumnActorTests.red)""#
                return CommentTests.nodeField("updateActor", naming: AddUpdateTaskTests.alice, with: color)
            },
            changing: [(.actor, .updated)]
        ),
        MutationCase("deleteActor", running: deleteAliceField, changing: [(.actor, .deleted)]),
        MutationCase(
            "undeleteActor",
            after: [deleteAliceField],
            running: { _ in CommentTests.nodeField("undeleteActor", naming: AddUpdateTaskTests.alice) },
            changing: [(.actor, .restored)]
        ),
    ]

    /// The tag mutations.
    static let tagCases: [MutationCase] = [
        MutationCase(
            "addTag",
            running: { _ in TagMutationTests.addTag(named: TaskOperationTests.feature) },
            changing: [(.tag, .created)]
        ),
        MutationCase(
            "updateTag",
            running: { _ in
                CommentTests.nodeField("updateTag", naming: TagMutationTests.bug, with: TagMutationTests.greenInput)
            },
            changing: [(.tag, .updated)]
        ),
        MutationCase("deleteTag", running: deleteBugField, changing: [(.tag, .deleted)]),
        MutationCase(
            "undeleteTag",
            after: [deleteBugField],
            running: { _ in CommentTests.nodeField("undeleteTag", naming: TagMutationTests.bug) },
            changing: [(.tag, .restored)]
        ),
        MutationCase("renameTag", running: renameBugField, changing: [(.tag, .created), (.tag, .updated)]),
    ]

    /// The comment mutations.
    static let commentCases: [MutationCase] = [
        MutationCase("addComment", running: addCommentField, changing: [(.comment, .created)]),
        MutationCase(
            "updateComment",
            after: [addCommentField],
            running: { refs in
                let body = #"body: "\#(CommentTests.editedBody)""#
                return CommentTests.nodeField(MutationName.updateComment, naming: refs.comment, with: body)
            },
            changing: [(.comment, .updated)]
        ),
        MutationCase(
            "deleteComment",
            after: [addCommentField],
            running: deleteCommentField,
            changing: [(.comment, .deleted)]
        ),
        MutationCase(
            "undeleteComment",
            after: [addCommentField, deleteCommentField],
            running: { refs in CommentTests.nodeField(MutationName.undeleteComment, naming: refs.comment) },
            changing: [(.comment, .restored)]
        ),
    ]

    /// The case that completes the fixture task while a second task depends on it.
    static let completeWithDependent = MutationCase(
        "completeTask with a dependent task",
        after: [{ refs in AddUpdateTaskTests.addTask(with: AddUpdateTaskTests.dependsOn(refs.task)) }],
        running: { refs in TaskOperationTests.taskField("completeTask", of: refs.task) },
        changing: [(.task, .updated)]
    )

    /// The case that renames the tag `bug` of the fixture task.
    static let renameWithTaggedTask = MutationCase(
        "renameTag with a tagged task",
        after: [{ refs in tagField(of: refs) }],
        running: renameBugField,
        changing: [(.tag, .created), (.tag, .updated)]
    )

    // MARK: - Fields

    /// Makes the `assignTask` field that assigns `alice` to the fixture task.
    ///
    /// - Parameter refs: The refs of the case.
    /// - Returns: The field.
    @Sendable
    static func assignField(_ refs: CaseRefs) -> String {
        TaskOperationTests.taskField("assignTask", of: refs.task, with: TaskOperationTests.aliceInput)
    }

    /// Makes the `deleteTask` field of the fixture task.
    ///
    /// - Parameter refs: The refs of the case.
    /// - Returns: The field.
    @Sendable
    static func deleteTaskField(_ refs: CaseRefs) -> String {
        TaskOperationTests.taskField("deleteTask", of: refs.task)
    }

    /// Makes the `deleteColumn` field of the empty column `done`.
    ///
    /// The field does not read the refs of the case, so the parameter has no name.
    ///
    /// - Returns: The field.
    @Sendable
    static func deleteDoneField(_: CaseRefs) -> String {
        CommentTests.nodeField("deleteColumn", naming: TaskOperationTests.doneSlug)
    }

    /// Makes the `deleteActor` field of `alice`.
    ///
    /// The field does not read the refs of the case, so the parameter has no name.
    ///
    /// - Returns: The field.
    @Sendable
    static func deleteAliceField(_: CaseRefs) -> String {
        CommentTests.nodeField("deleteActor", naming: AddUpdateTaskTests.alice)
    }

    /// Makes the `deleteTag` field of `bug`.
    ///
    /// The field does not read the refs of the case, so the parameter has no name.
    ///
    /// - Returns: The field.
    @Sendable
    static func deleteBugField(_: CaseRefs) -> String {
        CommentTests.nodeField("deleteTag", naming: TagMutationTests.bug)
    }

    /// Makes the `renameTag` field that renames `bug` to `defect`.
    ///
    /// The field does not read the refs of the case, so the parameter has no name.
    ///
    /// - Returns: The field.
    @Sendable
    static func renameBugField(_: CaseRefs) -> String {
        TagMutationTests.renameTag(from: TagMutationTests.bug, to: TagMutationTests.defect)
    }

    /// Makes the `addComment` field on the fixture task.
    ///
    /// - Parameter refs: The refs of the case.
    /// - Returns: The field.
    @Sendable
    static func addCommentField(_ refs: CaseRefs) -> String {
        CommentTests.addComment(to: AddUpdateTaskTests.sigilRef(of: refs.task))
    }

    /// Makes the `deleteComment` field of the first comment of the board.
    ///
    /// - Parameter refs: The refs of the case.
    /// - Returns: The field.
    @Sendable
    static func deleteCommentField(_ refs: CaseRefs) -> String {
        CommentTests.nodeField(MutationName.deleteComment, naming: refs.comment)
    }

    /// Makes a `moveTask` field of the fixture task.
    ///
    /// - Parameters:
    ///   - refs: The refs of the case.
    ///   - column: The column slug.
    /// - Returns: The field.
    static func moveField(of refs: CaseRefs, to column: String) -> String {
        TaskOperationTests.taskField("moveTask", of: refs.task, with: TaskOperationTests.moveInput(to: column))
    }

    /// Makes a `tagTask` or an `untagTask` field of the fixture task with one tag.
    ///
    /// - Parameters:
    ///   - refs: The refs of the case.
    ///   - tag: The tag slug. The default is `bug`.
    ///   - name: The name of the mutation. The default is `tagTask`.
    /// - Returns: The field.
    static func tagField(
        of refs: CaseRefs,
        naming tag: String = TagMutationTests.bug,
        as name: String = "tagTask"
    ) -> String {
        TaskOperationTests.taskField(name, of: refs.task, with: TaskOperationTests.tagsInput(tag))
    }

    // MARK: - Helpers

    /// Gives the text of the type and the kind of an update, for example `TASK UPDATED`.
    ///
    /// - Parameters:
    ///   - type: The node type.
    ///   - kind: The kind of the update.
    /// - Returns: The text.
    static func signature(_ type: NodeType, _ kind: UpdateKind) -> String {
        "\(type.rawValue) \(kind.rawValue)"
    }

    /// Gives the read view of the live graph of a session.
    ///
    /// - Parameter session: The commit session.
    /// - Returns: The read view.
    static func view(of session: CommitSession) -> BoardView {
        BoardView(of: session.live.graph, inBoard: boardKey)
    }

    /// Gives a context whose store holds the live graph of a session.
    ///
    /// - Parameter session: The commit session.
    /// - Returns: The context.
    static func context(of session: CommitSession) -> KanbanContext {
        CommitTests.callContext(of: BoardStore.fixture(of: session.live.graph, inBoard: boardKey))
    }

    /// Runs one document in a session, and expects that it gives no error.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - session: The commit session.
    /// - Returns: The result of the document.
    @discardableResult
    static func run(_ document: String, in session: inout CommitSession) async throws -> GraphQLResult {
        let result = try await ColumnActorTests.result(of: document, in: &session)
        #expect(result.errors.isEmpty, "\(document) gave \(result.errors)")
        return result
    }

    /// Writes the fixture logs of ``KanbanGraphTests`` to a repo, and loads a new commit session of the board.
    ///
    /// - Parameters:
    ///   - directory: The temporary repo directory.
    ///   - events: The events to append to the logs after the fixture, before the session loads the board.
    /// - Returns: The session, and the ULID of the fixture task.
    static func fixtureSession(
        inRepoAt directory: TemporaryDirectory,
        writing events: [Event] = []
    ) async throws -> (session: CommitSession, task: ULID) {
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let log = EventLog(repositoryAt: directory.url)
        for event in events {
            try log.append(contentsOf: [event], toLogOf: event.patch.node)
        }
        return (try await CommitTests.makeSession(of: log), task)
    }

    /// Writes the fixture logs of ``KanbanGraphTests`` to a repo, loads a new commit session of the board, and runs
    /// ``baseSetup`` in it.
    ///
    /// - Parameters:
    ///   - directory: The temporary repo directory.
    ///   - events: The events to append to the logs after the fixture, before the session loads the board.
    /// - Returns: The session, and the ULID of the fixture task.
    static func baseSession(
        inRepoAt directory: TemporaryDirectory,
        writing events: [Event] = []
    ) async throws -> (session: CommitSession, task: ULID) {
        let fixture = try await fixtureSession(inRepoAt: directory, writing: events)
        var session = fixture.session
        try await run(baseSetup, in: &session)
        return (session, fixture.task)
    }

    /// Gives the refs of a case in the live graph of a session.
    ///
    /// - Parameters:
    ///   - task: The ULID of the fixture task.
    ///   - session: The commit session.
    /// - Returns: The refs.
    static func refs(of task: ULID, in session: CommitSession) -> CaseRefs {
        let graph = session.live.graph
        let comment = graph.allSlots.lazy.compactMap { slot in graph.node(at: slot, as: CommentNode.self) }.first
        return CaseRefs(task: task, comment: comment.map { node in AddUpdateTaskTests.sigilRef(of: node.id) } ?? "")
    }

    /// Runs the base setup and the setup of a case in a new session of the fixture repo, then runs the transaction
    /// of the case.
    ///
    /// - Parameter mutationCase: The case.
    /// - Returns: The transaction.
    static func record(_ mutationCase: MutationCase) async throws -> Recorded {
        let directory = try TemporaryDirectory()
        let base = try await baseSession(inRepoAt: directory)
        let task = base.task
        var session = base.session
        for step in mutationCase.setup {
            try await run(AddUpdateTaskTests.mutation(of: step(refs(of: task, in: session))), in: &session)
        }
        let before = session
        let known = Set(session.live.events.map(\.id))
        try await run(AddUpdateTaskTests.mutation(of: mutationCase.field(refs(of: task, in: session))), in: &session)
        let events = session.live.events.filter { event in !known.contains(event.id) }
        let builder = ChangeBuilder(from: view(of: before), to: view(of: session))
        let change = try #require(builder.change(of: events, markingUndone: false))
        return Recorded(directory: directory, before: before, after: session, events: events, change: change)
    }

    /// Gives the updates of a transaction of the nodes that a patch of the transaction changed, or of the other nodes:
    /// the nodes whose fields changed because of a write to a different node.
    ///
    /// - Parameters:
    ///   - recorded: The transaction.
    ///   - isPatched: `true` for the updates of the patched nodes, `false` for the updates of the other nodes.
    /// - Returns: The updates, in the order of the change.
    static func updates(of recorded: Recorded, ofPatchedNodes isPatched: Bool) -> [NodeUpdate] {
        let patched = Set(recorded.events.map(\.patch.node))
        return recorded.change.nodeUpdates.filter { update in patched.contains(update.ref) == isPatched }
    }

    /// Gives the field change of an update with a name.
    ///
    /// - Parameters:
    ///   - name: The public field name.
    ///   - update: The update.
    /// - Returns: The field change.
    static func field(named name: String, in update: NodeUpdate) throws -> FieldChange {
        try #require(update.fields.first { field in field.name == name })
    }

    /// Gives the full URI of a node of the fixture board as a JSON value.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The JSON string.
    static func idValue(of ref: LocalRef) -> Map {
        .string(ColumnActorTests.id(of: ref))
    }

    // MARK: - Query compare

    /// Queries the node of an update in a session: the fields of the update, with the selection of ``selections``.
    ///
    /// - Parameters:
    ///   - update: The update.
    ///   - session: The commit session.
    /// - Returns: The JSON object of the node, or `null` when the board has no node with the id.
    static func queriedNode(of update: NodeUpdate, in session: CommitSession) async throws -> Map {
        let selection = update.fields.map { field in selections[field.name] ?? field.name }.joined(separator: " ")
        let type = update.ref.nodeType.rawValue
        let query = #"{ node(id: "\#(update.id.text)") { ... on \#(type) { \#(selection) } } }"#
        var copy = session
        let result = try await ColumnActorTests.result(of: query, in: &copy)
        return result.data?["node"] ?? .null
    }

    /// Gives a value of a query in the form of a field change: the id of a node object, the ids of a list of node
    /// objects, and each object in sorted key order.
    ///
    /// - Parameter value: The value of the query.
    /// - Returns: The value in the form of a field change.
    static func normalized(_ value: Map) -> Map {
        switch value {
        case .dictionary(let fields) where Array(fields.keys) == ["id"]:
            fields["id"] ?? .null
        case .array(let items):
            .array(items.map(normalized))
        default:
            JSONScalar.canonical(value)
        }
    }

    /// Gives the field change that the values of a query before and after a transaction give.
    ///
    /// - Parameters:
    ///   - name: The public field name.
    ///   - old: The value of the query before the transaction, `null` when the node did not exist.
    ///   - new: The value of the query after the transaction.
    /// - Returns: The field change.
    static func expectedChange(named name: String, from old: Map, to new: Map) -> FieldChange {
        if name == bodyField {
            let diff = UnifiedDiff(from: old.string ?? "", to: new.string ?? "").text
            return FieldChange(name: name, before: nil, after: nil, added: nil, removed: nil, diff: diff)
        }
        if listFields.contains(name) {
            let before = normalized(old).array ?? []
            let after = normalized(new).array ?? []
            let added = after.filter { item in !before.contains(item) }
            let removed = before.filter { item in !after.contains(item) }
            return FieldChange(name: name, before: nil, after: nil, added: added, removed: removed, diff: nil)
        }
        let before = normalized(old)
        let after = normalized(new)
        return FieldChange(
            name: name,
            before: before.isNull ? nil : before,
            after: after.isNull ? nil : after,
            added: nil,
            removed: nil,
            diff: nil
        )
    }

    /// Expects that each field change of a transaction equals the values of a query of the node before and after
    /// the transaction.
    ///
    /// - Parameter recorded: The transaction.
    static func expectFieldsEqualQueries(of recorded: Recorded) async throws {
        for update in recorded.change.nodeUpdates where !update.fields.isEmpty {
            let old = try await queriedNode(of: update, in: recorded.before)
            let new = try await queriedNode(of: update, in: recorded.after)
            for field in update.fields {
                let expected = expectedChange(named: field.name, from: old[field.name], to: new[field.name])
                #expect(field == expected, "\(update.id.text) \(field.name)")
            }
        }
    }

    // MARK: - Each public mutation

    @Test(
        "Each public mutation gives one update for each node that it changed, with the kind of the change",
        arguments: mutationCases
    )
    func mutationGivesPatchUpdates(mutationCase: MutationCase) async throws {
        let recorded = try await Self.record(mutationCase)
        let patchUpdates = Self.updates(of: recorded, ofPatchedNodes: true)
        let signatures = patchUpdates.map { update in Self.signature(update.type, update.kind) }
        #expect(signatures.sorted() == mutationCase.updates)
        #expect(Set(patchUpdates.map(\.ref)) == Set(recorded.events.map(\.patch.node)))
        let ids = recorded.change.nodeUpdates.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test(
        "Each field change of each public mutation equals the value of a query before and after the mutation",
        arguments: mutationCases
    )
    func fieldChangesEqualQueries(mutationCase: MutationCase) async throws {
        let recorded = try await Self.record(mutationCase)
        #expect(recorded.change.nodeUpdates.contains { update in !update.fields.isEmpty })
        try await Self.expectFieldsEqualQueries(of: recorded)
    }

    // MARK: - Envelope

    @Test("A Change has the txn, the time, the actor, the ops, and the board of its events, and is not undone")
    func changeHasEnvelopeOfEvents() async throws {
        let recorded = try await Self.record(try #require(Self.taskCases.first))
        let first = try #require(recorded.events.first)
        let change = recorded.change
        #expect(change.txn.text == first.txn.ulidString)
        #expect(change.at == CommitTests.callTime)
        #expect(change.actorRef == ReplayTests.actor)
        #expect(change.ops == [MutationName.initBoard])
        #expect(change.boards == [Self.boardKey])
        #expect(!change.undone)
        #expect(change.undoes == nil)
    }

    @Test("The body field change gives only the diff from the body before to the body after")
    func bodyChangeGivesOnlyDiff() async throws {
        let updateTask = try #require(Self.taskCases.first { $0.testDescription == "updateTask" })
        let recorded = try await Self.record(updateTask)
        let update = try #require(Self.updates(of: recorded, ofPatchedNodes: true).first)
        let body = try Self.field(named: Self.bodyField, in: update)
        let checked = "- [x] read the grammar\n"
        let expected = FieldChange(
            name: Self.bodyField,
            before: nil,
            after: nil,
            added: nil,
            removed: nil,
            diff: UnifiedDiff(from: "", to: checked).text
        )
        #expect(body == expected)
    }

    // MARK: - Updates of the nodes that no patch changed

    @Test("completeTask gives updates of ready, blockedBy, and virtualTags for a task that depends on it")
    func completeTaskUpdatesDependentTask() async throws {
        let recorded = try await Self.record(Self.completeWithDependent)
        let derived = Self.updates(of: recorded, ofPatchedNodes: false).filter { update in update.type == .task }
        let dependent = try #require(derived.first)
        #expect(derived.count == 1)
        #expect(dependent.kind == .updated)
        let task = try #require(recorded.events.first).patch.node
        let ready = FieldChange(name: "ready", before: false, after: true, added: nil, removed: nil, diff: nil)
        #expect(try Self.field(named: "ready", in: dependent) == ready)
        let blockedBy = FieldChange(
            name: "blockedBy",
            before: nil,
            after: nil,
            added: [],
            removed: [Self.idValue(of: task)],
            diff: nil
        )
        #expect(try Self.field(named: "blockedBy", in: dependent) == blockedBy)
        let virtualTags = FieldChange(
            name: "virtualTags",
            before: nil,
            after: nil,
            added: [.string(VirtualTag.ready.rawValue), .string(VirtualTag.high.rawValue)],
            removed: [.string(VirtualTag.blocked.rawValue), .string(VirtualTag.medium.rawValue)],
            diff: nil
        )
        #expect(try Self.field(named: "virtualTags", in: dependent) == virtualTags)
    }

    @Test("completeTask gives an update of the summary of the board")
    func completeTaskUpdatesBoardSummary() async throws {
        let recorded = try await Self.record(Self.completeWithDependent)
        let board = Self.updates(of: recorded, ofPatchedNodes: false).filter { update in update.type == .board }
        #expect(board.map { update in update.fields.map(\.name) } == [["summary"]])
        try await Self.expectFieldsEqualQueries(of: recorded)
    }

    @Test("renameTag gives a tags update of a task that has the old tag")
    func renameTagUpdatesTaskTags() async throws {
        let recorded = try await Self.record(Self.renameWithTaggedTask)
        let derived = Self.updates(of: recorded, ofPatchedNodes: false)
        let task = try #require(derived.first { update in update.type == .task })
        let tags = FieldChange(
            name: "tags",
            before: nil,
            after: nil,
            added: [Self.idValue(of: .tag(slug: TagMutationTests.defect))],
            removed: [Self.idValue(of: .tag(slug: TagMutationTests.bug))],
            diff: nil
        )
        #expect(task.fields == [tags])
    }

    // MARK: - Batches of transactions

    /// The refs that a batch case names: the fixture task, and a task that depends on it.
    struct BatchRefs: Sendable {
        /// The local ref of the fixture task.
        let task: LocalRef

        /// The local ref of the task that depends on the fixture task.
        let dependent: LocalRef
    }

    /// One batch of transactions that a different process writes, and the refs of the updates of each `Change` that
    /// the change feed makes of the batch.
    struct BatchCase: Sendable, CustomTestStringConvertible {
        /// What the case proves.
        let testDescription: String

        /// Gives the patch of each transaction of the batch, in order. Each patch is one transaction.
        let patches: @Sendable (BatchRefs) throws -> [PatchInput]

        /// Gives the local refs of the updates of each `Change` of the board of the batch, in the order of the
        /// transactions.
        let updates: @Sendable (BatchRefs) -> [[LocalRef]]

        /// Gives the local refs of the updates of each `Change` when the batch is of a different board, in the order
        /// of the transactions. All the updates are then derived updates.
        let otherBoardUpdates: @Sendable (BatchRefs) -> [[LocalRef]]
    }

    /// One batch that a test applied to a commit session.
    struct AppliedBatch {
        /// The temporary repo directory. The value holds it, so that the repo stays on disk while the test runs.
        let directory: TemporaryDirectory

        /// The refs of the case.
        let refs: BatchRefs

        /// The commit session before the batch.
        let before: CommitSession

        /// The commit session after the batch.
        let after: CommitSession

        /// The changes of the live graph that the batch added.
        let changes: [LiveGraphChange]
    }

    /// The cases of ``batchGivesEachUpdateToOneChange(batchCase:)`` and
    /// ``otherBoardBatchGivesUpdatesToLastChange(batchCase:)``.
    static let batchCases = [
        BatchCase(
            testDescription: "The derived updates of the first transaction go only to the Change of the last one",
            patches: { refs in
                let board = try PatchInput(node: .board, set: [PropertyName.name: .json(.string(newTitle))])
                return [try SubscriptionTests.donePatch(of: refs.task), board]
            },
            updates: { refs in [[refs.task], [.board, refs.dependent]] },
            otherBoardUpdates: { refs in [[], [.board, refs.task, refs.dependent]] }
        ),
        BatchCase(
            testDescription: "A node that two transactions patch has its update only in the Change of the last one",
            patches: { refs in
                let title = try ReplayTests.titlePatch(setting: newTitle, of: refs.task)
                return [title, try SubscriptionTests.donePatch(of: refs.task)]
            },
            updates: { refs in [[], [refs.task, .board, refs.dependent]] },
            otherBoardUpdates: { refs in [[], [.board, refs.task, refs.dependent]] }
        ),
    ]

    /// Gives the local ref of the task that depends on the fixture task.
    ///
    /// - Parameters:
    ///   - task: The ULID of the fixture task.
    ///   - session: The commit session. Its board has the fixture task and one more task.
    /// - Returns: The local ref of the other task.
    static func dependentRef(of task: ULID, in session: CommitSession) throws -> LocalRef {
        let graph = session.live.graph
        let refs = graph.allSlots.compactMap { slot in graph.node(at: slot)?.ref }
        return try #require(refs.first { ref in ref.nodeType == .task && ref != .task(task) })
    }

    /// Adds a task that depends on the fixture task, writes the transactions of a case to the logs as a different
    /// process writes them, and applies them to the session as one batch of the file watcher.
    ///
    /// - Parameter batchCase: The case.
    /// - Returns: The batch.
    static func applyBatch(of batchCase: BatchCase) async throws -> AppliedBatch {
        let directory = try TemporaryDirectory()
        var (session, task) = try await baseSession(inRepoAt: directory)
        let addDependent = AddUpdateTaskTests.addTask(with: AddUpdateTaskTests.dependsOn(task))
        try await run(AddUpdateTaskTests.mutation(of: addDependent), in: &session)
        let refs = BatchRefs(task: .task(task), dependent: try dependentRef(of: task, in: session))
        _ = session.takeLiveChanges()
        let before = session
        for (step, patch) in zip(LiveGraphApplyTests.laterStep..., try batchCase.patches(refs)) {
            _ = try LoaderTests.append(patch, atStep: step, to: session.live.log)
        }
        _ = try await session.apply(watchedPaths: [session.live.log.directory])
        let changes = session.takeLiveChanges()
        return AppliedBatch(directory: directory, refs: refs, before: before, after: session, changes: changes)
    }

    /// Gives the local refs of the updates of each change.
    ///
    /// - Parameter changes: The changes.
    /// - Returns: The local refs of the updates of each change, in order.
    static func updateRefs(of changes: [Change]) -> [[LocalRef]] {
        changes.map { change in change.nodeUpdates.map(\.ref) }
    }

    @Test("A batch of transactions gives each update to one Change only", arguments: batchCases)
    func batchGivesEachUpdateToOneChange(batchCase: BatchCase) async throws {
        let batch = try await Self.applyBatch(of: batchCase)
        let path = batch.directory.url.path
        let changed = try #require(BoardChanges(of: batch.after, changes: batch.changes))
        let round = ChangeRound(
            of: [path: changed],
            amongBoards: [path: batch.after],
            currentPath: path,
            reading: .loadable
        )
        let changes = round.changes(of: batch.after, atPath: path)
        #expect(Self.updateRefs(of: changes) == batchCase.updates(batch.refs))
    }

    @Test(
        "A batch of transactions of a different board gives the updates only to its last Change",
        arguments: batchCases
    )
    func otherBoardBatchGivesUpdatesToLastChange(batchCase: BatchCase) async throws {
        let batch = try await Self.applyBatch(of: batchCase)
        let undone = UndoneState(of: batch.after.live.events)
        let transactions = batch.changes.flatMap { change in
            BatchTransaction.grouping(change.events, inBoard: LoaderTests.remoteBoardKey, markingUndoneBy: undone)
        }
        let builder = ChangeBuilder(from: Self.view(of: batch.before), to: Self.view(of: batch.after))
        let changes = builder.changesOfOtherBoards(ofBatch: transactions)
        #expect(Self.updateRefs(of: changes) == batchCase.otherBoardUpdates(batch.refs))
    }

    // MARK: - Resolvers

    @Test("The actor of a Change made by an actor that was later deleted is the tombstone of the actor")
    func actorOfChangeIsTombstoneAfterDelete() async throws {
        let recorded = try await Self.record(try #require(Self.taskCases.first))
        var later = recorded.after
        let sessionActor = CommentTests.nodeField("deleteActor", naming: ColumnActorTests.id(of: ReplayTests.actor))
        try await Self.run(AddUpdateTaskTests.mutation(of: sessionActor), in: &later)
        let actor = try await recorded.change.actor(context: Self.context(of: later), arguments: NoArguments())
        #expect(actor.id.text == ColumnActorTests.id(of: ReplayTests.actor))
        #expect(actor.deleted == CommitTests.callTime)
    }

    @Test("The node of a DELETED update is the tombstone with deleted set")
    func deletedUpdateGivesTombstone() async throws {
        let deleteTask = try #require(Self.taskCases.first { $0.testDescription == "deleteTask" })
        let recorded = try await Self.record(deleteTask)
        let update = try #require(Self.updates(of: recorded, ofPatchedNodes: true).first)
        let node = try #require(await update.node(context: Self.context(of: recorded.after), arguments: NoArguments()))
        #expect(node.id == update.id)
        #expect(node.deleted == CommitTests.callTime)
    }

    /// Runs `Change.updates` of a transaction with a filter, in the board after the transaction.
    ///
    /// - Parameters:
    ///   - filter: The filter, or `nil` for no filter.
    ///   - recorded: The transaction.
    /// - Returns: The local refs of the updates that the field gives, in order.
    static func updateRefs(filteredBy filter: String?, of recorded: Recorded) async throws -> [LocalRef] {
        let context = context(of: recorded.after)
        let updates = try await recorded.change.updates(context: context, arguments: FilterArguments(filter: filter))
        return try #require(updates).map(\.ref)
    }

    @Test("Change.updates(filter: \"~board\") keeps only the updates of the node type, and no filter keeps each one")
    func updatesFilterByNodeType() async throws {
        let recorded = try await Self.record(Self.completeWithDependent)
        #expect(try await Self.updateRefs(filteredBy: "~board", of: recorded) == [.board])
        #expect(try await Self.updateRefs(filteredBy: nil, of: recorded) == recorded.change.nodeUpdates.map(\.ref))
    }

    @Test("Change.updates(filter: \"^id\") keeps the update of the node, and on a task also of its dependent tasks")
    func updatesFilterByRef() async throws {
        let recorded = try await Self.record(Self.completeWithDependent)
        let board = "^\(ColumnActorTests.id(of: .board))"
        #expect(try await Self.updateRefs(filteredBy: board, of: recorded) == [.board])
        let task = AddUpdateTaskTests.sigilRef(of: try AddUpdateTaskTests.fixtureTask())
        let tasks = recorded.change.nodeUpdates.filter { update in update.type == .task }.map(\.ref)
        #expect(tasks.count > 1)
        #expect(try await Self.updateRefs(filteredBy: task, of: recorded) == tasks)
    }

    // MARK: - Schema

    @Test("The public schema has the Change, NodeUpdate, and FieldChange types and their enums")
    func schemaHasChangeTypes() {
        let sdl = KanbanGraph.schemaSDL
        let lines = [
            "type Change {",
            "  actor: Actor!",
            "  updates(filter: String): [NodeUpdate!]",
            "type NodeUpdate {",
            "  kind: UpdateKind!",
            "  node: Node",
            "type FieldChange {",
            "  before: JSON",
            "  added: [JSON!]",
            "  diff: String",
            "enum NodeType {",
            "enum UpdateKind {",
        ]
        for line in lines {
            #expect(sdl.contains(line), "\(line)")
        }
        #expect(!sdl.contains("UpdateSource"))
        #expect(!sdl.contains("  source: "))
    }
}
