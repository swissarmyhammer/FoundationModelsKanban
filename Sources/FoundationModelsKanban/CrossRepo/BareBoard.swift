import Foundation
import Synchronization
import ULID

/// Finds the board of a folder that is not in a git repo (divergence.md M9, where the board is).
///
/// Outside git, the board is in the nearest folder, from the folder up, that has a `.kanban/`. When no folder has one,
/// the board is in the folder itself, and the first write makes its `.kanban/`. This works like other dot folders,
/// and `collectBoards` combines boards that a user made in subfolders by mistake.
enum BareBoard {
    /// Gives the root directory of the board of a folder that is not in a git repo: the nearest folder, from the folder
    /// up, that has a `.kanban/`, or the folder itself when no folder has one.
    ///
    /// - Parameter folder: The folder, for example the working directory of a session.
    /// - Returns: The root directory of the board.
    static func root(of folder: URL) -> URL {
        nearestBoardFolder(from: folder, below: nil) ?? folder
    }

    /// Finds the nearest folder, from a folder up, that has a `.kanban/`.
    ///
    /// - Parameters:
    ///   - folder: The first folder to look in.
    ///   - top: The folder where the search stops, or `nil` to look up to the root of the file system. The search does
    ///     not look in `top`.
    /// - Returns: The folder, or `nil` when no folder has a `.kanban/`.
    static func nearestBoardFolder(from folder: URL, below top: URL?) -> URL? {
        let stop = top?.canonicalPath
        var candidate = folder.standardizedFileURL
        while candidate.canonicalPath != stop {
            if BoardWatcher.existingBoardDirectory(ofBoardAt: candidate) != nil {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else {
                return nil
            }
            candidate = parent
        }
        return nil
    }
}

/// The board ID keys of the boards outside git that a host gave, for the boards whose log has no board ID yet
/// (divergence.md M9).
///
/// The key of a board outside git is its primary board ID. A board with no ID yet (a new board, or an old board) gets
/// a new ID, and its next write records that ID in its log. Until then, each reader of the host gets the same ID for
/// the folder, so the engine, the scan, and a path ref agree on the key.
final class BareBoardIDs: Sendable {
    /// The new IDs that the record gave, and the source of the next one. A lock keeps them, because each reader of
    /// the host calls the record from its own task.
    private let state: Mutex<MintedIDs>

    /// Makes an empty record.
    ///
    /// - Parameter source: The source of the new IDs.
    init(mintingFrom source: any ULIDSource) {
        state = Mutex(MintedIDs(source: source))
    }

    /// Gives the key of the board of a folder outside git: the primary board ID of its log, or the new ID that this
    /// record gives the folder when its log has no ID. A board log that cannot be read gives a new ID, and the record
    /// records the fault with swift-log: the load of the board then reports the fault.
    ///
    /// - Parameter root: The root directory of the board.
    /// - Returns: The key: a board ID.
    func key(ofBoardAt root: URL) -> BoardKey {
        if let id = Self.primaryID(ofBoardAt: root) {
            return BoardKey(boardID: id)
        }
        return BoardKey(boardID: state.withLock { state in state.id(forBoardAt: root.canonicalPath) })
    }

    /// Reads the primary board ID of a board from its board log now.
    ///
    /// - Parameter root: The root directory of the board.
    /// - Returns: The lowest board ID, or `nil` when the log has no ID or cannot be read.
    private static func primaryID(ofBoardAt root: URL) -> ULID? {
        do {
            return try BoardNode.stored(inRepoAt: root)?.ids.first
        } catch {
            Log.kanban.warning(
                "The kanban cannot read the board log of a folder outside git, so the board gets a new board ID",
                metadata: ["path": "\(root.path)", "error": "\(error)"]
            )
            return nil
        }
    }
}

/// The new board IDs of a ``BareBoardIDs`` record, and the source of the next one.
private struct MintedIDs {
    /// The new ID of each board with no ID in its log, by the canonical path of the root directory of the board.
    var ids: [String: ULID] = [:]

    /// The source of the new IDs.
    var source: any ULIDSource

    /// Gives the new ID of a board: the ID that the record gave the board before, or a new one.
    ///
    /// - Parameter path: The canonical path of the root directory of the board.
    /// - Returns: The ID.
    mutating func id(forBoardAt path: String) -> ULID {
        if let id = ids[path] {
            return id
        }
        let id = source.makeULID()
        ids[path] = id
        return id
    }
}
