import FoundationModelsExtras
import Graphiti
import GraphQL

// MARK: - Names

extension MutationName {
    /// The mutation that makes a column.
    static let addColumn = "addColumn"

    /// The mutation that changes the name, the order, or the body of a column.
    static let updateColumn = "updateColumn"

    /// The mutation that makes a column a tombstone.
    static let deleteColumn = "deleteColumn"

    /// The mutation that makes a tombstoned column live again.
    static let undeleteColumn = "undeleteColumn"

    /// The mutation that makes an actor.
    static let addActor = "addActor"

    /// The mutation that changes the name, the color, the avatar, or the body of an actor.
    static let updateActor = "updateActor"

    /// The mutation that makes an actor a tombstone.
    static let deleteActor = "deleteActor"

    /// The mutation that makes a tombstoned actor live again.
    static let undeleteActor = "undeleteActor"
}

// MARK: - Arguments

/// The arguments of a mutation: the one required argument `input` (plan.md §4.2, EXTRAS-9 rule 7). The argument is
/// required also when its type has no required field, so a call that sets no field gives `input: {}`.
struct InputArguments<Input: Decodable & Sendable>: Decodable, Sendable {
    /// The `input` object of the mutation.
    let input: Input
}

/// The `input` object of `addColumn` (plan.md §4.2).
private struct AddColumnInput: Codable, NewNodeBodyInput, TargetBoardInput {
    /// The id of the new column, or `nil` for the slug of ``name``. The id is the slug of this text, or the slug of a
    /// full column URI of the board (plan.md §3.2).
    let id: NodeID?

    /// The name of the column.
    let name: String

    /// The sort key of the column, or `nil` for one more than the order of the terminal column.
    let order: Int?

    /// The Markdown body of the column: the full text, or `nil` for no body.
    let body: String?

    /// The board of the column: a board key, a repo directory name, or a path, or `nil` for the current board
    /// (plan.md §6.6).
    let board: String?
}

/// The `input` object of `updateColumn` (plan.md §4.2). A field that is not set does not change. `null` for the
/// `order` gives the order 0, and `null` clears the body. The `name` is required, so `null` does not change it
/// (``IgnoredNull``).
private struct UpdateColumnInput: ChangedNameInput, ChangedBodyInput {
    /// The column: a full URI, the stored form `column/<slug>`, the slug, or a name that gives the slug (plan.md
    /// §3.2, ``RefResolver``).
    let id: NodeID

    /// The new name of the column. `null` gives no change and a warning (``IgnoredNull``).
    let name: FieldUpdate<String>

    /// The new sort key of the column. `null` gives the order 0.
    let order: FieldUpdate<Int>

    /// The new Markdown body of the column: the full text. The mutation writes the diff from the current body.
    let body: FieldUpdate<String>
}

/// The `input` object of `addActor` (plan.md §4.2). The input must give an id or a name, or both.
private struct AddActorInput: Codable, NewNodeBodyInput, TargetBoardInput {
    /// The id of the new actor, or `nil` for the slug of ``name``. The id is the slug of this text, or the slug of a
    /// full actor URI of the board (plan.md §3.2).
    let id: NodeID?

    /// The name of the actor, or `nil` for the slug of ``id`` (divergence.md Q19, `addActor(input: { id: "x" })`).
    let name: String?

    /// The color of the actor, or `nil` for no color.
    let color: String?

    /// The avatar of the actor, for example a URL or an emoji, or `nil` for no avatar (divergence.md Q19).
    let avatar: String?

    /// The Markdown body of the actor: the full text, or `nil` for no body.
    let body: String?

    /// `true` to return the actor that has the id when the board has that actor, live or tombstoned. The call makes a
    /// tombstoned actor live again, and writes each given name, color, and avatar that is different (divergence.md
    /// Q16). Else that actor gives `DUPLICATE_ID`.
    let ensure: Bool?

    /// The board of the actor: a board key, a repo directory name, or a path, or `nil` for the current board
    /// (plan.md §6.6).
    let board: String?
}

/// The `input` object of `updateActor` (plan.md §4.2). A field that is not set does not change, and `null` clears
/// the field. The `name` is required, so `null` does not change it (``IgnoredNull``).
private struct UpdateActorInput: ChangedNameInput, ChangedColorInput, ChangedBodyInput {
    /// The actor: a full URI, the stored form `actor/<slug>`, the slug, or a name that gives the slug (plan.md §3.2,
    /// ``RefResolver``).
    let id: NodeID

    /// The new name of the actor. `null` gives no change and a warning (``IgnoredNull``).
    let name: FieldUpdate<String>

    /// The new color of the actor.
    let color: FieldUpdate<String>

    /// The new avatar of the actor (divergence.md Q19).
    let avatar: FieldUpdate<String>

    /// The new Markdown body of the actor: the full text. The mutation writes the diff from the current body.
    let body: FieldUpdate<String>
}

/// The `input` object of a mutation that names one node and has no other field: `completeTask`, and the delete and the
/// undelete mutations of columns, actors, tasks, and tags (plan.md §4.2). Each of these mutations has its own `input`
/// type, `<Mutation>Input` (``SharedInputMutation``), that ``SchemaBuilder/makeNodeReferenceInput(of:)`` gives. The
/// comment mutations use `CommentReferenceInput`, which can also name the task of the comment.
struct NodeReferenceInput<Mutation: SharedInputMutation>: Codable, Sendable {
    /// The node: a full URI or a short form (plan.md §3.2).
    let id: NodeID
}

/// The `deleteColumn` mutation, for its `input` type `DeleteColumnInput`.
private enum DeleteColumnMutation: SharedInputMutation {
    /// The name of the mutation.
    static let name = MutationName.deleteColumn
}

/// The `undeleteColumn` mutation, for its `input` type `UndeleteColumnInput`.
private enum UndeleteColumnMutation: SharedInputMutation {
    /// The name of the mutation.
    static let name = MutationName.undeleteColumn
}

/// The `deleteActor` mutation, for its `input` type `DeleteActorInput`.
private enum DeleteActorMutation: SharedInputMutation {
    /// The name of the mutation.
    static let name = MutationName.deleteActor
}

/// The `undeleteActor` mutation, for its `input` type `UndeleteActorInput`.
private enum UndeleteActorMutation: SharedInputMutation {
    /// The name of the mutation.
    static let name = MutationName.undeleteActor
}

// MARK: - Column resolvers

extension KanbanResolver {
    /// Resolves `Mutation.addColumn`: makes a column with a `set` of the name and the order, and an `edit` of the
    /// body, in one patch (plan.md §4.2).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The new column.
    /// - Returns: The column. The GraphQL field is nullable, so that an error gives `null` for this field only.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the id is a URI that does not name a column of the
    ///   board. ``KanbanError/invalidSlug(name:)`` when the id gives an empty slug.
    ///   ``KanbanError/reservedSlug(type:)`` when the id gives the slug ``Slug/reservedForBoard``.
    ///   ``KanbanError/duplicateID(type:id:)`` when the board has a column with the slug, live or tombstoned.
    fileprivate func addColumn(
        context: KanbanContext,
        arguments: InputArguments<AddColumnInput>
    ) async throws -> ColumnObject? {
        let input = arguments.input
        let board = MutationBoard.named(input.board)
        return try await context.changeNode(named: MutationName.addColumn, on: board) { work, resolver, time in
            let slug = try resolver.slug(ofNewNode: input.id, named: input.name, ofType: .column)
            let ref = LocalRef.column(slug: slug.value)
            let order = input.order ?? work.graph.nextColumnOrder
            let values = [String: PatchValue](
                givenValues: [PropertyName.name: .string(input.name), PropertyName.order: .integer(order)]
            )
            try work.addNode(ref, setting: values, body: input.body, at: time)
            return ref
        }
    }

    /// Resolves `Mutation.updateColumn`: changes the given fields of a column. The slug does not change.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The column and the changes.
    /// - Returns: The column after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live column has the id.
    fileprivate func updateColumn(
        context: KanbanContext,
        arguments: InputArguments<UpdateColumnInput>
    ) async throws -> ColumnObject? {
        let input = arguments.input
        let board = MutationBoard.holding(input.id)
        let column: ColumnObject? = try await context.changeNode(
            named: MutationName.updateColumn,
            on: board
        ) { work, resolver, time in
            let ref = try resolver.nodeRef(for: input.id, ofType: .column)
            let values = [
                PropertyName.name: input.name.ignoringNull.map(PatchValue.string),
                PropertyName.order: input.order.map(PatchValue.integer),
            ]
            try work.updateNode(ref, updating: values, body: input.body, at: time)
            return ref
        }
        await context.warnIfNull(input.name, forField: PropertyName.name, of: MutationName.updateColumn)
        return column
    }

    /// Resolves `Mutation.deleteColumn`: makes the column a tombstone (plan.md §3.3).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The column.
    /// - Returns: The tombstone, with `deleted` set.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live column has the id.
    ///   ``KanbanError/columnNotEmpty(column:liveTaskCount:)`` when the column shows live tasks.
    fileprivate func deleteColumn(
        context: KanbanContext,
        arguments: InputArguments<NodeReferenceInput<DeleteColumnMutation>>
    ) async throws -> ColumnObject? {
        try await changeDeleted(to: true, ofType: .column, context: context, arguments)
    }

    /// Resolves `Mutation.undeleteColumn`: makes a tombstoned column live again. A live column does not change.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The column.
    /// - Returns: The live column.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no column has the id.
    fileprivate func undeleteColumn(
        context: KanbanContext,
        arguments: InputArguments<NodeReferenceInput<UndeleteColumnMutation>>
    ) async throws -> ColumnObject? {
        try await changeDeleted(to: false, ofType: .column, context: context, arguments)
    }
}

// MARK: - Actor resolvers

extension KanbanResolver {
    /// Resolves `Mutation.addActor`: makes an actor with a `set` of the name, the color, and the avatar, and an `edit`
    /// of the body, in one patch (plan.md §4.2). An input with no name gives the slug as the name.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The new actor. ``AddActorInput`` has no required field, so `input: {}` gives no id and no name.
    /// - Returns: The actor. With `ensure`, the actor that the board has, live, with each given name, color, and avatar
    ///   (``WorkingCopy/ensureActor(_:matching:at:)``).
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the id is a URI that does not name an actor of the
    ///   board. ``KanbanError/invalidSlug(name:)`` when the id gives an empty slug, or when the input gives no id and
    ///   no name. ``KanbanError/reservedSlug(type:)`` when the board has no actor with the slug, and the id gives the
    ///   slug ``Slug/reservedForBoard``.
    ///   ``KanbanError/duplicateID(type:id:)`` when the board has an actor with the slug and `ensure` is not `true`.
    fileprivate func addActor(
        context: KanbanContext,
        arguments: InputArguments<AddActorInput>
    ) async throws -> ActorObject? {
        let input = arguments.input
        let board = MutationBoard.named(input.board)
        return try await context.changeNode(named: MutationName.addActor, on: board) { work, resolver, time in
            let slug = try resolver.slug(ofNewNode: input.id, named: input.name ?? "", ofType: .actor)
            let ref = LocalRef.actor(slug: slug.value)
            if input.ensure == true, work.graph.hasNode(ref) {
                try work.ensureActor(ref, matching: input, at: time)
                return ref
            }
            let values = [String: PatchValue](
                givenValues: [
                    PropertyName.name: .string(input.name ?? slug.value),
                    PropertyName.color: input.color.map(PatchValue.string),
                    PropertyName.avatar: input.avatar.map(PatchValue.string),
                ]
            )
            try work.addNode(ref, setting: values, body: input.body, at: time)
            return ref
        }
    }

    /// Resolves `Mutation.updateActor`: changes the given fields of an actor. The slug does not change.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The actor and the changes.
    /// - Returns: The actor after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live actor has the id.
    fileprivate func updateActor(
        context: KanbanContext,
        arguments: InputArguments<UpdateActorInput>
    ) async throws -> ActorObject? {
        let input = arguments.input
        let board = MutationBoard.holding(input.id)
        let actor: ActorObject? = try await context.changeNode(
            named: MutationName.updateActor,
            on: board
        ) { work, resolver, time in
            let ref = try resolver.nodeRef(for: input.id, ofType: .actor)
            let values = [
                PropertyName.name: input.name.ignoringNull.map(PatchValue.string),
                PropertyName.color: input.color.map(PatchValue.string),
                PropertyName.avatar: input.avatar.map(PatchValue.string),
            ]
            try work.updateNode(ref, updating: values, body: input.body, at: time)
            return ref
        }
        await context.warnIfNull(input.name, forField: PropertyName.name, of: MutationName.updateActor)
        return actor
    }

    /// Resolves `Mutation.deleteActor`: makes the actor a tombstone (plan.md §3.3).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The actor.
    /// - Returns: The tombstone, with `deleted` set.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live actor has the id.
    fileprivate func deleteActor(
        context: KanbanContext,
        arguments: InputArguments<NodeReferenceInput<DeleteActorMutation>>
    ) async throws -> ActorObject? {
        try await changeDeleted(to: true, ofType: .actor, context: context, arguments)
    }

    /// Resolves `Mutation.undeleteActor`: makes a tombstoned actor live again. A live actor does not change.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The actor.
    /// - Returns: The live actor.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no actor has the id.
    fileprivate func undeleteActor(
        context: KanbanContext,
        arguments: InputArguments<NodeReferenceInput<UndeleteActorMutation>>
    ) async throws -> ActorObject? {
        try await changeDeleted(to: false, ofType: .actor, context: context, arguments)
    }

    /// Writes a `delete` patch on one node: `true` makes a tombstone, `false` makes a tombstone live again (plan.md
    /// §4.2). A patch that does not change the node is not written. The node can be in a related board (plan.md
    /// §6.6).
    ///
    /// - Parameters:
    ///   - isDeleted: `true` for a delete, `false` for an undelete.
    ///   - type: The node type.
    ///   - context: The context of the call.
    ///   - arguments: The node. A delete names a live node. An undelete can also name a tombstone. The mutation of
    ///     the `input` type is the public mutation of the call.
    /// - Returns: The node after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no node of the type has the id.
    ///   ``KanbanError/columnNotEmpty(column:liveTaskCount:)`` when a deleted column shows live tasks.
    ///   ``KanbanError/dependencyCycle(path:)`` when an undeleted task closes a `dependsOn` cycle.
    func changeDeleted<Object: SlotNodeObject, Mutation: SharedInputMutation>(
        to isDeleted: Bool,
        ofType type: PatchNodeType,
        context: KanbanContext,
        _ arguments: InputArguments<NodeReferenceInput<Mutation>>
    ) async throws -> Object? {
        let id = arguments.input.id
        return try await changeDeleted(to: isDeleted, as: Mutation.name, context: context, holding: id) { resolver in
            try resolver.nodeRef(for: id, ofType: type, includingTombstones: !isDeleted)
        }
    }

    /// Writes a `delete` patch on the node that a resolve gives: `true` makes a tombstone, `false` makes a tombstone
    /// live again. The rules are the rules of ``changeDeleted(to:ofType:context:_:)``.
    ///
    /// - Parameters:
    ///   - isDeleted: `true` for a delete, `false` for an undelete.
    ///   - operation: The name of the public mutation.
    ///   - context: The context of the call.
    ///   - id: The node ref that the input gives. It names the board of the field.
    ///   - resolve: Gives the local ref of the node from the resolver of the forgiving refs of the board.
    /// - Returns: The node after the change.
    /// - Throws: The error of `resolve`. ``KanbanError/columnNotEmpty(column:liveTaskCount:)`` when a deleted column
    ///   shows live tasks. ``KanbanError/dependencyCycle(path:)`` when an undeleted task closes a `dependsOn` cycle.
    func changeDeleted<Object: SlotNodeObject>(
        to isDeleted: Bool,
        as operation: String,
        context: KanbanContext,
        holding id: NodeID,
        resolving resolve: @escaping @Sendable (RefResolver) throws -> LocalRef
    ) async throws -> Object? {
        try await context.changeNode(named: operation, on: .holding(id)) { work, resolver, time in
            let ref = try resolve(resolver)
            try work.setDeleted(isDeleted, of: ref, inBoard: resolver.boardKey, at: time)
            return ref
        }
    }
}

// MARK: - Store

extension BoardView {
    /// Gives the object of the node of a local ref, live or tombstoned.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The object, or `nil` when the graph has no node of the type of the object for the ref.
    func object<Object: SlotNodeObject>(of ref: LocalRef) -> Object? {
        graph.slot(for: ref).flatMap { slot in object(at: slot) }
    }
}

extension KanbanContext {
    /// Runs one public mutation field at the time of ``clock``, and gives the value of the body and the read view of
    /// the board after the field.
    ///
    /// The field obeys the rules of ``BoardStore/runMutation(named:on:at:_:)``: it writes to the board that it names,
    /// with the auto-init and the session actor of that board.
    ///
    /// - Parameters:
    ///   - operation: The name of the public mutation of the field.
    ///   - board: The board of the field.
    ///   - body: Makes and applies the patches of the field, and gives its value. It gets the working copy, a resolver
    ///     of the forgiving refs of the working graph, and the time.
    /// - Returns: The value of the body and the read view of the board after the field, or `nil` when the engine did
    ///   not load the board yet.
    /// - Throws: ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board for the ref. The
    ///   error of the body, or an ``EventError`` when a patch breaks a rule of the log.
    func runMutation<Value: Sendable>(
        named operation: String,
        on board: MutationBoard,
        _ body: sending (inout WorkingCopy, RefResolver, DateTime) throws -> Value
    ) async throws -> (value: Value, view: BoardView)? {
        let time = clock()
        return try await store.runMutation(named: operation, on: board, at: time) { work, resolver in
            try body(&work, resolver, time)
        }
    }

    /// Runs one public mutation field that changes one node at the time of ``clock``, and gives the object of the node
    /// after the field. The field obeys the rules of ``runMutation(named:on:_:)``.
    ///
    /// - Parameters:
    ///   - operation: The name of the public mutation of the field.
    ///   - board: The board of the field.
    ///   - body: Makes and applies the patches of the field, and gives the local ref of the node. It gets the working
    ///     copy, a resolver of the forgiving refs of the working graph, and the time.
    /// - Returns: The object of the node, live or tombstoned, or `nil` when the engine did not load the board yet.
    /// - Throws: ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board for the ref. The
    ///   error of the body, or an ``EventError`` when a patch breaks a rule of the log.
    func changeNode<Object: SlotNodeObject>(
        named operation: String,
        on board: MutationBoard,
        _ body: sending (inout WorkingCopy, RefResolver, DateTime) throws -> LocalRef
    ) async throws -> Object? {
        let changed = try await runMutation(named: operation, on: board, body)
        return changed.flatMap { ref, view in view.object(of: ref) }
    }
}

// MARK: - Patches

extension WorkingCopy {
    /// Makes a node with one patch: a `set` of the values and an `edit` diff from the empty body (plan.md §4.2).
    ///
    /// - Parameters:
    ///   - ref: The local ref of the new node.
    ///   - values: The properties of the node.
    ///   - body: The body of the node, or `nil` for no body.
    ///   - time: The time of the change.
    /// - Throws: ``KanbanError/reservedSlug(type:)`` or ``KanbanError/reservedTagName`` when the slug of the node is
    ///   ``Slug/reservedForBoard``, and ``KanbanError/virtualTagName(tag:)`` when the slug of a tag is the name of a
    ///   virtual tag (``LocalRef/checkSlugIsNotReserved()``). ``KanbanError/duplicateID(type:id:)`` when the graph
    ///   has the node, live or tombstoned. A patch on a tombstone does not make it live, so the caller must
    ///   undelete it. An ``EventError`` when the patch breaks a rule of the log.
    mutating func addNode(
        _ ref: LocalRef,
        setting values: [String: PatchValue],
        body: String?,
        at time: DateTime
    ) throws {
        try ref.checkSlugIsNotReserved()
        guard !graph.hasNode(ref) else {
            throw KanbanError.duplicateID(type: ref.nodeType, id: ref.localID ?? ref.description)
        }
        try apply(PatchInput(changing: ref, setting: values, body: body, from: ""), at: time)
    }

    /// Changes a node with one patch: a `set` of each new value, an `unset` of each cleared property, and an `edit`
    /// diff from the current body (plan.md §4.2, §6). A value that does not change is not written.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - values: The update of each property.
    ///   - body: The update of the body.
    ///   - time: The time of the change.
    /// - Throws: An ``EventError`` when the patch breaks a rule of the log.
    mutating func updateNode(
        _ ref: LocalRef,
        updating values: [String: FieldUpdate<PatchValue>],
        body: FieldUpdate<String>,
        at time: DateTime
    ) throws(EventError) {
        try apply(PatchInput(changing: ref, updating: values, body: body, from: graph.body(of: ref)), at: time)
    }

    /// Writes a `delete` patch on a node. A delete of a column obeys the graph rule of plan.md §3.3, rule 5. An
    /// undelete of a tombstoned task obeys the dependency rule of plan.md §3.3, rule 6: the edges of a tombstone do
    /// not count, so the task can close a `dependsOn` cycle when it is live again (divergence.md X7).
    ///
    /// - Parameters:
    ///   - isDeleted: `true` for a delete, `false` for an undelete.
    ///   - ref: The local ref of the node.
    ///   - key: The current key of the board, for the read view of the rule.
    ///   - time: The time of the change.
    /// - Throws: ``KanbanError/columnNotEmpty(column:liveTaskCount:)`` when a deleted column shows live tasks.
    ///   ``KanbanError/dependencyCycle(path:)`` when an undeleted task closes a cycle. An ``EventError`` when the
    ///   patch breaks a rule of the log.
    fileprivate mutating func setDeleted(
        _ isDeleted: Bool,
        of ref: LocalRef,
        inBoard key: String,
        at time: DateTime
    ) throws {
        if isDeleted, ref.nodeType == .column {
            try checkEmpty(column: ref, inBoard: key)
        }
        let isTombstone = graph.node(for: ref)?.state.fields.isDeleted == true
        let makesTaskLive = !isDeleted && ref.nodeType == .task && isTombstone
        try apply(PatchInput(node: ref, delete: isDeleted), at: time)
        if makesTaskLive {
            try checkNoCycle(throughTask: ref, inBoard: key)
        }
    }

    /// Makes an actor that the graph has match the input of `addActor(ensure: true)`, the same as Rust (divergence.md
    /// Q16). A tombstoned actor gets a `delete: false` patch, so that it is live again. Then each of the name, the
    /// color, and the avatar that the input gives gets a `set` when it is different. A field that the input does not
    /// give does not change, and a patch that changes nothing is not written.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the actor.
    ///   - input: The input of `addActor`.
    ///   - time: The time of the change.
    /// - Throws: An ``EventError`` when a patch breaks a rule of the log.
    fileprivate mutating func ensureActor(
        _ ref: LocalRef,
        matching input: AddActorInput,
        at time: DateTime
    ) throws(EventError) {
        try apply(PatchInput(node: ref, delete: false), at: time)
        let given = [
            PropertyName.name: input.name,
            PropertyName.color: input.color,
            PropertyName.avatar: input.avatar,
        ]
        let values: [String: FieldUpdate<PatchValue>] = given.mapValues { value in
            value.map(PatchValue.string).map(FieldUpdate.changed) ?? .unchanged
        }
        try updateNode(ref, updating: values, body: .unchanged, at: time)
    }

    /// Checks that a column shows no live task, so that a delete can make it a tombstone (plan.md §3.3, rule 5). The
    /// tasks are the tasks of `Column.tasks`, so the count in the error is the count that the caller sees.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the column.
    ///   - key: The current key of the board.
    /// - Throws: ``KanbanError/columnNotEmpty(column:liveTaskCount:)`` when the column shows live tasks.
    ///   ``KanbanError/notFound(type:reference:)`` when the graph does not have the column.
    func checkEmpty(column ref: LocalRef, inBoard key: String) throws(KanbanError) {
        let view = BoardView(of: graph, inBoard: key)
        let column: ColumnObject = try view.requiredObject(
            at: graph.slot(for: ref),
            forEdge: .unresolved(.local(ref)),
            ofType: .column
        )
        let taskCount = try column.tasks(filteredBy: nil).count
        guard taskCount == .zero else {
            throw .columnNotEmpty(column: column.state.slug, liveTaskCount: taskCount)
        }
    }
}

extension Graph {
    /// The order of a column that the call adds with no order: one more than the order of the terminal column, or 0
    /// on a board with no live column. Thus the new column comes last (plan.md §6).
    var nextColumnOrder: Int {
        let terminal = ColumnOrder(of: self).terminal.flatMap { slot in node(at: slot, as: ColumnNode.self) }
        return terminal.map { column in column.order + 1 } ?? .zero
    }
}

extension RefResolver {
    /// Changes a forgiving ref to the local ref of a node of this board.
    ///
    /// - Parameters:
    ///   - id: The ref as the caller wrote it: a full URI or a short form.
    ///   - type: The node type that the caller expects.
    ///   - includesTombstones: `true` when the ref can name a tombstone.
    /// - Returns: The local ref of the node.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no node of the type has the ref.
    func nodeRef(
        for id: NodeID,
        ofType type: PatchNodeType,
        includingTombstones includesTombstones: Bool = false
    ) throws(KanbanError) -> LocalRef {
        let stored = try storedRef(for: id.text, ofType: type, includingTombstones: includesTombstones)
        guard case .local(let ref) = stored else {
            throw .notFound(type: type, reference: id.text)
        }
        return ref
    }

    /// Gives the slug of a column or an actor that an add mutation makes (plan.md §3.2). The slug is the slug of the
    /// key of the node (``newNodeKey(for:named:ofType:)``).
    ///
    /// - Parameters:
    ///   - id: The id that the input gives, or `nil` for no id.
    ///   - name: The name that the input gives.
    ///   - type: The node type: ``PatchNodeType/column`` or ``PatchNodeType/actor``.
    /// - Returns: The slug.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when a URI does not parse, names a node of a different
    ///   type, or has the key of a different board. ``KanbanError/invalidSlug(name:)`` when the text gives an empty
    ///   slug.
    func slug(ofNewNode id: NodeID?, named name: String, ofType type: PatchNodeType) throws(KanbanError) -> Slug {
        try Slug(columnOrActorName: newNodeKey(for: id, named: name, ofType: type))
    }

    /// Gives the key of a node that an add mutation makes (plan.md §3.2): the id, or the name when the input gives
    /// no id. A full URI gives its local id (``newNodeKey(for:ofType:)``). The caller applies the slug rule of the
    /// node type to the key.
    ///
    /// - Parameters:
    ///   - id: The id that the input gives, or `nil` for no id.
    ///   - name: The name that the input gives.
    ///   - type: The node type that the mutation makes.
    /// - Returns: The key of the node.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when a URI does not parse, names a node of a different
    ///   type, or has the key of a different board.
    func newNodeKey(for id: NodeID?, named name: String, ofType type: PatchNodeType) throws(KanbanError) -> String {
        guard let id else {
            return name
        }
        return try newNodeKey(for: id.text, ofType: type)
    }
}

extension PatchValue {
    /// Gives the value of a text property.
    ///
    /// - Parameter text: The text.
    /// - Returns: The JSON string value.
    static func string(_ text: String) -> PatchValue {
        .json(.string(text))
    }

    /// Gives the value of an integer property.
    ///
    /// - Parameter value: The integer.
    /// - Returns: The JSON number value.
    static func integer(_ value: Int) -> PatchValue {
        .json(.number(Number(value)))
    }
}

extension [String: PatchValue] {
    /// Makes the `set` part of a patch from the values that an input gives. A value that the input does not give is
    /// not in the part, so the property does not change.
    ///
    /// - Parameter values: The value of each property, or `nil` when the input does not give it.
    init(givenValues values: [String: PatchValue?]) {
        self = values.compactMapValues { value in value }
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the column and the actor mutations, and their `input` types (plan.md §4.2).
    ///
    /// - Returns: This builder, for method chaining.
    func addColumnActorMutations() -> Self {
        add {
            Input(AddColumnInput.self) {
                InputField("id", at: \.id).description(SchemaDescription.newColumnID)
                InputField("name", at: \.name).description(SchemaDescription.columnName)
                InputField("order", at: \.order).description(SchemaDescription.columnOrder)
                Self.makeNewBodyField()
                Self.makeTargetBoardField()
            }
            .description(SchemaDescription.addColumnInput)
            Input(UpdateColumnInput.self) {
                InputField("id", at: \.id).description(SchemaDescription.columnReference)
                Self.makeChangedNameField()
                InputField("order", at: \.order.value).description(SchemaDescription.changedColumnOrder)
                Self.makeChangedBodyField()
            }
            .description(SchemaDescription.updateColumnInput)
            Input(AddActorInput.self) {
                InputField("id", at: \.id).description(SchemaDescription.newActorID)
                InputField("name", at: \.name).description(SchemaDescription.addActorName)
                InputField("color", at: \.color).description(SchemaDescription.actorColor)
                InputField("avatar", at: \.avatar).description(SchemaDescription.actorAvatar)
                Self.makeNewBodyField()
                InputField("ensure", at: \.ensure).description(SchemaDescription.actorEnsure)
                Self.makeTargetBoardField()
            }
            .description(SchemaDescription.addActorInput)
            Input(UpdateActorInput.self) {
                InputField("id", at: \.id).description(SchemaDescription.actorReference)
                Self.makeChangedNameField()
                Self.makeChangedColorField()
                InputField("avatar", at: \.avatar.value).description(SchemaDescription.actorAvatar)
                Self.makeChangedBodyField()
            }
            .description(SchemaDescription.updateActorInput)
            Self.makeNodeReferenceInput(of: DeleteColumnMutation.self)
            Self.makeNodeReferenceInput(of: UndeleteColumnMutation.self)
            Self.makeNodeReferenceInput(of: DeleteActorMutation.self)
            Self.makeNodeReferenceInput(of: UndeleteActorMutation.self)
        }
        .addMutation {
            Self.mutationField(
                MutationName.addColumn,
                at: KanbanResolver.addColumn,
                description: SchemaDescription.addColumn
            )
            Self.mutationField(
                MutationName.updateColumn,
                at: KanbanResolver.updateColumn,
                description: SchemaDescription.updateColumn
            )
            Self.mutationField(
                MutationName.deleteColumn,
                at: KanbanResolver.deleteColumn,
                description: SchemaDescription.deleteColumn
            )
            Self.mutationField(
                MutationName.undeleteColumn,
                at: KanbanResolver.undeleteColumn,
                description: SchemaDescription.undeleteColumn
            )
            Self.mutationField(
                MutationName.addActor,
                at: KanbanResolver.addActor,
                description: SchemaDescription.addActor
            )
            Self.mutationField(
                MutationName.updateActor,
                at: KanbanResolver.updateActor,
                description: SchemaDescription.updateActor
            )
            Self.mutationField(
                MutationName.deleteActor,
                at: KanbanResolver.deleteActor,
                description: SchemaDescription.deleteActor
            )
            Self.mutationField(
                MutationName.undeleteActor,
                at: KanbanResolver.undeleteActor,
                description: SchemaDescription.undeleteActor
            )
        }
    }
}
