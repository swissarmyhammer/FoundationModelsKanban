import Foundation

/// Evaluates a parsed filter against the tasks of one board (plan.md §6.3).
///
/// The evaluator resolves each atom one time, when it is made, so that the test of each task does no name lookup.
/// Each match ignores case. An atom whose value names nothing matches nothing; it is not an error.
///
/// - `#tag` matches a task that has the tag from an edge or from a `#marker` in its body, after the rename redirect
///   (``Graph/tagSlots(of:)``). It also matches a task that has the virtual tag of that name (``VirtualTag``).
/// - `@user` matches a task that is assigned to a live actor whose slug, or the slug of whose name, is the slug of
///   the value.
/// - `^id` matches the task itself, and each task that depends on it, from an edge or a dependency marker. The value
///   can be a full ULID, a short id, or a ULID prefix. As in Rust, the value resolves among the task and its
///   dependencies in this board (``ShortID/resolve(_:among:)``), so a prefix that is ambiguous there matches nothing.
/// - `%column` matches a task that shows in a live column whose slug, or the slug of whose name, is the slug of the
///   value. A task with no live column shows in the first column (``ColumnOrder``).
///
/// A `kanban://` URL with the current key of the board is the same as its local id. A tag, actor, or column URL of
/// a different board matches nothing, because those edges stay in one board (plan.md §6.6). A task URL of a
/// different board matches each task that depends on that task. The parser refuses a URL of the wrong type for its
/// atom; an atom that holds one anyway matches nothing.
///
/// This is a port of `evaluate` in the Rust file `swissarmyhammer-filter-expr/src/eval.rs`, and of
/// `TaskFilterAdapter` in the Rust file `swissarmyhammer-kanban/src/task_helpers.rs`.
struct FilterEvaluator {
    /// The test of the full filter.
    private let test: TaskTest

    /// Makes the evaluator of a filter for one board.
    ///
    /// - Parameters:
    ///   - filter: The parsed filter.
    ///   - readiness: The readiness of the tasks of the board. It holds the graph and the column order.
    ///   - boardKey: The current key of the board. A URL with this key names a node of the board.
    init(evaluating filter: FilterExpr, over readiness: Readiness, inBoard boardKey: String) {
        test = FilterCompiler(readiness: readiness, boardKey: boardKey).taskTest(for: filter)
    }

    /// Tells if a task matches the filter.
    ///
    /// - Parameter slot: The slot of the task, live or tombstoned.
    /// - Returns: `true` when the task matches. A slot that holds no task gives `false`.
    func matches(taskAt slot: Int) -> Bool {
        test(slot)
    }
}

// MARK: - Compile

/// A test of the task in one slot of the graph.
private typealias TaskTest = (Int) -> Bool

/// What the value of an atom names, after the resolve of a URL.
private enum AtomTarget {
    /// A short form in this board: a name, a slug, or a ULID form. A URL with the current key gives its local id.
    case local(String)

    /// A node of a different board.
    case remote(NodeURI)
}

/// Makes the test of each part of a filter for one board.
private struct FilterCompiler {
    /// The readiness of the tasks of the board.
    let readiness: Readiness

    /// The current key of the board.
    let boardKey: String

    /// The test that matches no task.
    private static var noMatch: TaskTest {
        { _ in false }
    }

    /// The graph of the board.
    private var graph: Graph {
        readiness.graph
    }

    /// Makes the test of a full filter: the slot must hold a task, and the task must match the filter.
    ///
    /// - Parameter filter: The parsed filter.
    /// - Returns: The test.
    func taskTest(for filter: FilterExpr) -> TaskTest {
        let filterTest = test(for: filter)
        return { slot in isTask(at: slot) && filterTest(slot) }
    }

    /// Makes the test of one part of a filter.
    ///
    /// - Parameter filter: The part of the filter.
    /// - Returns: The test.
    private func test(for filter: FilterExpr) -> TaskTest {
        switch filter {
        case .atom(let kind, let value):
            return test(for: kind, naming: target(of: value, for: kind))
        case .and(let lhs, let rhs):
            let left = test(for: lhs)
            let right = test(for: rhs)
            return { slot in left(slot) && right(slot) }
        case .or(let lhs, let rhs):
            let left = test(for: lhs)
            let right = test(for: rhs)
            return { slot in left(slot) || right(slot) }
        case .not(let operand):
            let operandTest = test(for: operand)
            return { slot in !operandTest(slot) }
        }
    }

    /// Tells if a slot holds a task, live or tombstoned.
    ///
    /// - Parameter slot: A slot of the graph.
    /// - Returns: `true` when the slot holds a task.
    private func isTask(at slot: Int) -> Bool {
        graph.node(at: slot, as: TaskNode.self) != nil
    }

    /// Finds what the value of an atom names.
    ///
    /// - Parameters:
    ///   - value: The value of the atom.
    ///   - kind: The kind of the atom.
    /// - Returns: The local form or the URI of a different board, or `nil` when the value is a URL of a node type
    ///   that the atom does not accept.
    private func target(of value: FilterValue, for kind: FilterAtomKind) -> AtomTarget? {
        switch value {
        case .name(let name):
            return .local(name)
        case .uri(let uri):
            guard uri.ref.nodeType == kind.nodeType else {
                return nil
            }
            guard let localID = uri.localRef(inBoard: boardKey)?.localID else {
                return .remote(uri)
            }
            return .local(localID)
        }
    }

    /// Makes the test of one atom.
    ///
    /// - Parameters:
    ///   - kind: The kind of the atom.
    ///   - target: What the value of the atom names, or `nil` when it names nothing.
    /// - Returns: The test.
    private func test(for kind: FilterAtomKind, naming target: AtomTarget?) -> TaskTest {
        switch target {
        case .local(let key)?:
            return localTest(for: kind, key: key)
        case .remote(let uri)?:
            return kind == .ref ? dependentTest(onRemoteTask: uri) : Self.noMatch
        case nil:
            return Self.noMatch
        }
    }

    /// Makes the test of one atom whose value is a short form in this board.
    ///
    /// - Parameters:
    ///   - kind: The kind of the atom.
    ///   - key: The short form.
    /// - Returns: The test.
    private func localTest(for kind: FilterAtomKind, key: String) -> TaskTest {
        switch kind {
        case .tag: tagTest(named: key)
        case .assignee: assigneeTest(named: key)
        case .ref: refTest(for: key)
        case .column: columnTest(named: key)
        }
    }
}

// MARK: - Tags

extension FilterCompiler {
    /// Makes the test of a `#tag` atom: a real tag from an edge or a marker, or a virtual tag.
    ///
    /// - Parameter name: The tag name, the slug, or the name of a virtual tag, in any case.
    /// - Returns: The test.
    private func tagTest(named name: String) -> TaskTest {
        let virtualTag = VirtualTag(named: name)
        let tagSlot = liveTagSlot(named: name)
        return { slot in isTagged(taskAt: slot, with: virtualTag) || isTagged(taskAt: slot, withTagAt: tagSlot) }
    }

    /// Finds the live tag that a tag name names, after the rename redirect (``RefResolver``).
    ///
    /// - Parameter name: The tag name or the slug.
    /// - Returns: The slot of the tag at the end of the rename chain, or `nil` when the name names no live tag.
    private func liveTagSlot(named name: String) -> Int? {
        let resolver = RefResolver(graph: graph, boardKey: boardKey)
        guard case .local(let ref)? = try? resolver.storedRef(for: name, ofType: .tag) else {
            return nil
        }
        return graph.slot(for: ref)
    }

    /// Tells if a task has a virtual tag.
    ///
    /// - Parameters:
    ///   - slot: The slot of the task.
    ///   - virtualTag: The virtual tag, or `nil` when the atom names no virtual tag.
    /// - Returns: `true` when the virtual tag applies to the task.
    private func isTagged(taskAt slot: Int, with virtualTag: VirtualTag?) -> Bool {
        guard let virtualTag else {
            return false
        }
        return readiness.hasVirtualTag(virtualTag, taskAt: slot)
    }

    /// Tells if a task has a real tag, from an edge or a marker.
    ///
    /// - Parameters:
    ///   - slot: The slot of the task.
    ///   - tagSlot: The slot of the live tag, or `nil` when the atom names no live tag.
    /// - Returns: `true` when the tags of the task hold the tag.
    private func isTagged(taskAt slot: Int, withTagAt tagSlot: Int?) -> Bool {
        guard let tagSlot, let task = graph.node(at: slot, as: TaskNode.self) else {
            return false
        }
        return graph.tagSlots(of: task).contains(tagSlot)
    }
}

// MARK: - Actors and columns

/// The state of a node that a filter atom can name by its slug or by the slug of its name: an actor or a column.
private protocol SlugNamedState: NodeState {
    /// The slug of the node: its local id.
    var slug: String { get }

    /// The name of the node.
    var name: String { get }
}

extension ActorNode: SlugNamedState {}

extension ColumnNode: SlugNamedState {}

extension FilterCompiler {
    /// Makes the test of an `@user` atom.
    ///
    /// - Parameter name: The slug or the name of the actor, in any case.
    /// - Returns: The test.
    private func assigneeTest(named name: String) -> TaskTest {
        let actorSlots = liveSlots(of: ActorNode.self, named: name)
        return { slot in isAssigned(taskAt: slot, toActorAmong: actorSlots) }
    }

    /// Makes the test of a `%column` atom.
    ///
    /// - Parameter name: The slug or the name of the column, in any case.
    /// - Returns: The test.
    private func columnTest(named name: String) -> TaskTest {
        let columnSlots = liveSlots(of: ColumnNode.self, named: name)
        return { slot in readiness.column(ofTaskAt: slot).map(columnSlots.contains) ?? false }
    }

    /// Finds the live nodes of one type whose slug, or the slug of whose name, is the slug of a name.
    ///
    /// - Parameters:
    ///   - type: The state type of the nodes, for example `ActorNode.self`.
    ///   - name: The name as the filter writes it.
    /// - Returns: The slots of the nodes. A name that gives an empty slug gives no slots.
    private func liveSlots<State: SlugNamedState>(of type: State.Type, named name: String) -> Set<Int> {
        let key = Slug.normalizedText(of: name)
        guard !key.isEmpty else {
            return []
        }
        return Set(
            graph.allSlots.filter { slot in
                graph.node(at: slot, as: type).map { node in matches(liveNode: node, withSlug: key) } ?? false
            }
        )
    }

    /// Tells if a node is live, and has a slug, or the slug of a name, that is a key.
    ///
    /// - Parameters:
    ///   - node: The state of the node.
    ///   - key: The slug to find.
    /// - Returns: `true` when the node is live and the slug of the node or of its name is the key.
    private func matches(liveNode node: some SlugNamedState, withSlug key: String) -> Bool {
        !node.fields.isDeleted && (node.slug == key || Slug.normalizedText(of: node.name) == key)
    }

    /// Tells if a task is assigned to one of some actors.
    ///
    /// - Parameters:
    ///   - slot: The slot of the task.
    ///   - actorSlots: The slots of the actors.
    /// - Returns: `true` when an `assignees` edge of the task has one of the actors as its target.
    private func isAssigned(taskAt slot: Int, toActorAmong actorSlots: Set<Int>) -> Bool {
        let assignees = graph.node(at: slot, as: TaskNode.self)?.assignees ?? []
        return assignees.contains { edge in edge.resolvedSlot.map(actorSlots.contains) ?? false }
    }
}

// MARK: - Refs

extension FilterCompiler {
    /// Makes the test of a `^id` atom whose value is a ULID form in this board.
    ///
    /// - Parameter reference: The full ULID, the short id, or a ULID prefix, in any case.
    /// - Returns: The test.
    private func refTest(for reference: String) -> TaskTest {
        { slot in isReferenced(taskAt: slot, by: reference) }
    }

    /// Makes the test of a `^id` atom whose value is the URL of a task of a different board.
    ///
    /// - Parameter uri: The URI of the task of the different board.
    /// - Returns: The test: a task matches when it depends on that task.
    private func dependentTest(onRemoteTask uri: NodeURI) -> TaskTest {
        let target = EdgeTarget.unresolved(.remote(uri))
        return { slot in readiness.dependencies(ofTaskAt: slot).contains(target) }
    }

    /// Tells if a reference names a task, or one of its dependencies in this board.
    ///
    /// This is a port of `short_ref_matches` in the Rust file `task_helpers.rs`: the candidates are the ULID of the
    /// task and the ULIDs of its dependencies in this board.
    ///
    /// - Parameters:
    ///   - slot: The slot of the task.
    ///   - reference: The full ULID, the short id, or a ULID prefix.
    /// - Returns: `true` when the reference resolves to exactly one candidate.
    private func isReferenced(taskAt slot: Int, by reference: String) -> Bool {
        guard let task = graph.node(at: slot, as: TaskNode.self) else {
            return false
        }
        let dependencies = readiness.dependencies(ofTaskAt: slot).compactMap(localTaskULID(of:))
        switch ShortID.resolve(reference, among: [task.id.ulidString] + dependencies) {
        case .found:
            return true
        case .notFound, .ambiguous:
            return false
        }
    }

    /// Gives the ULID text of a dependency in this board.
    ///
    /// - Parameter target: The target of the dependency.
    /// - Returns: The ULID text of the task, or `nil` for a task of a different board.
    private func localTaskULID(of target: EdgeTarget) -> String? {
        switch target {
        case .slot(let slot):
            graph.node(at: slot, as: TaskNode.self)?.id.ulidString
        case .unresolved(.local(let ref)):
            ref.nodeType == .task ? ref.localID : nil
        case .unresolved(.remote):
            nil
        }
    }
}

// MARK: - Names a column or a virtual tag

extension FilterExpr {
    /// `true` when the filter names a column: it has a `%` atom or a column URL at any depth, also under a NOT.
    ///
    /// The `excludeDone` default of a task list is `false` for such a filter, so that `%done` lists the done tasks
    /// (plan.md §6.3, scoping arguments).
    var namesColumn: Bool {
        containsAtom { kind, _ in kind == .column }
    }

    /// Tells if the filter names a virtual tag: it has a `#` atom or a tag URL with the name of the tag, in any case,
    /// at any depth, also under a NOT.
    ///
    /// A task list uses this test for each tag of ``VirtualTag/hiddenUnlessNamed`` (``TaskFilter``).
    ///
    /// - Parameter virtualTag: The virtual tag.
    /// - Returns: `true` when an atom of the filter names the tag.
    func names(_ virtualTag: VirtualTag) -> Bool {
        containsAtom { kind, value in kind == .tag && value.localName.flatMap(VirtualTag.init(named:)) == virtualTag }
    }

    /// Walks the filter, and tells if one of its atoms satisfies a condition.
    ///
    /// - Parameter predicate: The condition on the kind and the value of an atom.
    /// - Returns: `true` when an atom at any depth, also under a NOT, satisfies the condition.
    private func containsAtom(where predicate: (FilterAtomKind, FilterValue) -> Bool) -> Bool {
        switch self {
        case .atom(let kind, let value):
            predicate(kind, value)
        case .and(let lhs, let rhs), .or(let lhs, let rhs):
            lhs.containsAtom(where: predicate) || rhs.containsAtom(where: predicate)
        case .not(let operand):
            operand.containsAtom(where: predicate)
        }
    }
}

extension FilterValue {
    /// The name that the value gives in its board: the name as the filter writes it, or the local id of a URL, or
    /// `nil` for a board URL, which has no local id. A URL of any board counts, the same as for
    /// ``FilterExpr/namesColumn``.
    fileprivate var localName: String? {
        switch self {
        case .name(let name): name
        case .uri(let uri): uri.ref.localID
        }
    }
}
