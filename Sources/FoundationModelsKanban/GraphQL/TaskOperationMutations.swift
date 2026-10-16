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

/// The `input` object of `assignTask` and `unassignTask` (plan.md §4.2).
private struct AssignTaskInput: Decodable, Sendable {
    /// The task: a full URI or a short form (plan.md §3.2).
    let id: NodeID

    /// The actor: a full URI or the slug.
    let actor: NodeID
}

/// The `input` object of `tagTask` and `untagTask` (plan.md §4.2).
private struct TagTaskInput: Decodable, Sendable {
    /// The task: a full URI or a short form (plan.md §3.2).
    let id: NodeID

    /// The tag names, slugs, stored local forms `tag/<slug>`, or tag URIs.
    let tags: [String]
}

/// The side of a neighbor task where a moved task goes. The raw value is the name of the place field of the input.
private enum NeighborSide: String {
    /// Before the neighbor.
    case before

    /// After the neighbor.
    case after
}

/// The place of a moved or copied task in its column, from the place fields of a `moveTask` or `copyTask` input
/// (plan.md §4.2, §6, "moveTask"). A value holds one place, so an input with more than one place field cannot make a
/// value.
enum Placement: Decodable, Sendable {
    /// The code of the warning for a `before` or `after` ref that names no task, in `extensions.warnings`
    /// (divergence.md P1).
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

    /// Gives the warning for a `before` or `after` ref that names no task: the call put the task at the end of the
    /// column (divergence.md P1).
    ///
    /// - Parameters:
    ///   - neighbor: The neighbor ref as the input writes it. The warning quotes it.
    ///   - side: The place field of the ref.
    /// - Returns: The warning, for example "The before ref `zzzzzzz` names no task. …".
    fileprivate static func neighborNotFoundWarning(for neighbor: NodeID, on side: NeighborSide) -> ResponseWarning {
        let message = "The \(side.rawValue) ref `\(neighbor.text)` names no task. The call put the task at the end of "
            + "the column. Send the id of a task in the column to put the task next to that task."
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
        arguments: InputArguments<NodeReferenceInput>
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
        arguments: InputArguments<AssignTaskInput>
    ) async throws -> TaskObject? {
        try await changeAssignee(to: true, as: MutationName.assignTask, context: context, arguments)
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
        arguments: InputArguments<AssignTaskInput>
    ) async throws -> TaskObject? {
        try await changeAssignee(to: false, as: MutationName.unassignTask, context: context, arguments)
    }

    /// Writes an `add` or a `remove` of one actor on the `assignees` of a task.
    ///
    /// - Parameters:
    ///   - isAssigned: `true` to add the actor, `false` to remove it.
    ///   - operation: The name of the public mutation.
    ///   - context: The context of the call.
    ///   - arguments: The task and the actor. A remove can also name a tombstoned actor.
    /// - Returns: The task after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the id.
    ///   ``KanbanError/actorNotFound(reference:)`` when the actor names no actor that the change accepts.
    private func changeAssignee(
        to isAssigned: Bool,
        as operation: String,
        context: KanbanContext,
        _ arguments: InputArguments<AssignTaskInput>
    ) async throws -> TaskObject? {
        let input = arguments.input
        return try await context.changeTask(input.id, named: operation) { work, resolver, ref, time in
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
        arguments: InputArguments<TagTaskInput>
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
        arguments: InputArguments<TagTaskInput>
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
        arguments: InputArguments<NodeReferenceInput>
    ) async throws -> TaskObject? {
        try await changeDeleted(to: true, ofType: .task, as: MutationName.deleteTask, context: context, arguments)
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
        arguments: InputArguments<NodeReferenceInput>
    ) async throws -> TaskObject? {
        try await changeDeleted(to: false, ofType: .task, as: MutationName.undeleteTask, context: context, arguments)
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
    fileprivate func changeTask(
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
    fileprivate mutating func move(
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
            ResolverWarnings.current?.add(Placement.neighborNotFoundWarning(for: neighbor, on: side))
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
    private func ordinal(
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
    /// Adds the task operation mutations and their `input` types (plan.md §4.2): `moveTask`, `completeTask`,
    /// `assignTask`, `unassignTask`, `tagTask`, `untagTask`, `deleteTask`, and `undeleteTask`. The mutations that name
    /// only the task use the `input` type of ``NodeReferenceInput``, which ``addColumnActorMutations()`` adds.
    ///
    /// - Returns: This builder, for method chaining.
    func addTaskOperationMutations() -> Self {
        add {
            Input(MoveTaskInput.self, Self.placementFields)
            Input(AssignTaskInput.self) {
                InputField("id", at: \.id)
                InputField("actor", at: \.actor)
            }
            Input(TagTaskInput.self) {
                InputField("id", at: \.id)
                InputField("tags", at: \.tags)
            }
        }
        .addMutation {
            Field(MutationName.moveTask, at: KanbanResolver.moveTask) { Argument("input", at: \.input) }
            Field(MutationName.completeTask, at: KanbanResolver.completeTask) { Argument("input", at: \.input) }
            Field(MutationName.assignTask, at: KanbanResolver.assignTask) { Argument("input", at: \.input) }
            Field(MutationName.unassignTask, at: KanbanResolver.unassignTask) { Argument("input", at: \.input) }
            Field(MutationName.tagTask, at: KanbanResolver.tagTask) { Argument("input", at: \.input) }
            Field(MutationName.untagTask, at: KanbanResolver.untagTask) { Argument("input", at: \.input) }
            Field(MutationName.deleteTask, at: KanbanResolver.deleteTask) { Argument("input", at: \.input) }
            Field(MutationName.undeleteTask, at: KanbanResolver.undeleteTask) { Argument("input", at: \.input) }
        }
    }
}
