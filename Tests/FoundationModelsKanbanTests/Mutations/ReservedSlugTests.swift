import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the rule of the reserved slug `board` (plan.md §3.2): no mutation makes a column, an actor, or a tag with the
/// slug ``Slug/reservedForBoard``, because the URI `kanban://<board-key>/column/board` parses as the board URI of the
/// key `<board-key>/column`. A log that already has such a node still loads.
@Suite("The reserved slug board")
struct ReservedSlugTests {
    /// A name whose slug is the reserved slug. The name is in mixed case, because the rule ignores case.
    static let reservedName = "Board"

    /// An id whose slug is the reserved slug, in uppercase.
    static let reservedID = "BOARD"

    /// A name whose slug is not reserved, for a node that the input gives an id.
    static let legalName = "Main"

    /// The order of the column with the reserved slug in the old log: after the fixture column `todo`.
    static let oldColumnOrder = 1

    /// One mutation field that makes a column, an actor, or a tag with the reserved slug. ``field(on:naming:id:)``
    /// can also give a different name or id, for example the name of a virtual tag (``VirtualTagNameTests``).
    enum Refusal: CaseIterable, Sendable {
        /// `addColumn` with a name that gives the reserved slug.
        case addColumnByName

        /// `addColumn` with an id that gives the reserved slug.
        case addColumnByID

        /// `moveTask` to a column slug that no column has, so that the move makes the column.
        case moveTaskToNewColumn

        /// `addActor` with a name that gives the reserved slug.
        case addActorByName

        /// `addActor` with an id that gives the reserved slug.
        case addActorByID

        /// `addActor` with `ensure: true` on an actor that the board does not have.
        case addActorEnsure

        /// `addComment` with an author name that no actor has, so that the comment makes the actor.
        case addCommentByNewActor

        /// `addTag` with a name that gives the reserved slug.
        case addTagByName

        /// `addTag` with an id that gives the reserved slug.
        case addTagByID

        /// `renameTag` to a name that gives the reserved slug.
        case renameTag

        /// `addTask` with a tag name that gives the reserved slug.
        case addTaskTag

        /// `addTask` with a body marker that gives the reserved slug.
        case addTaskMarker

        /// `updateTask` with a tag name that gives the reserved slug.
        case updateTaskTag

        /// `updateTask` with a body marker that gives the reserved slug.
        case updateTaskMarker

        /// `tagTask` with a tag name that gives the reserved slug.
        case tagTask

        /// The mutation field, with its selection.
        ///
        /// - Parameters:
        ///   - task: The ULID of the fixture task.
        ///   - name: The name that the field gives to the new node. The default is ``reservedName``.
        ///   - id: The id that a field with an id gives to the new node. The default is ``reservedID``.
        /// - Returns: The field.
        func field(on task: ULID, naming name: String = reservedName, id: String = reservedID) -> String {
            switch self {
            case .addColumnByName: #"addColumn(input: { name: "\#(name)" }) { id }"#
            case .addColumnByID: #"addColumn(input: { id: "\#(id)", name: "\#(legalName)" }) { id }"#
            case .moveTaskToNewColumn:
                TaskOperationTests.taskField("moveTask", of: task, with: TaskOperationTests.moveInput(to: name))
            case .addActorByName: #"addActor(input: { name: "\#(name)" }) { id }"#
            case .addActorByID: #"addActor(input: { id: "\#(id)", name: "\#(legalName)" }) { id }"#
            case .addActorEnsure: #"addActor(input: { name: "\#(name)", ensure: true }) { id }"#
            case .addCommentByNewActor:
                CommentTests.addComment(to: AddUpdateTaskTests.sigilRef(of: task), with: #"actor: "\#(name)""#)
            case .addTagByName: TagMutationTests.addTag(named: name)
            case .addTagByID: #"addTag(input: { id: "\#(id)", name: "\#(legalName)" }) { id }"#
            case .renameTag: TagMutationTests.renameTag(from: TagMutationTests.bug, to: name)
            case .addTaskTag: AddUpdateTaskTests.addTask(with: TaskOperationTests.tagsInput(name))
            case .addTaskMarker: AddUpdateTaskTests.addTask(with: Self.markerBody(naming: name))
            case .updateTaskTag: AddUpdateTaskTests.updateTask(task, with: TaskOperationTests.tagsInput(name))
            case .updateTaskMarker: AddUpdateTaskTests.updateTask(task, with: Self.markerBody(naming: name))
            case .tagTask: TaskOperationTests.taskField("tagTask", of: task, with: TaskOperationTests.tagsInput(name))
            }
        }

        /// Makes the body text that a marker field writes: a body with a marker of a name.
        ///
        /// - Parameter name: The name of the marker, with no `#`.
        /// - Returns: The body text.
        static func markedBody(naming name: String) -> String {
            "Fix #\(name)"
        }

        /// Makes the `body` part of a task input whose body has a marker of a name (``markedBody(naming:)``).
        ///
        /// - Parameter name: The name of the marker, with no `#`.
        /// - Returns: The `input` field.
        private static func markerBody(naming name: String) -> String {
            #"body: "\#(markedBody(naming: name))""#
        }

        /// The document that runs before the field, or `nil` for none.
        var setup: String? {
            guard self == .renameTag else {
                return nil
            }
            return AddUpdateTaskTests.mutation(of: TagMutationTests.addTag(named: TagMutationTests.bug))
        }

        /// The error that the field gives.
        var error: KanbanError {
            switch self {
            case .addColumnByName, .addColumnByID, .moveTaskToNewColumn: .reservedSlug(type: .column)
            case .addActorByName, .addActorByID, .addActorEnsure, .addCommentByNewActor: .reservedSlug(type: .actor)
            case .addTagByName, .addTagByID, .renameTag, .addTaskTag, .addTaskMarker, .updateTaskTag,
                .updateTaskMarker, .tagTask:
                .reservedTagName
            }
        }
    }

    // MARK: - Refusal

    @Test(
        "A mutation that makes a column, an actor, or a tag with the slug board gives its slug error and writes nothing",
        arguments: Refusal.allCases
    )
    func mutationRefusesReservedSlug(refusal: Refusal) async throws {
        let directory = try TemporaryDirectory()
        let field = refusal.field(on: try AddUpdateTaskTests.fixtureTask())
        let error = try await ColumnActorTests.failure(
            of: AddUpdateTaskTests.mutation(of: field),
            after: refusal.setup,
            in: directory
        )
        #expect(error == refusal.error)
    }

    @Test("A session actor name that gives the slug board gives INVALID_SLUG")
    func sessionActorRefusesReservedSlug() {
        #expect(throws: KanbanError.reservedSlug(type: .actor)) {
            try KanbanGraph.sessionActor(named: Self.reservedName)
        }
    }

    // MARK: - Old logs

    @Test("A log that has a column, an actor, and a tag with the slug board still loads")
    func oldLogWithReservedSlugLoads() async throws {
        let directory = try TemporaryDirectory()
        var ids = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).ids
        let log = EventLog(repositoryAt: directory.url)
        let name: [String: PatchValue] = [PropertyName.name: .string(Self.legalName)]
        let order: [String: PatchValue] = [PropertyName.order: .integer(Self.oldColumnOrder)]
        let patches = try [
            PatchInput(node: .column(slug: Slug.reservedForBoard), set: name.merging(order) { first, _ in first }),
            PatchInput(node: .actor(slug: Slug.reservedForBoard), set: name),
            PatchInput(node: .tag(slug: Slug.reservedForBoard), set: name),
        ]
        for patch in patches {
            try KanbanGraphTests.append(patch, mintingFrom: &ids, to: log)
        }
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let response = try await KanbanGraphTests.execute(
            "{ board { columns { name } actors { name } tags { name } } }",
            on: graph
        )
        let todo = KanbanGraphTests.todoName
        let main = Self.legalName
        #expect(
            response == #"{"data":{"board":{"actors":[{"name":"\#(main)"}],"#
                + #""columns":[{"name":"\#(todo)"},{"name":"\#(main)"}],"tags":[{"name":"\#(main)"}]}}}"#
        )
    }
}
