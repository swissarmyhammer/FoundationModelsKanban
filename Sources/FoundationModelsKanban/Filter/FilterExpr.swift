import Foundation

/// A parsed filter: the AST of the filter language (plan.md §6.3).
///
/// AND binds tighter than OR, and NOT binds tighter than AND. Two terms next to each other are an AND. A chain of the
/// same operator is left-associative: `#a #b #c` is `(#a && #b) && #c`.
indirect enum FilterExpr: Hashable, Sendable {
    /// One atom, for example `#bug` or `%doing`.
    case atom(FilterAtomKind, FilterValue)

    /// Both sides must match.
    case and(FilterExpr, FilterExpr)

    /// One side or the two sides must match.
    case or(FilterExpr, FilterExpr)

    /// The expression must not match.
    case not(FilterExpr)
}

extension FilterExpr {
    /// Reads a filter.
    ///
    /// - Parameter filter: The text of the filter, for example `#bug && @alice`.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse. The error gives the position of the problem, the problem, and one correct filter.
    init(parsing filter: String) throws(KanbanError) {
        var input = filter[...]
        do throws(FilterSyntaxError) {
            self = try FilterParser.Filter().parse(&input)
        } catch {
            throw error.kanbanError(in: filter)
        }
    }
}

/// The value of an atom: the text after the sigil, or a `kanban://` URL.
enum FilterValue: Hashable, Sendable {
    /// A name, a slug, or an id, as the filter writes it, for example `bug` or `ajv8v4t`.
    case name(String)

    /// The full URI of a node, for example `kanban://local/my-repo/tag/bug`.
    case uri(NodeURI)
}

/// The kind of an atom of a filter. The sigil of an atom gives its kind, and so does the node type of a bare
/// `kanban://` URL.
enum FilterAtomKind: CaseIterable, Hashable, Sendable {
    /// `#tag`: tasks with a tag.
    case tag

    /// `@user`: tasks assigned to an actor.
    case assignee

    /// `^id`: a node of any type. On a task, it also matches the tasks that depend on the task.
    case ref

    /// `%column`: tasks in a column.
    case column

    /// `~type`: the nodes of a node type, for example `~task` or `~comment`.
    case type
}

// MARK: - Spelling

extension FilterAtomKind {
    /// The text forms of one kind of atom.
    private struct Spelling {
        /// The character before the body of the atom.
        let sigil: Character

        /// The node type of a bare URL that gives the atom, or `nil` when the atom takes no URL.
        let bareURLType: PatchNodeType?

        /// The name of the body in a message, with its article, for example `a tag name`.
        let bodyNoun: String

        /// One correct atom of the kind.
        let example: String
    }

    /// The sigil of the atom, for example `#`.
    var sigil: Character {
        spelling.sigil
    }

    /// The node type of a bare URL that gives the atom, for example ``PatchNodeType/actor`` for `@`. It is `nil` for
    /// `~`, which takes a node type name and no URL.
    var bareURLType: PatchNodeType? {
        spelling.bareURLType
    }

    /// The name of the body in a message, with its article, for example `a tag name`.
    var bodyNoun: String {
        spelling.bodyNoun
    }

    /// One correct atom of the kind, for example `#bug`.
    var example: String {
        spelling.example
    }

    /// The text forms of the kind.
    private var spelling: Spelling {
        switch self {
        case .tag: Spelling(sigil: "#", bareURLType: .tag, bodyNoun: "a tag name", example: "#bug")
        case .assignee: Spelling(sigil: "@", bareURLType: .actor, bodyNoun: "an actor name", example: "@alice")
        case .ref: Spelling(sigil: "^", bareURLType: .task, bodyNoun: "a node id", example: "^ajv8v4t")
        case .column: Spelling(sigil: "%", bareURLType: .column, bodyNoun: "a column name", example: "%doing")
        case .type: Spelling(sigil: "~", bareURLType: nil, bodyNoun: "a node type name", example: "~task")
        }
    }

    /// Tells if the atom accepts a URL of a node type after its sigil. `^` accepts a URL of each node type. `#`, `@`,
    /// and `%` accept only the URL of their own node type, and `~` accepts no URL.
    ///
    /// - Parameter type: The node type of the URL.
    /// - Returns: `true` when the atom accepts the URL.
    func acceptsURL(of type: PatchNodeType) -> Bool {
        self == .ref || bareURLType == type
    }

    /// Finds the kind of atom of a sigil.
    ///
    /// - Parameter sigil: The first character of an atom.
    /// - Returns: The kind, or `nil` when the character is not a sigil.
    init?(sigil: Character) {
        self.init(firstWhere: { $0.sigil == sigil })
    }

    /// Finds the kind of atom of a bare URL with a node type.
    ///
    /// - Parameter nodeType: The node type of the URL.
    /// - Returns: The kind, or `nil` for the board and for a comment, which need `^` before the URL.
    init?(nodeType: PatchNodeType) {
        self.init(firstWhere: { $0.bareURLType == nodeType })
    }

    /// Finds the first kind that satisfies a condition.
    ///
    /// - Parameter predicate: The condition.
    /// - Returns: The kind, or `nil` when no kind satisfies the condition.
    private init?(firstWhere predicate: (Self) -> Bool) {
        guard let kind = Self.allCases.first(where: predicate) else {
            return nil
        }
        self = kind
    }
}
