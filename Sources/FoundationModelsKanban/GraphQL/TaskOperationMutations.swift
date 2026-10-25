import FoundationModelsExtras
import Graphiti
import GraphQL

// MARK: - Names

extension MutationName {
    /// The mutation that moves a task to a column and to a place in that column.
    static let moveTask = "moveTask"

    /// The mutation that copies a task, to the same board or to a different board.
    static let copyTask = "copyTask"

    /// The mutation that moves a task to the end of the terminal column.
    static let completeTask = "completeTask"

    /// The mutation that adds an actor to the assignees of a task.
    static let assignTask = "assignTask"

    /// The mutation that removes an actor from the assignees of a task.
    static let unassignTask = "unassignTask"

    /// The mutation that adds tag edges to a task.
    static let tagTask = "tagTask"

    /// The mutation that removes tags from a task: the tag edges, and the `#markers` of the body.
    static let untagTask = "untagTask"

    /// The mutation that makes a task a tombstone.
    static let deleteTask = "deleteTask"

    /// The mutation that makes a tombstoned task live again.
    static let undeleteTask = "undeleteTask"
}

// MARK: - Arguments

/// The `input` object of `moveTask` (plan.md §4.2, divergence.md Q21): the fields of ``TaskPlacementFields``. A
/// `board` field that names a different board moves the task to that board.
private struct MoveTaskInput: TaskPlacementInput {
    /// The fields of the input.
    let fields: TaskPlacementFields

    /// Reads the input object of a move.
    ///
    /// - Parameter decoder: The decoder of the input object.
    /// - Throws: The errors of ``TaskPlacementFields/init(from:)``.
    init(from decoder: any Decoder) throws {
        fields = try TaskPlacementFields(from: decoder)
    }
}

/// The `input` object of `assignTask` or `unassignTask` (plan.md §4.2). Each mutation has its own `input` type,
/// `AssignTaskInput` or `UnassignTaskInput` (``SharedInputMutation``), that
/// ``SchemaBuilder/makeAssignTaskInput(of:)`` gives.
private struct AssignTaskInput<Mutation: SharedInputMutation>: TaskReferenceInput {
    /// The GraphQL name of this `input` type: the `input` type name of its mutation (EXTRAS-9 rule 7).
    static var inputTypeName: String { Mutation.inputTypeName }

    /// The task: a full URI or a short form (plan.md §3.2).
    let id: NodeID

    /// The actor: a full URI, the stored form `actor/<slug>`, the slug, or a name that gives the slug.
    let actor: NodeID
}

/// The `input` object of `tagTask` or `untagTask` (plan.md §4.2). Each mutation has its own `input` type,
/// `TagTaskInput` or `UntagTaskInput` (``SharedInputMutation``), that ``SchemaBuilder/makeTagTaskInput(of:)`` gives.
private struct TagTaskInput<Mutation: SharedInputMutation>: TaskReferenceInput {
    /// The GraphQL name of this `input` type: the `input` type name of its mutation (EXTRAS-9 rule 7).
    static var inputTypeName: String { Mutation.inputTypeName }

    /// The task: a full URI or a short form (plan.md §3.2).
    let id: NodeID

    /// The tag names, slugs, stored local forms `tag/<slug>`, or tag URIs.
    let tags: [String]
}

/// The `completeTask` mutation, for its `input` type `CompleteTaskInput`.
private enum CompleteTaskMutation: SharedInputMutation {
    /// The name of the mutation.
    static let name = MutationName.completeTask
}

/// The `assignTask` mutation, for its `input` type `AssignTaskInput`.
private enum AssignTaskMutation: SharedInputMutation {
    /// The name of the mutation.
    static let name = MutationName.assignTask
}

/// The `unassignTask` mutation, for its `input` type `UnassignTaskInput`.
private enum UnassignTaskMutation: SharedInputMutation {
    /// The name of the mutation.
    static let name = MutationName.unassignTask
}

/// The `tagTask` mutation, for its `input` type `TagTaskInput`.
private enum TagTaskMutation: SharedInputMutation {
    /// The name of the mutation.
    static let name = MutationName.tagTask
}

/// The `untagTask` mutation, for its `input` type `UntagTaskInput`.
private enum UntagTaskMutation: SharedInputMutation {
    /// The name of the mutation.
    static let name = MutationName.untagTask
}

/// The `deleteTask` mutation, for its `input` type `DeleteTaskInput`.
private enum DeleteTaskMutation: SharedInputMutation {
    /// The name of the mutation.
    static let name = MutationName.deleteTask
}

/// The `undeleteTask` mutation, for its `input` type `UndeleteTaskInput`.
private enum UndeleteTaskMutation: SharedInputMutation {
    /// The name of the mutation.
    static let name = MutationName.undeleteTask
}

/// The side of a neighbor where a moved task or a moved column goes. The raw value is the name of the place field of
/// the input.
enum NeighborSide: String {
    /// Before the neighbor.
    case before

    /// After the neighbor.
    case after
}

/// The place of a moved or copied task in its column, from the place fields of a `moveTask` or `copyTask` input
/// (plan.md §4.2, §6, "moveTask"). A value holds one place, so an input with more than one place field cannot make a
/// value.
enum Placement: Decodable, Sendable {
    /// The code of the warning for a `before` or `after` ref that names no task, or no column for `moveColumn`, in
    /// `extensions.warnings` (divergence.md P1, §25).
    static let neighborNotFoundWarningCode = "NEIGHBOR_NOT_FOUND"

    /// The keys of the place fields of the input.
    private enum CodingKeys: String, CodingKey {
        /// The key of the ordinal.
        case ordinal

        /// The key of the neighbor that the task goes before.
        case before

        /// The key of the neighbor that the task goes after.
        case after
    }

    /// After the last task of the column. The input gives no place field.
    case end

    /// At an ordinal, as the input writes it.
    case ordinal(String)

    /// Before a neighbor task. A neighbor that is not in the column puts the task at the end. A ref that names no task
    /// also puts the task at the end, with a warning (divergence.md P1).
    case before(NodeID)

    /// After a neighbor task. A neighbor that is not in the column puts the task at the end. A ref that names no task
    /// also puts the task at the end, with a warning (divergence.md P1).
    case after(NodeID)

    /// What the call did with a task when its `before` or `after` ref names no task (divergence.md P1).
    static let taskAtEndOutcome = "The call put the task at the end of the column. Send the id of a task in the "
        + "column to put the task next to that task."

    /// Gives the warning for a `before` or `after` ref that names no node of the type of the moved node. A task goes
    /// to the end of its column (divergence.md P1). A column goes to the place of its other ref (divergence.md §25).
    ///
    /// - Parameters:
    ///   - neighbor: The neighbor ref as the input writes it. The warning quotes it.
    ///   - side: The place field of the ref.
    ///   - type: The node type of the moved node and of its neighbors: ``PatchNodeType/task`` or
    ///     ``PatchNodeType/column``.
    ///   - outcome: The text that tells what the call did, for example ``taskAtEndOutcome``.
    /// - Returns: The warning, for example "The before ref `zzzzzzz` names no task. …".
    static func neighborNotFoundWarning(
        for neighbor: NodeID,
        on side: NeighborSide,
        moving type: PatchNodeType,
        outcome: String
    ) -> ResponseWarning {
        let message = "The \(side.rawValue) ref `\(neighbor.text)` names no \(type.pathSegment). \(outcome)"
        return ResponseWarning(message: message, code: neighborNotFoundWarningCode)
    }

    /// Reads the place fields of the input object of a move.
    ///
    /// - Parameter decoder: The decoder of the input object.
    /// - Throws: ``KanbanError/conflictingPlacement(fields:)`` when the input gives more than one place field. A
    ///   `DecodingError` when a place field has the wrong type.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let given: [(key: CodingKeys, placement: Self?)] = [
            (.ordinal, try container.decodeIfPresent(String.self, forKey: .ordinal).map(Self.ordinal)),
            (.before, try container.decodeIfPresent(NodeID.self, forKey: .before).map(Self.before)),
            (.after, try container.decodeIfPresent(NodeID.self, forKey: .after).map(Self.after)),
        ]
        let places = given.filter { field in field.placement != nil }
        guard places.dropFirst().isEmpty else {
            throw KanbanError.conflictingPlacement(fields: places.map(\.key.stringValue))
        }
        self = places.first?.placement ?? .end
    }
}

// MARK: - Resolvers

extension KanbanResolver {
    /// Resolves `Mutation.moveTask`: writes one task patch with a `set` of the column and the ordinal (plan.md §4.2,
    /// §6). A column slug that no column has gets a column `set` patch first. No column keeps the column where the
    /// task shows now. A `board` field that names a different board moves the task to that board
    /// (``KanbanContext/transferTask(_:as:)``, divergence.md Q21); a `board` field that names the board of the task
    /// moves the task in its board. A `before` or `after` ref that names no live task puts the task at the end of the
    /// column, with a warning (divergence.md P1).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The task, the column, the place in the column, and the board.
    /// - Returns: The task after the move: the new task on the other board for a move to a different board. The
    ///   GraphQL field is nullable, so that an error gives `null` for this field only.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the id, or the column is a
    ///   tombstone. ``KanbanError/invalidOrdinal(ordinal:)`` and
    ///   ``KanbanError/invalidSlug(name:)``. ``KanbanError/reservedSlug(type:)`` when a new column would get the slug
    ///   ``Slug/reservedForBoard``. ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board
    ///   for the `board` field. The errors of ``BoardStore/isBoard(_:holdingTask:)`` and of
    ///   ``KanbanContext/transferTask(_:as:)``, so that a board that the engine did not load yet gives an error, not a
    ///   `null` with no error. The decode of the input throws
    ///   ``KanbanError/conflictingPlacement(fields:)`` before this resolver runs, so that the field writes nothing.
    fileprivate func moveTask(
        context: KanbanContext,
        arguments: InputArguments<MoveTaskInput>
    ) async throws -> TaskObject? {
        let fields = arguments.input.fields
        if let board = fields.board, try await !context.store.isBoard(board, holdingTask: fields.id) {
            return try await context.transferTask(fields, as: .move)
        }
        return try await context.changeTask(fields.id, named: MutationName.moveTask) { work, resolver, ref, time in
            let column = try work.columnRef(forMoveOf: ref, to: fields.column, resolvingWith: resolver, at: time)
            let ordinal = try work.graph.ordinal(
                placing: fields.placement,
                inColumn: column,
                moving: ref,
                resolvingWith: resolver
            )
            try work.move(ref, to: column, placingAt: ordinal, at: time)
        }
    }

    /// Resolves `Mutation.completeTask`: moves the task to the terminal column, after the last ordinal there (plan.md
    /// §6, "completeTask").
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The task.
    /// - Returns: The task after the move.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the id, or the board has no live
    ///   column.
    fileprivate func completeTask(
        context: KanbanContext,
        arguments: InputArguments<NodeReferenceInput<CompleteTaskMutation>>
    ) async throws -> TaskObject? {
        let input = arguments.input
        return try await context.changeTask(input.id, named: MutationName.completeTask) { work, _, ref, time in
            let column = try work.graph.columnRef(atSlot: ColumnOrder(of: work.graph).terminal)
            let ordinal = work.graph.nextOrdinal(inColumn: column, excluding: ref)
            try work.move(ref, to: column, placingAt: ordinal, at: time)
        }
    }

    /// Resolves `Mutation.assignTask`: writes an `add` of the actor on `assignees`. An actor that the task has writes
    /// nothing.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The task and the actor.
    /// - Returns: The task after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the id.
    ///   ``KanbanError/actorNotFound(reference:)`` when the actor names no live actor.
    fileprivate func assignTask(
        context: KanbanContext,
        arguments: InputArguments<AssignTaskInput<AssignTaskMutation>>
    ) async throws -> TaskObject? {
        try await changeAssignee(to: true, context: context, arguments)
    }

    /// Resolves `Mutation.unassignTask`: writes a `remove` of the actor on `assignees`. An actor that the task does
    /// not have writes nothing.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The task and the actor.
    /// - Returns: The task after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the id.
    ///   ``KanbanError/actorNotFound(reference:)`` when the actor names no actor, live or tombstoned.
    fileprivate func unassignTask(
        context: KanbanContext,
        arguments: InputArguments<AssignTaskInput<UnassignTaskMutation>>
    ) async throws -> TaskObject? {
        try await changeAssignee(to: false, context: context, arguments)
    }

    /// Writes an `add` or a `remove` of one actor on the `assignees` of a task.
    ///
    /// - Parameters:
    ///   - isAssigned: `true` to add the actor, `false` to remove it.
    ///   - context: The context of the call.
    ///   - arguments: The task and the actor. A remove can also name a tombstoned actor. The mutation of the `input`
    ///     type is the public mutation of the call.
    /// - Returns: The task after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the id.
    ///   ``KanbanError/actorNotFound(reference:)`` when the actor names no actor that the change accepts.
    private func changeAssignee<Mutation: SharedInputMutation>(
        to isAssigned: Bool,
        context: KanbanContext,
        _ arguments: InputArguments<AssignTaskInput<Mutation>>
    ) async throws -> TaskObject? {
        let input = arguments.input
        return try await context.changeTask(input.id, named: Mutation.name) { work, resolver, ref, time in
            let actor = try resolver.actorRef(for: input.actor, includingTombstones: !isAssigned)
            let edges = [PropertyName.assignees: [StoredRef.local(actor)]]
            let patch = try isAssigned ? PatchInput(node: ref, add: edges) : PatchInput(node: ref, remove: edges)
            try work.apply(patch, at: time)
        }
    }

    /// Resolves `Mutation.tagTask`: writes an `add` of the tags on `tags`. The body does not change (plan.md §6.1). An
    /// unknown tag gets a tag `set` patch first, and a tombstoned tag gets a `delete: false` patch.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The task and the tags.
    /// - Returns: The task after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the id, or a tag URI names no live
    ///   tag. ``KanbanError/invalidTagName(name:)`` when a name gives an empty slug.
    ///   ``KanbanError/reservedTagName`` when a new tag would get the slug ``Slug/reservedForBoard``.
    ///   ``KanbanError/virtualTagName(tag:)`` when a new tag would get the name of a virtual tag as its slug.
    fileprivate func tagTask(
        context: KanbanContext,
        arguments: InputArguments<TagTaskInput<TagTaskMutation>>
    ) async throws -> TaskObject? {
        let input = arguments.input
        return try await context.changeTask(input.id, named: MutationName.tagTask) { work, resolver, ref, time in
            let tags = try work.tagRefs(named: input.tags, resolvingWith: resolver, at: time)
            try work.apply(PatchInput(node: ref, add: [PropertyName.tags: tags]), at: time)
        }
    }

    /// Resolves `Mutation.untagTask`: writes a `remove` of each tag edge, and an `edit` that removes each `#marker` of
    /// the tags from the body (plan.md §6.1). The match follows the rename redirect.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The task and the tags.
    /// - Returns: The task after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the id, or a tag URI names no tag.
    ///   ``KanbanError/invalidTagName(name:)`` when a name gives an empty slug.
    fileprivate func untagTask(
        context: KanbanContext,
        arguments: InputArguments<TagTaskInput<UntagTaskMutation>>
    ) async throws -> TaskObject? {
        let input = arguments.input
        return try await context.changeTask(input.id, named: MutationName.untagTask) { work, resolver, ref, time in
            try work.untag(ref, removing: input.tags, resolvingWith: resolver, at: time)
        }
    }

    /// Resolves `Mutation.deleteTask`: makes the task a tombstone (plan.md §3.3). The lists do not show it, and a
    /// `dependsOn` edge to it does not count.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The task.
    /// - Returns: The tombstone, with `deleted` set.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the id.
    fileprivate func deleteTask(
        context: KanbanContext,
        arguments: InputArguments<NodeReferenceInput<DeleteTaskMutation>>
    ) async throws -> TaskObject? {
        try await changeDeleted(to: true, ofType: .task, context: context, arguments)
    }

    /// Resolves `Mutation.undeleteTask`: makes a tombstoned task live again. A live task does not change. The task
    /// obeys the dependency rule of plan.md §3.3, rule 6, the same as a write of `dependsOn`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The task.
    /// - Returns: The live task.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no task has the id.
    ///   ``KanbanError/dependencyCycle(path:)`` when the live task closes a `dependsOn` cycle. The call then writes
    ///   nothing, and the task stays a tombstone.
    fileprivate func undeleteTask(
        context: KanbanContext,
        arguments: InputArguments<NodeReferenceInput<UndeleteTaskMutation>>
    ) async throws -> TaskObject? {
        try await changeDeleted(to: false, ofType: .task, context: context, arguments)
    }
}

// MARK: - Context

extension KanbanContext {
    /// Runs one public mutation field that changes a live task at the time of ``clock``, and gives the task after the
    /// field. The field obeys the rules of ``changeNode(named:on:_:)``, in the board of the task.
    ///
    /// - Parameters:
    ///   - id: The task: a full URI or a short form.
    ///   - operation: The name of the public mutation of the field.
    ///   - body: Makes and applies the patches of the field. It gets the working copy, a resolver of the forgiving
    ///     refs of the working graph, the local ref of the task, and the time.
    /// - Returns: The task object.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the id, or the engine did not load
    ///   the board of the task yet, so that the field never gives `null` with no error. The store then records the
    ///   request, and the call runs again after the load. The error of the body.
    func changeTask(
        _ id: NodeID,
        named operation: String,
        _ body: sending (inout WorkingCopy, RefResolver, LocalRef, DateTime) throws -> Void
    ) async throws -> TaskObject {
        let task: TaskObject? = try await changeNode(named: operation, on: .holding(id)) { work, resolver, time in
            let ref = try resolver.nodeRef(for: id, ofType: .task)
            try body(&work, resolver, ref, time)
            return ref
        }
        guard let task else {
            throw KanbanError.notFound(type: .task, reference: id.text)
        }
        return task
    }
}

// MARK: - Patches

extension WorkingCopy {
    /// Finds the column of a move. A slug that no column has, live or tombstoned, gets a column `set` patch with the
    /// words of the slug in title case and the order after the terminal column (plan.md §6, "moveTask").
    ///
    /// - Parameters:
    ///   - id: The column that the input names: a full URI, the slug, or a name.
    ///   - resolver: The resolver of the forgiving refs of the board.
    ///   - time: The time of the change.
    /// - Returns: The local ref of the column.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when a URI names no live column, or the slug names a
    ///   tombstone. ``KanbanError/invalidSlug(name:)`` when the name gives an empty slug.
    ///   ``KanbanError/reservedSlug(type:)`` when a new column would get the slug ``Slug/reservedForBoard``.
    mutating func columnRef(
        forMoveTo id: NodeID,
        resolvingWith resolver: RefResolver,
        at time: DateTime
    ) throws -> LocalRef {
        if !NodeURI.hasScheme(atStartOf: id.text) {
            let slug = try Slug(columnOrActorName: id.text)
            let ref = LocalRef.column(slug: slug.value)
            if !graph.hasNode(ref) {
                let values = [
                    PropertyName.name: PatchValue.string(slug.titleCaseName),
                    PropertyName.order: .integer(graph.nextColumnOrder),
                ]
                try addNode(ref, setting: values, body: nil, at: time)
                return ref
            }
        }
        return try resolver.nodeRef(for: id, ofType: .column)
    }

    /// Finds the column of a move of a task in its board: the column that the input names, with the rule of
    /// ``columnRef(forMoveTo:resolvingWith:at:)``, or the column where the task shows now when the input names no
    /// column.
    ///
    /// - Parameters:
    ///   - task: The local ref of the task.
    ///   - id: The column that the input names, or `nil` for no column.
    ///   - resolver: The resolver of the forgiving refs of the board.
    ///   - time: The time of the change.
    /// - Returns: The local ref of the column.
    /// - Throws: The errors of ``columnRef(forMoveTo:resolvingWith:at:)``. ``KanbanError/notFound(type:reference:)``
    ///   when the graph does not have the task, or the board has no live column.
    fileprivate mutating func columnRef(
        forMoveOf task: LocalRef,
        to id: NodeID?,
        resolvingWith resolver: RefResolver,
        at time: DateTime
    ) throws -> LocalRef {
        if let id {
            return try columnRef(forMoveTo: id, resolvingWith: resolver, at: time)
        }
        guard let node = graph.node(for: task)?.state as? TaskNode else {
            throw KanbanError.notFound(type: .task, reference: task.description)
        }
        return try graph.displayColumn(of: node)
    }

    /// Writes the task patch of a move: a `set` of the column and the ordinal.
    ///
    /// - Parameters:
    ///   - task: The local ref of the task.
    ///   - column: The local ref of the column.
    ///   - ordinal: The ordinal of the task in the column.
    ///   - time: The time of the change.
    /// - Throws: An ``EventError`` when the patch breaks a rule of the log.
    mutating func move(
        _ task: LocalRef,
        to column: LocalRef,
        placingAt ordinal: Ordinal,
        at time: DateTime
    ) throws(EventError) {
        let values = [
            PropertyName.column: PatchValue.ref(.local(column)),
            PropertyName.ordinal: .string(ordinal.value),
        ]
        try apply(PatchInput(node: task, set: values), at: time)
    }

    /// Removes tags from a task: a `remove` of each tag edge, and an `edit` that removes each `#marker` of the tags
    /// from the body (plan.md §6.1). An edge or a marker matches when its tag and an input tag end at the same tag of
    /// the rename chain. A tag that the task does not have changes nothing.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the live task.
    ///   - names: The tag names, slugs, stored local forms `tag/<slug>`, or tag URIs.
    ///   - resolver: The resolver of the forgiving refs of the board, for a tag URI.
    ///   - time: The time of the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when a tag URI names no tag, or the graph does not have the
    ///   task. ``KanbanError/invalidTagName(name:)`` when a name gives an empty slug. An ``EventError`` when the patch
    ///   breaks a rule of the log.
    fileprivate mutating func untag(
        _ ref: LocalRef,
        removing names: [String],
        resolvingWith resolver: RefResolver,
        at time: DateTime
    ) throws {
        let targets = Set(
            try names.map { name in
                try graph.tagRef(redirectedFrom: resolver.tag(named: name, includingTombstones: true).ref)
            }
        )
        guard let task = graph.node(for: ref)?.state as? TaskNode else {
            throw KanbanError.notFound(type: .task, reference: ref.description)
        }
        let removed = task.tags.compactMap(graph.storedRef(of:)).filter { edge in
            guard case .local(let tag) = edge else {
                return false
            }
            return targets.contains(graph.tagRef(redirectedFrom: tag))
        }
        let oldBody = task.fields.body
        let newBody = TagMarkers.slugs(in: oldBody)
            .filter { slug in targets.contains(graph.tagRef(redirectedFrom: .tag(slug: slug.value))) }
            .reduce(oldBody) { body, slug in TagMarkers.removing(markersOf: slug, from: body) }
        let patch = try PatchInput(
            changing: ref,
            updating: [:],
            removing: [PropertyName.tags: removed],
            body: newBody == oldBody ? .unchanged : .changed(newBody),
            from: oldBody
        )
        try apply(patch, at: time)
    }
}

// MARK: - Graph

extension Graph {
    /// Gives the ordinal of a task that a move puts in a column (plan.md §6, "moveTask").
    ///
    /// - Parameters:
    ///   - placement: The place in the column.
    ///   - column: The local ref of the column.
    ///   - task: The local ref of the moved task. The column order does not count this task.
    ///   - resolver: The resolver of the forgiving refs of the board, for a neighbor.
    /// - Returns: The ordinal.
    /// - Throws: ``KanbanError/invalidOrdinal(ordinal:)`` when the ordinal is not a valid fractional index. The errors
    ///   of ``ordinal(besideRef:on:inColumn:moving:resolvingWith:)`` for a neighbor. A neighbor that names no live task
    ///   gives no error.
    func ordinal(
        placing placement: Placement,
        inColumn column: LocalRef,
        moving task: LocalRef,
        resolvingWith resolver: RefResolver
    ) throws(KanbanError) -> Ordinal {
        switch placement {
        case .end:
            return nextOrdinal(inColumn: column, excluding: task)
        case .ordinal(let text):
            return try Ordinal(parsing: text)
        case .before(let neighbor):
            return try ordinal(besideRef: neighbor, on: .before, inColumn: column, moving: task, resolvingWith: resolver)
        case .after(let neighbor):
            return try ordinal(besideRef: neighbor, on: .after, inColumn: column, moving: task, resolvingWith: resolver)
        }
    }

    /// Gives the ordinal of a task that a move puts next to the neighbor task of a `before` or `after` ref. A ref that
    /// names no live task puts the task at the end of the column, the same as Rust, and adds a warning that names the
    /// ref to the response (divergence.md P1).
    ///
    /// - Parameters:
    ///   - neighbor: The neighbor ref as the input writes it.
    ///   - side: The side of the neighbor where the task goes.
    ///   - column: The local ref of the column.
    ///   - task: The local ref of the moved task. The column order does not count this task.
    ///   - resolver: The resolver of the forgiving refs of the board.
    /// - Returns: The ordinal.
    /// - Throws: The errors of ``RefResolver/nodeRef(for:ofType:includingTombstones:)`` other than
    ///   ``KanbanError/notFound(type:reference:)``, for example ``KanbanError/ambiguousID(reference:matches:)``.
    private func ordinal(
        besideRef neighbor: NodeID,
        on side: NeighborSide,
        inColumn column: LocalRef,
        moving task: LocalRef,
        resolvingWith resolver: RefResolver
    ) throws(KanbanError) -> Ordinal {
        do {
            let ref = try resolver.nodeRef(for: neighbor, ofType: .task)
            return ordinal(beside: ref, on: side, inColumn: column, moving: task)
        } catch .notFound {
            let outcome = Placement.taskAtEndOutcome
            let warning = Placement.neighborNotFoundWarning(for: neighbor, on: side, moving: .task, outcome: outcome)
            ResolverWarnings.current?.add(warning)
            return nextOrdinal(inColumn: column, excluding: task)
        }
    }

    /// Gives the ordinal of a task that a move puts next to a neighbor task. A neighbor that is not in the column
    /// puts the task at the end of the column, the same as Rust.
    ///
    /// - Parameters:
    ///   - neighbor: The local ref of the neighbor task.
    ///   - side: The side of the neighbor where the task goes.
    ///   - column: The local ref of the column.
    ///   - task: The local ref of the moved task. The column order does not count this task.
    /// - Returns: The ordinal.
    fileprivate func ordinal(
        beside neighbor: LocalRef,
        on side: NeighborSide,
        inColumn column: LocalRef,
        moving task: LocalRef
    ) -> Ordinal {
        let tasks = tasks(inColumn: column, excluding: task)
        guard let index = tasks.firstIndex(where: { shown in shown.ref == neighbor }) else {
            return nextOrdinal(inColumn: column, excluding: task)
        }
        let neighborOrdinal = tasks[index].ordinal
        switch side {
        case .before:
            guard index > tasks.startIndex else {
                return Ordinal(before: neighborOrdinal)
            }
            return Ordinal(between: tasks[tasks.index(before: index)].ordinal, and: neighborOrdinal)
        case .after:
            let next = tasks.index(after: index)
            guard next < tasks.endIndex else {
                return Ordinal(after: neighborOrdinal)
            }
            return Ordinal(between: neighborOrdinal, and: tasks[next].ordinal)
        }
    }
}

extension Slug {
    /// The text between two words of a column name that a move makes from a slug.
    private static let wordSeparator = " "

    /// The name of a column that a move makes from the slug: each word of the slug, with its first letter in
    /// uppercase, for example `In Review` for `in-review` (Rust `slug_to_name`).
    fileprivate var titleCaseName: String {
        value.split(separator: Self.separator)
            .map { word in word.prefix(1).uppercased() + word.dropFirst() }
            .joined(separator: Self.wordSeparator)
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Gives the `input` type of `assignTask` or `unassignTask` (``AssignTaskInput``), with the name of the mutation
    /// (EXTRAS-9 rule 7), so that the fields have one definition.
    ///
    /// - Parameter mutation: The mutation of the `input` type.
    /// - Returns: The `input` type `<Mutation>Input`, with its fields `id` and `actor`.
    fileprivate static func makeAssignTaskInput<Mutation: SharedInputMutation>(
        of mutation: Mutation.Type
    ) -> Input<KanbanResolver, KanbanContext, AssignTaskInput<Mutation>> {
        Input(AssignTaskInput<Mutation>.self, as: AssignTaskInput<Mutation>.inputTypeName) {
            Self.makeTaskReferenceField()
            InputField("actor", at: \.actor).description(SchemaDescription.actorReference)
        }
        .description(SchemaDescription.mutationFields(of: mutation.name))
    }

    /// Gives the `input` type of `tagTask` or `untagTask` (``TagTaskInput``), with the name of the mutation (EXTRAS-9
    /// rule 7), so that the fields have one definition.
    ///
    /// - Parameter mutation: The mutation of the `input` type.
    /// - Returns: The `input` type `<Mutation>Input`, with its fields `id` and `tags`.
    fileprivate static func makeTagTaskInput<Mutation: SharedInputMutation>(
        of mutation: Mutation.Type
    ) -> Input<KanbanResolver, KanbanContext, TagTaskInput<Mutation>> {
        Input(TagTaskInput<Mutation>.self, as: TagTaskInput<Mutation>.inputTypeName) {
            Self.makeTaskReferenceField()
            InputField("tags", at: \.tags).description(SchemaDescription.tagTaskTags)
        }
        .description(SchemaDescription.mutationFields(of: mutation.name))
    }

    /// Adds the task operation mutations and their `input` types (plan.md §4.2): `moveTask`, `completeTask`,
    /// `assignTask`, `unassignTask`, `tagTask`, `untagTask`, `deleteTask`, and `undeleteTask`. Each mutation has an
    /// `input` type of its own name (EXTRAS-9 rule 7). The mutations that name only the task use the `input` types of
    /// ``NodeReferenceInput``.
    ///
    /// - Returns: This builder, for method chaining.
    func addTaskOperationMutations() -> Self {
        add {
            Input(MoveTaskInput.self, Self.placementFields).description(SchemaDescription.moveTaskInput)
            Self.makeNodeReferenceInput(of: CompleteTaskMutation.self)
            Self.makeAssignTaskInput(of: AssignTaskMutation.self)
            Self.makeAssignTaskInput(of: UnassignTaskMutation.self)
            Self.makeTagTaskInput(of: TagTaskMutation.self)
            Self.makeTagTaskInput(of: UntagTaskMutation.self)
            Self.makeNodeReferenceInput(of: DeleteTaskMutation.self)
            Self.makeNodeReferenceInput(of: UndeleteTaskMutation.self)
        }
        .addMutation {
            Self.mutationField(
                MutationName.moveTask,
                at: KanbanResolver.moveTask,
                description: SchemaDescription.moveTask
            )
            Self.mutationField(
                MutationName.completeTask,
                at: KanbanResolver.completeTask,
                description: SchemaDescription.completeTask
            )
            Self.mutationField(
                MutationName.assignTask,
                at: KanbanResolver.assignTask,
                description: SchemaDescription.assignTask
            )
            Self.mutationField(
                MutationName.unassignTask,
                at: KanbanResolver.unassignTask,
                description: SchemaDescription.unassignTask
            )
            Self.mutationField(MutationName.tagTask, at: KanbanResolver.tagTask, description: SchemaDescription.tagTask)
            Self.mutationField(
                MutationName.untagTask,
                at: KanbanResolver.untagTask,
                description: SchemaDescription.untagTask
            )
            Self.mutationField(
                MutationName.deleteTask,
                at: KanbanResolver.deleteTask,
                description: SchemaDescription.deleteTask
            )
            Self.mutationField(
                MutationName.undeleteTask,
                at: KanbanResolver.undeleteTask,
                description: SchemaDescription.undeleteTask
            )
        }
        .addTaskListMutations()
    }
}

// MARK: - List mutations

extension MutationName {
    /// The mutation that moves a list of tasks to a column, as one block at one place in that column (divergence.md
    /// §20).
    static let moveTasks = "moveTasks"

    /// The mutation that makes each task of a list a tombstone (divergence.md §20).
    static let deleteTasks = "deleteTasks"

    /// The mutation that makes each tombstoned task of a list live again (divergence.md §20).
    static let undeleteTasks = "undeleteTasks"
}

/// An `input` object that names a list of tasks in its `id` field: the input of `moveTasks`, `deleteTasks`, or
/// `undeleteTasks` (divergence.md §20). ``SchemaBuilder/makeTaskListField()`` gives the schema of the field.
private protocol TaskListReferenceInput: Decodable, Sendable {
    /// The tasks: full URIs or short forms (plan.md §3.2), in the order of the list.
    var id: [NodeID] { get }
}

/// The `input` object of `moveTasks` (divergence.md §20): the tasks, the column, and one place field or none. The
/// input has no `board` field, so the tasks stay on their board. It has no `ifVersion` field, because a move is never
/// refused (KanbanViewKit D100).
private struct MoveTasksInput: TaskListReferenceInput, TaskPlaceInput {
    /// The keys of the fields of the input that are not place fields. ``Placement`` reads the place fields.
    private enum CodingKeys: String, CodingKey {
        /// The key of the tasks.
        case id

        /// The key of the column.
        case column
    }

    /// The tasks: full URIs or short forms (plan.md §3.2), in the order of the block.
    let id: [NodeID]

    /// The column: a full URI, the slug, or a name, or `nil` for the column where the first task shows. A slug that
    /// no column has makes a new column.
    let column: NodeID?

    /// The place of the block in the column.
    let placement: Placement

    /// Reads the input object of a move of a list of tasks.
    ///
    /// - Parameter decoder: The decoder of the input object.
    /// - Throws: ``KanbanError/conflictingPlacement(fields:)`` when the input gives more than one place field. A
    ///   `DecodingError` when the input has no `id`, or a field has the wrong type.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode([NodeID].self, forKey: .id)
        column = try container.decodeIfPresent(NodeID.self, forKey: .column)
        placement = try Placement(from: decoder)
    }
}

/// The `input` object of `deleteTasks` or `undeleteTasks` (divergence.md §20): the tasks. Each mutation has its own
/// `input` type, `DeleteTasksInput` or `UndeleteTasksInput` (``SharedInputMutation``), that
/// ``SchemaBuilder/makeTaskListInput(of:)`` gives.
private struct TaskListInput<Mutation: SharedInputMutation>: TaskListReferenceInput {
    /// The GraphQL name of this `input` type: the `input` type name of its mutation (EXTRAS-9 rule 7).
    static var inputTypeName: String { Mutation.inputTypeName }

    /// The tasks: full URIs or short forms (plan.md §3.2), in the order of the list.
    let id: [NodeID]
}

/// The `deleteTasks` mutation, for its `input` type `DeleteTasksInput`.
private enum DeleteTasksMutation: SharedInputMutation {
    /// The name of the mutation.
    static let name = MutationName.deleteTasks
}

/// The `undeleteTasks` mutation, for its `input` type `UndeleteTasksInput`.
private enum UndeleteTasksMutation: SharedInputMutation {
    /// The name of the mutation.
    static let name = MutationName.undeleteTasks
}

extension KanbanResolver {
    /// Resolves `Mutation.moveTasks`: writes one task patch with a `set` of the column and the ordinal for each task
    /// of the list, in one transaction (divergence.md §20). The tasks go to the column as one block, in the order of
    /// the list (``WorkingCopy/move(_:to:placing:resolvingWith:at:)``). A move is never refused for a version
    /// conflict (KanbanViewKit D100).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The tasks, the column, and the place of the block in the column.
    /// - Returns: Each task after the move, in the order of the list. The GraphQL field is nullable, so that an error
    ///   gives `null` for this field only.
    /// - Throws: The errors of ``KanbanContext/changeTasks(_:named:includingTombstones:_:)``, and of the column and
    ///   the place: ``KanbanError/invalidOrdinal(ordinal:)``, ``KanbanError/invalidSlug(name:)``, and
    ///   ``KanbanError/reservedSlug(type:)``. The decode of the input throws
    ///   ``KanbanError/conflictingPlacement(fields:)`` before this resolver runs, so that the field writes nothing.
    fileprivate func moveTasks(
        context: KanbanContext,
        arguments: InputArguments<MoveTasksInput>
    ) async throws -> [TaskObject]? {
        let input = arguments.input
        return try await context.changeTasks(input.id, named: MutationName.moveTasks) { work, resolver, refs, time in
            try work.move(refs, to: input.column, placing: input.placement, resolvingWith: resolver, at: time)
        }
    }

    /// Resolves `Mutation.deleteTasks`: makes each task of the list a tombstone, in one transaction (divergence.md
    /// §20).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The tasks.
    /// - Returns: Each tombstone, with `deleted` set, in the order of the list.
    /// - Throws: The errors of ``KanbanContext/changeTasks(_:named:includingTombstones:_:)``: a ref that names no live
    ///   task gives `NOT_FOUND`.
    fileprivate func deleteTasks(
        context: KanbanContext,
        arguments: InputArguments<TaskListInput<DeleteTasksMutation>>
    ) async throws -> [TaskObject]? {
        try await changeTombstones(to: true, context: context, arguments)
    }

    /// Resolves `Mutation.undeleteTasks`: makes each tombstoned task of the list live again, in one transaction
    /// (divergence.md §20). A live task does not change. Each task obeys the dependency rule of plan.md §3.3, rule 6.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The tasks.
    /// - Returns: Each live task, in the order of the list.
    /// - Throws: The errors of ``KanbanContext/changeTasks(_:named:includingTombstones:_:)``: a ref that names no task
    ///   gives `NOT_FOUND`. ``KanbanError/dependencyCycle(path:)`` when a task closes a `dependsOn` cycle. The call
    ///   then writes nothing.
    fileprivate func undeleteTasks(
        context: KanbanContext,
        arguments: InputArguments<TaskListInput<UndeleteTasksMutation>>
    ) async throws -> [TaskObject]? {
        try await changeTombstones(to: false, context: context, arguments)
    }

    /// Writes a `delete` patch on each task of a list, in one transaction: `true` makes a tombstone, `false` makes a
    /// tombstone live again. A patch that does not change the task is not written.
    ///
    /// - Parameters:
    ///   - isDeleted: `true` for a delete, `false` for an undelete.
    ///   - context: The context of the call.
    ///   - arguments: The tasks. A delete names live tasks. An undelete can also name tombstones. The mutation of the
    ///     `input` type is the public mutation of the call.
    /// - Returns: Each task after the change, in the order of the list.
    /// - Throws: The errors of ``KanbanContext/changeTasks(_:named:includingTombstones:_:)``.
    ///   ``KanbanError/dependencyCycle(path:)`` when an undeleted task closes a `dependsOn` cycle.
    private func changeTombstones<Mutation: SharedInputMutation>(
        to isDeleted: Bool,
        context: KanbanContext,
        _ arguments: InputArguments<TaskListInput<Mutation>>
    ) async throws -> [TaskObject]? {
        try await context.changeTasks(
            arguments.input.id,
            named: Mutation.name,
            includingTombstones: !isDeleted
        ) { work, resolver, refs, time in
            for ref in refs {
                try work.setDeleted(isDeleted, of: ref, inBoard: resolver.boardKey, at: time)
            }
        }
    }
}

extension KanbanContext {
    /// Runs one public list mutation field that changes tasks of one board at the time of ``clock``, and gives the
    /// tasks after the field (divergence.md §20). The first ref names the board of the field. The field obeys the
    /// rules of ``runMutation(named:on:_:)``: its patches are one transaction, and the field writes nothing when the
    /// body throws. An empty list writes nothing and gives an empty list.
    ///
    /// - Parameters:
    ///   - ids: The tasks: full URIs or short forms, in the order of the list.
    ///   - operation: The name of the public mutation of the field.
    ///   - includesTombstones: `true` when a ref can name a tombstone.
    ///   - body: Makes and applies the patches of the field. It gets the working copy, a resolver of the forgiving
    ///     refs of the working graph, the local ref of each task in the order of the list with each task one time, and
    ///     the time.
    /// - Returns: Each task object, in the order of the list.
    /// - Throws: The errors of ``RefResolver/taskRefs(for:includingTombstones:)``.
    ///   ``KanbanError/notFound(type:reference:)`` when the engine did not load the board of the tasks yet, so that the
    ///   field never gives `null` with no error. The store then records the request, and the call runs again after the
    ///   load. The error of the body.
    fileprivate func changeTasks(
        _ ids: [NodeID],
        named operation: String,
        includingTombstones includesTombstones: Bool = false,
        _ body: sending (inout WorkingCopy, RefResolver, [LocalRef], DateTime) throws -> Void
    ) async throws -> [TaskObject] {
        guard let first = ids.first else {
            return []
        }
        let changed = try await runMutation(named: operation, on: .holding(first)) { work, resolver, time in
            let refs = try resolver.taskRefs(for: ids, includingTombstones: includesTombstones)
            try body(&work, resolver, refs, time)
            return refs
        }
        guard let changed else {
            throw KanbanError.notFound(type: .task, reference: first.text)
        }
        return changed.value.compactMap { ref -> TaskObject? in changed.view.object(of: ref) }
    }
}

extension RefResolver {
    /// Changes the forgiving refs of a list mutation to the local refs of tasks of this board (divergence.md §20).
    /// The result keeps the order of the list, and gives a task that two refs name one time, at its first place. Each
    /// ref is resolved before the call writes, so that a ref that names no task stops the whole call.
    ///
    /// - Parameters:
    ///   - ids: The refs as the caller wrote them.
    ///   - includesTombstones: `true` when a ref can name a tombstone.
    /// - Returns: The local ref of each task.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when one ref names no task, and
    ///   ``KanbanError/nodesNotFound(type:references:)`` with each such ref when two or more refs name no task. The
    ///   other errors of ``nodeRef(for:ofType:includingTombstones:)``, for example
    ///   ``KanbanError/ambiguousID(reference:matches:)``.
    fileprivate func taskRefs(
        for ids: [NodeID],
        includingTombstones includesTombstones: Bool
    ) throws(KanbanError) -> [LocalRef] {
        let resolved = ids.map { id in
            Result { () throws(KanbanError) in
                try nodeRef(for: id, ofType: .task, includingTombstones: includesTombstones)
            }
        }
        let missing = zip(ids, resolved).compactMap { id, result -> String? in
            guard case .failure(.notFound) = result else {
                return nil
            }
            return id.text
        }
        guard missing.isEmpty else {
            throw missing.count == 1
                ? .notFound(type: .task, reference: missing[0])
                : .nodesNotFound(type: .task, references: missing)
        }
        let refs = try resolved.map { result throws(KanbanError) in try result.get() }
        return refs.enumerated()
            .filter { entry in refs.firstIndex(of: entry.element) == entry.offset }
            .map(\.element)
    }
}

extension WorkingCopy {
    /// Writes the task patches of a move of a list of tasks: the tasks go to the column as one block, in the order of
    /// the list (divergence.md §20). The first task goes to the place of the input, with the rules of
    /// ``Graph/ordinal(placing:inColumn:moving:resolvingWith:)``, and each next task goes just after the task before
    /// it. A `before` or `after` ref that names no live task puts the block at the end of the column, with one
    /// warning (divergence.md P1).
    ///
    /// - Parameters:
    ///   - tasks: The local refs of the tasks, in the order of the block.
    ///   - id: The column that the input names, or `nil` for the column where the first task shows.
    ///   - placement: The place of the block in the column.
    ///   - resolver: The resolver of the forgiving refs of the board.
    ///   - time: The time of the change.
    /// - Throws: The errors of ``columnRef(forMoveOf:to:resolvingWith:at:)`` and of
    ///   ``Graph/ordinal(placing:inColumn:moving:resolvingWith:)``. An ``EventError`` when a patch breaks a rule of
    ///   the log.
    fileprivate mutating func move(
        _ tasks: [LocalRef],
        to id: NodeID?,
        placing placement: Placement,
        resolvingWith resolver: RefResolver,
        at time: DateTime
    ) throws {
        guard let first = tasks.first else {
            return
        }
        let column = try columnRef(forMoveOf: first, to: id, resolvingWith: resolver, at: time)
        let ordinal = try graph.ordinal(placing: placement, inColumn: column, moving: first, resolvingWith: resolver)
        try move(first, to: column, placingAt: ordinal, at: time)
        for (previous, task) in zip(tasks, tasks.dropFirst()) {
            let next = graph.ordinal(beside: previous, on: .after, inColumn: column, moving: task)
            try move(task, to: column, placingAt: next, at: time)
        }
    }
}

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Gives the `id` input field of an `input` type of a list mutation of tasks, so that the field has one
    /// definition.
    ///
    /// - Returns: The field `id`, with the description of a list of task refs.
    fileprivate static func makeTaskListField<Listed: TaskListReferenceInput>(
    ) -> InputFieldComponent<Listed, KanbanContext> {
        InputField("id", at: \Listed.id).description(SchemaDescription.taskListReference)
    }

    /// The input fields of `MoveTasksInput`.
    ///
    /// - Returns: The fields `id`, `column`, `ordinal`, `before`, and `after`.
    fileprivate static func moveTasksFields() -> [InputFieldComponent<MoveTasksInput, KanbanContext>] {
        let head: [InputFieldComponent<MoveTasksInput, KanbanContext>] = [
            makeTaskListField(),
            InputField("column", at: \.column).description(SchemaDescription.taskBlockColumn),
        ]
        return head + placeFields(describedBy: .taskBlock)
    }

    /// Gives the `input` type of `deleteTasks` or `undeleteTasks` (``TaskListInput``), with the name of the mutation
    /// (EXTRAS-9 rule 7), so that the fields have one definition.
    ///
    /// - Parameter mutation: The mutation of the `input` type.
    /// - Returns: The `input` type `<Mutation>Input`, with its one field `id`.
    fileprivate static func makeTaskListInput<Mutation: SharedInputMutation>(
        of mutation: Mutation.Type
    ) -> Input<KanbanResolver, KanbanContext, TaskListInput<Mutation>> {
        Input(TaskListInput<Mutation>.self, as: TaskListInput<Mutation>.inputTypeName) {
            Self.makeTaskListField()
        }
        .description(SchemaDescription.taskListInput(of: mutation.name))
    }

    /// Adds the list mutations of tasks and their `input` types (divergence.md §20): `moveTasks`, `deleteTasks`, and
    /// `undeleteTasks`. These are the list mutations of the TestudoApp design KANBAN-8. Each mutation has an `input`
    /// type of its own name (EXTRAS-9 rule 7).
    ///
    /// - Returns: This builder, for method chaining.
    fileprivate func addTaskListMutations() -> Self {
        add {
            Input(MoveTasksInput.self, Self.moveTasksFields).description(SchemaDescription.moveTasksInput)
            Self.makeTaskListInput(of: DeleteTasksMutation.self)
            Self.makeTaskListInput(of: UndeleteTasksMutation.self)
        }
        .addMutation {
            Self.mutationField(
                MutationName.moveTasks,
                at: KanbanResolver.moveTasks,
                description: SchemaDescription.moveTasks
            )
            Self.mutationField(
                MutationName.deleteTasks,
                at: KanbanResolver.deleteTasks,
                description: SchemaDescription.deleteTasks
            )
            Self.mutationField(
                MutationName.undeleteTasks,
                at: KanbanResolver.undeleteTasks,
                description: SchemaDescription.undeleteTasks
            )
        }
    }
}
