import Foundation

/// The tasks that one task list of a query selects (plan.md §6.3): a filter, the atoms of the scoping arguments, and
/// the `excludeDone` rule.
///
/// The filter applies to `Board.tasks`, to `Board.nextTask`, and to the `tasks` fields of `Column`, `Actor`, and
/// `Tag`. A filter that is empty or does not parse gives `INVALID_FILTER`. A value that names nothing gives no task.
struct TaskSelection {
    /// The full filter: the `filter` argument ANDed with the atom of each scoping argument, or `nil` when the list has
    /// no filter.
    private let filter: FilterExpr?

    /// `true` when the list leaves out the done tasks.
    private let excludesDone: Bool

    /// Makes the selection of a list that has only a `filter` argument.
    ///
    /// - Parameters:
    ///   - text: The `filter` argument, or `nil` when the call gives no filter.
    ///   - excludesDone: `true` when the list leaves out the done tasks.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse.
    init(filtering text: String?, excludingDone excludesDone: Bool = false) throws(KanbanError) {
        filter = try Self.expression(parsing: text)
        self.excludesDone = excludesDone
    }

    /// Makes the selection of `Board.tasks`.
    ///
    /// Each scoping argument is one atom, ANDed with the full filter: `tag` is `#x`, `assignee` is `@x`, and `column`
    /// is `%x`. The atom goes into the parsed filter, not into its text. Thus `&&` does not bind to the last OR branch
    /// of the filter, and a value with a space or an operator does not add a second atom. As in Rust, `excludeDone`
    /// with no value is `true`, and `false` when the call names a column: a `column` argument, or a `%` atom or a
    /// column URL anywhere in the filter (``FilterExpr/namesColumn``).
    ///
    /// - Parameter arguments: The arguments of `Board.tasks`.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse, when a scoping value is empty, or when a scoping value is a URL of the wrong type.
    init(for arguments: TasksArguments) throws(KanbanError) {
        var filter = try Self.expression(parsing: arguments.filter)
        let scopes: [(FilterAtomKind, NodeID?)] = [
            (.tag, arguments.tag), (.assignee, arguments.assignee), (.column, arguments.column),
        ]
        for case (let kind, let value?) in scopes {
            let atom = try Self.scopeAtom(of: kind, naming: value.text)
            filter = filter.map { expression in .and(expression, atom) } ?? atom
        }
        self.filter = filter
        excludesDone = arguments.excludeDone ?? !(filter?.namesColumn ?? false)
    }

    /// Gives the selected live tasks of a board, in board order.
    ///
    /// - Parameters:
    ///   - view: The read view of the board.
    ///   - isIncluded: One more test that each task must pass, for example "the task shows in this column".
    /// - Returns: The live tasks that pass `isIncluded`, are not done when the list leaves out the done tasks, and
    ///   match the filter.
    func tasks(in view: BoardView, where isIncluded: (TaskObject) -> Bool = { _ in true }) -> [TaskObject] {
        let evaluator = filter.map { expression in
            FilterEvaluator(evaluating: expression, over: view.readiness, inBoard: view.boardKey)
        }
        return view.orderedTasks { task in
            isIncluded(task)
                && !(excludesDone && view.readiness.isDone(taskAt: task.slot))
                && (evaluator?.matches(taskAt: task.slot) ?? true)
        }
    }

    /// Reads a `filter` argument.
    ///
    /// - Parameter text: The `filter` argument, or `nil` when the call gives no filter.
    /// - Returns: The parsed filter, or `nil` when the call gives no filter.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse.
    private static func expression(parsing text: String?) throws(KanbanError) -> FilterExpr? {
        guard let text else {
            return nil
        }
        return try FilterExpr(parsing: text)
    }

    /// Makes the atom of a scoping argument.
    ///
    /// A value that is a `kanban://` URL goes through the parser after the sigil of the atom, so that it gets the same
    /// checks as the atom in a filter. An empty value also goes through the parser, which refuses a sigil with no
    /// body. Each other value is one name, as the caller wrote it.
    ///
    /// - Parameters:
    ///   - kind: The kind of the atom: `#` for `tag`, `@` for `assignee`, `%` for `column`.
    ///   - value: The value of the argument.
    /// - Returns: The atom.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the value is empty, or when it is
    ///   a URL that is not valid or is of the wrong type for the atom.
    private static func scopeAtom(of kind: FilterAtomKind, naming value: String) throws(KanbanError) -> FilterExpr {
        let body = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let isURL = NodeURI.hasScheme(atStartOf: body) && body.allSatisfy(\.isFilterBodyCharacter)
        guard body.isEmpty || isURL else {
            return .atom(kind, .name(body))
        }
        return try FilterExpr(parsing: "\(kind.sigil)\(body)")
    }
}
