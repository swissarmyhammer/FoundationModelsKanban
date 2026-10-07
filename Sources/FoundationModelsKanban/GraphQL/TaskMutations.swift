import Graphiti
import GraphQL

// MARK: - Names

extension MutationName {
    /// The mutation that makes a task.
    static let addTask = "addTask"

    /// The mutation that changes the title, the body, the assignees, the tags, or the dependencies of a task.
    static let updateTask = "updateTask"
}

// MARK: - Arguments

/// The `input` object of `addTask` (plan.md §4.2). The input has no time value: a `created`, `due`, or `scheduled`
/// field is not in the schema, so the schema validation refuses it (plan.md §12, item 20).
private struct AddTaskInput: Decodable, Sendable {
    /// The title of the task.
    let title: String

    /// The Markdown body of the task: the full text, or `nil` for no body.
    let body: String?

    /// The column of the task, or `nil` for the column with the minimum order.
    let column: NodeID?

    /// The ordinal of the task in its column, or `nil` for the end of the column.
    let ordinal: String?

    /// The actors of the task, or `nil` for the session actor when the board knew it before the call.
    let assignees: [NodeID]?

    /// The tag names, slugs, or tag URIs of the task. An unknown tag is made.
    let tags: [String]?

    /// The tasks that the task waits for, in this board or in a different board.
    let dependsOn: [NodeID]?
}

/// The `input` object of `updateTask` (plan.md §4.2). A field that is not set does not change, and `null` clears the
/// field. A list replaces the list.
private struct UpdateTaskInput: Decodable, Sendable {
    /// The task: a full URI or a short form (plan.md §3.2).
    let id: NodeID

    /// The new title of the task.
    let title: FieldUpdate<String>

    /// The new Markdown body of the task: the full text. The mutation writes the diff from the current body.
    let body: FieldUpdate<String>

    /// The new actors of the task.
    let assignees: FieldUpdate<[NodeID]>

    /// The new tags of the task: tag names, slugs, or tag URIs.
    let tags: FieldUpdate<[String]>

    /// The new dependencies of the task.
    let dependsOn: FieldUpdate<[NodeID]>
}

// MARK: - Change

/// The changes of one `addTask` or `updateTask` field, with each ref in the stored form (plan.md §4.3).
private struct TaskChange {
    /// The update of each single-value property: `title`, `column`, and `ordinal`.
    let values: [String: FieldUpdate<PatchValue>]

    /// The update of the body.
    let body: FieldUpdate<String>

    /// The new list of each edge property that the field changes: `assignees`, `tags`, or `dependsOn`.
    let edges: [String: [StoredRef]]
}

// MARK: - Resolvers

extension KanbanResolver {
    /// Resolves `Mutation.addTask`: mints the task ULID, and writes one task patch with the scalars, the edges, and
    /// the body diff, plus a tag patch for each unknown or tombstoned tag (plan.md §4.2, §6, §6.1).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The new task.
    /// - Returns: The task. The GraphQL field is nullable, so that an error gives `null` for this field only.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when a column or a dependency names no node.
    ///   ``KanbanError/actorNotFound(reference:)`` when an assignee is not an actor.
    ///   ``KanbanError/invalidOrdinal(ordinal:)``, ``KanbanError/invalidTagName(name:)``, and
    ///   ``KanbanError/dependencyCycle(path:)``.
    fileprivate func addTask(
        context: KanbanContext,
        arguments: InputArguments<AddTaskInput>
    ) async throws -> TaskObject? {
        let input = arguments.input
        let knownActor = context.store.knownSessionActor.map { actor in [StoredRef.local(actor)] }
        return try await context.changeNode(named: MutationName.addTask) { work, resolver, time in
            let ref = LocalRef.task(work.mintULID())
            let column = try work.graph.columnRef(for: input.column, resolvingWith: resolver)
            let ordinal = try input.ordinal.map(Ordinal.init(parsing:)) ?? work.graph.nextOrdinal(inColumn: column)
            var edges = try work.edges(
                assignees: input.assignees,
                tags: input.tags,
                dependsOn: input.dependsOn,
                resolvingWith: resolver,
                at: time
            )
            edges[PropertyName.assignees] = edges[PropertyName.assignees] ?? knownActor
            let values: [String: FieldUpdate<PatchValue>] = [
                PropertyName.title: .changed(.string(input.title)),
                PropertyName.column: .changed(.ref(.local(column))),
                PropertyName.ordinal: .changed(.string(ordinal.value)),
            ]
            let body = input.body.map(FieldUpdate.changed) ?? .unchanged
            let change = TaskChange(values: values, body: body, edges: edges)
            try work.write(change, toTask: ref, inBoard: resolver.boardKey, at: time)
            return ref
        }
    }

    /// Resolves `Mutation.updateTask`: writes one task patch with the given changes. A list writes the `add` and
    /// `remove` difference to the current list, and a removed dependency loses its URL in the body (plan.md §6.1).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The task and the changes.
    /// - Returns: The task after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the id, or a dependency names no
    ///   task. ``KanbanError/actorNotFound(reference:)``, ``KanbanError/invalidTagName(name:)``, and
    ///   ``KanbanError/dependencyCycle(path:)``.
    fileprivate func updateTask(
        context: KanbanContext,
        arguments: InputArguments<UpdateTaskInput>
    ) async throws -> TaskObject? {
        let input = arguments.input
        return try await context.changeNode(named: MutationName.updateTask) { work, resolver, time in
            let ref = try resolver.nodeRef(for: input.id, ofType: .task)
            let edges = try work.edges(
                assignees: input.assignees.value(clearingTo: []),
                tags: input.tags.value(clearingTo: []),
                dependsOn: input.dependsOn.value(clearingTo: []),
                resolvingWith: resolver,
                at: time
            )
            let values = [PropertyName.title: input.title.map(PatchValue.string)]
            let change = TaskChange(values: values, body: input.body, edges: edges)
            try work.write(change, toTask: ref, inBoard: resolver.boardKey, at: time)
            return ref
        }
    }
}

// MARK: - Refs

extension RefResolver {
    /// Changes the forgiving refs of the assignees to the local refs of live actors (plan.md §6, "Assignees").
    ///
    /// - Parameter ids: The refs as the caller wrote them.
    /// - Returns: The stored refs.
    /// - Throws: ``KanbanError/actorNotFound(reference:)`` when a ref names no live actor.
    fileprivate func actorRefs(for ids: [NodeID]) throws -> [StoredRef] {
        try ids.map { id in .local(try actorRef(for: id)) }
    }

    /// Changes the forgiving ref of one actor to the local ref of the actor.
    ///
    /// - Parameters:
    ///   - id: The ref as the caller wrote it: a full URI or the slug.
    ///   - includesTombstones: `true` when the ref can name a tombstoned actor.
    /// - Returns: The local ref of the actor.
    /// - Throws: ``KanbanError/actorNotFound(reference:)`` when the ref names no actor that the lookup accepts.
    func actorRef(
        for id: NodeID,
        includingTombstones includesTombstones: Bool = false
    ) throws(KanbanError) -> LocalRef {
        do {
            return try nodeRef(for: id, ofType: .actor, includingTombstones: includesTombstones)
        } catch {
            throw .actorNotFound(reference: id.text)
        }
    }

    /// Changes the forgiving refs of the dependencies to stored refs: a local ref for a live task of this board, and
    /// the full URI for a task of a different board (plan.md §3.2, §6.1).
    ///
    /// - Parameter ids: The refs as the caller wrote them.
    /// - Returns: The stored refs.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when a ref names no live task of this board.
    ///   ``KanbanError/ambiguousID(reference:matches:)`` when a ref is a prefix of more than one ULID.
    fileprivate func dependencyRefs(for ids: [NodeID]) throws -> [StoredRef] {
        try ids.map { id in try storedRef(for: id.text, ofType: .task, acceptingRemote: true) }
    }

    /// Changes the forgiving ref of one tag to the tag that it names (plan.md §6.1). A URI must name a tag of the
    /// graph. A name or a slug gives its tag name, also when the board has no tag with that slug.
    ///
    /// - Parameters:
    ///   - name: The tag name, the slug, or the tag URI.
    ///   - includesTombstones: `true` when a URI can name a tombstoned tag.
    /// - Returns: The tag node that a URI names, or the tag name of a name or a slug.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when a URI names no tag that the lookup accepts.
    ///   ``KanbanError/invalidTagName(name:)`` when a name gives an empty slug.
    func tag(named name: String, includingTombstones includesTombstones: Bool) throws(KanbanError) -> TagReference {
        guard NodeURI.hasScheme(atStartOf: name) else {
            return .name(try TagName(normalizing: name))
        }
        return .node(try nodeRef(for: NodeID(text: name), ofType: .tag, includingTombstones: includesTombstones))
    }
}

/// The tag that one forgiving tag ref names: a tag name, a slug, or a tag URI (plan.md §6.1).
enum TagReference {
    /// A tag node of the graph, that a URI names.
    case node(LocalRef)

    /// A tag name. The board can have no tag with its slug.
    case name(TagName)

    /// The local ref of the tag: the node, or the tag with the slug of the name.
    var ref: LocalRef {
        switch self {
        case .node(let ref): ref
        case .name(let name): .tag(slug: name.slug.value)
        }
    }
}

// MARK: - Patches

extension WorkingCopy {
    /// Resolves the edge lists of a task field. A list that the field does not give is not in the result.
    ///
    /// - Parameters:
    ///   - assignees: The actor refs, or `nil` for no change.
    ///   - tags: The tag names, slugs, or tag URIs, or `nil` for no change. An unknown or tombstoned tag gets a tag
    ///     patch first.
    ///   - dependsOn: The task refs, or `nil` for no change.
    ///   - resolver: The resolver of the forgiving refs of the board.
    ///   - time: The time of the change.
    /// - Returns: The new list of each edge property that the field gives.
    /// - Throws: A ``KanbanError`` when a ref does not resolve, or a tag name gives an empty slug.
    fileprivate mutating func edges(
        assignees: [NodeID]?,
        tags: [String]?,
        dependsOn: [NodeID]?,
        resolvingWith resolver: RefResolver,
        at time: DateTime
    ) throws -> [String: [StoredRef]] {
        let lists: [String: [StoredRef]?] = [
            PropertyName.assignees: try assignees.map(resolver.actorRefs(for:)),
            PropertyName.tags: try tags.map { names in try tagRefs(named: names, resolvingWith: resolver, at: time) },
            PropertyName.dependsOn: try dependsOn.map(resolver.dependencyRefs(for:)),
        ]
        return lists.compactMapValues { list in list }
    }

    /// Writes the task patch of a field, and checks the dependency rule (plan.md §3.3, rule 6).
    ///
    /// The patch writes the given scalars, the `add` of each new list, and the `remove` of each current edge that the
    /// new list does not have. When the field replaces `dependsOn`, the body loses the URL of each removed dependency.
    /// A new `#marker` in the body gets a tag patch first (plan.md §6.1).
    ///
    /// - Parameters:
    ///   - change: The changes of the field.
    ///   - ref: The local ref of the task. A task that the graph does not have is a new task.
    ///   - key: The current key of the board. A dependency marker with this key names a task of the board.
    ///   - time: The time of the change.
    /// - Throws: ``KanbanError/dependencyCycle(path:)`` when an edge or a marker makes a cycle.
    ///   ``KanbanError/invalidTagName(name:)``, or an ``EventError`` when a patch breaks a rule of the log.
    fileprivate mutating func write(
        _ change: TaskChange,
        toTask ref: LocalRef,
        inBoard key: String,
        at time: DateTime
    ) throws {
        let task = graph.node(for: ref)?.state as? TaskNode
        let oldBody = task?.fields.body ?? ""
        let removedTargets = task.map { task in
            removedDependencies(of: task, keeping: change.edges, inBoard: key)
        } ?? []
        let newBody = removedTargets.reduce(change.body.newBody ?? oldBody) { body, target in
            DependencyMarkers.removing(markersOf: target, from: body)
        }
        try addMarkerTags(in: newBody, after: oldBody, at: time)
        let patch = try PatchInput(
            changing: ref,
            updating: change.values,
            adding: change.edges,
            removing: task.map { task in removedEdges(of: task, keeping: change.edges) } ?? [:],
            body: newBody == oldBody ? .unchanged : .changed(newBody),
            from: oldBody
        )
        try apply(patch, at: time)
        if change.edges[PropertyName.dependsOn] != nil || newBody != oldBody {
            try checkNoCycle(throughTask: ref, inBoard: key)
        }
    }

    /// Gives the current edges of a task that a new list does not have.
    ///
    /// - Parameters:
    ///   - task: The current task.
    ///   - edges: The new list of each edge property that the field changes.
    /// - Returns: The refs to remove, for each property of `edges`.
    private func removedEdges(of task: TaskNode, keeping edges: [String: [StoredRef]]) -> [String: [StoredRef]] {
        let current = [
            PropertyName.assignees: task.assignees,
            PropertyName.tags: task.tags,
            PropertyName.dependsOn: task.dependsOn,
        ]
        return Dictionary(
            uniqueKeysWithValues: edges.map { name, list in
                let stored = current[name, default: []].compactMap(graph.storedRef(of:))
                return (name, stored.filter { ref in !list.contains(ref) })
            }
        )
    }

    /// Gives the URIs of the current dependencies of a task, edges and markers, that a new `dependsOn` list does not
    /// have (plan.md §6.1, "Remove a dependency").
    ///
    /// - Parameters:
    ///   - task: The current task.
    ///   - edges: The new list of each edge property that the field changes.
    ///   - key: The current key of the board.
    /// - Returns: The URIs, or no URI when the field does not change `dependsOn`.
    private func removedDependencies(
        of task: TaskNode,
        keeping edges: [String: [StoredRef]],
        inBoard key: String
    ) -> [NodeURI] {
        guard let kept = edges[PropertyName.dependsOn] else {
            return []
        }
        return graph.dependencies(of: task, inBoard: key)
            .compactMap(graph.storedRef(of:))
            .filter { target in !kept.contains(target) }
            .map { target in target.uri(inBoard: key) }
    }

    /// Checks that no `dependsOn` cycle goes through a task (plan.md §3.3, rule 6).
    ///
    /// - Parameters:
    ///   - ref: The local ref of the task.
    ///   - key: The current key of the board.
    /// - Throws: ``KanbanError/dependencyCycle(path:)`` with the short id of each task on the cycle.
    private func checkNoCycle(throughTask ref: LocalRef, inBoard key: String) throws(KanbanError) {
        guard
            let slot = graph.slot(for: ref),
            let cycle = Readiness(of: graph, inBoard: key).cycle(throughTaskAt: slot)
        else {
            return
        }
        let path = cycle.compactMap { step in graph.node(at: step, as: TaskNode.self) }.map { task in
            "\(ShortID.sigil)\(ShortID(of: task.id).value)"
        }
        throw .dependencyCycle(path: path)
    }
}

// MARK: - Tags

extension WorkingCopy {
    /// Gives the tags that a list of tag names names. An unknown tag gets a `set` patch, and a tombstoned tag gets a
    /// `delete: false` patch, so that each tag is live (plan.md §6.1).
    ///
    /// - Parameters:
    ///   - names: The tag names, slugs, or tag URIs.
    ///   - resolver: The resolver of the forgiving refs of the board, for a tag URI.
    ///   - time: The time of the change.
    /// - Returns: The stored refs of the tags, after the rename redirect.
    /// - Throws: ``KanbanError/invalidTagName(name:)`` when a name gives an empty slug.
    ///   ``KanbanError/notFound(type:reference:)`` when a tag URI names no live tag.
    mutating func tagRefs(
        named names: [String],
        resolvingWith resolver: RefResolver,
        at time: DateTime
    ) throws -> [StoredRef] {
        try names.map { name in
            switch try resolver.tag(named: name, includingTombstones: false) {
            case .node(let ref):
                return .local(ref)
            case .name(let tagName):
                return .local(try addTag(tagName, at: time))
            }
        }
    }

    /// Makes sure that each new `#marker` of a body names a live tag (plan.md §6.1). A marker that the old body
    /// already had does not change.
    ///
    /// - Parameters:
    ///   - newBody: The body after the change.
    ///   - oldBody: The body before the change.
    ///   - time: The time of the change.
    /// - Throws: An ``EventError`` when a patch breaks a rule of the log.
    private mutating func addMarkerTags(in newBody: String, after oldBody: String, at time: DateTime) throws {
        let oldSlugs = Set(TagMarkers.slugs(in: oldBody))
        for slug in TagMarkers.slugs(in: newBody) where !oldSlugs.contains(slug) {
            _ = try addTag(TagName(normalizing: slug.value), at: time)
        }
    }

    /// Makes a tag live with ``ensureLiveTag(_:setting:body:at:)``. An unknown tag gets a `set` patch with the name.
    ///
    /// - Parameters:
    ///   - name: The tag name.
    ///   - time: The time of the change.
    /// - Returns: The local ref of the tag at the end of the rename chain.
    /// - Throws: An ``EventError`` when a patch breaks a rule of the log.
    private mutating func addTag(_ name: TagName, at time: DateTime) throws -> LocalRef {
        try ensureLiveTag(.tag(slug: name.slug.value), setting: [PropertyName.name: .string(name.name)], at: time)
    }
}

// MARK: - Graph

extension Graph {
    /// Finds the column of a new task: the column that the input names, else the column with the minimum order
    /// (plan.md §6, "Default column on add").
    ///
    /// - Parameters:
    ///   - id: The column that the input names, or `nil` for the default column.
    ///   - resolver: The resolver of the forgiving refs of the board.
    /// - Returns: The local ref of the column.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the input names no live column, or when the board has
    ///   no live column.
    fileprivate func columnRef(for id: NodeID?, resolvingWith resolver: RefResolver) throws(KanbanError) -> LocalRef {
        if let id {
            return try resolver.nodeRef(for: id, ofType: .column)
        }
        return try columnRef(atSlot: ColumnOrder(of: self).first)
    }

    /// Gives the local ref of the column in a slot of ``ColumnOrder``, for example its first or its terminal column.
    ///
    /// - Parameter slot: The slot of the column, or `nil` when the board has no live column.
    /// - Returns: The local ref of the column.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the slot is `nil` or holds no node.
    func columnRef(atSlot slot: Int?) throws(KanbanError) -> LocalRef {
        guard let slot, let column = node(at: slot) else {
            throw .notFound(type: .column, reference: "")
        }
        return column.ref
    }

    /// Gives the live tasks that show in a column, in the order of the column: ordinal, then ULID.
    ///
    /// - Parameters:
    ///   - column: The local ref of the column.
    ///   - task: The local ref of a task to leave out, for example the task that a move puts in the column, or `nil`
    ///     to keep each task.
    /// - Returns: The tasks.
    func tasks(inColumn column: LocalRef, excluding task: LocalRef? = nil) -> [TaskNode] {
        let order = ColumnOrder(of: self)
        let columnSlot = slot(for: column)
        return allSlots.filter(isLiveTask(at:))
            .compactMap { slot in node(at: slot, as: TaskNode.self) }
            .filter { shown in shown.ref != task && order.displaySlot(of: shown.column) == columnSlot }
            .sorted { lhs, rhs in (lhs.ordinal, lhs.id) < (rhs.ordinal, rhs.id) }
    }

    /// Gives the ordinal of a task that the call puts at the end of a column: after the last ordinal of the live tasks
    /// that show in the column, or the first ordinal for an empty column (plan.md §6, "Ordinals").
    ///
    /// - Parameters:
    ///   - column: The local ref of the column.
    ///   - task: The local ref of the task that the call moves, or `nil` for a new task. The column order does not
    ///     count this task.
    /// - Returns: The ordinal.
    func nextOrdinal(inColumn column: LocalRef, excluding task: LocalRef? = nil) -> Ordinal {
        tasks(inColumn: column, excluding: task).last.map { last in Ordinal(after: last.ordinal) } ?? .first
    }

    /// Gives the stored ref of an edge.
    ///
    /// - Parameter edge: The edge.
    /// - Returns: The local ref of the target in a slot, the ref of an unresolved edge, or `nil` when the slot holds
    ///   no node.
    func storedRef(of edge: EdgeTarget) -> StoredRef? {
        switch edge {
        case .slot(let slot): node(at: slot).map { node in .local(node.ref) }
        case .unresolved(let ref): ref
        }
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the task mutations, `addTask` and `updateTask`, and their `input` types (plan.md §4.2).
    ///
    /// - Returns: This builder, for method chaining.
    func addTaskMutations() -> Self {
        add {
            Input(AddTaskInput.self) {
                InputField("title", at: \.title)
                InputField("body", at: \.body)
                InputField("column", at: \.column)
                InputField("ordinal", at: \.ordinal)
                InputField("assignees", at: \.assignees)
                InputField("tags", at: \.tags)
                InputField("dependsOn", at: \.dependsOn)
            }
            Input(UpdateTaskInput.self) {
                InputField("id", at: \.id)
                InputField("title", at: \.title.value)
                InputField("body", at: \.body.value)
                InputField("assignees", at: \.assignees.value)
                InputField("tags", at: \.tags.value)
                InputField("dependsOn", at: \.dependsOn.value)
            }
        }
        .addMutation {
            Field(MutationName.addTask, at: KanbanResolver.addTask) { Argument("input", at: \.input) }
            Field(MutationName.updateTask, at: KanbanResolver.updateTask) { Argument("input", at: \.input) }
        }
    }
}
