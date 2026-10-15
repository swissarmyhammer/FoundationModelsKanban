import Graphiti
import GraphQL

// MARK: - Arguments

/// The fields of the `input` object of `moveTask` and `copyTask` (plan.md §4.2, divergence.md Q21): the task, the
/// column, one place field (`ordinal`, `before`, or `after`) or none of them for the end of the column, and the board.
/// An input with more than one place field does not decode.
struct TaskPlacementFields: Decodable, Sendable {
    /// The keys of the fields of the input that are not place fields. ``Placement`` reads the place fields.
    private enum CodingKeys: String, CodingKey {
        /// The key of the task.
        case id

        /// The key of the column.
        case column

        /// The key of the board.
        case board
    }

    /// The task: a full URI or a short form (plan.md §3.2).
    let id: NodeID

    /// The column: a full URI, the slug, or a name, or `nil` for no column. A slug that no column has makes a new
    /// column.
    let column: NodeID?

    /// The board to move or copy the task to: a board key, a repo directory name, a path, or the URI of a board, or
    /// `nil` for the board of the task (plan.md §6.6).
    let board: String?

    /// The place of the task in the column.
    let placement: Placement

    /// Reads the fields of the input object of a move or a copy.
    ///
    /// - Parameter decoder: The decoder of the input object.
    /// - Throws: ``KanbanError/conflictingPlacement(fields:)`` when the input gives more than one place field. A
    ///   `DecodingError` when the input has no `id`, or a field has the wrong type.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(NodeID.self, forKey: .id)
        column = try container.decodeIfPresent(NodeID.self, forKey: .column)
        board = try container.decodeIfPresent(String.self, forKey: .board)
        placement = try Placement(from: decoder)
    }
}

/// An `input` object with the fields of ``TaskPlacementFields``: the input of `moveTask` or `copyTask`. The schema
/// gets the type of each input field from the properties of this protocol.
protocol TaskPlacementInput: Decodable, Sendable {
    /// The fields of the input.
    var fields: TaskPlacementFields { get }
}

extension TaskPlacementInput {
    /// The `id` field of the input.
    var id: NodeID {
        fields.id
    }

    /// The `column` field of the input, or `nil`.
    var column: NodeID? {
        fields.column
    }

    /// The `board` field of the input, or `nil`.
    var board: String? {
        fields.board
    }

    /// The `ordinal` field of the input, or `nil`.
    var ordinal: String? {
        guard case .ordinal(let text) = fields.placement else {
            return nil
        }
        return text
    }

    /// The `before` field of the input, or `nil`.
    var before: NodeID? {
        guard case .before(let neighbor) = fields.placement else {
            return nil
        }
        return neighbor
    }

    /// The `after` field of the input, or `nil`.
    var after: NodeID? {
        guard case .after(let neighbor) = fields.placement else {
            return nil
        }
        return neighbor
    }
}

/// The `input` object of `copyTask` (divergence.md Q21): the fields of ``TaskPlacementFields``. No `board` field
/// copies the task in its board.
private struct CopyTaskInput: TaskPlacementInput {
    /// The fields of the input.
    let fields: TaskPlacementFields

    /// Reads the input object of a copy.
    ///
    /// - Parameter decoder: The decoder of the input object.
    /// - Throws: The errors of ``TaskPlacementFields/init(from:)``.
    init(from decoder: any Decoder) throws {
        fields = try TaskPlacementFields(from: decoder)
    }
}

// MARK: - Transfer

/// The kind of a transfer of a task to a board (divergence.md Q21).
enum TaskTransferKind: Sendable {
    /// A move: the new task replaces the old task, which becomes a tombstone.
    case move

    /// A copy: the old task does not change.
    case copy

    /// The name of the public mutation of the transfer, for the `ops` of the events.
    var operation: String {
        switch self {
        case .move: MutationName.moveTask
        case .copy: MutationName.copyTask
        }
    }
}

/// The new task of a transfer, as the store gives it to the resolver.
struct TransferredTask: Sendable {
    /// The local ref of the new task in its board.
    let ref: LocalRef

    /// The read view of the board of the new task after the transfer.
    let view: BoardView

    /// The warnings of the cross-board dependencies that the new task has (``DependencyWarnings``).
    let warnings: [ResponseWarning]
}

/// The parts of a task that a transfer writes to the new task, read from the board of the old task.
struct TaskCopy {
    /// The title of the task.
    let title: String

    /// The Markdown body of the task.
    let body: String

    /// The column where the task shows, or `nil` when the board has no live column.
    let column: LocalRef?

    /// The `assignees` edges, in the stored form of the board of the old task.
    let assignees: [StoredRef]

    /// The tag of each `tags` edge, at the end of its rename chain.
    let tags: [TagNode]

    /// The `dependsOn` edges, in the stored form of the board of the old task.
    let dependsOn: [StoredRef]

    /// Reads the parts of a task.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the task.
    ///   - graph: The graph of the board of the task.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the graph does not have the task.
    init(of ref: LocalRef, in graph: Graph) throws(KanbanError) {
        guard let task = graph.node(for: ref)?.state as? TaskNode else {
            throw .notFound(type: .task, reference: ref.description)
        }
        title = task.title
        body = task.fields.body
        column = ColumnOrder(of: graph).displaySlot(of: task.column).flatMap { slot in graph.node(at: slot)?.ref }
        assignees = task.assignees.compactMap(graph.storedRef(of:))
        tags = task.tags.compactMap(graph.storedRef(of:)).compactMap { edge in
            guard case .local(let tag) = edge else {
                return nil
            }
            return graph.node(for: graph.tagRef(redirectedFrom: tag))?.state as? TagNode
        }
        dependsOn = task.dependsOn.compactMap(graph.storedRef(of:))
    }
}

extension StoredRef {
    /// Gives this ref of a task of one board as the new task of a transfer stores it in a different board
    /// (divergence.md Q21): a local ref of the old board becomes the full URI with the key of the old board, and a
    /// URI with the key of the new board becomes a local ref. Each other ref does not change.
    ///
    /// - Parameters:
    ///   - sourceKey: The current key of the board of the old task.
    ///   - targetKey: The current key of the board of the new task.
    /// - Returns: The ref in the stored form of the new board.
    func carried(from sourceKey: String, to targetKey: String) -> StoredRef {
        let target = BoardKey.normalizedText(of: targetKey)
        switch self {
        case .local(let ref):
            guard BoardKey.normalizedText(of: sourceKey) != target else {
                return self
            }
            return .remote(NodeURI(boardKey: sourceKey, ref: ref))
        case .remote(let uri):
            return BoardKey.normalizedText(of: uri.boardKey) == target ? .local(uri.ref) : self
        }
    }
}

// MARK: - Resolvers

extension KanbanResolver {
    /// Resolves `Mutation.copyTask`: makes a copy of a task, on the board that the `board` field names or on the
    /// board of the task (``KanbanContext/transferTask(_:as:)``, divergence.md Q21).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The task, the column, the place in the column, and the board.
    /// - Returns: The copy. The GraphQL field is nullable, so that an error gives `null` for this field only.
    /// - Throws: The errors of ``KanbanContext/transferTask(_:as:)``.
    fileprivate func copyTask(
        context: KanbanContext,
        arguments: InputArguments<CopyTaskInput>
    ) async throws -> TaskObject? {
        try await context.transferTask(arguments.input.fields, as: .copy)
    }
}

// MARK: - Context

extension KanbanContext {
    /// Runs one `moveTask` or `copyTask` field that writes the task to a board at the time of ``clock``, and adds the
    /// warnings of the field to the warnings of the run (divergence.md Q21, E6). The rules are those of
    /// ``BoardStore/transfer(_:as:at:)``.
    ///
    /// - Parameters:
    ///   - fields: The task, the column, the place in the column, and the board.
    ///   - kind: A move or a copy.
    /// - Returns: The new task.
    /// - Throws: The errors of ``BoardStore/transfer(_:as:at:)``.
    func transferTask(_ fields: TaskPlacementFields, as kind: TaskTransferKind) async throws -> TaskObject? {
        let transferred = try await store.transfer(fields, as: kind, at: clock())
        await warnings.add(contentsOf: transferred.warnings)
        return transferred.view.object(of: transferred.ref)
    }
}

// MARK: - Store

extension BoardStore {
    /// Tells if a board ref names the board of a task.
    ///
    /// - Parameters:
    ///   - reference: The board ref.
    ///   - id: The task: a full URI or a short form.
    /// - Returns: `true` when the ref names the board of the task.
    /// - Throws: The errors of ``loadedTarget(of:holding:)``: ``KanbanError/notFound(type:reference:)`` when the
    ///   engine did not load the board of the task yet, and ``KanbanError/boardNotFound(reference:searchRoots:)`` when
    ///   the scan finds no board for the ref, or the engine did not load it yet.
    func isBoard(_ reference: String, holdingTask id: NodeID) throws(KanbanError) -> Bool {
        let source = try loadedTarget(of: .holding(id), holding: .task)
        let destination = try loadedTarget(of: .named(reference), holding: .task)
        return source.relatedPath == destination.relatedPath
    }

    /// Writes a task to a board (divergence.md Q21, E6), in one transaction of the call:
    ///
    /// - The target board gets a new task with the title, the body, the tags, the assignees, and the dependencies of
    ///   the task. A ref to a node of the old board becomes a full URI, so that a dependency on the old board still
    ///   resolves. Each tag that the target board does not have, from an edge or a body marker, is made there. The
    ///   column is the column of the input, else the column with the slug of the column of the task, else the first
    ///   column.
    /// - A move also adds a line with the URI of the new task to the body of the old task, and makes the old task a
    ///   tombstone, so that each dependent on the old board can find the new task.
    ///
    /// Each board obeys the rules of ``runMutation(named:on:at:_:)``. When one step fails, no board keeps a patch.
    ///
    /// - Parameters:
    ///   - fields: The task, the column, the place in the column, and the target board.
    ///   - kind: A move or a copy.
    ///   - time: The time of the change.
    /// - Returns: The new task.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the id, the engine did not load the
    ///   board of the task yet, a neighbor names no live task, or the column is a tombstone.
    ///   ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board for the `board` field, or
    ///   the engine did not load it yet (``loadedTarget(of:holding:)``). ``KanbanError/dependencyCycle(path:)`` when
    ///   the new task closes a cycle. The errors of a tag or a column that the field makes, or an ``EventError`` when
    ///   a patch breaks a rule of the log.
    func transfer(
        _ fields: TaskPlacementFields,
        as kind: TaskTransferKind,
        at time: DateTime
    ) throws -> TransferredTask {
        let source = try loadedTarget(of: .holding(fields.id), holding: .task)
        let destinationBoard = fields.board.map(MutationBoard.named) ?? .holding(fields.id)
        let destination = try loadedTarget(of: destinationBoard, holding: .task)
        let sourceKey = key(of: source)
        let sourceGraph = workingCopy(of: source).graph
        let ref = try RefResolver(graph: sourceGraph, boardKey: sourceKey).nodeRef(for: fields.id, ofType: .task)
        let copy = try TaskCopy(of: ref, in: sourceGraph)
        let actor = sessionActor
        return try runAtomically {
            let made = try runField(as: kind.operation, in: destination) { work, targetKey in
                try work.applyMutationRules(actingAs: actor, at: time) { work in
                    try work.addCopy(copy, from: sourceKey, placedBy: fields, inBoard: targetKey, at: time)
                }
            }
            if kind == .move {
                let uri = NodeURI(boardKey: key(of: destination), ref: made.value.ref)
                _ = try runField(as: kind.operation, in: source) { work, _ in
                    try work.applyMutationRules(actingAs: actor, at: time) { work in
                        try work.retire(ref, movedTo: uri, at: time)
                    }
                }
            }
            return TransferredTask(ref: made.value.ref, view: made.view, warnings: made.value.warnings)
        }
    }
}

// MARK: - Patches

extension WorkingCopy {
    /// The text before the URI of the new task in the line that a move adds to the body of the old task.
    private static let movedLinePrefix = "Moved to "

    /// The text between the body of the old task and the line that a move adds, when the body ends with a newline.
    private static let lineBreak = "\n"

    /// The text between the body of the old task and the line that a move adds, when the body does not end with a
    /// newline: an empty line, so that the line is a new paragraph.
    private static let paragraphBreak = "\n\n"

    /// Writes the new task of a transfer to the board of this working copy (divergence.md Q21, E6).
    ///
    /// - Parameters:
    ///   - copy: The parts of the old task.
    ///   - sourceKey: The current key of the board of the old task.
    ///   - fields: The column and the place in the column that the input names.
    ///   - key: The current key of this board.
    ///   - time: The time of the change.
    /// - Returns: The local ref of the new task, and the warnings of its cross-board dependencies.
    /// - Throws: The errors of ``columnRef(forMoveTo:resolvingWith:at:)``, of
    ///   ``Graph/ordinal(placing:inColumn:moving:resolvingWith:)``, of ``ensureLiveTag(_:setting:body:at:)``, and of
    ///   ``write(_:toTask:inBoard:at:)``.
    fileprivate mutating func addCopy(
        _ copy: TaskCopy,
        from sourceKey: String,
        placedBy fields: TaskPlacementFields,
        inBoard key: String,
        at time: DateTime
    ) throws -> (ref: LocalRef, warnings: [ResponseWarning]) {
        let ref = LocalRef.task(mintULID())
        let resolver = RefResolver(graph: graph, boardKey: key)
        let column = try column(of: copy, named: fields.column, resolvingWith: resolver, at: time)
        let ordinal = try graph.ordinal(
            placing: fields.placement,
            inColumn: column,
            moving: ref,
            resolvingWith: resolver
        )
        let tags = try copy.tags.map { tag in
            StoredRef.local(try ensureLiveTag(tag.ref, setting: tag.copiedValues, at: time))
        }
        let edges = [
            PropertyName.assignees: copy.assignees.map { edge in edge.carried(from: sourceKey, to: key) },
            PropertyName.tags: tags,
            PropertyName.dependsOn: copy.dependsOn.map { edge in edge.carried(from: sourceKey, to: key) },
        ]
        let values: [String: FieldUpdate<PatchValue>] = [
            PropertyName.title: .changed(.string(copy.title)),
            PropertyName.column: .changed(.ref(.local(column))),
            PropertyName.ordinal: .changed(.string(ordinal.value)),
        ]
        let change = TaskChange(values: values, body: .changed(copy.body), edges: edges)
        return (ref, try write(change, toTask: ref, inBoard: key, at: time))
    }

    /// Finds the column of the new task of a transfer: the column that the input names, with the rule of
    /// ``columnRef(forMoveTo:resolvingWith:at:)``, else the live column with the slug of the column of the old task,
    /// else the first column.
    ///
    /// - Parameters:
    ///   - copy: The parts of the old task.
    ///   - id: The column that the input names, or `nil` for no column.
    ///   - resolver: The resolver of the forgiving refs of this board.
    ///   - time: The time of the change.
    /// - Returns: The local ref of the column.
    /// - Throws: The errors of ``columnRef(forMoveTo:resolvingWith:at:)``. ``KanbanError/notFound(type:reference:)``
    ///   when the board has no live column.
    private mutating func column(
        of copy: TaskCopy,
        named id: NodeID?,
        resolvingWith resolver: RefResolver,
        at time: DateTime
    ) throws -> LocalRef {
        if let id {
            return try columnRef(forMoveTo: id, resolvingWith: resolver, at: time)
        }
        if let column = copy.column, graph.isLive(ColumnNode.self, for: column) {
            return column
        }
        return try graph.columnRef(atSlot: ColumnOrder(of: graph).first)
    }

    /// Makes the old task of a move a tombstone, after a line with the URI of the new task is added to its body
    /// (divergence.md E6).
    ///
    /// - Parameters:
    ///   - ref: The local ref of the old task.
    ///   - uri: The full URI of the new task.
    ///   - time: The time of the change.
    /// - Throws: An ``EventError`` when a patch breaks a rule of the log.
    fileprivate mutating func retire(_ ref: LocalRef, movedTo uri: NodeURI, at time: DateTime) throws(EventError) {
        let oldBody = graph.body(of: ref)
        let line = Self.movedLinePrefix + uri.description
        let separator = oldBody.hasSuffix(Self.lineBreak) ? Self.lineBreak : Self.paragraphBreak
        let newBody = oldBody.isEmpty ? line : oldBody + separator + line
        try apply(PatchInput(changing: ref, updating: [:], body: .changed(newBody), from: oldBody), at: time)
        try apply(PatchInput(node: ref, delete: true), at: time)
    }
}

extension TagNode {
    /// The values of a tag that a transfer makes on a board that does not have it: the name and the color of this
    /// tag. A value that this tag does not have is not in the result.
    fileprivate var copiedValues: [String: PatchValue] {
        let values: [String: PatchValue?] = [
            PropertyName.name: name.isEmpty ? nil : .string(name),
            PropertyName.color: color.map(PatchValue.string),
        ]
        return values.compactMapValues { value in value }
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// The input fields of `MoveTaskInput` and `CopyTaskInput`: the fields of ``TaskPlacementFields``.
    ///
    /// - Returns: The fields `id`, `column`, `ordinal`, `before`, `after`, and `board`.
    @InputFieldComponentBuilder<Placed, KanbanContext>
    static func placementFields<Placed: TaskPlacementInput>() -> [InputFieldComponent<Placed, KanbanContext>] {
        InputField("id", at: \.id)
        InputField("column", at: \.column)
        InputField("ordinal", at: \.ordinal)
        InputField("before", at: \.before)
        InputField("after", at: \.after)
        InputField("board", at: \.board).description(SchemaDescription.taskTargetBoard)
    }

    /// Adds the `copyTask` mutation and its `input` type (divergence.md Q21).
    ///
    /// - Returns: This builder, for method chaining.
    func addTaskTransferMutations() -> Self {
        add {
            Input(CopyTaskInput.self, Self.placementFields)
        }
        .addMutation {
            Field(MutationName.copyTask, at: KanbanResolver.copyTask) { Argument("input", at: \.input) }
        }
    }
}
