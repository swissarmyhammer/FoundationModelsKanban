import Foundation

/// The global id of a node: `kanban://<board-key>/<type>/<local-id>`, or `kanban://<board-key>/board` for the
/// board (plan.md §3.2).
///
/// The URI is the GraphQL `ID`, in input and in output. The log does not store the URI of a node of its own board.
/// It stores the ``LocalRef``, and a resolver adds the current board key when it returns an `ID`. Only a ref to a
/// node of a different board is stored as a URI (``StoredRef/remote(_:)``).
///
/// The board key has slashes, for example `github.com/swissarmyhammer/FoundationModelsKanban` or `local/my-repo`.
/// Thus, the parse finds the local ref at the end of the URI, and the board key is the rest.
struct NodeURI: Hashable, Sendable, CustomStringConvertible {
    /// The scheme at the start of each URI. The parse ignores the case of the scheme.
    static let scheme = "kanban://"

    /// The key of the board of the node, for example `github.com/swissarmyhammer/FoundationModelsKanban`.
    let boardKey: String

    /// The id of the node in its board.
    let ref: LocalRef

    /// The text of the URI, for example `kanban://github.com/swissarmyhammer/FoundationModelsKanban/column/doing`.
    var description: String {
        "\(Self.scheme)\(boardKey)\(LocalRef.separator)\(ref)"
    }

    /// Gives the local ref of the node when the node is in a board.
    ///
    /// - Parameter currentBoardKey: The key of the board.
    /// - Returns: The local ref when the URI has the key of the board, or `nil` when the node is in a different
    ///   board.
    func localRef(inBoard currentBoardKey: String) -> LocalRef? {
        boardKey == currentBoardKey ? ref : nil
    }
}

// MARK: - Parse

extension NodeURI {
    /// Tells if a text starts with the ``scheme``. The compare ignores case.
    ///
    /// - Parameter text: The text, for example a stored ref.
    /// - Returns: `true` when the text starts with `kanban://`.
    static func hasScheme(atStartOf text: String) -> Bool {
        text.prefix(scheme.count).lowercased() == scheme
    }

    /// Reads a URI from its text.
    ///
    /// When the second-to-last segment is a node type other than the board, the last two segments are the local
    /// ref. Else, when the last segment is `board`, that segment is the local ref. Thus, a column with the slug
    /// `board` is a column. All segments before the local ref are the board key.
    ///
    /// - Parameter text: The text of the URI, for example `kanban://local/my-repo/tag/bug`.
    /// - Throws: ``NodeRefError/missingScheme(uri:)`` when the text does not start with the scheme.
    ///   ``NodeRefError/invalidBoardKey(uri:)`` when the board key is empty or has an empty segment. An error of
    ///   ``LocalRef/init(parsing:)`` when the end of the URI is not a valid local ref.
    init(parsing text: String) throws(NodeRefError) {
        guard Self.hasScheme(atStartOf: text) else {
            throw .missingScheme(uri: text)
        }
        let separator = String(LocalRef.separator)
        let segments = text.dropFirst(Self.scheme.count)
            .split(separator: LocalRef.separator, omittingEmptySubsequences: false)
            .map(String.init)
        let refSegmentCount = Self.refSegmentCount(in: segments)
        let keySegments = segments.dropLast(refSegmentCount)
        guard !keySegments.isEmpty, !keySegments.contains(where: \.isEmpty) else {
            throw .invalidBoardKey(uri: text)
        }
        let ref = try LocalRef(parsing: segments.suffix(refSegmentCount).joined(separator: separator))
        self.init(boardKey: keySegments.joined(separator: separator), ref: ref)
    }

    /// Finds the number of segments at the end of a URI path that make the local ref.
    ///
    /// - Parameter segments: The segments of the URI after the scheme.
    /// - Returns: ``LocalRef/boardSegmentCount`` for the board ref, else ``LocalRef/typedSegmentCount``.
    private static func refSegmentCount(in segments: [String]) -> Int {
        let typeIndex = segments.count - LocalRef.typedSegmentCount
        let typeOfPair = segments.indices.contains(typeIndex) ? PatchNodeType(pathSegment: segments[typeIndex]) : nil
        let typeOfLast = segments.last.flatMap(PatchNodeType.init(pathSegment:))
        guard typeOfPair == nil || typeOfPair == .board, typeOfLast == .board else {
            return LocalRef.typedSegmentCount
        }
        return LocalRef.boardSegmentCount
    }
}
