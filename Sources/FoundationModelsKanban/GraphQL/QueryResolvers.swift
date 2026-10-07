import Foundation
import Graphiti
import ULID

/// One read view of the graph of the current board: the data that each resolver of one query reads (plan.md §4.1).
///
/// The view calculates the readiness and the board order of the tasks one time, so that one query can ask about many
/// tasks. Each `id` that the view gives is the full URI of a node, with the current key of the board (plan.md §3.2).
struct BoardView: Sendable {
    /// The readiness of the tasks. It holds the graph and the column order.
    let readiness: Readiness

    /// The current key of the board.
    let boardKey: String

    /// The slots of the live tasks, in board order: by the position of the column where the task shows, then by
    /// ordinal, then by ULID. A task with no live column to show in comes last.
    let taskOrder: [Int]

    /// Makes the read view of a graph.
    ///
    /// - Parameters:
    ///   - graph: The graph of the board.
    ///   - boardKey: The current key of the board.
    init(of graph: Graph, inBoard boardKey: String) {
        readiness = Readiness(of: graph, inBoard: boardKey)
        self.boardKey = boardKey
        taskOrder = Self.boardOrder(of: readiness)
    }

    /// The graph of the board.
    var graph: Graph {
        readiness.graph
    }

    /// The resolver of the forgiving refs of the board.
    var resolver: RefResolver {
        RefResolver(graph: graph, boardKey: boardKey)
    }

    /// Gives the GraphQL `ID` of a node of the board.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The full URI of the node.
    func id(of ref: LocalRef) -> NodeID {
        NodeID(text: NodeURI(boardKey: boardKey, ref: ref).description)
    }

    /// Sorts the live tasks of a board in board order.
    ///
    /// - Parameter readiness: The readiness of the tasks of the board.
    /// - Returns: The slots of the live tasks, in board order.
    private static func boardOrder(of readiness: Readiness) -> [Int] {
        let columnSlots = readiness.columnOrder.slots
        let positions = Dictionary(uniqueKeysWithValues: zip(columnSlots, columnSlots.indices))
        let tasks = readiness.graph.allSlots.compactMap { slot -> (slot: Int, position: Int, task: TaskNode)? in
            guard let task = readiness.graph.node(at: slot, as: TaskNode.self), !task.fields.isDeleted else {
                return nil
            }
            let position = readiness.column(ofTaskAt: slot).flatMap { column in positions[column] } ?? positions.count
            return (slot, position, task)
        }
        return tasks.sorted { lhs, rhs in
            (lhs.position, lhs.task.ordinal, lhs.task.id) < (rhs.position, rhs.task.ordinal, rhs.task.id)
        }
        .map(\.slot)
    }
}

// MARK: - Objects

/// A GraphQL object that shows the state of one node of a ``BoardView``. It gives the fields of the `Node`
/// interface.
protocol GraphNodeObject: NodeObject {
    /// The state type of the node.
    associatedtype State: NodeState

    /// The read view of the graph.
    var view: BoardView { get }

    /// The state of the node.
    var state: State { get }
}

extension GraphNodeObject {
    /// The full URI of the node.
    var id: NodeID {
        view.id(of: state.ref)
    }

    /// The Markdown body of the node.
    var body: String {
        state.fields.body
    }

    /// The time of the first patch of the node.
    var created: DateTime {
        state.fields.created
    }

    /// The time of the last patch of the node.
    var updated: DateTime {
        state.fields.updated
    }

    /// The time of the delete, only on a tombstone.
    var deleted: DateTime? {
        state.fields.deleted
    }
}

/// A GraphQL object of a node that has a slot in the graph: each node type other than the board.
protocol SlotNodeObject: GraphNodeObject {
    /// Makes the object of a node.
    ///
    /// - Parameters:
    ///   - view: The read view of the graph.
    ///   - slot: The slot of the node.
    ///   - state: The state of the node.
    init(view: BoardView, slot: Int, state: State)
}

/// The state of a node whose local id is a ULID: a task or a comment.
protocol ULIDNodeState: NodeState {
    /// The ULID of the node: its local id.
    var id: ULID { get }
}

extension TaskNode: ULIDNodeState {}

extension CommentNode: ULIDNodeState {}

extension GraphNodeObject where State: ULIDNodeState {
    /// The short id of the node: the last characters of its ULID, in lowercase (plan.md §3.2).
    var shortID: String {
        ShortID(of: state.id).value
    }
}

extension BoardView {
    /// Gives the object of the node in a slot, live or tombstoned.
    ///
    /// - Parameter slot: A slot of the graph.
    /// - Returns: The object, or `nil` when the slot holds no node of the type of the object.
    func object<Object: SlotNodeObject>(at slot: Int) -> Object? {
        graph.node(at: slot, as: Object.State.self).map { state in
            Object(view: self, slot: slot, state: state)
        }
    }

    /// Gives the objects of the live nodes in some slots. A list does not show a tombstone (plan.md §3.3, rule 3).
    ///
    /// - Parameter slots: Slots of the graph.
    /// - Returns: The objects, in the order of the slots. A slot that holds a tombstone, or no node of the type of the
    ///   objects, gives no object.
    func liveObjects<Object: SlotNodeObject>(at slots: some Sequence<Int>) -> [Object] {
        slots.compactMap { slot in object(at: slot) }.filter { (object: Object) in !object.state.fields.isDeleted }
    }

    /// Gives the object of a non-null edge field, live or tombstoned.
    ///
    /// - Parameters:
    ///   - slot: The slot of the target, or `nil` when the edge has no target in the graph.
    ///   - edge: The stored edge, for the error.
    ///   - type: The node type of the target, for the error.
    /// - Returns: The object of the target.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the graph has no node of the type for the edge.
    func requiredObject<Object: SlotNodeObject>(
        at slot: Int?,
        forEdge edge: EdgeTarget?,
        ofType type: PatchNodeType
    ) throws(KanbanError) -> Object {
        guard let slot, let object: Object = object(at: slot) else {
            throw .notFound(type: type, reference: referenceText(of: edge))
        }
        return object
    }

    /// Gives the live tasks of the board in board order.
    ///
    /// - Parameter isIncluded: Tells if a task is in the result.
    /// - Returns: The tasks that `isIncluded` accepts, in board order.
    func orderedTasks(where isIncluded: (TaskObject) -> Bool = { _ in true }) -> [TaskObject] {
        taskOrder.compactMap { slot in object(at: slot) }.filter(isIncluded)
    }

    /// Finds the live task that a forgiving ref names.
    ///
    /// - Parameter reference: The ref as the caller wrote it: a full URI or a short form.
    /// - Returns: The task.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the ref.
    ///   ``KanbanError/ambiguousID(reference:matches:)`` when the ref is a prefix of more than one ULID.
    func task(for reference: String) throws(KanbanError) -> TaskObject {
        guard
            case .local(let ref) = try resolver.storedRef(for: reference, ofType: .task),
            let slot = graph.slot(for: ref),
            let task: TaskObject = object(at: slot)
        else {
            throw .notFound(type: .task, reference: reference)
        }
        return task
    }

    /// Gives the text of a stored edge for an error message: the full URI of its target.
    ///
    /// - Parameter edge: The stored edge, or `nil` when no patch set the edge.
    /// - Returns: The full URI of the target, or the empty text when there is no edge.
    private func referenceText(of edge: EdgeTarget?) -> String {
        switch edge {
        case .slot(let slot)?:
            graph.node(at: slot).map { node in id(of: node.ref).text } ?? ""
        case .unresolved(let ref)?:
            ref.uri(inBoard: boardKey).description
        case nil:
            ""
        }
    }
}

extension Graph {
    /// The state of the board node, or `nil` when the graph has no board node.
    var boardNode: BoardNode? {
        slot(for: .board).flatMap { slot in node(at: slot, as: BoardNode.self) }
    }
}

// MARK: - Board

extension BoardObject {
    /// Makes the object of the board of a read view.
    ///
    /// - Parameter view: The read view of the graph.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the graph has no board node.
    init(in view: BoardView) throws(KanbanError) {
        guard let state = view.graph.boardNode else {
            throw .notFound(type: .board, reference: view.boardKey)
        }
        self.init(view: view, state: state)
    }

    /// The current key of the board.
    var key: String {
        view.boardKey
    }

    /// The name of the board.
    var name: String {
        state.name
    }

    /// The live columns, in board order.
    var columns: [ColumnObject] {
        view.liveObjects(at: view.readiness.columnOrder.slots)
    }

    /// The live actors, in slot order.
    var actors: [ActorObject] {
        view.liveObjects(at: view.graph.allSlots)
    }

    /// The tags that the board lists: each live tag that is not renamed (plan.md §6.2), in slot order.
    var tags: [TagObject] {
        view.liveObjects(at: view.graph.boardTagSlots)
    }

    /// The counts of the live tasks.
    var summary: BoardSummary {
        view.readiness.summary
    }

    /// Resolves `Board.task`: one live task by a full URI or a short form.
    ///
    /// The GraphQL field is nullable (plan.md §4.1): an error gives `null` for the field and one item in `errors`,
    /// and the other fields of the board keep their data.
    ///
    /// - Parameters:
    ///   - context: The context of the call. The field does not read it.
    ///   - arguments: The ref of the task.
    /// - Returns: The task. The value is never `nil`. The optional type makes the GraphQL field nullable.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the ref.
    ///   ``KanbanError/ambiguousID(reference:matches:)`` when the ref is a prefix of more than one ULID.
    func task(context _: KanbanContext, arguments: TaskArguments) throws(KanbanError) -> TaskObject? {
        try view.task(for: arguments.id.text)
    }

    /// Resolves `Board.nextTask` (plan.md §6): the first task in board order that is not done, is ready, and matches
    /// the filter.
    ///
    /// - Parameters:
    ///   - context: The context of the call. The field does not read it.
    ///   - arguments: The filter.
    /// - Returns: The next task, or `nil` when no task is next.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse.
    func nextTask(context _: KanbanContext, arguments: FilterArguments) throws(KanbanError) -> TaskObject? {
        try TaskSelection(filtering: arguments.filter, excludingDone: true).tasks(in: view, where: \.ready).first
    }

    /// Resolves `Board.tasks`: one page of the live tasks that the filter and the scoping arguments select, in board
    /// order (plan.md §6.3).
    ///
    /// The GraphQL field is nullable: an error gives `null` for the field and one item in `errors`, and the other
    /// fields of the board keep their data.
    ///
    /// - Parameters:
    ///   - context: The context of the call. The field does not read it.
    ///   - arguments: The filter, the scoping arguments, the page size, and the cursor before the page.
    /// - Returns: The page, the page info, and the number of all selected tasks. The value is never `nil`. The
    ///   optional type makes the GraphQL field nullable.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter or a scoping value is
    ///   not valid. ``KanbanError/notFound(type:reference:)`` when the cursor names no task of the list.
    ///   ``KanbanError/ambiguousID(reference:matches:)`` when the cursor is a prefix of more than one ULID.
    func tasks(context _: KanbanContext, arguments: TasksArguments) throws(KanbanError) -> TaskConnection? {
        let tasks = try TaskSelection(for: arguments).tasks(in: view)
        var start = tasks.startIndex
        if let cursor = arguments.after {
            let after = try view.task(for: cursor)
            guard let position = tasks.firstIndex(where: { task in task.slot == after.slot }) else {
                throw .notFound(type: .task, reference: cursor)
            }
            start = tasks.index(after: position)
        }
        let pageSize = arguments.first ?? TasksArguments.defaultPageSize
        let page = tasks[start...].prefix(max(pageSize, .zero))
        let edges = page.map { task in TaskEdge(node: task, cursor: task.id.text) }
        let pageInfo = PageInfo(
            hasPreviousPage: start > tasks.startIndex,
            hasNextPage: page.endIndex < tasks.endIndex,
            startCursor: edges.first?.cursor,
            endCursor: edges.last?.cursor
        )
        return TaskConnection(edges: edges, pageInfo: pageInfo, totalCount: tasks.count)
    }
}

// MARK: - Column, actor, and tag

/// A GraphQL object of a node that lists the tasks that it holds in a `tasks(filter:)` field: a column, an actor, or
/// a tag.
protocol TaskHolderObject: GraphNodeObject {
    /// Tells if the node holds a task.
    ///
    /// - Parameter task: A live task of the board.
    /// - Returns: `true` when the node holds the task.
    func isHolder(of task: TaskObject) -> Bool
}

extension TaskHolderObject {
    /// Resolves the `tasks` field: the live tasks that the node holds and that match the filter, in board order. The
    /// list keeps the done tasks.
    ///
    /// The GraphQL field is nullable: an error gives `null` for the field and one item in `errors`, and the other
    /// fields keep their data.
    ///
    /// - Parameters:
    ///   - context: The context of the call. The field does not read it.
    ///   - arguments: The filter.
    /// - Returns: The tasks. The value is never `nil`. The optional type makes the GraphQL field nullable.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse.
    func tasks(context _: KanbanContext, arguments: FilterArguments) throws(KanbanError) -> [TaskObject]? {
        try TaskSelection(filtering: arguments.filter).tasks(in: view, where: isHolder(of:))
    }
}

extension ColumnObject: TaskHolderObject {
    /// The name of the column.
    var name: String {
        state.name
    }

    /// The sort key of the column on the board.
    var order: Int {
        state.order
    }

    /// Tells if a task shows in the column.
    ///
    /// - Parameter task: A live task of the board.
    /// - Returns: `true` when the task shows in the column.
    func isHolder(of task: TaskObject) -> Bool {
        view.readiness.column(ofTaskAt: task.slot) == slot
    }
}

extension ActorObject {
    /// The name of the actor.
    var name: String {
        state.name
    }

    /// The color of the actor, or `nil` when the actor has no color.
    var color: String? {
        state.color
    }

    /// Tells if a task has the actor as assignee.
    ///
    /// - Parameter task: A live task of the board.
    /// - Returns: `true` when an `assignees` edge of the task has the actor as its target.
    func isHolder(of task: TaskObject) -> Bool {
        task.state.assignees.contains(.slot(slot))
    }
}

extension TagObject {
    /// The name of the tag.
    var name: String {
        state.name
    }

    /// The color of the tag: the color that a patch set, else the auto color of the slug.
    var color: String {
        state.color ?? AutoColor.color(forText: state.slug)
    }

    /// Tells if a task has the tag, from an edge or a marker (plan.md §6.1).
    ///
    /// - Parameter task: A live task of the board.
    /// - Returns: `true` when the tags of the task hold the tag.
    func isHolder(of task: TaskObject) -> Bool {
        view.graph.tagSlots(of: task.state).contains(slot)
    }
}

// MARK: - Task

extension TaskObject {
    /// The title of the task.
    var title: String {
        state.title
    }

    /// The position of the task in its column, as text.
    var ordinal: String {
        state.ordinal.description
    }

    /// The live actors of the task.
    var assignees: [ActorObject] {
        view.liveObjects(at: state.assignees.compactMap(\.resolvedSlot))
    }

    /// The live tags of the task: the edges and the markers (plan.md §6.1).
    var tags: [TagObject] {
        view.liveObjects(at: view.graph.tagSlots(of: state))
    }

    /// The live tasks of this board that the task depends on: the edges and the markers (plan.md §6.1). A task of a
    /// different board is not in the list until the cross-repo task.
    var dependsOn: [TaskObject] {
        view.liveObjects(at: view.graph.dependencies(of: state, inBoard: view.boardKey).compactMap(\.resolvedSlot))
    }

    /// The tasks of this board that block the task.
    var blockedBy: [TaskObject] {
        view.liveObjects(at: view.readiness.blockers(ofTaskAt: slot).compactMap(\.resolvedSlot))
    }

    /// The live tasks that depend on the task.
    var blocks: [TaskObject] {
        view.liveObjects(at: view.readiness.dependents(ofTaskAt: slot))
    }

    /// `true` when no dependency blocks the task.
    var ready: Bool {
        view.readiness.isReady(taskAt: slot)
    }

    /// The virtual tags of the task, for example `READY`.
    var virtualTags: [String] {
        view.readiness.virtualTags(ofTaskAt: slot).map(\.rawValue)
    }

    /// The counts of the checklist of the body.
    var progress: TaskProgress {
        TaskProgress(of: state.fields.body)
    }

    /// The live comments of the task, in the order of their ULIDs.
    var comments: [CommentObject] {
        view.liveObjects(at: view.graph.comments(ofTaskAt: slot))
    }

    /// The time when the task left the first column.
    var started: DateTime? {
        view.readiness.started(ofTaskAt: slot)
    }

    /// The time when the task became done.
    var completed: DateTime? {
        view.readiness.completed(ofTaskAt: slot)
    }

    /// Resolves `Task.column`: the column where the task shows.
    ///
    /// - Parameters:
    ///   - context: The context of the call. The field does not read it.
    ///   - arguments: The field has no arguments.
    /// - Returns: The column.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the board has no live column.
    func column(context _: KanbanContext, arguments _: NoArguments) throws(KanbanError) -> ColumnObject {
        try view.requiredObject(at: view.readiness.column(ofTaskAt: slot), forEdge: state.column, ofType: .column)
    }
}

// MARK: - Comment

extension CommentObject {
    /// Resolves `Comment.task`: the task of the comment, live or tombstoned.
    ///
    /// - Parameters:
    ///   - context: The context of the call. The field does not read it.
    ///   - arguments: The field has no arguments.
    /// - Returns: The task.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the graph does not have the task.
    func task(context _: KanbanContext, arguments _: NoArguments) throws(KanbanError) -> TaskObject {
        try view.requiredObject(at: state.task?.resolvedSlot, forEdge: state.task, ofType: .task)
    }

    /// Resolves `Comment.author`: the actor that wrote the comment. A tombstoned actor is the author too
    /// (``Graph/author(ofCommentAt:)``).
    ///
    /// - Parameters:
    ///   - context: The context of the call. The field does not read it.
    ///   - arguments: The field has no arguments.
    /// - Returns: The actor.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the graph does not have the actor.
    func author(context _: KanbanContext, arguments _: NoArguments) throws(KanbanError) -> ActorObject {
        let authorSlot = view.graph.author(ofCommentAt: slot).flatMap { actor in view.graph.slot(for: actor.ref) }
        return try view.requiredObject(at: authorSlot, forEdge: state.author, ofType: .actor)
    }
}
