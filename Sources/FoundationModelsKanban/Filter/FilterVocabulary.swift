import Foundation

/// The vocabulary of the board that the filter agent adds after its system prompt (divergence.md §17, "The
/// vocabulary of the board"): the live names of the board, and the caller actor.
///
/// The text is Markdown. It has a part for the tags (slug, name, and description), a part for the actors (slug and
/// name), a part for the columns (slug and name, numbered in board order), and a part for the caller actor with the
/// rule that "me" becomes `@<actor>`. The tags and the actors are in slug order, so the text of a board does not
/// change from one call to the next. The board has no projects (plan.md §2.2), so the text has no project part.
enum FilterVocabulary {
    /// The heading of the vocabulary.
    private static let heading = "## The vocabulary of the board"

    /// The heading of the part of the tags.
    private static let tagsHeading = "### Tags"

    /// The heading of the part of the actors.
    private static let actorsHeading = "### Actors"

    /// The heading of the part of the columns.
    private static let columnsHeading = "### Columns"

    /// The line before the numbered list of the columns.
    private static let columnsIntroduction = """
        The columns in board order, from the first column to the terminal column:
        """

    /// The heading of the part of the caller actor.
    private static let callerHeading = "### The caller"

    /// The text of the caller part when there is no caller actor.
    private static let noCallerText = """
        There is no caller actor. "Me", "my", "I", and "my tasks" have no meaning: do not write an `@` atom for them.
        """

    /// The line of a list that has no item.
    private static let emptyListLine = "- none"

    /// The start of a line of the tag list and of the actor list.
    private static let bulletPrefix = "- "

    /// The number of the first column in the numbered list of the columns.
    private static let firstColumnNumber = 1

    /// The text between two parts of the vocabulary.
    private static let partSeparator = "\n\n"

    /// Gives the vocabulary of a board for a caller.
    ///
    /// - Parameters:
    ///   - view: The read view of the board.
    ///   - caller: The session actor of the call, or `nil` when the call has no caller actor.
    /// - Returns: The Markdown text of the vocabulary, with a line break at the end.
    static func text(of view: BoardView, for caller: SessionActor?) -> String {
        let parts = [
            heading,
            tagsHeading,
            list(of: tags(of: view.graph).map(bulletLine(of:))),
            actorsHeading,
            list(of: actors(of: view).map(bulletLine(of:))),
            columnsHeading,
            columnsIntroduction,
            list(of: numberedLines(of: columns(of: view))),
            callerHeading,
            callerText(for: caller),
        ]
        return parts.joined(separator: partSeparator) + "\n"
    }

    /// Gives the tags that the board lists: each live tag that is not renamed (plan.md §6.2), in slug order.
    ///
    /// - Parameter graph: The graph of the board.
    /// - Returns: The states of the tags.
    private static func tags(of graph: Graph) -> [TagNode] {
        graph.boardTagSlots.compactMap { slot in graph.node(at: slot, as: TagNode.self) }.sorted(by: isInSlugOrder)
    }

    /// Gives the live actors of the board, in slug order.
    ///
    /// - Parameter view: The read view of the board.
    /// - Returns: The states of the actors.
    private static func actors(of view: BoardView) -> [ActorNode] {
        FilterNames(readiness: view.readiness, boardKey: view.boardKey)
            .liveNodes(of: ActorNode.self)
            .sorted(by: isInSlugOrder)
    }

    /// Gives the live columns of the board, in board order (``ColumnOrder``).
    ///
    /// - Parameter view: The read view of the board.
    /// - Returns: The states of the columns.
    private static func columns(of view: BoardView) -> [ColumnNode] {
        view.readiness.columnOrder.slots.compactMap { slot in view.graph.node(at: slot, as: ColumnNode.self) }
    }

    /// Tells if two nodes are in slug order.
    ///
    /// - Parameters:
    ///   - lhs: The first node.
    ///   - rhs: The second node.
    /// - Returns: `true` when the slug of `lhs` sorts before the slug of `rhs`.
    private static func isInSlugOrder(_ lhs: some SlugNamedState, _ rhs: some SlugNamedState) -> Bool {
        lhs.slug < rhs.slug
    }

    /// Gives the line of a tag in the tag list.
    ///
    /// - Parameter tag: The state of the tag.
    /// - Returns: The line, with the body of the tag as its description.
    private static func bulletLine(of tag: TagNode) -> String {
        bulletPrefix + entry(slug: tag.slug, name: tag.name, description: tag.fields.body)
    }

    /// Gives the line of an actor in the actor list.
    ///
    /// - Parameter actor: The state of the actor.
    /// - Returns: The line.
    private static func bulletLine(of actor: ActorNode) -> String {
        bulletPrefix + entry(slug: actor.slug, name: actor.name)
    }

    /// Gives the numbered lines of the columns.
    ///
    /// - Parameter columns: The states of the columns, in board order.
    /// - Returns: One line for each column, with its number in board order.
    private static func numberedLines(of columns: [ColumnNode]) -> [String] {
        zip(firstColumnNumber..., columns).map { number, column in
            "\(number). \(entry(slug: column.slug, name: column.name))"
        }
    }

    /// Gives the text of a list.
    ///
    /// - Parameter lines: The lines of the items.
    /// - Returns: The lines, one on each line of the text, or ``emptyListLine`` when there is no item.
    private static func list(of lines: [String]) -> String {
        lines.isEmpty ? emptyListLine : lines.joined(separator: "\n")
    }

    /// Gives the text of one name of the board: the slug in code font, the name in parentheses when the node has a
    /// name, and the description after a colon when the node has a description.
    ///
    /// - Parameters:
    ///   - slug: The slug of the node.
    ///   - name: The name of the node, or the empty text for no name.
    ///   - description: The description of the node, or the empty text for no description. Each line break of the
    ///     description becomes a space, so that the entry stays on one line.
    /// - Returns: The text of the name.
    private static func entry(slug: String, name: String, description: String = "") -> String {
        let namePart = name.isEmpty ? "" : " (\(name))"
        let oneLineDescription = description.split(whereSeparator: \.isNewline).joined(separator: " ")
        let descriptionPart = oneLineDescription.isEmpty ? "" : ": \(oneLineDescription)"
        return "`\(slug)`\(namePart)\(descriptionPart)"
    }

    /// Gives the text of the caller part: the caller actor and the rule that "me" becomes `@<actor>`.
    ///
    /// - Parameter caller: The session actor of the call, or `nil` when the call has no caller actor.
    /// - Returns: The text, or ``noCallerText`` when there is no caller actor.
    private static func callerText(for caller: SessionActor?) -> String {
        guard let caller, let slug = caller.ref.localID else {
            return noCallerText
        }
        let actor = entry(slug: slug, name: caller.name)
        return "The caller actor is \(actor). For \"me\", \"my\", \"I\", or \"my tasks\", write `@\(slug)`."
    }
}
