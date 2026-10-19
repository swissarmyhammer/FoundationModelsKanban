import Foundation

/// The field of a task that holds a stored link (divergence.md M9): the GraphQL `LinkField` enum.
enum LinkField: String, Codable, Sendable, CaseIterable {
    /// A `dependsOn` edge.
    case dependsOn = "DEPENDS_ON"

    /// An assignee that is the full URI of an actor of a different board (divergence.md Q21).
    case assignee = "ASSIGNEE"

    /// A task URL in the body of a live task (plan.md §6.1).
    case body = "BODY"

    /// The line of a tombstoned task that points to the task that a move made (divergence.md E6).
    case tombstone = "TOMBSTONE"
}

/// The class of one stored link (divergence.md M9): the GraphQL `LinkStatus` enum.
enum LinkStatus: String, Codable, Sendable, CaseIterable {
    /// The link names its board by a current name, and the board has the node.
    case ok = "OK"

    /// The link names its board by an old name. The link works at read time, and the response has an
    /// ``OldBoardName`` warning for it.
    case oldName = "OLD_NAME"

    /// No reachable board has the name of the link.
    case dangling = "DANGLING"

    /// The board of the link is found, and the board does not have the node.
    case missingNode = "MISSING_NODE"
}

/// One stored link of a task of a board (divergence.md M9): the task that holds the link, the field, and the URI of
/// the target. A local ref has the current key of the board in its URI.
struct StoredLink: Hashable, Sendable {
    /// The local ref of the task that holds the link.
    let holder: LocalRef

    /// The field of the task that holds the link.
    let field: LinkField

    /// The URI of the target, as the board stores it.
    let target: NodeURI
}

/// One checked link: the GraphQL `LinkCheck` type of `Query.checkLinks` (divergence.md M9).
struct LinkCheck: Encodable, Sendable {
    /// The current key of the board that holds the link.
    let board: String

    /// The full URI of the task that holds the link.
    let node: NodeID

    /// The field of the task that holds the link.
    let field: LinkField

    /// The URI of the target, as the board stores it.
    let target: String

    /// The class of the link.
    let status: LinkStatus

    /// The current key of the board that the link names, or `nil` when no reachable board has the name.
    let currentName: String?
}

extension LinkCheck {
    /// Checks one stored link against the board that its board key names.
    ///
    /// - Parameters:
    ///   - link: The link.
    ///   - view: The read view of the board that holds the link.
    ///   - linked: The board that the board key of the link names.
    init(of link: StoredLink, in view: BoardView, against linked: LinkedBoard) {
        let result = linked.check(of: link.target)
        self.init(
            board: view.boardKey,
            node: view.id(of: link.holder),
            field: link.field,
            target: link.target.description,
            status: result.status,
            currentName: result.currentName
        )
    }
}

/// The board that the board key of a stored link names, as one run sees it (divergence.md M9).
enum LinkedBoard: Sendable {
    /// A loaded board: the current board, or a loaded related board.
    case loaded(BoardSnapshot)

    /// A related board that cannot be read (divergence.md Q7). The response has a warning that names it.
    case unreadable(UnreadableBoard)

    /// No reachable board has the name.
    case notFound

    /// Makes the linked board of a resolution.
    ///
    /// - Parameters:
    ///   - resolution: The board that the board key names.
    ///   - related: The related boards as the reads of the run see them.
    /// - Returns: The linked board, or `nil` when the resolution is a copy that the run did not load yet.
    init?(_ resolution: BoardResolution, reading related: RelatedBoards) {
        switch resolution {
        case .notFound:
            self = .notFound
        case .unreadable(let board):
            self = .unreadable(board)
        case .current, .copy:
            guard let board = related.board(resolvedAs: resolution) else {
                return nil
            }
            self = .loaded(board)
        }
    }

    /// Gives the class of a link to a node of this board, and the current name of this board.
    ///
    /// A board that cannot be read gives the class of the name only, because the node cannot be checked: `OK` or
    /// `OLD_NAME`. The `BOARD_UNREADABLE` warning of the response names that board.
    ///
    /// - Parameter target: The URI of the target of the link.
    /// - Returns: The class, and the current key of this board, or `nil` when no board has the name.
    func check(of target: NodeURI) -> (status: LinkStatus, currentName: String?) {
        switch self {
        case .notFound:
            return (.dangling, nil)
        case .unreadable(let board):
            let isOld = board.copy.names.kind(of: target.boardKey) == .oldName
            return (isOld ? .oldName : .ok, board.copy.key.description)
        case .loaded(let board):
            guard board.graph.hasNode(target.ref) else {
                return (.missingNode, board.key)
            }
            return (board.oldName(named: target.boardKey) == nil ? .ok : .oldName, board.key)
        }
    }
}

// MARK: - Links of a graph

extension Graph {
    /// Gives each stored link of the tasks of the graph, in slot order (divergence.md M9). A live task gives its
    /// `dependsOn` edges, its assignees that are the full URI of an actor of a different board, and the task URLs in
    /// its body. A tombstone gives only the line that points to the task that a move made, because the other links
    /// of a tombstone do not act at read time.
    ///
    /// - Parameter key: The current key of the board.
    /// - Returns: The links.
    func storedLinks(inBoard key: String) -> [StoredLink] {
        allSlots.compactMap { slot in node(at: slot, as: TaskNode.self) }.flatMap { task in
            storedLinks(of: task, inBoard: key)
        }
    }

    /// Gives the stored links of one task, with the rule of ``storedLinks(inBoard:)``.
    ///
    /// - Parameters:
    ///   - task: The task, as this graph stores it, so that its edges hold slots.
    ///   - key: The current key of the board.
    /// - Returns: The links, by field in the order of ``LinkField``, and in stored order in each field.
    private func storedLinks(of task: TaskNode, inBoard key: String) -> [StoredLink] {
        let body = task.fields.body
        let targets: [(field: LinkField, uris: [NodeURI])] =
            task.fields.isDeleted
            ? [(.tombstone, MovedTaskLine.targets(in: body))]
            : [
                (.dependsOn, task.dependsOn.compactMap { edge in uri(of: edge, inBoard: key) }),
                (.assignee, task.assignees.compactMap(\.remoteURI)),
                (.body, DependencyMarkers.all(in: body).map(\.uri)),
            ]
        return targets.flatMap { field, uris in
            uris.map { uri in StoredLink(holder: task.ref, field: field, target: uri) }
        }
    }
}

/// The line that a move to a different board adds to the body of the old task (divergence.md E6): `Moved to` and
/// the full URI of the new task.
enum MovedTaskLine {
    /// The text before the URI of the new task.
    private static let prefix = "Moved to "

    /// Makes the line that points to the new task of a move.
    ///
    /// - Parameter uri: The full URI of the new task.
    /// - Returns: The text of the line, with no line break.
    static func text(pointingTo uri: NodeURI) -> String {
        prefix + uri.description
    }

    /// Finds the URI of each line of a body that points to the new task of a move. Each line break ends a line, also
    /// a `\r\n` that an editor wrote, because Swift reads `\r\n` as one character.
    ///
    /// - Parameter body: The Markdown body of a task.
    /// - Returns: The URIs, in text order. A line whose text after the prefix is not a node URI gives no URI.
    static func targets(in body: String) -> [NodeURI] {
        body.split(whereSeparator: \.isNewline).compactMap(target(ofLine:))
    }

    /// Replaces the URI of each line of a body that points to one task with a different URI: the `repairLinks`
    /// rewrite of a moved line with an old board name (divergence.md M9). Each other line stays the same, byte for
    /// byte, and a changed line keeps its line break, also a `\r\n`.
    ///
    /// - Parameters:
    ///   - old: The URI that the line points to now.
    ///   - new: The URI that the line gets.
    ///   - body: The Markdown body of a task.
    /// - Returns: The body with the new line in place of each line that points to the old URI.
    static func replacing(_ old: NodeURI, with new: NodeURI, in body: String) -> String {
        let lines = BodyLines.lines(of: body)
        let edits = lines.map { line in
            let content = BodyLines.content(of: line)
            return target(ofLine: content) == old ? text(pointingTo: new) + line[content.endIndex...] : nil
        }
        return BodyLines.body(joining: lines, with: edits)
    }

    /// Finds the URI of one line that points to the new task of a move.
    ///
    /// - Parameter line: The text of the line, with no line break.
    /// - Returns: The URI, or `nil` when the line does not start with the prefix, or its text after the prefix is not
    ///   a node URI.
    private static func target(ofLine line: Substring) -> NodeURI? {
        guard line.hasPrefix(prefix) else {
            return nil
        }
        let text = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        // A text that does not parse is not a line of a move: each parse error means "no URI".
        return try? NodeURI(parsing: text)
    }
}
