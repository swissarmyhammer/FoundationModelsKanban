import CryptoKit
import Foundation

/// A cheap stamp of the log files of the board of a folder (TestudoApp D214). Compare two stamps to know if the
/// board changed between them, so that a reader reads the board again only after a change.
///
/// The stamp reads no log file. It lists the node directories of `.kanban/` and calls `stat` on each item: the
/// `.kanban/` directory, `board.jsonl`, each node directory (`columns/`, `tasks/`, `comments/`, `tags/`, `actors/`),
/// and each node log in them. A `stat` opens no file. The value is a SHA-256 digest, so it is the same in each
/// process and after a restart, and a reader can keep it.
///
/// - A new line in a log file, a new log file, a removed log file, and a file that a rename puts at the path of a log
///   file each change the stamp.
/// - The lock file, the git files, and each other file that is not a node log do not change the stamp. Thus the lock
///   of a session does not change it.
/// - A directory adds only its identity (device and inode) to the digest. A new item in a directory changes the
///   times of the directory, and the list of log files already shows a new or a removed log file.
///
/// The limit: the stamp cannot see a rewrite of a log file in place that keeps the size, the inode, the time of the
/// last change of the content, and the time of the last change of the status. On APFS the times have nanoseconds,
/// so each write gives new times. On a file system with times of one second or more (for example HFS+, FAT, or some
/// network shares), a rewrite in place with the same size in the same second does not show. A session only appends
/// to a log file, so each write of a session makes the file larger and changes the stamp.
///
/// The device number of a volume can change after the volume mounts again. The stamp then changes one time with no
/// change of the board, and the reader reads the board one time more.
public struct BoardStamp: Hashable, Sendable, Codable {
    /// The SHA-256 digest of the entries of the board, as lowercase hexadecimal text.
    public let value: String
}

extension BoardStamp {
    /// The key of the entry of the `.kanban/` directory itself.
    static let boardDirectoryKey = "."

    /// The character between the parts of one entry in the text of the digest.
    private static let fieldSeparator = "\t"

    /// The character after each entry in the text of the digest.
    private static let entrySeparator = "\n"

    /// The format of one byte of the digest as two lowercase hexadecimal digits.
    private static let byteFormat = "%02x"

    /// Reads the stamp of the board of a folder.
    ///
    /// - Parameter root: The folder that holds `.kanban/`. The stamp does not go up to a parent folder.
    /// - Returns: The stamp, or `nil` when the folder has no `.kanban/` folder (a regular file with that name is not a
    ///   board).
    init?(ofBoardAt root: URL) {
        guard let entries = Self.entries(ofBoardAt: root) else {
            return nil
        }
        self.init(digesting: entries)
    }

    /// Makes the stamp of a set of entries.
    ///
    /// - Parameter entries: The stamp of each item, by its path relative to the `.kanban/` directory.
    init(digesting entries: [String: FileStamp]) {
        let text = entries.sorted { first, second in first.key < second.key }
            .map { path, stamp in path + Self.fieldSeparator + stamp.digestText + Self.entrySeparator }
            .joined()
        value = SHA256.hash(data: Data(text.utf8)).map { byte in String(format: Self.byteFormat, byte) }.joined()
    }

    /// Reads the stamp of each item of the board of a folder that the board stamp holds. The change stream of a board
    /// compares these entries to find the changed files.
    ///
    /// A node directory that cannot be listed gives its own entry and no entry for its files. The skip is recorded
    /// with swift-log. A read of the board then fails, and the stamp changes when the directory can be listed again.
    ///
    /// - Parameter root: The folder that holds `.kanban/`.
    /// - Returns: The stamp of each item, by its path relative to the `.kanban/` directory (``boardDirectoryKey`` for
    ///   the directory itself, for example `tasks/<ULID>.jsonl` for a task), or `nil` when the folder has no `.kanban/`
    ///   folder. An item that is not there has no entry.
    static func entries(ofBoardAt root: URL) -> [String: FileStamp]? {
        let log = EventLog(repositoryAt: root)
        guard let boardDirectory = FileStamp(ofItemAt: log.directory), boardDirectory.isDirectory else {
            return nil
        }
        let boardFile = (EventLog.boardFileName, log.fileURL(for: .board))
        let items = [boardFile] + PatchNodeType.allCases.flatMap { type in nodeItems(ofType: type, in: log) }
        let stamps = items.compactMap { path, item in FileStamp(ofItemAt: item).map { stamp in (path, stamp) } }
        return Dictionary(uniqueKeysWithValues: [(boardDirectoryKey, boardDirectory)] + stamps)
    }

    /// Lists the node directory of a node type and its node logs. The list leaves out each file that is not a node log
    /// (``EventLog/ref(ofFileAt:)``).
    ///
    /// - Parameters:
    ///   - type: The node type.
    ///   - log: The event log of the board.
    /// - Returns: The path relative to the `.kanban/` directory and the URL of the directory and of each node log in
    ///   it. The board type has no directory, so it gives an empty list.
    private static func nodeItems(ofType type: PatchNodeType, in log: EventLog) -> [(String, URL)] {
        guard let name = type.logDirectoryName else {
            return []
        }
        let directory = log.directory.appending(path: name, directoryHint: .isDirectory)
        let logFiles = listedItems(in: directory)
            .filter { file in log.ref(ofFileAt: file) != nil }
            .map { file in (name + "/" + file.lastPathComponent, file) }
        return [(name, directory)] + logFiles
    }

    /// Lists the items of a node directory that does not have to exist.
    ///
    /// - Parameter directory: The node directory.
    /// - Returns: The items, or an empty list when the directory is not there or cannot be listed.
    private static func listedItems(in directory: URL) -> [URL] {
        do {
            return try EventLog.items(in: directory)
        } catch {
            Log.kanban.warning(
                "The board stamp leaves out the files of a node directory that cannot be listed",
                metadata: ["directory": "\(directory.path)", "error": "\(error)"]
            )
            return []
        }
    }
}

extension FileStamp {
    /// The mark of a directory in the text of the digest.
    private static let directoryMark = "d"

    /// The mark of a file in the text of the digest.
    private static let fileMark = "f"

    /// The text of this stamp in the digest of a ``BoardStamp``. A directory gives only its identity, so that a new
    /// item that is not a node log (for example the lock file) does not change the digest. A file gives its identity,
    /// its size, and its two times.
    var digestText: String {
        let identity = "\(device) \(inode)"
        guard !isDirectory else {
            return "\(Self.directoryMark) \(identity)"
        }
        return "\(Self.fileMark) \(identity) \(size) \(modified.digestText) \(changed.digestText)"
    }
}

extension StampTime {
    /// The text of this time in the digest of a ``BoardStamp``: the seconds and the nanoseconds.
    var digestText: String {
        "\(seconds).\(nanoseconds)"
    }
}
