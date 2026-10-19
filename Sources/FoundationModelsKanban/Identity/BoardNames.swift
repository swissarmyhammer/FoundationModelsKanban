import Foundation
import OrderedCollections
import ULID

/// The names of one board (divergence.md M9). Each name resolves to the board:
///
/// - the current key, which a stored ref uses: the git key of the repo of the board;
/// - each board ID, as a bare ULID: `kanban://<ULID>/<type>/<id>`. A git key always has a `/`, so the two forms
///   cannot be confused;
/// - each old name: a git key that the board log records from before a change of the git key.
///
/// The board log holds the IDs and the old names (``BoardNode/ids``, ``BoardNode/oldNames``). A git key that the last
/// write recorded (``BoardNode/gitKey``) and that is not the current key is an old name too, also before the next
/// write records it in ``BoardNode/oldNames``.
struct BoardNames: Hashable, Sendable {
    /// The current key of the board: the text of its git key.
    let key: String

    /// The board IDs, the lowest first. The lowest is the primary ID.
    let ids: [ULID]

    /// The old names, in the order of the log, each one time and never the current key.
    let oldNames: [String]

    /// Makes the names of a board from its current key and its board node.
    ///
    /// - Parameters:
    ///   - key: The current key of the board.
    ///   - board: The board node, or `nil` when the board has no board node yet.
    init(key: String, board: BoardNode?) {
        self.key = key
        ids = board?.ids ?? []
        let recorded = (board?.oldNames ?? []) + (board?.gitKey.map { gitKey in [gitKey] } ?? [])
        oldNames = OrderedSet(recorded.map(BoardKey.normalizedText(of:))).elements.filter { name in name != key }
    }

    /// The primary ID of the board: the lowest board ID, or `nil` when the board has no ID yet.
    var primaryID: ULID? {
        ids.first
    }

    /// Each name of the board: the current key, each board ID, and each old name, each one time.
    var all: [String] {
        Array(OrderedSet([key] + ids.map(\.ulidString) + oldNames))
    }

    /// Tells if a text is a name of the board. The text gets the rule of ``BoardKey/normalizedText(of:)``, so the host
    /// of a git key and each letter of a board ID ignore case.
    ///
    /// - Parameter text: The board key of a ref, for example a git key or a board ID.
    /// - Returns: `true` when the text names the board.
    func contains(_ text: String) -> Bool {
        kind(of: text) != nil
    }

    /// Gives the kind of name that a text is for the board. The text gets the rule of
    /// ``BoardKey/normalizedText(of:)``.
    ///
    /// - Parameter text: The board key of a ref, for example a git key or a board ID.
    /// - Returns: The kind, or `nil` when the text is not a name of the board.
    func kind(of text: String) -> BoardNameKind? {
        let name = BoardKey.normalizedText(of: text)
        if name == key {
            return .key
        }
        if ids.contains(where: { id in id.ulidString == name }) {
            return .boardID
        }
        return oldNames.contains(name) ? .oldName : nil
    }
}

/// The kind of one name of a board (divergence.md M9). When two boards have one name, the board with the better kind
/// gets the ref: the current key comes first, then a board ID, then an old name.
enum BoardNameKind: Int, Comparable, Sendable {
    /// The current key of the board.
    case key

    /// A board ID of the board.
    case boardID

    /// An old name of the board.
    case oldName

    /// Tells if one kind comes before a different kind.
    ///
    /// - Parameters:
    ///   - lhs: A kind.
    ///   - rhs: A different kind.
    /// - Returns: `true` when `lhs` comes first.
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension BoardNames {
    /// Reads the names of the board of a repo from its board log, for the index of a scan (divergence.md M9). The
    /// read takes no lock and makes no file. A board log that cannot be read gives the key alone, and the read records
    /// it with swift-log: the load of the board then reports the fault.
    ///
    /// - Parameters:
    ///   - directory: The root directory of the repo.
    ///   - key: The current key of the board.
    /// - Returns: The names of the board.
    static func read(fromRepoAt directory: URL, key: BoardKey) -> BoardNames {
        do {
            let board = try EventLog(repositoryAt: directory).readLog(of: .board).node?.state as? BoardNode
            return BoardNames(key: key.description, board: board)
        } catch {
            Log.kanban.warning(
                "The scan cannot read the board log of a repo, so the board has only its key as a name",
                metadata: ["path": "\(directory.path)", "error": "\(error)"]
            )
            return BoardNames(key: key.description, board: nil)
        }
    }
}

// MARK: - Board name refs

extension StoredRef {
    /// Makes the stored ref of a board by one of its names, for a member of ``PropertyName/boardIDs`` or
    /// ``PropertyName/oldNames``: the URI `kanban://<name>/board`.
    ///
    /// - Parameter name: The name: a board ID or a git key.
    /// - Returns: The stored ref.
    static func board(named name: String) -> StoredRef {
        .remote(NodeURI(boardKey: name, ref: .board))
    }

    /// The name of the board that the ref names, or `nil` when the ref is not the URI of a board.
    var boardName: String? {
        guard case .remote(let uri) = self, uri.ref == .board else {
            return nil
        }
        return uri.boardKey
    }
}

extension ULID {
    /// Reads a board ID from the board key of a ref (divergence.md M9). A board ID ignores case, the same as each ULID.
    ///
    /// - Parameter text: The board key, for example `01M52RKMDD8RJ7TNTQVE65466D` or the same text in lowercase.
    /// - Returns: The ULID, or `nil` when the text is not a ULID.
    init?(boardKeyText text: String) {
        self.init(ulidString: text.uppercased())
    }
}
