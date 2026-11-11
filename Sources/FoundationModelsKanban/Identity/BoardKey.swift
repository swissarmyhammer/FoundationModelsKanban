import Foundation
import ULID

/// The key of a board: the current `origin` remote of its repo, normalized to `host/owner/repo` (plan.md §3.2, §12
/// item 4).
///
/// The SSH form (`git@host:owner/repo.git`), the HTTPS form (`https://host/owner/repo.git`), and the `ssh://` form of
/// one remote give the same key. A repo with no usable remote has the key `local/<root commit>`, with the first
/// ``rootCommitDigitCount`` hex digits of its root commit (divergence.md §16, M7). A board in a folder that is not in a
/// git repo has its board ID as its key (``init(boardID:)``, divergence.md M9). A node log does not store the key.
/// Only the board log records it, as a name of the board (``BoardNames``, divergence.md M9). Each call that opens a
/// board reads the key from git again with ``read(fromRepoAt:)``, so a repo that moves to a new remote gets a new key,
/// and its data does not change. ``NodeURI`` holds the text of the key (``description``).
struct BoardKey: Hashable, Sendable, CustomStringConvertible {
    /// The first segment of the key of a repo with no remote.
    static let localHost = "local"

    /// The number of hex digits of the root commit in the key of a repo with no remote.
    static let rootCommitDigitCount = 12

    /// The text between the scheme and the host of a remote URL, for example in `https://host/owner/repo`.
    static let schemeSeparator = "://"

    /// The character between the host and the path of an SSH remote, for example in `git@host:owner/repo`. In a URL,
    /// it is the character between the host and the port.
    static let hostSeparator: Character = ":"

    /// The character between the user and the host of a remote, for example in `git@host`.
    static let userSeparator: Character = "@"

    /// The suffix that the key removes from the last path segment of a remote.
    static let gitSuffix = ".git"

    /// The name of the git directory of a main clone. A worktree shares the git directory of its main clone.
    static let gitDirectoryName = ".git"

    /// The git config key of the URL of the `origin` remote.
    static let originConfigKey = "remote.origin.url"

    /// The text of the key, for example `github.com/swissarmyhammer/FoundationModelsKanban` or `local/c83fae4e58ce`.
    let description: String

    /// Makes the key of a remote URL.
    ///
    /// The key is the host in lowercase, then each segment of the path. The key removes the user and the port of the
    /// host, the slashes at the start and at the end of the path, and the `.git` suffix. The path keeps its case.
    ///
    /// - Parameter url: The URL of the remote, in the SSH form, the HTTPS form, or the `ssh://` form.
    /// - Throws: ``BoardKeyError/invalidRemoteURL(url:)`` when the remote has no host (for example a local path or a
    ///   `file://` URL), has no path, or has an empty path segment.
    init(remoteURL url: String) throws(BoardKeyError) {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let address = Self.splitAddress(ofRemoteURL: text),
            let host = Self.host(inAuthority: address.authority),
            let pathSegments = Self.pathSegments(ofRemotePath: address.path)
        else {
            throw .invalidRemoteURL(url: url)
        }
        description = Self.normalizedText(ofSegments: [String(host)] + pathSegments)
    }

    /// Makes the key of a repo with no remote: `local/<root commit>`, with the first ``rootCommitDigitCount`` hex
    /// digits of the root commit (divergence.md §16, M7).
    ///
    /// - Parameter commit: The SHA of the root commit of the repo, in hex.
    init(rootCommit commit: String) {
        description = "\(Self.localHost)\(LocalRef.separator)\(commit.prefix(Self.rootCommitDigitCount))"
    }

    /// Makes the key of a board outside git: its board ID (divergence.md M9). The text is the canonical ULID text.
    ///
    /// - Parameter id: The primary board ID of the board.
    init(boardID id: ULID) {
        description = id.ulidString
    }

    /// `true` when the key is a board ID, the key of a board outside git. A git key always has a `/`.
    var isBoardID: Bool {
        ULID(boardKeyText: description) != nil
    }
}

// MARK: - Normalization

extension BoardKey {
    /// Makes the text of a key from its segments. The host (the first segment) ignores case, so the text has the
    /// host in lowercase. Each other segment keeps its case.
    ///
    /// The key of a remote and the key in a parsed ``NodeURI`` both use this rule, so `GitHub.com/owner/repo` and
    /// `github.com/owner/repo` name the same board.
    ///
    /// A key of one segment that is a ULID is a board ID (divergence.md M9). A git key always has a `/`, so the two
    /// forms cannot be confused. A board ID ignores case, so its text is the canonical ULID text in uppercase.
    ///
    /// - Parameter segments: The segments of the key, the host first.
    /// - Returns: The text of the key, for example `github.com/swissarmyhammer/FoundationModelsKanban`, or the
    ///   canonical text of a board ID.
    static func normalizedText(ofSegments segments: some Collection<String>) -> String {
        if segments.count == 1, let id = segments.first.flatMap(ULID.init(boardKeyText:)) {
            return id.ulidString
        }
        let host = segments.first.map { host in [host.lowercased()] } ?? []
        return (host + segments.dropFirst()).joined(separator: String(LocalRef.separator))
    }

    /// Makes the text of a key from a key that a caller wrote, with the rule of ``normalizedText(ofSegments:)``.
    ///
    /// A bare key in a board ref or in a short form uses this rule, so `GitHub.com/owner/repo` names the board
    /// `github.com/owner/repo` (plan.md §3.2).
    ///
    /// - Parameter text: The key as the caller wrote it, for example `GitHub.com/owner/repo`.
    /// - Returns: The text of the key with the host in lowercase, for example `github.com/owner/repo`.
    static func normalizedText(of text: String) -> String {
        normalizedText(
            ofSegments: text.split(separator: LocalRef.separator, omittingEmptySubsequences: false).map(String.init)
        )
    }

    /// Splits a remote URL into its authority (the user, the host, and the port) and its path.
    ///
    /// - Parameter text: The remote URL, with no spaces at the start or at the end.
    /// - Returns: The authority and the path, or `nil` when the text is not a URL and not an SSH remote, for example
    ///   a local path.
    private static func splitAddress(ofRemoteURL text: String) -> (authority: Substring, path: Substring)? {
        if let schemeRange = text.range(of: schemeSeparator) {
            let rest = text[schemeRange.upperBound...]
            let pathStart = rest.firstIndex(of: LocalRef.separator) ?? rest.endIndex
            return (rest[..<pathStart], rest[pathStart...])
        }
        guard let colon = text.firstIndex(of: hostSeparator), !text[..<colon].contains(LocalRef.separator) else {
            return nil
        }
        return (text[..<colon], text[text.index(after: colon)...])
    }

    /// Finds the host in the authority of a remote.
    ///
    /// - Parameter authority: The authority, for example `git@github.com` or `reader@github.com:443`.
    /// - Returns: The host without the user and the port, or `nil` when the host is empty.
    private static func host(inAuthority authority: Substring) -> Substring? {
        let hostAndPort = authority.lastIndex(of: userSeparator).map { authority[authority.index(after: $0)...] }
        let host = (hostAndPort ?? authority).prefix { $0 != hostSeparator }
        return host.isEmpty ? nil : host
    }

    /// Finds the segments of the path of a remote.
    ///
    /// - Parameter path: The path, for example `/swissarmyhammer/FoundationModelsKanban.git/`.
    /// - Returns: The segments without the slashes at the start and at the end and without the `.git` suffix, or
    ///   `nil` when the path has no segment or has an empty segment.
    private static func pathSegments(ofRemotePath path: Substring) -> [String]? {
        var trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: String(LocalRef.separator)))
        if trimmed.hasSuffix(gitSuffix) {
            trimmed.removeLast(gitSuffix.count)
        }
        let segments = trimmed.split(separator: LocalRef.separator, omittingEmptySubsequences: false).map(String.init)
        return segments.contains(where: \.isEmpty) ? nil : segments
    }
}

// MARK: - Read from git

extension BoardKey {
    /// The name of the current commit of a repo in git.
    static let headName = "HEAD"

    /// The subject of the message of the empty first commit that ``read(fromRepoAt:)`` makes in a repo with no commit.
    static let firstCommitMessage = "Initial commit"

    /// The name of the trailer in the message of the empty first commit. The value of the trailer is a new ULID (see
    /// ``makeFirstCommitMessage()``).
    static let firstCommitTrailerName = "Kanban-Root-ID"

    /// Reads the key of the board of a repo (plan.md §3.2, §12 item 4). An empty first commit gets the current time.
    ///
    /// See ``read(fromRepoAt:firstCommitTime:)``.
    ///
    /// - Parameter directory: A folder in the repo: the top folder of a clone or of a worktree, or a folder in it.
    /// - Returns: The key of the board.
    /// - Throws: The errors of ``read(fromRepoAt:firstCommitTime:)``.
    static func read(fromRepoAt directory: URL) async throws(BoardKeyError) -> BoardKey {
        try await read(fromRepoAt: directory, firstCommitTime: Date())
    }

    /// Reads the key of the board of a repo (plan.md §3.2, §12 item 4). A folder that is not in a git repo, or whose
    /// git state cannot be read, has no git key: its board has its board ID as its key (divergence.md M9).
    ///
    /// The read uses libgit2 in the process and starts no `git` program (D128). Thus it works in the App Sandbox and
    /// on a Mac with no developer tools.
    ///
    /// When the repo has no commit, the read first makes one empty first commit on the current branch (divergence.md
    /// §16, M8). The commit has the empty tree, so it does not take the staged files, and the index and the working
    /// files do not change. A repo with commits gets no new commit.
    ///
    /// The key comes from the current `origin` remote of the repo. When the repo has no remote, or the `origin` URL
    /// gives no key (a URL with no host, for example a local path or a `file://` URL, or a URL with a host but no
    /// path), the key is `local/<root commit>` (divergence.md §16, M7). The root commit is the root commit of
    /// ``headName``, or the lowest SHA when the history has more than one root commit. Thus each clone and each
    /// worktree of the repo, and each folder in it, gets the same key, also after a move or a new name of the folder.
    ///
    /// - Parameters:
    ///   - directory: A folder in the repo: the top folder of a clone or of a worktree, or a folder in it.
    ///   - time: The time of the author and of the committer of an empty first commit.
    /// - Returns: The key of the board.
    /// - Throws: ``BoardKeyError/notARepo(path:)`` when the folder is not in a git repo, or when its git state cannot
    ///   be read. ``BoardKeyError/cancelled`` when the task is cancelled before the read.
    ///   ``BoardKeyError/gitFailed(message:)`` when the empty first commit cannot be made, for example because no
    ///   `user.name` or `user.email` is set.
    static func read(fromRepoAt directory: URL, firstCommitTime time: Date) async throws(BoardKeyError) -> BoardKey {
        let repo = try openRepo(at: directory)
        if try !repo.hasHeadCommit {
            try makeFirstCommit(in: repo, at: time)
        }
        if let key = try originKey(of: repo) {
            return key
        }
        return BoardKey(rootCommit: try repo.lowestRootCommit())
    }

    /// Reads the top folder of the worktree of a folder (divergence.md §16). The board of the folder is in the
    /// `.kanban/` directory of this top folder. In the main clone, it is the top folder of the main clone. In a linked
    /// worktree, it is the top folder of that worktree.
    ///
    /// The top folder keeps the path form of the folder. libgit2 gives the path with the symbolic links resolved (for
    /// example `/private/var/…` for `/var/…`), so the read gives the parent folder of `directory` that is the same
    /// folder as the path of libgit2. When no parent folder is the same folder, the read gives the path of libgit2.
    ///
    /// - Parameter directory: The folder.
    /// - Returns: The top folder of the worktree.
    /// - Throws: ``BoardKeyError/notARepo(path:)`` when the folder is not in a git repo, or when its git state cannot
    ///   be read. ``BoardKeyError/cancelled`` when the task is cancelled before the read.
    static func worktreeTop(of directory: URL) async throws(BoardKeyError) -> URL {
        let repo = try openRepo(at: directory)
        return topLevel(repo.workDirectory, seenFrom: directory)
    }

    /// Opens the repo of a folder, unless the task is cancelled.
    ///
    /// - Parameter directory: The folder.
    /// - Returns: The open repo.
    /// - Throws: ``BoardKeyError/cancelled`` when the task is cancelled. The errors of
    ///   ``BoardRepo/init(discoveringFrom:)``.
    private static func openRepo(at directory: URL) throws(BoardKeyError) -> BoardRepo {
        guard !Task.isCancelled else {
            throw .cancelled
        }
        return try BoardRepo(discoveringFrom: directory)
    }

    /// Gives the top folder of a work tree in the path form of a folder in the work tree: the folder itself, or the
    /// parent folder that is the same folder as `top` with the symbolic links resolved.
    ///
    /// - Parameters:
    ///   - top: The top folder of the work tree, as libgit2 gives it.
    ///   - directory: A folder in the work tree.
    /// - Returns: The top folder in the path form of `directory`, or `top` when no parent folder of `directory` is
    ///   the same folder.
    private static func topLevel(_ top: URL, seenFrom directory: URL) -> URL {
        let topPath = top.canonicalPath
        let folders = sequence(first: directory.standardizedFileURL) { folder in
            folder.pathComponents.count > 1 ? folder.deletingLastPathComponent() : nil
        }
        return folders.first { folder in folder.canonicalPath == topPath } ?? top
    }

    /// Reads the key of the current `origin` remote of a repo.
    ///
    /// An `origin` URL that ``init(remoteURL:)`` refuses gives no key: a URL with no host (for example a local path
    /// or a `file://` URL), or a URL with a host but no path (for example `https://example.com/`). The caller then
    /// uses the key `local/<root commit>`, the same as for a repo with no remote.
    ///
    /// - Parameter repo: The open repo.
    /// - Returns: The key, or `nil` when the repo has no `origin` remote, or when ``init(remoteURL:)`` refuses the
    ///   `origin` URL.
    /// - Throws: ``BoardKeyError/notARepo(path:)`` when the git config cannot be read.
    private static func originKey(of repo: BoardRepo) throws(BoardKeyError) -> BoardKey? {
        try repo.configValue(named: originConfigKey).flatMap { url in try? BoardKey(remoteURL: url) }
    }

    /// Makes one empty first commit on the current branch of a repo with no commit (divergence.md §16, M8).
    ///
    /// The message has the subject ``firstCommitMessage`` and the trailer of ``makeFirstCommitMessage()``, with a new
    /// ULID. Thus the first commits of two repos are different, also when the two commits have the same author and the
    /// same time, and the two repos get different keys `local/<root commit>` (divergence.md §16, M8).
    ///
    /// - Parameters:
    ///   - repo: The open repo.
    ///   - time: The time of the author and of the committer.
    /// - Throws: The errors of ``BoardRepo/makeFirstCommit(message:at:)``.
    private static func makeFirstCommit(in repo: BoardRepo, at time: Date) throws(BoardKeyError) {
        try repo.makeFirstCommit(message: makeFirstCommitMessage(), at: time)
    }

    /// Makes the message of the empty first commit: the subject ``firstCommitMessage``, an empty line, and the trailer
    /// ``firstCommitTrailerName`` with a new ULID from ``SystemULIDSource``, for example
    /// `Kanban-Root-ID: 01M503RY75N5Q0M6QSAPWPN97E`. Each call gives a new ULID.
    ///
    /// - Returns: The message, with a newline at the end, the same as the message of `git commit-tree -m … -m …`.
    private static func makeFirstCommitMessage() -> String {
        "\(firstCommitMessage)\n\n\(firstCommitTrailerName): \(SystemULIDSource().makeULID().ulidString)\n"
    }
}

// MARK: - Errors

/// An error from the calculation of a ``BoardKey``.
enum BoardKeyError: Error, Hashable, Sendable {
    /// The remote URL has no host, no path, or an empty path segment.
    case invalidRemoteURL(url: String)

    /// The folder is not in a git repo, or its git state cannot be read, so it has no git key and no worktree top. Its
    /// board is outside git, and the key of that board is its board ID (divergence.md M9). The path is the path of the
    /// folder.
    case notARepo(path: String)

    /// The empty first commit of a repo with no commit cannot be made. The message gives the reason, for example a
    /// git config with no `user.name`.
    case gitFailed(message: String)

    /// The task that needed the key or the worktree top was cancelled.
    case cancelled
}
