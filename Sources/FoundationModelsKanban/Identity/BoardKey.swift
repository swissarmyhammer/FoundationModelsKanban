import Foundation
import Synchronization

/// The key of a board: the current `origin` remote of its repo, normalized to `host/owner/repo` (plan.md §3.2, §12
/// item 4).
///
/// The SSH form (`git@host:owner/repo.git`), the HTTPS form (`https://host/owner/repo.git`), and the `ssh://` form of
/// one remote give the same key. A repo with no usable remote has the key `local/<root commit>`, with the first
/// ``rootCommitDigitCount`` hex digits of its root commit (divergence.md §16, M7). A board is only in a git repo
/// (divergence.md §16), so a folder that is not in a git repo has no key. The log does not store the key. Each call
/// that opens a board reads the key from git again with ``read(fromRepoAt:)``, so a repo that moves to a new remote
/// gets a new key, and its data does not change. ``NodeURI`` holds the text of the key (``description``).
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

    /// The exit status of `git config --get` when the repo does not have the key.
    static let missingConfigKeyStatus: Int32 = 1

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
}

// MARK: - Normalization

extension BoardKey {
    /// Makes the text of a key from its segments. The host (the first segment) ignores case, so the text has the
    /// host in lowercase. Each other segment keeps its case.
    ///
    /// The key of a remote and the key in a parsed ``NodeURI`` both use this rule, so `GitHub.com/owner/repo` and
    /// `github.com/owner/repo` name the same board.
    ///
    /// - Parameter segments: The segments of the key, the host first.
    /// - Returns: The text of the key, for example `github.com/swissarmyhammer/FoundationModelsKanban`.
    static func normalizedText(ofSegments segments: some Collection<String>) -> String {
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
    /// The arguments of the `git rev-parse` command that gives the top-level directory of the work tree of a repo.
    static let repoPathsArguments = ["rev-parse", "--path-format=absolute", "--show-toplevel"]

    /// The text in the standard error of git when a directory is not in a git repo, for example in
    /// `fatal: not a git repository (or any of the parent directories): .git`. The match ignores case.
    static let notInRepoMessage = "not a git repository"

    /// The name of the current commit of a repo in git.
    static let headName = "HEAD"

    /// The arguments of the git command that tells if ``headName`` names a commit. With `--quiet`, git exits with
    /// ``missingRevisionStatus`` and writes no message when ``headName`` names no commit, for example in a new repo.
    static let headCommitArguments = ["rev-parse", "--verify", "--quiet", headName]

    /// The exit status of ``headCommitArguments`` when ``headName`` names no commit.
    static let missingRevisionStatus: Int32 = 1

    /// The arguments of the git command that gives the SHA of the empty tree, in the hash of the repo.
    static let emptyTreeArguments = ["hash-object", "-t", "tree", "/dev/null"]

    /// The message of the empty first commit that ``read(fromRepoAt:)`` makes in a repo with no commit.
    static let firstCommitMessage = "Initial commit"

    /// The old value that `git update-ref` requires for a ref that must not exist yet. Thus two reads at the same
    /// time cannot both set the first commit.
    static let missingRefValue = ""

    /// The arguments of the git command that lists the root commits of ``headName``, one SHA on each line.
    static let rootCommitsArguments = ["rev-list", "--max-parents=0", headName]

    /// Reads the key of the board of a repo (plan.md §3.2, §12 item 4). A board is only in a git repo (divergence.md
    /// §16). Git runs with the environment of the process.
    ///
    /// See ``read(fromRepoAt:gitEnvironment:)``.
    ///
    /// - Parameter directory: A folder in the repo: the top folder of a clone or of a worktree, or a folder in it.
    /// - Returns: The key of the board.
    /// - Throws: The errors of ``read(fromRepoAt:gitEnvironment:)``.
    static func read(fromRepoAt directory: URL) async throws(BoardKeyError) -> BoardKey {
        try await read(fromRepoAt: directory, gitEnvironment: nil)
    }

    /// Reads the key of the board of a repo (plan.md §3.2, §12 item 4). A board is only in a git repo (divergence.md
    /// §16).
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
    ///   - environment: The environment of git, or `nil` for the environment of the process.
    /// - Returns: The key of the board.
    /// - Throws: ``BoardKeyError/notARepo(path:)`` when the folder is not in a git repo.
    ///   ``BoardKeyError/gitTimedOut(arguments:)`` when git does not end in its time limit.
    ///   ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled before git ends.
    ///   ``BoardKeyError/gitUnavailable(message:)`` when git cannot start.
    ///   ``BoardKeyError/gitFailed(arguments:status:message:)`` when git fails for a different cause, with the message
    ///   of git: for example a config file that git cannot read, or a first commit that git cannot make because no
    ///   `user.name` or `user.email` is set.
    static func read(
        fromRepoAt directory: URL,
        gitEnvironment environment: [String: String]?
    ) async throws(BoardKeyError) -> BoardKey {
        let repo = RepoGit(directory: directory, environment: environment)
        // The read of the paths throws notARepo when the folder is not in a git repo.
        _ = try await repoPaths(of: repo)
        try await makeFirstCommitIfNeeded(in: repo)
        if let key = try await originKey(of: repo) {
            return key
        }
        return BoardKey(rootCommit: try await lowestRootCommit(of: repo))
    }

    /// Reads the top folder of the worktree of a folder with `git rev-parse --show-toplevel` (divergence.md §16). The
    /// board of the folder is in the `.kanban/` directory of this top folder. In the main clone, it is the top folder
    /// of the main clone. In a linked worktree, it is the top folder of that worktree.
    ///
    /// The top folder keeps the path form of the folder. Git gives the path with the symbolic links resolved (for
    /// example `/private/var/…` for `/var/…`), so the read gives the parent folder of `directory` that is the same
    /// folder as the path of git. When no parent folder is the same folder, the read gives the path of git.
    ///
    /// - Parameter directory: The folder.
    /// - Returns: The top folder of the worktree.
    /// - Throws: The errors of ``read(fromRepoAt:)``: ``BoardKeyError/notARepo(path:)`` when the folder is not in a
    ///   git repo, and the failures of git.
    static func worktreeTop(of directory: URL) async throws(BoardKeyError) -> URL {
        let repo = RepoGit(directory: directory, environment: nil)
        return try await repoPaths(of: repo).topLevel(seenFrom: directory)
    }

    /// Reads the paths of the repo of a directory with `git rev-parse`.
    ///
    /// The directory is not in a git repo only when the standard error of git has ``notInRepoMessage`` (in any case).
    /// Each other failure of git is a real failure, so it throws.
    ///
    /// - Parameter repo: The directory, and the environment of git.
    /// - Returns: The paths.
    /// - Throws: ``BoardKeyError/notARepo(path:)`` when the directory is not in a git repo.
    ///   ``BoardKeyError/gitFailed(arguments:status:message:)`` when git exits with each other failure status, or when
    ///   its output does not have the path. ``BoardKeyError/gitUnavailable(message:)`` when git cannot start.
    ///   ``BoardKeyError/gitTimedOut(arguments:)`` and ``BoardKeyError/gitCancelled(arguments:)`` when git does not
    ///   end.
    private static func repoPaths(of repo: RepoGit) async throws(BoardKeyError) -> RepoPaths {
        let result = try await repo.run(repoPathsArguments)
        guard result.status == Git.successStatus else {
            guard isNoRepoFailure(result) else {
                throw .gitFailed(arguments: repoPathsArguments, status: result.status, message: result.errorOutput)
            }
            throw .notARepo(path: repo.directory.path)
        }
        guard let paths = RepoPaths(gitOutput: result.output) else {
            throw .gitFailed(arguments: repoPathsArguments, status: result.status, message: result.output)
        }
        return paths
    }

    /// Tells if a failed `git rev-parse` shows that the directory is not in a git repo.
    ///
    /// - Parameter result: The result of git, with a failure status.
    /// - Returns: `true` when the standard error has ``notInRepoMessage`` (in any case).
    private static func isNoRepoFailure(_ result: Git.Output) -> Bool {
        result.errorOutput.range(of: notInRepoMessage, options: .caseInsensitive) != nil
    }

    /// Reads the key of the current `origin` remote of a repo.
    ///
    /// An `origin` URL that ``init(remoteURL:)`` refuses gives no key: a URL with no host (for example a local path
    /// or a `file://` URL), or a URL with a host but no path (for example `https://example.com/`). The caller then
    /// uses the key `local/<root commit>`, the same as for a repo with no remote.
    ///
    /// - Parameter repo: A directory in the repo, and the environment of git.
    /// - Returns: The key, or `nil` when the repo has no `origin` remote, or when ``init(remoteURL:)`` refuses the
    ///   `origin` URL.
    /// - Throws: A ``BoardKeyError`` when git cannot start or fails.
    private static func originKey(of repo: RepoGit) async throws(BoardKeyError) -> BoardKey? {
        try await originURL(of: repo).flatMap { url in try? BoardKey(remoteURL: url) }
    }

    /// Reads the URL of the `origin` remote with `git config --get remote.origin.url`.
    ///
    /// - Parameter repo: A directory in the repo, and the environment of git.
    /// - Returns: The URL, or `nil` when the repo has no `origin` remote.
    /// - Throws: A ``BoardKeyError`` when git cannot start or fails.
    private static func originURL(of repo: RepoGit) async throws(BoardKeyError) -> String? {
        let arguments = ["config", "--get", originConfigKey]
        let result = try await repo.run(arguments)
        switch result.status {
        case Git.successStatus: return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        case missingConfigKeyStatus: return nil
        default: throw .gitFailed(arguments: arguments, status: result.status, message: result.errorOutput)
        }
    }

    /// Makes one empty first commit on the current branch when ``headName`` names no commit (divergence.md §16, M8).
    ///
    /// The commit does not use `git commit`, so it does not take the staged files. `git commit-tree` makes the commit
    /// from the empty tree, and `git update-ref` sets the current branch to it. The index and the working files do not
    /// change. The update requires that the branch does not exist yet. When a different read made the first commit at
    /// the same time, the update fails, and the read uses the commit of the other read.
    ///
    /// - Parameter repo: A directory in the repo, and the environment of git.
    /// - Throws: ``BoardKeyError/gitFailed(arguments:status:message:)`` with the message of git when git cannot make
    ///   the commit (for example when no `user.name` or `user.email` is set) or cannot set the branch. The other
    ///   errors of ``Git/run(withArguments:inDirectory:environment:timeLimit:)``.
    private static func makeFirstCommitIfNeeded(in repo: RepoGit) async throws(BoardKeyError) {
        guard try await !hasHeadCommit(repo) else {
            return
        }
        let tree = try await repo.output(of: emptyTreeArguments)
        let commit = try await repo.output(of: ["commit-tree", tree, "-m", firstCommitMessage])
        let arguments = ["update-ref", headName, commit, missingRefValue]
        let result = try await repo.run(arguments)
        if result.status != Git.successStatus, try await !hasHeadCommit(repo) {
            throw .gitFailed(arguments: arguments, status: result.status, message: result.errorOutput)
        }
    }

    /// Tells if ``headName`` names a commit.
    ///
    /// - Parameter repo: A directory in the repo, and the environment of git.
    /// - Returns: `false` when ``headName`` names no commit, for example in a repo with no commit.
    /// - Throws: ``BoardKeyError/gitFailed(arguments:status:message:)`` when git fails for a different cause. The
    ///   other errors of ``Git/run(withArguments:inDirectory:environment:timeLimit:)``.
    private static func hasHeadCommit(_ repo: RepoGit) async throws(BoardKeyError) -> Bool {
        let result = try await repo.run(headCommitArguments)
        switch result.status {
        case Git.successStatus: return true
        case missingRevisionStatus: return false
        default: throw .gitFailed(arguments: headCommitArguments, status: result.status, message: result.errorOutput)
        }
    }

    /// Reads the root commit of ``headName``. When the history has more than one root commit, for example after a
    /// merge of an orphan branch, the read gives the lowest SHA, so the key is the same each time (divergence.md
    /// §16, M7).
    ///
    /// - Parameter repo: A directory in the repo, and the environment of git.
    /// - Returns: The SHA of the root commit, in hex.
    /// - Throws: ``BoardKeyError/gitFailed(arguments:status:message:)`` when git fails, or when git lists no root
    ///   commit. The other errors of ``Git/run(withArguments:inDirectory:environment:timeLimit:)``.
    private static func lowestRootCommit(of repo: RepoGit) async throws(BoardKeyError) -> String {
        let output = try await repo.output(of: rootCommitsArguments)
        // Each SHA has the same number of lowercase hex digits, so the text order is the order of the numbers.
        guard let lowest = output.split(whereSeparator: \.isNewline).min() else {
            throw .gitFailed(arguments: rootCommitsArguments, status: Git.successStatus, message: output)
        }
        return String(lowest)
    }
}

/// A directory of a repo and the environment of git: the place where the git commands of a key read run.
private struct RepoGit {
    /// A directory in the repo, where git runs.
    let directory: URL

    /// The environment of git, or `nil` for the environment of the process.
    let environment: [String: String]?

    /// Runs git in ``directory`` with ``environment``.
    ///
    /// - Parameter arguments: The arguments after `git`.
    /// - Returns: The exit status and the output of git.
    /// - Throws: The errors of ``Git/run(withArguments:inDirectory:environment:timeLimit:)``.
    func run(_ arguments: [String]) async throws(BoardKeyError) -> Git.Output {
        try await Git.run(withArguments: arguments, inDirectory: directory, environment: environment)
    }

    /// Runs git in ``directory`` with ``environment``, and requires that it succeeds.
    ///
    /// - Parameter arguments: The arguments after `git`.
    /// - Returns: The standard output of git, with no white space at the start and at the end.
    /// - Throws: ``BoardKeyError/gitFailed(arguments:status:message:)`` with the standard error of git when git exits
    ///   with a failure status. The other errors of ``Git/run(withArguments:inDirectory:environment:timeLimit:)``.
    func output(of arguments: [String]) async throws(BoardKeyError) -> String {
        let result = try await run(arguments)
        guard result.status == Git.successStatus else {
            throw .gitFailed(arguments: arguments, status: result.status, message: result.errorOutput)
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The paths of a repo that ``BoardKey/repoPathsArguments`` gives: the top-level directory of the work tree.
private struct RepoPaths {
    /// The number of lines in the output of git: one for the top-level directory.
    private static let lineCount = 1

    /// The top-level directory of the work tree: the root of a clone or of a worktree.
    let topLevel: URL

    /// Reads the paths from the output of git.
    ///
    /// - Parameter output: The standard output of git: the top-level directory on one line.
    /// - Returns: `nil` when the output does not have the one line.
    init?(gitOutput output: String) {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count == Self.lineCount, let topLevelPath = lines.first else {
            return nil
        }
        topLevel = URL(filePath: topLevelPath, directoryHint: .isDirectory)
    }

    /// Gives the top-level directory in the path form of a folder in the work tree: the folder itself, or the parent
    /// folder that is the same folder as ``topLevel`` with the symbolic links resolved.
    ///
    /// - Parameter directory: A folder in the work tree.
    /// - Returns: The top-level directory in the path form of `directory`, or ``topLevel`` when no parent folder of
    ///   `directory` is the same folder.
    func topLevel(seenFrom directory: URL) -> URL {
        let topPath = topLevel.canonicalPath
        let folders = sequence(first: directory.standardizedFileURL) { folder in
            folder.pathComponents.count > 1 ? folder.deletingLastPathComponent() : nil
        }
        return folders.first { folder in folder.canonicalPath == topPath } ?? topLevel
    }
}

// MARK: - Errors

/// An error from the calculation of a ``BoardKey``.
enum BoardKeyError: Error, Hashable, Sendable {
    /// The remote URL has no host, no path, or an empty path segment.
    case invalidRemoteURL(url: String)

    /// The folder is not in a git repo, so it has no board (divergence.md §16). The path is the path of the folder.
    case notARepo(path: String)

    /// The `git` tool did not start, for example because git is not installed or the directory does not exist.
    case gitUnavailable(message: String)

    /// A `git` command exited with a failure status.
    case gitFailed(arguments: [String], status: Int32, message: String)

    /// A `git` command did not end in its time limit, so it was stopped.
    case gitTimedOut(arguments: [String])

    /// The task that waited for a `git` command was cancelled, so the command was stopped.
    case gitCancelled(arguments: [String])
}

// MARK: - Git

/// Runs the `git` command-line tool.
enum Git {
    /// The exit status of a git command that succeeded.
    static let successStatus: Int32 = 0

    /// The program that finds `git` on the `PATH`.
    static let launcherPath = "/usr/bin/env"

    /// The name of the git program, which ``launcherPath`` finds.
    static let programName = "git"

    /// The number of seconds in ``defaultTimeLimit``.
    private static let defaultTimeLimitSeconds = 30

    /// The longest time that a git command can run before it is stopped. A local git command ends in much less time.
    static let defaultTimeLimit = Duration.seconds(defaultTimeLimitSeconds)

    /// The result of a git command.
    struct Output: Sendable {
        /// The exit status.
        let status: Int32

        /// The standard output, as UTF-8 text.
        let output: String

        /// The standard error, as UTF-8 text.
        let errorOutput: String
    }

    /// Runs git in a directory, and waits until it exits, until its time limit ends, or until the task is cancelled.
    ///
    /// The wait blocks no thread: the exit of git and the ends of its two pipes resume the caller. Thus many calls at
    /// the same time do not take the threads of Swift concurrency from other tasks. Git gets an empty standard input,
    /// so it never waits for input. The standard output and the standard error are read at the same time, so a large
    /// output on one pipe cannot stop git while the run waits for the other pipe. When the time limit ends or the task
    /// is cancelled, the run stops git and returns at once. It does not wait for the pipes then, because a child of
    /// git (for example the shell of an alias) can keep them open.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git`.
    ///   - directory: The directory where git runs.
    ///   - environment: The environment of git, or `nil` for the environment of the process.
    ///   - limit: The longest time that git can run. When this time ends, git is stopped.
    /// - Returns: The exit status and the output of git.
    /// - Throws: ``BoardKeyError/gitUnavailable(message:)`` when git cannot start.
    ///   ``BoardKeyError/gitTimedOut(arguments:)`` when git does not end in the time limit.
    ///   ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled before git ends.
    static func run(
        withArguments arguments: [String],
        inDirectory directory: URL,
        environment: [String: String]? = nil,
        timeLimit limit: Duration = defaultTimeLimit
    ) async throws(BoardKeyError) -> Output {
        let record = GitRecord()
        let process = makeProcess(withArguments: arguments, inDirectory: directory, recordingTo: record)
        process.environment = environment
        async let _ = record.stop(process, after: limit, with: .gitTimedOut(arguments: arguments))
        let outcome = await withTaskCancellationHandler {
            await record.outcome(ofStarting: process)
        } onCancel: {
            record.stop(process, with: .gitCancelled(arguments: arguments))
        }
        return try outcome.get()
    }

    /// Makes the git process, and connects its exit and its two pipes to a record.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git`.
    ///   - directory: The directory where git runs.
    ///   - record: The record that gets the exit status and the bytes of the two pipes.
    /// - Returns: The process, not started.
    private static func makeProcess(
        withArguments arguments: [String],
        inDirectory directory: URL,
        recordingTo record: GitRecord
    ) -> Process {
        let process = Process()
        process.executableURL = URL(filePath: launcherPath)
        process.arguments = [programName] + arguments
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = record.makePipe(for: .output)
        process.standardError = record.makePipe(for: .errorOutput)
        process.terminationHandler = { ended in record.recordExit(withStatus: ended.terminationStatus) }
        return process
    }
}

/// One of the two output streams of a git process.
private enum GitStream {
    /// The standard output.
    case output

    /// The standard error.
    case errorOutput
}

/// The bytes of one output stream of a git process.
private struct StreamBytes {
    /// The bytes that the pipe gave until now.
    private var data = Data()

    /// `true` after the pipe ended.
    private(set) var isEnded = false

    /// The bytes as UTF-8 text.
    var text: String {
        String(decoding: data, as: UTF8.self)
    }

    /// Adds one chunk of the pipe. An empty chunk is the end of the pipe.
    ///
    /// - Parameter chunk: The bytes that the pipe gave.
    mutating func add(_ chunk: Data) {
        if chunk.isEmpty {
            isEnded = true
        } else {
            data.append(chunk)
        }
    }
}

/// The state of one git run.
private struct GitRunState {
    /// The phase of the git process.
    enum Phase {
        /// The process did not start.
        case notStarted

        /// The process runs.
        case running

        /// The process exited with a status.
        case exited(status: Int32)
    }

    /// The phase of the git process.
    var phase = Phase.notStarted

    /// The bytes of the standard output.
    var output = StreamBytes()

    /// The bytes of the standard error.
    var errorOutput = StreamBytes()

    /// The result of the run, or `nil` until git and its pipes end or the run stops. The first result stays.
    var outcome: GitRecord.Outcome?

    /// The caller that waits for the result, or `nil` before the wait and after the resume.
    var waiter: GitRecord.Waiter?

    /// Adds one chunk to the bytes of a stream.
    ///
    /// - Parameters:
    ///   - chunk: The bytes that the pipe gave. An empty chunk is the end of the pipe.
    ///   - stream: The stream of the pipe.
    mutating func add(_ chunk: Data, to stream: GitStream) {
        switch stream {
        case .output: output.add(chunk)
        case .errorOutput: errorOutput.add(chunk)
        }
    }

    /// Starts git, unless the run stopped before the start.
    ///
    /// - Parameter process: The git process.
    mutating func start(_ process: Process) {
        guard outcome == nil else {
            return
        }
        do {
            try process.run()
            phase = .running
        } catch {
            outcome = .failure(.gitUnavailable(message: error.localizedDescription))
        }
    }

    /// Ends the run with an error, unless the run has a result already.
    ///
    /// - Parameter error: The error of the run.
    /// - Returns: `true` when git runs, so the caller must stop git.
    mutating func stop(with error: BoardKeyError) -> Bool {
        guard outcome == nil else {
            return false
        }
        outcome = .failure(error)
        guard case .running = phase else {
            return false
        }
        return true
    }

    /// Records the result when git exited and both pipes ended, unless the run has a result already.
    mutating func settle() {
        guard outcome == nil, case .exited(let status) = phase, output.isEnded, errorOutput.isEnded else {
            return
        }
        outcome = .success(Git.Output(status: status, output: output.text, errorOutput: errorOutput.text))
    }

    /// Takes the caller and the result when both are there, so that the caller is resumed one time only.
    ///
    /// - Returns: The caller and the result, or `nil` when one of them is not there.
    mutating func takeReadyWaiter() -> (waiter: GitRecord.Waiter, outcome: GitRecord.Outcome)? {
        guard let waiter, let outcome else {
            return nil
        }
        self.waiter = nil
        return (waiter, outcome)
    }
}

/// Collects the parts of the result of one git run, and resumes the caller that waits for the result.
///
/// The run blocks no thread. The termination handler of the process and the readability handlers of the two pipes
/// record their parts. The caller waits in a checked continuation, which the record resumes one time: when git exited
/// and both pipes ended, or at once when the run stops.
///
/// A `Mutex` guards the state, and not an actor: the handlers of Foundation and the cancel handler are synchronous, so
/// each must record its part at once, with no `await`. The record holds no reference to the process, so the handlers
/// that the process holds make no reference cycle.
private final class GitRecord: Sendable {
    /// The result of a run: the output of git, or the error of the run.
    typealias Outcome = Result<Git.Output, BoardKeyError>

    /// The caller that waits for the result of a run.
    typealias Waiter = CheckedContinuation<Outcome, Never>

    /// The state of the run.
    private let state = Mutex(GitRunState())

    /// Makes a pipe whose readability handler records each chunk of one stream of git.
    ///
    /// - Parameter stream: The stream that the pipe carries.
    /// - Returns: The pipe.
    func makePipe(for stream: GitStream) -> Pipe {
        let pipe = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { handle in self.read(from: handle, into: stream) }
        return pipe
    }

    /// Reads the data that a pipe has now. At the end of the pipe, the read also removes the readability handler.
    ///
    /// - Parameters:
    ///   - handle: The read end of the pipe.
    ///   - stream: The stream that the pipe carries.
    private func read(from handle: FileHandle, into stream: GitStream) {
        let chunk = handle.availableData
        if chunk.isEmpty {
            handle.readabilityHandler = nil
        }
        update { state in state.add(chunk, to: stream) }
    }

    /// Records the exit of git.
    ///
    /// - Parameter status: The exit status of git.
    func recordExit(withStatus status: Int32) {
        update { state in state.phase = .exited(status: status) }
    }

    /// Starts git, and waits for the result of the run. The wait blocks no thread.
    ///
    /// - Parameter process: The git process.
    /// - Returns: The result of the run.
    func outcome(ofStarting process: Process) async -> Outcome {
        await withCheckedContinuation { waiter in
            update { state in
                state.waiter = waiter
                state.start(process)
            }
        }
    }

    /// Ends the run with an error, and stops git when it runs. A run that has a result already does not change.
    ///
    /// - Parameters:
    ///   - process: The git process.
    ///   - error: The error of the run.
    func stop(_ process: Process, with error: BoardKeyError) {
        if update({ state in state.stop(with: error) }) {
            process.terminate()
        }
    }

    /// Waits for a time limit, and then ends the run with an error.
    ///
    /// The cancel of the task of the wait ends the wait with no stop. The task is cancelled when the run ended first,
    /// or when the caller was cancelled: the cancel handler of the caller then stops the run.
    ///
    /// - Parameters:
    ///   - process: The git process.
    ///   - limit: The time limit.
    ///   - error: The error of the run when the time limit ends.
    func stop(_ process: Process, after limit: Duration, with error: BoardKeyError) async {
        do {
            try await Task.sleep(for: limit)
        } catch {
            // `Task.sleep` throws only `CancellationError`, so the run ended or the cancel handler stops it.
            return
        }
        stop(process, with: error)
    }

    /// Changes the state under the lock, records the result when it is complete, and then resumes the waiting
    /// caller when the result is there.
    ///
    /// - Parameter change: The change of the state.
    /// - Returns: The value of the change.
    @discardableResult
    private func update<Value: Sendable>(_ change: (inout GitRunState) -> Value) -> Value {
        let (value, ready) = state.withLock { state in
            let value = change(&state)
            state.settle()
            return (value, state.takeReadyWaiter())
        }
        if let ready {
            ready.waiter.resume(returning: ready.outcome)
        }
        return value
    }
}
