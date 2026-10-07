import Graphiti
import GraphQL

// MARK: - Names

/// The names of the public mutations (plan.md §4.2). Each name is also the operation name in the `ops` of the events
/// of the mutation. The names of the column and the actor mutations are in `ColumnActorMutations.swift`.
enum MutationName {
    /// The mutation that makes the board, or changes the given fields of a board that exists.
    static let initBoard = "initBoard"

    /// The mutation that changes the name and the body of the board.
    static let updateBoard = "updateBoard"
}

// MARK: - Update input

/// One field of the `input` object of a mutation that changes a node (plan.md §6, "Missing and `null` input").
///
/// A field that the input does not have does not change. A field with the value `null` is cleared. A field with a
/// value gets the value. A `Decodable` type that holds this type reads the three forms with
/// ``Swift/KeyedDecodingContainer/decode(_:forKey:)``.
enum FieldUpdate<Value> {
    /// The input does not have the field, so the field does not change.
    case unchanged

    /// The input gives `null`, so the field is cleared.
    case cleared

    /// The input gives a new value.
    case changed(Value)

    /// The new value, or `nil` when the input does not give a value. The schema reads the type of this property, so
    /// that the GraphQL `input` field gets the nullable type of the value.
    var value: Value? {
        guard case .changed(let value) = self else {
            return nil
        }
        return value
    }

    /// Changes the new value, and keeps a missing or a cleared field as it is.
    ///
    /// - Parameter transform: Gives the changed value from the new value.
    /// - Returns: The field with the changed value.
    func map<Changed>(_ transform: (Value) throws -> Changed) rethrows -> FieldUpdate<Changed> {
        switch self {
        case .unchanged: .unchanged
        case .cleared: .cleared
        case .changed(let value): .changed(try transform(value))
        }
    }

    /// Gives the value after the update for a field whose clear gives an empty value, for example a body or a list.
    ///
    /// - Parameter empty: The value of a cleared field, for example `""` or `[]`.
    /// - Returns: The new value, `empty` for a cleared field, or `nil` when the field does not change.
    func value(clearingTo empty: Value) -> Value? {
        switch self {
        case .unchanged: nil
        case .cleared: empty
        case .changed(let value): value
        }
    }
}

extension FieldUpdate: Sendable where Value: Sendable {}

extension FieldUpdate: Decodable where Value: Decodable {
    /// Reads a field that the input has: `null` clears the field, and a value changes it.
    ///
    /// - Parameter decoder: The decoder that holds the value of the field.
    /// - Throws: A `DecodingError` when the value is not `null` and not a `Value`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = container.decodeNil() ? .cleared : .changed(try container.decode(Value.self))
    }
}

extension KeyedDecodingContainer {
    /// Reads one field of an update input. A missing key gives ``FieldUpdate/unchanged``. The synthesized
    /// `Decodable` conformance of an input type calls this method for each ``FieldUpdate`` property, because a key
    /// that the input does not have is not an error.
    ///
    /// - Parameters:
    ///   - type: The type of the field.
    ///   - key: The key of the field.
    /// - Returns: The field.
    /// - Throws: A `DecodingError` when the value is not `null` and not a `Value`.
    // The synthesized `Decodable` code of each update input calls this method; periphery does not see that call.
    // periphery:ignore
    func decode<Value: Decodable>(_ type: FieldUpdate<Value>.Type, forKey key: Key) throws -> FieldUpdate<Value> {
        guard contains(key) else {
            return .unchanged
        }
        return try type.init(from: superDecoder(forKey: key))
    }
}

extension FieldUpdate where Value == String {
    /// The new Markdown body of a node: the full text, `""` for a cleared body, or `nil` when the body does not
    /// change (plan.md §5.5: `body: null` writes a diff to the empty text).
    var newBody: String? {
        value(clearingTo: "")
    }
}

// MARK: - Arguments

/// The `input` object of `initBoard` and `updateBoard` (plan.md §4.2). A field that is not set does not change, and
/// `null` clears the field.
private struct BoardInput: Decodable, Sendable {
    /// The new name of the board.
    let name: FieldUpdate<String>

    /// The new Markdown body of the board: the full text. The mutation writes the diff from the current body
    /// (plan.md §5.5).
    let body: FieldUpdate<String>
}

/// The arguments of `initBoard` and `updateBoard`. The `input` argument is optional, because ``BoardInput`` has no
/// required field (plan.md §4.2).
private struct BoardMutationArguments: Decodable, Sendable {
    /// The changes to the board, or `nil` for no change.
    let input: BoardInput?
}

// MARK: - Default columns

/// A column that a new board gets (plan.md §6, "Default columns").
private struct DefaultColumn: Sendable {
    /// The columns of a new board, in board order. The `order` of each column is its index in this list.
    static let all = [
        DefaultColumn(slug: "todo", name: "To Do"),
        DefaultColumn(slug: "doing", name: "Doing"),
        DefaultColumn(slug: "review", name: "Review"),
        DefaultColumn(slug: "done", name: "Done"),
    ]

    /// The slug of the column, for example `todo`.
    let slug: String

    /// The name of the column, for example `To Do`.
    let name: String
}

// MARK: - Resolvers

extension KanbanResolver {
    /// Resolves `Mutation.initBoard`: makes the board, or changes the given fields of a board that exists.
    ///
    /// The auto-init of ``BoardStore/runMutation(named:at:_:)`` makes a new board. On a board that exists, the
    /// mutation writes only the given fields that differ, and adds no column (plan.md §4.2).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The changes to the board.
    /// - Returns: The board after the change. The GraphQL field is nullable, so that an error gives `null` for this
    ///   field only, and the other fields of the call keep their data.
    /// - Throws: An ``EventError`` when a patch breaks a rule of the log.
    fileprivate func initBoard(
        context: KanbanContext,
        arguments: BoardMutationArguments
    ) async throws -> BoardObject? {
        try await changeBoard(as: MutationName.initBoard, context: context, arguments: arguments)
    }

    /// Resolves `Mutation.updateBoard`: changes the name and the body of the board.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The changes to the board.
    /// - Returns: The board after the change. The GraphQL field is nullable, so that an error gives `null` for this
    ///   field only, and the other fields of the call keep their data.
    /// - Throws: An ``EventError`` when a patch breaks a rule of the log.
    fileprivate func updateBoard(
        context: KanbanContext,
        arguments: BoardMutationArguments
    ) async throws -> BoardObject? {
        try await changeBoard(as: MutationName.updateBoard, context: context, arguments: arguments)
    }

    /// Changes the board with the input of a board mutation.
    ///
    /// - Parameters:
    ///   - operation: The name of the mutation.
    ///   - context: The context of the call.
    ///   - arguments: The changes to the board.
    /// - Returns: The board after the change.
    /// - Throws: An ``EventError`` when a patch breaks a rule of the log.
    private func changeBoard(
        as operation: String,
        context: KanbanContext,
        arguments: BoardMutationArguments
    ) async throws -> BoardObject? {
        try await BoardObject(in: context.store.changeBoard(with: arguments.input, as: operation, at: context.clock()))
    }
}

// MARK: - Store

extension BoardStore {
    /// Runs one public mutation field on the working copy, with the rules that each public mutation obeys (plan.md
    /// §6).
    ///
    /// - Auto-init: when the log has no board, the field writes the default columns before the body, and the board
    ///   `set name` with the name of the repo directory after the body, when the body set no name. Thus a field that
    ///   sets the name writes one board patch.
    /// - Session actor: when the field kept a patch and the board has no node of the session actor, the field also
    ///   writes an actor `set name` patch. A field that keeps no patch writes no actor patch.
    ///
    /// - Parameters:
    ///   - operation: The name of the public mutation of the field.
    ///   - time: The time of the change.
    ///   - body: Makes and applies the patches of the field, and checks the graph rules.
    /// - Returns: The value of the body.
    /// - Throws: The error of the body, or an ``EventError`` when a patch breaks a rule of the log. Then the field
    ///   keeps none of its patches.
    func runMutation<Value: Sendable>(
        named operation: String,
        at time: DateTime,
        _ body: (inout WorkingCopy) throws -> Value
    ) throws -> Value {
        let actor = sessionActor
        return try runField(as: operation) { work in
            let keptCount = work.kept.count
            let isNewBoard = !work.hasEvents(of: .board)
            let directoryName = work.graph.boardNode?.name
            if isNewBoard {
                try work.addDefaultColumns(at: time)
            }
            let value = try body(&work)
            if isNewBoard, let directoryName {
                try work.nameNewBoard(directoryName, at: time)
            }
            if work.kept.count > keptCount {
                try work.addActor(actor, at: time)
            }
            return value
        }
    }

    /// Changes the board with one patch: `set` or `unset` of the name, and an `edit` diff of the body (plan.md §4.2,
    /// §5.5). The patch keeps only the parts that change the board, so a field that changes nothing writes nothing.
    ///
    /// - Parameters:
    ///   - input: The changes. A field that is not set does not change, and `null` clears the field.
    ///   - operation: The name of the public mutation.
    ///   - time: The time of the change.
    /// - Returns: The read view of the graph after the change.
    /// - Throws: An ``EventError`` when a patch breaks a rule of the log.
    fileprivate func changeBoard(
        with input: BoardInput?,
        as operation: String,
        at time: DateTime
    ) throws -> BoardView {
        try runMutation(named: operation, at: time) { work in
            let patch = try PatchInput(
                changing: .board,
                updating: [PropertyName.name: (input?.name ?? .unchanged).map(PatchValue.string)],
                body: input?.body ?? .unchanged,
                from: work.graph.body(of: .board)
            )
            try work.apply(patch, at: time)
        }
        return view
    }
}

// MARK: - Patches

extension WorkingCopy {
    /// Writes the default columns of a new board (plan.md §6). A column that the log already has does not change.
    ///
    /// - Parameter time: The time of the change.
    /// - Throws: An ``EventError`` when a patch breaks a rule of the log.
    fileprivate mutating func addDefaultColumns(at time: DateTime) throws(EventError) {
        for (order, column) in DefaultColumn.all.enumerated() where !hasEvents(of: .column(slug: column.slug)) {
            let patch = try PatchInput(
                node: .column(slug: column.slug),
                set: [
                    PropertyName.name: .json(.string(column.name)),
                    PropertyName.order: .json(.number(Number(order))),
                ]
            )
            try apply(patch, at: time)
        }
    }

    /// Writes the default name of a new board (plan.md §6, "Auto-init"). A name that a kept patch already wrote does
    /// not change.
    ///
    /// - Parameters:
    ///   - name: The default name: the name of the repo directory.
    ///   - time: The time of the change.
    /// - Throws: An ``EventError`` when the patch breaks a rule of the log.
    fileprivate mutating func nameNewBoard(_ name: String, at time: DateTime) throws(EventError) {
        let hasStoredName = hasEvents(of: .board) && graph.boardNode?.name.isEmpty == false
        guard !hasStoredName else {
            return
        }
        try apply(PatchInput(node: .board, set: [PropertyName.name: .json(.string(name))]), at: time)
    }

    /// Makes sure that the session actor exists in the board: writes an actor `set name` patch when the graph has no
    /// node of the actor (plan.md §6, "Session actor").
    ///
    /// - Parameters:
    ///   - actor: The session actor.
    ///   - time: The time of the change.
    /// - Throws: An ``EventError`` when the patch breaks a rule of the log.
    fileprivate mutating func addActor(_ actor: SessionActor, at time: DateTime) throws(EventError) {
        guard !graph.hasNode(actor.ref) else {
            return
        }
        try apply(PatchInput(node: actor.ref, set: [PropertyName.name: .json(.string(actor.name))]), at: time)
    }
}

extension PatchInput {
    /// Makes the patch of a mutation that makes one node: a `set` of the given values, and an `edit` diff from the
    /// current body when the input has a body (plan.md §4.2, §5.5). The working copy keeps only the parts that change
    /// the node, so an equal value or an equal body writes nothing.
    ///
    /// - Parameters:
    ///   - node: The local ref of the node.
    ///   - values: The properties to write.
    ///   - newBody: The new body: the full text, or `nil` for no change of the body.
    ///   - body: The current body of the node.
    /// - Throws: An ``EventError`` when the patch breaks a rule of the log.
    init(
        changing node: LocalRef,
        setting values: [String: PatchValue],
        body newBody: String?,
        from body: String
    ) throws(EventError) {
        try self.init(
            changing: node,
            updating: values.mapValues(FieldUpdate.changed),
            body: newBody.map(FieldUpdate.changed) ?? .unchanged,
            from: body
        )
    }

    /// Makes the patch of a mutation that changes one node: a `set` of each new value, an `unset` of each cleared
    /// property, the `add` and `remove` parts of the set-valued properties, and an `edit` diff from the current body
    /// when the input changes the body (plan.md §4.2, §5.5, §6). A cleared body gets the diff to the empty text. The
    /// working copy keeps only the parts that change the node, so an equal value or an equal body writes nothing.
    ///
    /// - Parameters:
    ///   - node: The local ref of the node.
    ///   - values: The update of each property. A property that does not change can be left out.
    ///   - add: The refs to add to set-valued properties.
    ///   - remove: The refs to remove from set-valued properties.
    ///   - newBody: The update of the body.
    ///   - body: The current body of the node.
    /// - Throws: An ``EventError`` when the patch breaks a rule of the log.
    init(
        changing node: LocalRef,
        updating values: [String: FieldUpdate<PatchValue>],
        adding add: [String: [StoredRef]] = [:],
        removing remove: [String: [StoredRef]] = [:],
        body newBody: FieldUpdate<String>,
        from body: String
    ) throws(EventError) {
        try self.init(
            node: node,
            set: values.compactMapValues(\.value),
            unset: values.filter { _, update in update.isCleared }.keys.sorted(),
            add: add,
            remove: remove,
            edit: newBody.newBody.map { newBody in PatchEdit(body: UnifiedDiff(from: body, to: newBody).text) }
        )
    }
}

extension FieldUpdate {
    /// `true` when the input gives `null`, so that the field is cleared.
    fileprivate var isCleared: Bool {
        guard case .cleared = self else {
            return false
        }
        return true
    }
}

extension Graph {
    /// Gives the node of a ref, live or tombstoned.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The node, or `nil` when no slot of the graph holds the node.
    func node(for ref: LocalRef) -> Node? {
        slot(for: ref).flatMap(node(at:))
    }

    /// Tells if the graph has the node of a ref, live or tombstoned.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: `true` when a slot of the graph holds the node.
    func hasNode(_ ref: LocalRef) -> Bool {
        node(for: ref) != nil
    }

    /// Gives the body of the node of a ref.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The Markdown body, or `""` when the graph does not have the node.
    func body(of ref: LocalRef) -> String {
        node(for: ref)?.state.fields.body ?? ""
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the board mutations, `initBoard` and `updateBoard`, and their `input` type.
    ///
    /// - Returns: This builder, for method chaining.
    func addBoardMutations() -> Self {
        add {
            Input(BoardInput.self) {
                InputField("name", at: \.name.value)
                InputField("body", at: \.body.value)
            }
        }
        .addMutation {
            Field(MutationName.initBoard, at: KanbanResolver.initBoard) {
                Argument("input", at: \.input)
            }
            Field(MutationName.updateBoard, at: KanbanResolver.updateBoard) {
                Argument("input", at: \.input)
            }
        }
    }
}
