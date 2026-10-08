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

    /// The directory, the search, and the events of the board, or `nil` for a view that only a graph rule, the
    /// history replay, or a test fixture reads.
    let source: BoardSource?

    /// Makes the read view of a graph.
    ///
    /// - Parameters:
    ///   - graph: The graph of the board.
    ///   - boardKey: The current key of the board.
    ///   - source: The directory, the search, and the events of the board. The default is `nil`.
    ///   - related: The related boards that the cross-board dependencies read (plan.md §6.6). The default reads no
    ///     related board.
    init(
        of graph: Graph,
        inBoard boardKey: String,
        from source: BoardSource? = nil,
        reading related: RelatedBoards = .unavailable
    ) {
        readiness = Readiness(of: graph, inBoard: boardKey, reading: related)
        self.boardKey = boardKey
        self.source = source
    }

    /// The graph of the board.
    var graph: Graph {
        readiness.graph
    }

    /// The related boards that the cross-board dependencies read.
    var related: RelatedBoards {
        readiness.related
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

    /// The tasks of the board, live and tombstoned, in board order. A task list selects from them with a
    /// ``TaskFilter``, which leaves out the tombstones unless the filter names `#DELETED` (plan.md §3.3, rule 3).
    var allTasks: [TaskObject] {
        readiness.taskOrder.compactMap { slot in object(at: slot) }
    }

    /// Finds the task that a forgiving ref names.
    ///
    /// - Parameters:
    ///   - reference: The ref as the caller wrote it: a full URI or a short form.
    ///   - includesTombstones: `true` when the ref can name a tombstoned task.
    /// - Returns: The task.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no task that the call accepts has the ref.
    ///   ``KanbanError/ambiguousID(reference:matches:)`` when the ref is a prefix of more than one ULID.
    func task(
        for reference: String,
        includingTombstones includesTombstones: Bool = false
    ) throws(KanbanError) -> TaskObject {
        let storedRef = try resolver.storedRef(
            for: reference,
            ofType: .task,
            includingTombstones: includesTombstones
        )
        guard
            case .local(let ref) = storedRef,
            let slot = graph.slot(for: ref),
            let task: TaskObject = object(at: slot)
        else {
            throw .notFound(type: .task, reference: reference)
        }
        return task
    }

    /// Finds the node of any type that a forgiving ref names, live or tombstoned: `node(id:)` (plan.md §3.3, rule 3).
    ///
    /// - Parameter reference: The ref as the caller wrote it: a full URI or a short form.
    /// - Returns: The object of the node, or `nil` when no node of this board has the ref.
    /// - Throws: ``KanbanError/ambiguousID(reference:matches:)`` when the ref is a prefix of more than one ULID.
    func node(for reference: String) throws(KanbanError) -> (any NodeObject)? {
        try resolver.anyLocalRef(for: reference)
            .flatMap { ref in graph.slot(for: ref) }
            .flatMap { slot in nodeObject(at: slot) }
    }

    /// Gives the object of the node in a slot as a value of the `Node` interface, live or tombstoned.
    ///
    /// - Parameter slot: A slot of the graph.
    /// - Returns: The object of the type of the node, or `nil` when the slot holds no node.
    func nodeObject(at slot: Int) -> (any NodeObject)? {
        switch graph.node(at: slot) {
        case .board(let board)?: BoardObject(view: self, state: board)
        case .column(let column)?: ColumnObject(view: self, slot: slot, state: column)
        case .actor(let actor)?: ActorObject(view: self, slot: slot, state: actor)
        case .tag(let tag)?: TagObject(view: self, slot: slot, state: tag)
        case .task(let task)?: TaskObject(view: self, slot: slot, state: task)
        case .comment(let comment)?: CommentObject(view: self, slot: slot, state: comment)
        case nil: nil
        }
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

    /// The root directory of the repo of the board (plan.md §6.6), or `nil` for a board in memory only.
    var path: String? {
        view.source?.directory.path
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
    func task(context _: KanbanContext, arguments: NodeArguments) throws(KanbanError) -> TaskObject? {
        try view.task(for: arguments.id.text)
    }

    /// Resolves `Board.nextTask` (plan.md §6): the first task in board order that has the virtual tag `READY` and
    /// matches the filter. `READY` is live, not done, and ready, so a filter that names `#DELETED` or `#DONE` gives
    /// no tombstone and no done task.
    ///
    /// - Parameters:
    ///   - context: The context of the call. The field does not read it.
    ///   - arguments: The filter.
    /// - Returns: The next task, or `nil` when no task is next.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse.
    func nextTask(context _: KanbanContext, arguments: FilterArguments) throws(KanbanError) -> TaskObject? {
        let isReady: (TaskObject) -> Bool = { task in view.readiness.hasVirtualTag(.ready, taskAt: task.slot) }
        return try TaskSelection(filtering: arguments.filter).tasks(in: view, where: isReady).first
    }

    /// Resolves `Board.searchTasks` (plan.md §6.4): the tasks that the search ranks for the query, highest score
    /// first. The selection is the same as in `Board.tasks`: the filter applies, a done task is a hit as each other
    /// live task, and a tombstone is a hit only when the filter names `#DELETED`.
    ///
    /// The GraphQL field is nullable: an error gives `null` for the field and one item in `errors`, and the other
    /// fields of the board keep their data.
    ///
    /// - Parameters:
    ///   - context: The context of the call. It holds the search of the current board, for a view with no source.
    ///   - arguments: The query, the filter, and the largest number of hits.
    /// - Returns: The hits. The value is never `nil`. The optional type makes the GraphQL field nullable.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse.
    func searchTasks(context: KanbanContext, arguments: SearchTasksArguments) async throws -> [TaskHit]? {
        let tasks = try TaskSelection(filtering: arguments.filter).tasks(in: view)
        return try await (view.source?.search ?? context.search).hits(
            for: arguments.query,
            in: view,
            among: tasks,
            first: arguments.first ?? TasksArguments.defaultPageSize
        )
    }

    /// Resolves `Board.tasks`: one page of the tasks that the filter selects, in board order (plan.md §3.3 rule 3,
    /// §6.3). With no filter, the list has each live task, done or not. The list has a tombstone only when the filter
    /// names `#DELETED`.
    ///
    /// The GraphQL field is nullable: an error gives `null` for the field and one item in `errors`, and the other
    /// fields of the board keep their data.
    ///
    /// - Parameters:
    ///   - context: The context of the call. The field does not read it.
    ///   - arguments: The filter, the page size, and the cursor before the page.
    /// - Returns: The page, the page info, and the number of all selected tasks. The value is never `nil`. The
    ///   optional type makes the GraphQL field nullable.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse. ``KanbanError/notFound(type:reference:)`` when the cursor names no task of the list.
    ///   ``KanbanError/ambiguousID(reference:matches:)`` when the cursor is a prefix of more than one ULID.
    func tasks(context _: KanbanContext, arguments: TasksArguments) throws(KanbanError) -> TaskConnection? {
        let tasks = try TaskSelection(filtering: arguments.filter).tasks(in: view)
        var start = tasks.startIndex
        if let cursor = arguments.after {
            // The cursor can name a tombstone of a `#DELETED` list. A task that the list does not hold is not found.
            let after = try view.task(for: cursor, includingTombstones: true)
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
    /// The kind of the filter atom that names a node of this type: `%` for a column, `@` for an actor, and `#` for a
    /// tag.
    static var scopeKind: FilterAtomKind { get }
}

extension TaskHolderObject {
    /// The filter atom that names the node by its URL, for example `%kanban://<board-key>/column/doing`.
    private var scope: FilterExpr {
        .atom(Self.scopeKind, .uri(NodeURI(boardKey: view.boardKey, ref: state.ref)))
    }

    /// Resolves the `tasks` field: the tasks that the node holds and that match the filter, in board order.
    ///
    /// The list is the same as `Board.tasks` with the filter `<scope> && (<filter>)`, where the scope is the atom of
    /// the node. Thus the defaults are the same: with no filter, the node lists each live task that it holds, done or
    /// not, and a tombstone only when the filter names `#DELETED` (``TaskFilter``).
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
        try tasks(filteredBy: arguments.filter)
    }

    /// Gives the tasks that the node holds and that match a filter, in board order: the list of the `tasks` field.
    ///
    /// - Parameter text: The filter, or `nil` for no filter.
    /// - Returns: The tasks.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse.
    func tasks(filteredBy text: String?) throws(KanbanError) -> [TaskObject] {
        try TaskSelection(filtering: text, within: scope).tasks(in: view)
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

    /// The `%` atom names a column.
    static let scopeKind = FilterAtomKind.column
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

    /// The `@` atom names the assignee of a task.
    static let scopeKind = FilterAtomKind.assignee
}

extension TagObject {
    /// The name of the tag.
    var name: String {
        state.name
    }

    /// The color of the tag: the color that a patch set, else the auto color of the slug.
    var color: String {
        state.resolvedColor
    }

    /// The `#` atom names a tag, from an edge or a marker (plan.md §6.1).
    static let scopeKind = FilterAtomKind.tag
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

    /// The live tasks that the task depends on: the edges and the markers (plan.md §6.1). A task of a related board
    /// is in the list when a loaded board has it (plan.md §6.6). A target that no loaded board has is not in the list.
    var dependsOn: [TaskObject] {
        view.readiness.dependencies(ofTaskAt: slot).compactMap(liveTask(at:))
    }

    /// The live tasks that block the task, also the tasks of related boards.
    var blockedBy: [TaskObject] {
        view.readiness.blockers(ofTaskAt: slot).compactMap(liveTask(at:))
    }

    /// Gives the live task at the target of a dependency.
    ///
    /// - Parameter target: The target: a slot of this board, or a ref to a task of a related board.
    /// - Returns: The task, with the read view of its own board, or `nil` when the target is a tombstone or no loaded
    ///   board has it.
    private func liveTask(at target: EdgeTarget) -> TaskObject? {
        switch target {
        case .slot(let targetSlot):
            return view.liveObjects(at: [targetSlot]).first
        case .unresolved(let ref):
            guard let found = view.related.task(for: ref), !found.state.fields.isDeleted else {
                return nil
            }
            return TaskObject(view: found.board.view(reading: view.related), slot: found.slot, state: found.state)
        }
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
        try view.requiredObject(at: authorSlot, forEdge: state.author, ofType: .actor)
    }

    /// The slot of the author of the comment, live or tombstoned (``Graph/author(ofCommentAt:)``), or `nil` when the
    /// graph does not have the actor.
    var authorSlot: Int? {
        view.graph.author(ofCommentAt: slot).flatMap { actor in view.graph.slot(for: actor.ref) }
    }
}
