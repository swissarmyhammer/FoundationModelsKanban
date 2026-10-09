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

    /// The mutation that changes the name, the color, or the body of an actor.
    static let updateActor = "updateActor"

    /// The mutation that makes an actor a tombstone.
    static let deleteActor = "deleteActor"

    /// The mutation that makes a tombstoned actor live again.
    static let undeleteActor = "undeleteActor"
}

// MARK: - Arguments

/// The arguments of a mutation whose `input` argument is required (plan.md §4.2).
struct InputArguments<Input: Decodable & Sendable>: Decodable, Sendable {
    /// The `input` object of the mutation.
    let input: Input
}

/// The arguments of a mutation whose `input` argument is optional, because the `input` type has no required field
/// (plan.md §4.2). For example, `mutation { addTag { id } }` is valid, and the resolver gets no `input`.
struct OptionalInputArguments<Input: Decodable & Sendable>: Decodable, Sendable {
    /// The `input` object of the mutation, or `nil` when the call gives no `input`.
    let input: Input?
}

/// The `input` object of `addColumn` (plan.md §4.2).
private struct AddColumnInput: Codable, Sendable {
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

/// The `input` object of `updateColumn` (plan.md §4.2). A field that is not set does not change, and `null` clears
/// the field.
private struct UpdateColumnInput: Decodable, Sendable {
    /// The column: a full URI or the slug (plan.md §3.2).
    let id: NodeID

    /// The new name of the column.
    let name: FieldUpdate<String>

    /// The new sort key of the column.
    let order: FieldUpdate<Int>

    /// The new Markdown body of the column: the full text. The mutation writes the diff from the current body.
    let body: FieldUpdate<String>
}

/// The `input` object of `addActor` (plan.md §4.2).
private struct AddActorInput: Codable, Sendable {
    /// The id of the new actor, or `nil` for the slug of ``name``. The id is the slug of this text, or the slug of a
    /// full actor URI of the board (plan.md §3.2).
    let id: NodeID?

    /// The name of the actor.
    let name: String

    /// The color of the actor, or `nil` for no color.
    let color: String?

    /// The Markdown body of the actor: the full text, or `nil` for no body.
    let body: String?

    /// `true` to return the actor that has the id, and write nothing, when the board has that actor. Else that actor
    /// gives `DUPLICATE_ID`.
    let ensure: Bool?

    /// The board of the actor: a board key, a repo directory name, or a path, or `nil` for the current board
    /// (plan.md §6.6).
    let board: String?
}

/// The `input` object of `updateActor` (plan.md §4.2). A field that is not set does not change, and `null` clears
/// the field.
private struct UpdateActorInput: Decodable, Sendable {
    /// The actor: a full URI or the slug (plan.md §3.2).
    let id: NodeID

    /// The new name of the actor.
    let name: FieldUpdate<String>

    /// The new color of the actor.
    let color: FieldUpdate<String>

    /// The new Markdown body of the actor: the full text. The mutation writes the diff from the current body.
    let body: FieldUpdate<String>
}

/// The `input` object of a mutation that names one node and has no other field: the delete and the undelete
/// mutations (plan.md §4.2). ``SchemaBuilder/addColumnActorMutations()`` adds its `input` type, and the comment
/// mutations use it too.
struct NodeReferenceInput: Codable, Sendable {
    /// The node: a full URI or a short form (plan.md §3.2).
    let id: NodeID
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
        return try await context.changeNode(named: MutationName.updateColumn, on: board) { work, resolver, time in
            let ref = try resolver.nodeRef(for: input.id, ofType: .column)
            let values = [
                PropertyName.name: input.name.map(PatchValue.string),
                PropertyName.order: input.order.map(PatchValue.integer),
            ]
            try work.updateNode(ref, updating: values, body: input.body, at: time)
            return ref
        }
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
        arguments: InputArguments<NodeReferenceInput>
    ) async throws -> ColumnObject? {
        try await changeDeleted(to: true, ofType: .column, as: MutationName.deleteColumn, context: context, arguments)
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
        arguments: InputArguments<NodeReferenceInput>
    ) async throws -> ColumnObject? {
        let operation = MutationName.undeleteColumn
        return try await changeDeleted(to: false, ofType: .column, as: operation, context: context, arguments)
    }
}

// MARK: - Actor resolvers

extension KanbanResolver {
    /// Resolves `Mutation.addActor`: makes an actor with a `set` of the name and the color, and an `edit` of the body,
    /// in one patch (plan.md §4.2).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The new actor.
    /// - Returns: The actor. With `ensure`, the actor that the board has, with no change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the id is a URI that does not name an actor of the
    ///   board. ``KanbanError/invalidSlug(name:)`` when the id gives an empty slug.
    ///   ``KanbanError/reservedSlug(type:)`` when the board has no actor with the slug, and the id gives the slug
    ///   ``Slug/reservedForBoard``.
    ///   ``KanbanError/duplicateID(type:id:)`` when the board has an actor with the slug and `ensure` is not `true`.
    fileprivate func addActor(
        context: KanbanContext,
        arguments: InputArguments<AddActorInput>
    ) async throws -> ActorObject? {
        let input = arguments.input
        let board = MutationBoard.named(input.board)
        return try await context.changeNode(named: MutationName.addActor, on: board) { work, resolver, time in
            let slug = try resolver.slug(ofNewNode: input.id, named: input.name, ofType: .actor)
            let ref = LocalRef.actor(slug: slug.value)
            if input.ensure == true, work.graph.hasNode(ref) {
                return ref
            }
            let values = [String: PatchValue](
                givenValues: [
                    PropertyName.name: .string(input.name),
                    PropertyName.color: input.color.map(PatchValue.string),
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
        return try await context.changeNode(named: MutationName.updateActor, on: board) { work, resolver, time in
            let ref = try resolver.nodeRef(for: input.id, ofType: .actor)
            let values = [
                PropertyName.name: input.name.map(PatchValue.string),
                PropertyName.color: input.color.map(PatchValue.string),
            ]
            try work.updateNode(ref, updating: values, body: input.body, at: time)
            return ref
        }
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
        arguments: InputArguments<NodeReferenceInput>
    ) async throws -> ActorObject? {
        try await changeDeleted(to: true, ofType: .actor, as: MutationName.deleteActor, context: context, arguments)
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
        arguments: InputArguments<NodeReferenceInput>
    ) async throws -> ActorObject? {
        try await changeDeleted(to: false, ofType: .actor, as: MutationName.undeleteActor, context: context, arguments)
    }

    /// Writes a `delete` patch on one node: `true` makes a tombstone, `false` makes a tombstone live again (plan.md
    /// §4.2). A patch that does not change the node is not written. The node can be in a related board (plan.md
    /// §6.6).
    ///
    /// - Parameters:
    ///   - isDeleted: `true` for a delete, `false` for an undelete.
    ///   - type: The node type.
    ///   - operation: The name of the public mutation.
    ///   - context: The context of the call.
    ///   - arguments: The node. A delete names a live node. An undelete can also name a tombstone.
    /// - Returns: The node after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no node of the type has the id.
    ///   ``KanbanError/columnNotEmpty(column:liveTaskCount:)`` when a deleted column shows live tasks.
    func changeDeleted<Object: SlotNodeObject>(
        to isDeleted: Bool,
        ofType type: PatchNodeType,
        as operation: String,
        context: KanbanContext,
        _ arguments: InputArguments<NodeReferenceInput>
    ) async throws -> Object? {
        let id = arguments.input.id
        return try await context.changeNode(named: operation, on: .holding(id)) { work, resolver, time in
            let ref = try resolver.nodeRef(for: id, ofType: type, includingTombstones: !isDeleted)
            try work.setDeleted(isDeleted, of: ref, inBoard: resolver.boardKey, at: time)
            return ref
        }
    }
}

// MARK: - Store

extension BoardStore {
    /// Runs one public mutation field that changes one node, and gives the object of the node after the field.
    ///
    /// The field obeys the rules of ``runMutation(named:on:at:_:)``: it writes to the board that it names, with the
    /// auto-init and the session actor of that board.
    ///
    /// - Parameters:
    ///   - operation: The name of the public mutation of the field.
    ///   - board: The board of the field.
    ///   - time: The time of the change.
    ///   - body: Makes and applies the patches of the field, and gives the local ref of the node. It gets the working
    ///     copy, a resolver of the forgiving refs of the working graph, and the time.
    /// - Returns: The object of the node, live or tombstoned, or `nil` when the engine did not load the board yet.
    /// - Throws: ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board for the ref. The
    ///   error of the body, or an ``EventError`` when a patch breaks a rule of the log.
    func changeNode<Object: SlotNodeObject>(
        named operation: String,
        on board: MutationBoard,
        at time: DateTime,
        _ body: (inout WorkingCopy, RefResolver, DateTime) throws -> LocalRef
    ) throws -> Object? {
        let changed = try runMutation(named: operation, on: board, at: time) { work, resolver in
            try body(&work, resolver, time)
        }
        return changed.flatMap { ref, view in view.graph.slot(for: ref).flatMap { slot in view.object(at: slot) } }
    }
}

extension KanbanContext {
    /// Runs one public mutation field that changes one node at the time of ``clock``, and gives the object of the node
    /// after the field. The field obeys the rules of ``BoardStore/changeNode(named:on:at:_:)``.
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
        try await store.changeNode(named: operation, on: board, at: clock(), body)
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

    /// Writes a `delete` patch on a node. A delete of a column obeys the graph rule of plan.md §3.3, rule 5.
    ///
    /// - Parameters:
    ///   - isDeleted: `true` for a delete, `false` for an undelete.
    ///   - ref: The local ref of the node.
    ///   - key: The current key of the board, for the read view of the rule.
    ///   - time: The time of the change.
    /// - Throws: ``KanbanError/columnNotEmpty(column:liveTaskCount:)`` when a deleted column shows live tasks. An
    ///   ``EventError`` when the patch breaks a rule of the log.
    fileprivate mutating func setDeleted(
        _ isDeleted: Bool,
        of ref: LocalRef,
        inBoard key: String,
        at time: DateTime
    ) throws {
        if isDeleted, ref.nodeType == .column {
            try checkEmpty(column: ref, inBoard: key)
        }
        try apply(PatchInput(node: ref, delete: isDeleted), at: time)
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
                InputField("id", at: \.id)
                InputField("name", at: \.name)
                InputField("order", at: \.order)
                InputField("body", at: \.body)
                InputField("board", at: \.board)
            }
            Input(UpdateColumnInput.self) {
                InputField("id", at: \.id)
                InputField("name", at: \.name.value)
                InputField("order", at: \.order.value)
                InputField("body", at: \.body.value)
            }
            Input(AddActorInput.self) {
                InputField("id", at: \.id)
                InputField("name", at: \.name)
                InputField("color", at: \.color)
                InputField("body", at: \.body)
                InputField("ensure", at: \.ensure)
                InputField("board", at: \.board)
            }
            Input(UpdateActorInput.self) {
                InputField("id", at: \.id)
                InputField("name", at: \.name.value)
                InputField("color", at: \.color.value)
                InputField("body", at: \.body.value)
            }
            Input(NodeReferenceInput.self) {
                InputField("id", at: \.id)
            }
        }
        .addMutation {
            Field(MutationName.addColumn, at: KanbanResolver.addColumn) { Argument("input", at: \.input) }
            Field(MutationName.updateColumn, at: KanbanResolver.updateColumn) { Argument("input", at: \.input) }
            Field(MutationName.deleteColumn, at: KanbanResolver.deleteColumn) { Argument("input", at: \.input) }
            Field(MutationName.undeleteColumn, at: KanbanResolver.undeleteColumn) { Argument("input", at: \.input) }
            Field(MutationName.addActor, at: KanbanResolver.addActor) { Argument("input", at: \.input) }
            Field(MutationName.updateActor, at: KanbanResolver.updateActor) { Argument("input", at: \.input) }
            Field(MutationName.deleteActor, at: KanbanResolver.deleteActor) { Argument("input", at: \.input) }
            Field(MutationName.undeleteActor, at: KanbanResolver.undeleteActor) { Argument("input", at: \.input) }
        }
    }
}
