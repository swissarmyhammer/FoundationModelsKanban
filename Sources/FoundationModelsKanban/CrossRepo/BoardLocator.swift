import Foundation
import OrderedCollections

/// Reads the key of the board of a repo, for example ``BoardKey/read(fromRepoAt:)``.
typealias BoardKeyReader = @Sendable (URL) async throws(BoardKeyError) -> BoardKey

/// Reads the top folder of the worktree of a folder, for example ``BoardKey/worktreeTop(of:)``.
typealias WorktreeTopReader = @Sendable (URL) async throws(BoardKeyError) -> URL

/// Finds the repos of the related boards on the disk (plan.md §6.6, §12 items 13 and 26).
///
/// The locator looks one level down in the parent directory of the current repo, and then one level down in each
/// search root of the config, in config order. In each place, it reads the directory names in sort order. A
/// directory with a `.git` entry (the directory of a clone, or the file of a worktree) is a repo. A folder that is not
/// a git repo has no board, so the scan does not find it (divergence.md §16). The key of a repo comes from
/// ``BoardKey/read(fromRepoAt:)``: from its current `origin`, or `local/<root commit>` for a repo with no remote.
/// The board of the repo is enabled when `.kanban/board.jsonl` exists.
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
    /// A repo whose key cannot be read (for example, git fails in it) is not a copy of the index: the index records
    /// it in ``BoardIndex/unreadable``, and the scan records it with swift-log. A cancel of the task is not such a
    /// failure: it stops the scan, and the scan gives no index.
    ///
    /// - Parameters:
    ///   - root: The root directory of the current repo.
    ///   - earlier: The index of the earlier scan, or `nil` for the first scan. A repo of the earlier scan keeps its
    ///     key, and the scan does not read again the key of a repo whose key read failed in the earlier scan, so the
    ///     scan reads the key only of a new repo (plan.md §6.6, index life; divergence.md §16, Gap 1).
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
        let knownFailures = earlier?.unreadable ?? []
        let directories = places.flatMap(Self.repos(in:))
        let readable = directories.filter { directory in !knownFailures.contains(directory.canonicalPath) }
        let keys = try await Self.keys(ofReposAt: readable, knowing: knownKeys, readingKeysWith: keyReader)
        let copies = directories.compactMap { directory in
            keys[directory.canonicalPath].map { key in BoardCopy(directory: directory, key: key) }
        }
        let unreadable = Set(directories.map(\.canonicalPath)).subtracting(keys.keys)
        return BoardIndex(places: places, copies: copies, unreadable: unreadable)
    }

    /// Reads with git the board of the folder that a path ref names, also when the scan does not look in that folder
    /// (plan.md §6.6, board refs). The board of a folder is the board at the top folder of its worktree (divergence.md
    /// §16), so the folder can be a subfolder of a repo. The key comes from the key reader with the rule of the scan.
    ///
    /// - Parameters:
    ///   - directory: The folder, from ``folder(namedBy:currentRoot:)``.
    ///   - keyReader: Reads the key of the repo of the folder.
    ///   - topReader: Reads the top folder of the worktree of the folder.
    /// - Returns: The copy of the repo of the folder, ``FolderBoard/notARepo(path:)`` when the folder is not in a git
    ///   repo, or ``FolderBoard/unreadableKey(top:)`` when the key of the repo cannot be read.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during a read of git. Each
    ///   other ``BoardKeyError`` of the read of the top folder.
    static func board(
        ofFolderAt directory: URL,
        readingKeysWith keyReader: BoardKeyReader,
        findingTopsWith topReader: WorktreeTopReader
    ) async throws(BoardKeyError) -> FolderBoard {
        let top: URL
        do throws(BoardKeyError) {
            top = try await topReader(directory)
        } catch .notARepo(let path) {
            return .notARepo(path: path)
        }
        let key = try await key(ofRepoAt: top, knownKey: nil, readingKeysWith: keyReader).get()
        return key.map { key in .board(BoardCopy(directory: top, key: key)) } ?? .unreadableKey(top: top)
    }

    /// Gives the folder that a path ref names, when the folder exists. The lookup runs no `git`.
    ///
    /// - Parameters:
    ///   - reference: The board ref. White space at the two ends is ignored.
    ///   - root: The top folder of the worktree of the current board. A path that starts with `./` or `../` starts
    ///     from it.
    /// - Returns: The folder, or `nil` when the ref is not a path, or when no folder has the path.
    static func folder(namedBy reference: String, currentRoot root: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard let directory = BoardIndex.directory(ofPath: reference, currentRoot: root),
            FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return nil
        }
        return directory
    }

    /// Lists the repos one level down in a place: each directory that ``isCandidate(_:)`` accepts.
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
            .filter(isCandidate(_:))
    }

    /// Tells if a directory is a repo: it has a `.git` entry (the directory of a clone, or the file of a worktree). A
    /// folder that is not a git repo has no board (divergence.md §16).
    ///
    /// - Parameter directory: The directory.
    /// - Returns: `true` when the directory has a `.git` entry.
    private static func isCandidate(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: BoardKey.gitDirectoryName).path)
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
        return try Dictionary(
            uniqueKeysWithValues: reads.map { read throws(BoardKeyError) in (read.key, try read.value.get()) }
        )
        .compactMapValues { key in key }
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

    /// The key of the board of the copy, from its current `origin`, or `local/<root commit>` for a repo with no
    /// remote.
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
        self.init(directory: directory, key: key, isEnabled: Self.hasBoardLog(at: directory))
    }

    /// Tells if a directory has `.kanban/board.jsonl` now.
    ///
    /// - Parameter directory: The directory.
    /// - Returns: `true` when the board log exists.
    static func hasBoardLog(at directory: URL) -> Bool {
        let boardLog = EventLog(repositoryAt: directory).fileURL(for: .board)
        return FileManager.default.fileExists(atPath: boardLog.path)
    }
}

/// The repos that a scan found, in scan order (plan.md §6.6).
struct BoardIndex: Sendable {
    /// The places that the scan looked in, in scan order.
    let places: [URL]

    /// The copies that the scan found, in scan order.
    let copies: [BoardCopy]

    /// The canonical path of each repo whose key read failed. A later scan that reuses the index does not read these
    /// keys again; only a change of the scan place makes the host forget one (``ScanChange``).
    let unreadable: Set<String>

    /// Finds the board that a board ref names (plan.md §6.6, board refs).
    ///
    /// - A board key, or the URI of a board: the current key gives the current board, and a different key gives the
    ///   first copy with the key in scan order.
    /// - A repo directory name that only one copy has.
    /// - A path: absolute, from the home directory (`~`), or from the root directory of the current repo (`./` or
    ///   `../`). The path of the current repo gives the current board.
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
        guard let directory = Self.directory(ofPath: text, currentRoot: root) else {
            return copy(named: text).map { copy in BoardResolution(of: copy, currentRoot: root) }
        }
        return resolution(ofFolderAt: directory, currentRoot: root)
    }

    /// Gives the directory that a path ref names (plan.md §6.6, board refs).
    ///
    /// Trust decision (plan.md §6.6, trust of a path ref): the tool runs with the rights of its process, so a path can
    /// name a folder in any git repo, also a repo outside the search roots. There is no containment check. The path
    /// names the board at the top folder of the worktree of the folder (divergence.md §16). A folder that is not in a
    /// git repo gives `NOT_A_REPO`. The tool never makes the folder: a path to a folder that does not exist gives
    /// `NOT_FOUND`. The tool reads and writes only inside `<worktree top>/.kanban/`, because each read and each write
    /// of a board goes through ``EventLog``, whose files are all in that directory. The one exception is the reads of
    /// git: the tool runs `git` in the folder, and `git` only reads.
    ///
    /// - Parameters:
    ///   - reference: The board ref. White space at the two ends is ignored.
    ///   - root: The root directory of the current repo. A path that starts with `./` or `../` starts from it.
    /// - Returns: The directory with no `.` and `..` parts, or `nil` when the ref is not a path. The directory does
    ///   not have to exist.
    static func directory(ofPath reference: String, currentRoot root: URL) -> URL? {
        let text = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if relativePathPrefixes.contains(where: text.hasPrefix) {
            return root.appending(path: text, directoryHint: .isDirectory).standardizedFileURL
        }
        guard absolutePathPrefixes.contains(where: text.hasPrefix) else {
            return nil
        }
        let path = NSString(string: text).expandingTildeInPath
        return URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
    }

    /// The prefixes of a path ref that does not depend on the current repo: `/` for an absolute path, and `~` for a
    /// path from the home directory.
    private static let absolutePathPrefixes = ["/", "~"]

    /// The prefixes of a path ref from the root directory of the current repo.
    private static let relativePathPrefixes = ["./", "../"]

    /// Gives the board key that a ref names: the key of a board URI, or the ref itself. The host of the key ignores
    /// case, so the key has the host in lowercase (``BoardKey/normalizedText(of:)``).
    ///
    /// - Parameter text: The ref, without white space at the two ends.
    /// - Returns: The key, or `nil` when the ref is a URI that does not parse or that names a node other than a board.
    static func boardKey(in text: String) -> String? {
        guard NodeURI.hasScheme(atStartOf: text) else {
            return BoardKey.normalizedText(of: text)
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

    /// Finds the board of the directory of a path ref in the index.
    ///
    /// - Parameters:
    ///   - directory: The directory that the path names.
    ///   - root: The root directory of the current repo.
    /// - Returns: The current board for the directory of the current repo, the copy of the directory, or `nil` when
    ///   no copy has the directory.
    private func resolution(ofFolderAt directory: URL, currentRoot root: URL) -> BoardResolution? {
        let path = directory.canonicalPath
        guard path != root.canonicalPath else {
            return .current
        }
        return copies.first { copy in copy.directory.canonicalPath == path }.map(BoardResolution.copy)
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

    /// No board: the folder that a path ref names is not in a git repo (divergence.md §16). The path is the path of
    /// the folder.
    case notARepo(path: String)

    /// A copy of a related repo whose board cannot be read, for example a log file with no read permission
    /// (divergence.md Q7). The call continues: a read of the board gives nothing, and each dependency on a task of
    /// the board is not done. A board with a ``UnreadableBoard/callFailure`` stops the call.
    case unreadable(UnreadableBoard)
}

extension BoardResolution {
    /// Makes the board of a copy: the current board when the copy is the current repo.
    ///
    /// - Parameters:
    ///   - copy: The copy.
    ///   - root: The root directory of the current repo.
    init(of copy: BoardCopy, currentRoot root: URL) {
        self = copy.directory.canonicalPath == root.canonicalPath ? .current : .copy(copy)
    }

    /// The board that cannot be read, or `nil` for each other resolution.
    var unreadableBoard: UnreadableBoard? {
        guard case .unreadable(let board) = self else {
            return nil
        }
        return board
    }

    /// This board as the list of `Query.boards` reaches it (divergence.md Q6): a board of the old Rust kanban does not
    /// stop the call, and gives only a warning. Each other resolution does not change.
    var listed: BoardResolution {
        unreadableBoard.map { board in .unreadable(board.listed) } ?? self
    }
}

/// A copy of a related repo whose board cannot be read (divergence.md Q7). The response of each call that reaches the
/// board has a warning that names the board and the reason. A board of the old Rust kanban is the exception: it stops
/// each call that names it (divergence.md Q6), and only the change feed continues without it. When only the list of
/// `Query.boards` reaches it, the call continues with a `BOARD_INCOMPATIBLE` warning.
struct UnreadableBoard: Hashable, Sendable {
    /// The code of the warning of a board that cannot be read, in `extensions.warnings` (plan.md §4.4).
    static let warningCode = "BOARD_UNREADABLE"

    /// The code of the warning of a board of the old Rust kanban that the list of `Query.boards` leaves out
    /// (divergence.md Q6).
    static let incompatibleWarningCode = "BOARD_INCOMPATIBLE"

    /// What a call does when it reaches a board that cannot be read.
    enum Effect: Hashable, Sendable {
        /// The call continues with a `BOARD_UNREADABLE` warning (divergence.md Q7).
        case warning

        /// The board is a board of the old Rust kanban, and only the list of `Query.boards` reached it. The call
        /// continues with a `BOARD_INCOMPATIBLE` warning (divergence.md Q6).
        case incompatibleWarning

        /// The error stops the call, for example ``KanbanError/incompatibleBoard(directory:)``.
        case callFailure(KanbanError)
    }

    /// The copy of the repo of the board.
    let copy: BoardCopy

    /// The error of the load, as text.
    let reason: String

    /// What a call does when it reaches the board.
    let effect: Effect

    /// The error that stops each call that reaches the board, or `nil` when the call continues with a warning.
    var callFailure: KanbanError? {
        guard case .callFailure(let failure) = effect else {
            return nil
        }
        return failure
    }

    /// This board as the list of `Query.boards` reaches it (divergence.md Q6): a board of the old Rust kanban gives
    /// only a warning. Each other board does not change.
    var listed: UnreadableBoard {
        guard case .callFailure(.incompatibleBoard) = effect else {
            return self
        }
        return UnreadableBoard(copy: copy, reason: reason, effect: .incompatibleWarning)
    }

    /// The code of the warning, in `extensions.warnings` (plan.md §4.4).
    var warningCode: String {
        effect == .incompatibleWarning ? Self.incompatibleWarningCode : Self.warningCode
    }

    /// The text of the warning: the key and the `.kanban/` directory of the board, the reason, and what the call did.
    var warningMessage: String {
        let board = "The related board \(copy.key) at `\(EventLog(repositoryAt: copy.directory).directory.path)`"
        guard effect != .incompatibleWarning else {
            return "\(board) is an incompatible board of the old Rust kanban. The list of boards does not show it, "
                + "and the call did not load it. A call that names this board gives INCOMPATIBLE_BOARD. Remove the "
                + "board, then try again."
        }
        return "\(board) cannot be read: \(reason). The call continued without this board, and each dependency on a "
            + "task of this board is not done. Correct the board. The next call after a change of its files reads it "
            + "again."
    }
}

extension URL {
    /// The path of the file URL with no `.` and `..` parts and with the symbolic links resolved. Two URLs of one
    /// directory give the same path, for example `/var/…` and `/private/var/…`.
    var canonicalPath: String {
        standardizedFileURL.resolvingSymlinksInPath().path
    }
}
