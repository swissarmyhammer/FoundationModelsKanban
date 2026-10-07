import Foundation
import ULID

/// The id of a node in its own board: the full URI without the `kanban://<board-key>/` prefix (plan.md §3.2).
///
/// The log stores this form for each ref to a node in the same board, for example `task/01K6Z3…` or `tag/bug`.
/// Thus, the log does not hold the key of its own board, and a repo can move with no change to its data (plan.md
/// §12 item 18). ``NodeURI`` adds the key of a board to a local ref, and ``StoredRef`` holds a local ref or a URI to
/// a different board.
///
/// The text of a ref is `board`, or `<type>/<local-id>`. The type segment is the name of the node type in lowercase.
/// The local id of a column, an actor, or a tag is its slug. The local id of a task or a comment is its ULID.
enum LocalRef: Hashable, Sendable, CustomStringConvertible {
    /// The board of the repo. A board has no local id, because a repo has one board.
    case board

    /// A column, found by its slug, for example `doing`.
    case column(slug: String)

    /// An actor, found by its slug, for example `claude-code`.
    case actor(slug: String)

    /// A task, found by its ULID.
    case task(ULID)

    /// A tag, found by its slug, for example `bug`.
    case tag(slug: String)

    /// A comment, found by its ULID.
    case comment(ULID)

    /// The character between two segments of a ref or a URI.
    static let separator: Character = "/"

    /// The number of segments of the board ref: the type segment only.
    static let boardSegmentCount = 1

    /// The number of segments of a ref that has a local id: the type segment and the local id.
    static let typedSegmentCount = 2

    /// The type of the node that the ref names.
    var nodeType: PatchNodeType {
        switch self {
        case .board: .board
        case .column: .column
        case .actor: .actor
        case .task: .task
        case .tag: .tag
        case .comment: .comment
        }
    }

    /// The local id of the node: the slug or the ULID text. The board has no local id, so it gives `nil`.
    var localID: String? {
        switch self {
        case .board: nil
        case .column(let slug), .actor(let slug), .tag(let slug): slug
        case .task(let ulid), .comment(let ulid): ulid.ulidString
        }
    }

    /// The text of the ref, as the log stores it, for example `column/doing`.
    var description: String {
        let typeSegment = nodeType.pathSegment
        guard let localID else {
            return typeSegment
        }
        return "\(typeSegment)\(Self.separator)\(localID)"
    }
}

// MARK: - Parse

extension LocalRef {
    /// Reads a local ref from its text.
    ///
    /// The type segment ignores case. The ULID of a task or a comment ignores case, and the ref keeps it in
    /// uppercase. A slug is kept as written.
    ///
    /// - Parameter text: The text of the ref, for example `task/01K6Z3…`.
    /// - Throws: ``NodeRefError/invalidLocalRef(ref:)`` when the type is not known, the number of segments is not
    ///   correct for the type, or the local id is empty. ``NodeRefError/invalidULID(ref:)`` when the local id of a
    ///   task or a comment is not a ULID.
    init(parsing text: String) throws(NodeRefError) {
        let segments = text.split(separator: Self.separator, omittingEmptySubsequences: false).map(String.init)
        guard
            segments.count <= Self.typedSegmentCount,
            let typeSegment = segments.first,
            let type = PatchNodeType(pathSegment: typeSegment)
        else {
            throw .invalidLocalRef(ref: text)
        }
        if let localID = segments.dropFirst().first {
            self = try Self(type: type, localID: localID, text: text)
        } else if type == .board {
            self = .board
        } else {
            throw .invalidLocalRef(ref: text)
        }
    }

    /// Makes the ref of a node type that has a local id.
    ///
    /// - Parameters:
    ///   - type: The node type of the ref.
    ///   - localID: The local id: a slug, or the text of a ULID.
    ///   - text: The full text of the ref, for the error.
    /// - Throws: ``NodeRefError/invalidLocalRef(ref:)`` when the type is the board or the local id is empty.
    ///   ``NodeRefError/invalidULID(ref:)`` when the type needs a ULID and the local id is not one.
    private init(type: PatchNodeType, localID: String, text: String) throws(NodeRefError) {
        guard !localID.isEmpty else {
            throw .invalidLocalRef(ref: text)
        }
        switch type {
        case .board: throw .invalidLocalRef(ref: text)
        case .column: self = .column(slug: localID)
        case .actor: self = .actor(slug: localID)
        case .tag: self = .tag(slug: localID)
        case .task: self = .task(try Self.ulid(from: localID, in: text))
        case .comment: self = .comment(try Self.ulid(from: localID, in: text))
        }
    }

    /// Reads the ULID of a task or a comment ref.
    ///
    /// - Parameters:
    ///   - localID: The local id of the ref.
    ///   - text: The full text of the ref, for the error.
    /// - Returns: The ULID.
    /// - Throws: ``NodeRefError/invalidULID(ref:)`` when the local id is not a ULID.
    private static func ulid(from localID: String, in text: String) throws(NodeRefError) -> ULID {
        guard let ulid = ULID(ulidString: localID) else {
            throw .invalidULID(ref: text)
        }
        return ulid
    }
}

// MARK: - Type segment

extension PatchNodeType {
    /// The segment of the type in a ref or a URI: the name of the type in lowercase, for example `task`.
    var pathSegment: String {
        rawValue.lowercased()
    }

    /// Finds the node type of a segment of a ref or a URI. The compare ignores case.
    ///
    /// - Parameter segment: The type segment, for example `task` or `Task`.
    /// - Returns: The node type, or `nil` when the segment does not name a node type.
    init?(pathSegment segment: String) {
        let lowercased = segment.lowercased()
        guard let type = Self.allCases.first(where: { $0.pathSegment == lowercased }) else {
            return nil
        }
        self = type
    }
}

// MARK: - Stored ref

/// A ref as the log stores it: a local ref to a node of the same board, or a full URI to a node of a different
/// board (plan.md §3.2).
///
/// One rule decides the form: a stored text that starts with the `kanban://` scheme is remote, and all other stored
/// texts are local to the board of the log file. A URI with the key of the current board is stored as a local ref.
enum StoredRef: Hashable, Sendable, CustomStringConvertible {
    /// A ref to a node of the same board.
    case local(LocalRef)

    /// A ref to a node of a different board, with the key of that board.
    case remote(NodeURI)

    /// The text of the ref, as the log stores it.
    var description: String {
        switch self {
        case .local(let ref): ref.description
        case .remote(let uri): uri.description
        }
    }

    /// Reads a stored ref from the text of a log.
    ///
    /// - Parameter text: The stored text, for example `tag/bug` or `kanban://<board-key>/task/01K6Z3…`.
    /// - Throws: A ``NodeRefError`` when the text is not a valid URI or local ref.
    init(parsing text: String) throws(NodeRefError) {
        if NodeURI.hasScheme(atStartOf: text) {
            self = .remote(try NodeURI(parsing: text))
        } else {
            self = .local(try LocalRef(parsing: text))
        }
    }

    /// Changes a full URI to its stored form in a board.
    ///
    /// - Parameters:
    ///   - uri: The full URI of the node.
    ///   - currentBoardKey: The key of the board whose log stores the ref.
    init(uri: NodeURI, inBoard currentBoardKey: String) {
        if let ref = uri.localRef(inBoard: currentBoardKey) {
            self = .local(ref)
        } else {
            self = .remote(uri)
        }
    }

    /// Gives the full URI of the ref, as the GraphQL `ID` shows it.
    ///
    /// - Parameter currentBoardKey: The key of the board whose log stores the ref. A local ref gets this key.
    /// - Returns: The full URI. A remote ref keeps the key of its own board.
    func uri(inBoard currentBoardKey: String) -> NodeURI {
        switch self {
        case .local(let ref): NodeURI(boardKey: currentBoardKey, ref: ref)
        case .remote(let uri): uri
        }
    }
}

// MARK: - Codable

/// A ref that a log line holds as its text: the ``CustomStringConvertible/description`` writes the text, and
/// ``init(parsing:)`` reads it.
protocol TextCodable: Codable, CustomStringConvertible {
    /// Reads the ref from its text.
    ///
    /// - Parameter text: The text of the ref.
    /// - Throws: A ``NodeRefError`` when the text is not a valid ref.
    init(parsing text: String) throws(NodeRefError)
}

extension TextCodable {
    /// Reads the ref from its text in a log line.
    ///
    /// - Parameter decoder: The decoder that holds the text.
    /// - Throws: A `DecodingError` when the value is not text. A ``NodeRefError`` when the text is not a valid ref.
    init(from decoder: any Decoder) throws {
        try self.init(parsing: decoder.singleValueContainer().decode(String.self))
    }

    /// Writes the ref as its text.
    ///
    /// - Parameter encoder: The encoder that gets the text.
    /// - Throws: An error from the encoder.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension LocalRef: TextCodable {}

extension StoredRef: TextCodable {}

// MARK: - Errors

/// An error from the parse of a ``NodeURI``, a ``LocalRef``, or a ``StoredRef``.
///
/// The ``KanbanError`` catalog has no code for a malformed id (plan.md §4.4). The resolver of forgiving refs tells
/// the caller that no node has the ref.
enum NodeRefError: Error, Hashable, Sendable {
    /// The text does not start with the `kanban://` scheme.
    case missingScheme(uri: String)

    /// The URI has no board key, or a segment of the board key is empty.
    case invalidBoardKey(uri: String)

    /// The ref does not name a node type, has the wrong number of segments for its type, or has an empty local id.
    case invalidLocalRef(ref: String)

    /// The local id of a task or a comment ref is not a ULID.
    case invalidULID(ref: String)
}
