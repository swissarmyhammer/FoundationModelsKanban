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

    /// One mutation field that makes a column, an actor, or a tag with the reserved slug.
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
        /// - Parameter task: The ULID of the fixture task.
        /// - Returns: The field.
        func field(on task: ULID) -> String {
            switch self {
            case .addColumnByName: #"addColumn(input: { name: "\#(reservedName)" }) { id }"#
            case .addColumnByID: #"addColumn(input: { id: "\#(reservedID)", name: "\#(legalName)" }) { id }"#
            case .moveTaskToNewColumn:
                TaskOperationTests.taskField("moveTask", of: task, with: TaskOperationTests.moveInput(to: reservedName))
            case .addActorByName: #"addActor(input: { name: "\#(reservedName)" }) { id }"#
            case .addActorByID: #"addActor(input: { id: "\#(reservedID)", name: "\#(legalName)" }) { id }"#
            case .addActorEnsure: #"addActor(input: { name: "\#(reservedName)", ensure: true }) { id }"#
            case .addCommentByNewActor:
                CommentTests.addComment(to: AddUpdateTaskTests.sigilRef(of: task), with: #"actor: "\#(reservedName)""#)
            case .addTagByName: TagMutationTests.addTag(named: reservedName)
            case .addTagByID: #"addTag(input: { id: "\#(reservedID)", name: "\#(legalName)" }) { id }"#
            case .renameTag: TagMutationTests.renameTag(from: TagMutationTests.bug, to: reservedName)
            case .addTaskTag: AddUpdateTaskTests.addTask(with: Self.tagsInput)
            case .addTaskMarker: AddUpdateTaskTests.addTask(with: Self.markerBody)
            case .updateTaskTag: AddUpdateTaskTests.updateTask(task, with: Self.tagsInput)
            case .updateTaskMarker: AddUpdateTaskTests.updateTask(task, with: Self.markerBody)
            case .tagTask: TaskOperationTests.taskField("tagTask", of: task, with: Self.tagsInput)
            }
        }

        /// The `tags` part of a task input with the reserved name.
        private static let tagsInput = TaskOperationTests.tagsInput(reservedName)

        /// The `body` part of a task input whose body has a marker of the reserved name.
        private static let markerBody = #"body: "Fix #\#(reservedName)""#

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
