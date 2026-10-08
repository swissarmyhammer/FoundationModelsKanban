import Foundation
import OrderedCollections

/// Reads the key of the board of a repo, for example ``BoardKey/read(fromRepoAt:)``.
typealias BoardKeyReader = @Sendable (URL) async throws(BoardKeyError) -> BoardKey

/// Finds the repos of the related boards on the disk (plan.md §6.6, §12 items 13 and 26).
///
/// The locator looks one level down in the parent directory of the current repo, and then one level down in each
/// search root of the config, in config order. In each place, it reads the directory names in sort order. A
/// directory with a `.git` entry (the directory of a clone, or the file of a worktree) is a repo. The key of a repo
/// comes from its current `origin`, and the board of the repo is enabled when `.kanban/board.jsonl` exists.
public struct BoardLocator: Sendable {
    /// The locator with no search root: it looks only in the parent directory of the current repo.
    public static let `default` = BoardLocator(searchRoots: [])

    /// The extra places to look for repos, in config order, for example `~/src`.
    let searchRoots: [URL]

    /// Makes a locator.
    ///
    /// - Parameter searchRoots: The extra places to look for repos, in config order. The locator looks one level
    ///   down in each one.
    public init(searchRoots: [URL]) {
        self.searchRoots = searchRoots
    }

    /// Gives the places that a scan looks in. A place that is already in the list is not added again.
    ///
    /// - Parameter root: The root directory of the current repo.
    /// - Returns: The parent directory of the current repo, then each search root in config order.
    func places(around root: URL) -> [URL] {
        let candidates = [root.deletingLastPathComponent()] + searchRoots
        let unique = OrderedDictionary(
            candidates.map { place in (place.canonicalPath, place) },
            uniquingKeysWith: { first, _ in first }
        )
        return Array(unique.values)
    }

    /// Scans the places for repos.
    ///
    /// A repo whose key cannot be read (for example, git fails in it) is not in the index, and the scan records it
    /// with swift-log. A cancel of the task is not such a failure: it stops the scan, and the scan gives no index.
    ///
    /// - Parameters:
    ///   - root: The root directory of the current repo.
    ///   - earlier: The index of the earlier scan, or `nil` for the first scan. A repo of the earlier scan keeps its
    ///     key, so the scan reads the key only of a new repo (plan.md §6.6, index life).
    ///   - keyReader: Reads the key of a repo that the earlier scan did not find.
    /// - Returns: The index of the repos, in scan order.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled before the scan reads each
    ///   key. Then the scan gives no index: an index without the keys that the cancel stopped is not complete.
    func scan(
        around root: URL,
        reusing earlier: BoardIndex? = nil,
        readingKeysWith keyReader: @escaping BoardKeyReader
    ) async throws(BoardKeyError) -> BoardIndex {
        let places = places(around: root)
        let knownKeys = Dictionary(
            (earlier?.copies ?? []).map { copy in (copy.directory.canonicalPath, copy.key) },
            uniquingKeysWith: { first, _ in first }
        )
        let directories = places.flatMap(Self.repos(in:))
        let keys = try await Self.keys(ofReposAt: directories, knowing: knownKeys, readingKeysWith: keyReader)
        let copies = directories.compactMap { directory in
            keys[directory.canonicalPath].map { key in BoardCopy(directory: directory, key: key) }
        }
        return BoardIndex(places: places, copies: copies)
    }

    /// Lists the repos one level down in a place.
    ///
    /// - Parameter place: The place.
    /// - Returns: The root directory of each repo, in the sort order of the names. A place that cannot be read gives
    ///   no repo, and the scan records it with swift-log.
    private static func repos(in place: URL) -> [URL] {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: place.path)
        } catch {
            Log.kanban.warning(
                "The scan for related boards cannot read a place",
                metadata: ["path": "\(place.path)", "error": "\(error)"]
            )
            return []
        }
        return names.sorted()
            .map { name in place.appending(path: name, directoryHint: .isDirectory) }
            .filter { directory in
                FileManager.default.fileExists(atPath: directory.appending(path: BoardKey.gitDirectoryName).path)
            }
    }

    /// Gives the key of each repo. A repo of the earlier scan keeps its key. The keys of the new repos are read at the
    /// same time, and no read blocks a thread.
    ///
    /// - Parameters:
    ///   - directories: The root directory of each repo.
    ///   - knownKeys: The keys that the earlier scan read, by the canonical path of the repo directory.
    ///   - keyReader: Reads the key of a new repo.
    /// - Returns: The key of each repo whose key is known or can be read, by the canonical path of the repo directory.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled before each key is read.
    private static func keys(
        ofReposAt directories: [URL],
        knowing knownKeys: [String: BoardKey],
        readingKeysWith keyReader: @escaping BoardKeyReader
    ) async throws(BoardKeyError) -> [String: BoardKey] {
        let reads = await withTaskGroup(of: (path: String, key: KeyRead).self) { group in
            for directory in directories {
                let path = directory.canonicalPath
                group.addTask {
                    (path, await key(ofRepoAt: directory, knownKey: knownKeys[path], readingKeysWith: keyReader))
                }
            }
            return await group.reduce(into: [String: KeyRead]()) { reads, read in reads[read.path] = read.key }
        }
        var keys: [String: BoardKey] = [:]
        for (path, read) in reads {
            keys[path] = try read.get()
        }
        return keys
    }

    /// The result of the key read of one repo: the key, `nil` when the key cannot be read, or the cancel that stopped
    /// the read.
    private typealias KeyRead = Result<BoardKey?, BoardKeyError>

    /// Gives the key of a repo.
    ///
    /// - Parameters:
    ///   - directory: The root directory of the repo.
    ///   - knownKey: The key that the earlier scan read, or `nil` for a new repo.
    ///   - keyReader: Reads the key of a new repo.
    /// - Returns: The key, `nil` when the key of a new repo cannot be read, or
    ///   ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the read. A cancel is not a
    ///   repo that the scan skips: it stops the scan.
    private static func key(
        ofRepoAt directory: URL,
        knownKey: BoardKey?,
        readingKeysWith keyReader: BoardKeyReader
    ) async -> KeyRead {
        if let knownKey {
            return .success(knownKey)
        }
        do {
            return .success(try await keyReader(directory))
        } catch BoardKeyError.gitCancelled(let arguments) {
            return .failure(.gitCancelled(arguments: arguments))
        } catch {
            Log.kanban.warning(
                "The scan for related boards cannot read the key of a repo",
                metadata: ["path": "\(directory.path)", "error": "\(error)"]
            )
            return .success(nil)
        }
    }
}

// MARK: - Index

/// One copy of a repo that a scan found: a clone or a worktree (plan.md §6.6).
struct BoardCopy: Hashable, Sendable {
    /// The root directory of the copy.
    let directory: URL

    /// The key of the board of the copy, from its current `origin`.
    let key: BoardKey

    /// `true` when the copy has `.kanban/board.jsonl`.
    let isEnabled: Bool
}

extension BoardCopy {
    /// Makes the copy of a repo whose key is known. The copy is enabled when the repo has `.kanban/board.jsonl` now.
    ///
    /// - Parameters:
    ///   - directory: The root directory of the copy.
    ///   - key: The key of the board of the copy.
    init(directory: URL, key: BoardKey) {
        let boardLog = EventLog(repositoryAt: directory).fileURL(for: .board)
        self.init(directory: directory, key: key, isEnabled: FileManager.default.fileExists(atPath: boardLog.path))
    }
}

/// The repos that a scan found, in scan order (plan.md §6.6).
struct BoardIndex: Sendable {
    /// The places that the scan looked in, in scan order.
    let places: [URL]

    /// The copies that the scan found, in scan order.
    let copies: [BoardCopy]

    /// Finds the board that a board ref names (plan.md §6.6, board refs).
    ///
    /// - A board key, or the URI of a board: the current key gives the current board, and a different key gives the
    ///   first copy with the key in scan order.
    /// - A repo directory name that only one copy has.
    /// - A path, absolute or from the home directory (`~`). The path of the current repo gives the current board.
    ///
    /// - Parameters:
    ///   - reference: The board ref. White space at the two ends is ignored.
    ///   - root: The root directory of the current repo.
    ///   - key: The key of the current board.
    /// - Returns: The board, or `nil` when no copy of the index has the ref.
    func resolution(of reference: String, currentRoot root: URL, currentKey key: BoardKey) -> BoardResolution? {
        let text = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let boardKey = Self.boardKey(in: text) {
            if boardKey == key.description {
                return .current
            }
            if let copy = copies.first(where: { copy in copy.key.description == boardKey }) {
                return .copy(copy)
            }
        }
        guard Self.isPath(text) else {
            return copy(named: text).map { copy in resolution(of: copy, currentRoot: root) }
        }
        return resolution(ofPath: text, currentRoot: root)
    }

    /// Gives the board key that a ref names: the key of a board URI, or the ref itself.
    ///
    /// - Parameter text: The ref, without white space at the two ends.
    /// - Returns: The key, or `nil` when the ref is a URI that does not parse or that names a node other than a board.
    private static func boardKey(in text: String) -> String? {
        guard NodeURI.hasScheme(atStartOf: text) else {
            return text
        }
        guard let uri = try? NodeURI(parsing: text), uri.ref == .board else {
            return nil
        }
        return uri.boardKey
    }

    /// Finds the one copy whose repo directory has a name.
    ///
    /// - Parameter name: The repo directory name.
    /// - Returns: The copy, or `nil` when no copy or more than one copy has the name.
    private func copy(named name: String) -> BoardCopy? {
        let named = copies.filter { copy in copy.directory.lastPathComponent == name }
        return named.count == 1 ? named.first : nil
    }

    /// Finds the board of a path.
    ///
    /// - Parameters:
    ///   - text: The ref: a path, absolute or from the home directory.
    ///   - root: The root directory of the current repo.
    /// - Returns: The current board for the path of the current repo, the copy of the path, or `nil` when no copy
    ///   has the path.
    private func resolution(ofPath text: String, currentRoot root: URL) -> BoardResolution? {
        let path = URL(filePath: NSString(string: text).expandingTildeInPath, directoryHint: .isDirectory)
            .canonicalPath
        guard path != root.canonicalPath else {
            return .current
        }
        return copies.first { copy in copy.directory.canonicalPath == path }.map(BoardResolution.copy)
    }

    /// Gives the board of a copy: the current board when the copy is the current repo.
    ///
    /// - Parameters:
    ///   - copy: The copy.
    ///   - root: The root directory of the current repo.
    /// - Returns: The board.
    func resolution(of copy: BoardCopy, currentRoot root: URL) -> BoardResolution {
        copy.directory.canonicalPath == root.canonicalPath ? .current : .copy(copy)
    }

    /// Tells if a ref is a path: it starts with `/`, or with `~` for the home directory.
    ///
    /// - Parameter text: The ref.
    /// - Returns: `true` when the ref is a path.
    private static func isPath(_ text: String) -> Bool {
        text.hasPrefix("/") || text.hasPrefix("~")
    }
}

/// The board that a board ref names, as one call sees it (plan.md §6.6).
enum BoardResolution: Hashable, Sendable {
    /// The board of the current repo.
    case current

    /// A copy of a related repo, or a different copy of the current repo.
    case copy(BoardCopy)

    /// No board: the scan cannot find one.
    case notFound
}

extension URL {
    /// The path of the file URL with no `.` and `..` parts and with the symbolic links resolved. Two URLs of one
    /// directory give the same path, for example `/var/…` and `/private/var/…`.
    var canonicalPath: String {
        standardizedFileURL.resolvingSymlinksInPath().path
    }
}
