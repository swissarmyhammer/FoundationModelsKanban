import Foundation

/// The key of a board: the current `origin` remote of its repo, normalized to `host/owner/repo` (plan.md §3.2, §12
/// item 4).
///
/// The SSH form (`git@host:owner/repo.git`), the HTTPS form (`https://host/owner/repo.git`), and the `ssh://` form of
/// one remote give the same key. A repo with no remote has the key `local/<directory-name>`. The log does not store
/// the key. Each call that opens a board reads the key from git again with ``read(fromRepoAt:)``, so a repo that moves
/// to a new remote gets a new key, and its data does not change. ``NodeURI`` holds the text of the key
/// (``description``).
struct BoardKey: Hashable, Sendable, CustomStringConvertible {
    /// The first segment of the key of a repo with no remote.
    static let localHost = "local"

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

    /// The text of the key, for example `github.com/swissarmyhammer/FoundationModelsKanban` or `local/my-repo`.
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
        description = ([host.lowercased()] + pathSegments).joined(separator: String(LocalRef.separator))
    }

    /// Makes the key of a repo with no remote: `local/<directory-name>`.
    ///
    /// - Parameter name: The name of the directory of the main clone of the repo.
    init(localDirectoryName name: String) {
        description = "\(Self.localHost)\(LocalRef.separator)\(name)"
    }
}

// MARK: - Normalization

extension BoardKey {
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
    /// Reads the key of a repo from git.
    ///
    /// The key comes from the current `origin` remote. When the repo has no remote, the key is
    /// `local/<directory-name>`, with the name of the directory of the main clone. Thus, a worktree gets the same key
    /// as its main clone, with or without a remote.
    ///
    /// - Parameter directory: A directory in the repo: the root of a clone or of a worktree, or a subdirectory.
    /// - Returns: The key of the repo.
    /// - Throws: ``BoardKeyError/gitUnavailable(message:)`` when git cannot start.
    ///   ``BoardKeyError/gitFailed(arguments:status:message:)`` when git fails, for example when the directory is not
    ///   in a git repo. ``BoardKeyError/invalidRemoteURL(url:)`` when the `origin` URL has no host or no path.
    static func read(fromRepoAt directory: URL) throws(BoardKeyError) -> BoardKey {
        if let url = try originURL(ofRepoAt: directory) {
            return try BoardKey(remoteURL: url)
        }
        return BoardKey(localDirectoryName: try mainCloneName(ofRepoAt: directory))
    }

    /// Reads the URL of the `origin` remote with `git config --get remote.origin.url`.
    ///
    /// - Parameter directory: A directory in the repo.
    /// - Returns: The URL, or `nil` when the repo has no `origin` remote.
    /// - Throws: A ``BoardKeyError`` when git cannot start or fails.
    private static func originURL(ofRepoAt directory: URL) throws(BoardKeyError) -> String? {
        let arguments = ["config", "--get", originConfigKey]
        let result = try Git.run(withArguments: arguments, inDirectory: directory)
        switch result.status {
        case Git.successStatus: return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        case missingConfigKeyStatus: return nil
        default: throw .gitFailed(arguments: arguments, status: result.status, message: result.errorOutput)
        }
    }

    /// Finds the name of the directory of the main clone with `git rev-parse --git-common-dir`.
    ///
    /// A worktree shares the git directory of its main clone, so the common git directory is the same for each copy.
    /// The main clone is the directory that holds the common `.git` directory. A bare repo has no `.git` directory,
    /// so its main clone is the common git directory.
    ///
    /// - Parameter directory: A directory in the repo.
    /// - Returns: The name of the directory of the main clone.
    /// - Throws: A ``BoardKeyError`` when git cannot start or fails.
    private static func mainCloneName(ofRepoAt directory: URL) throws(BoardKeyError) -> String {
        let arguments = ["rev-parse", "--path-format=absolute", "--git-common-dir"]
        let result = try Git.run(withArguments: arguments, inDirectory: directory)
        guard result.status == Git.successStatus else {
            throw .gitFailed(arguments: arguments, status: result.status, message: result.errorOutput)
        }
        let commonPath = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let commonDirectory = URL(filePath: commonPath, directoryHint: .isDirectory)
        let isInMainClone = commonDirectory.lastPathComponent == gitDirectoryName
        let mainClone = isInMainClone ? commonDirectory.deletingLastPathComponent() : commonDirectory
        return mainClone.lastPathComponent
    }
}

// MARK: - Errors

/// An error from the calculation of a ``BoardKey``.
enum BoardKeyError: Error, Hashable, Sendable {
    /// The remote URL has no host, no path, or an empty path segment.
    case invalidRemoteURL(url: String)

    /// The `git` tool did not start, for example because git is not installed or the directory does not exist.
    case gitUnavailable(message: String)

    /// A `git` command exited with a failure status.
    case gitFailed(arguments: [String], status: Int32, message: String)
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

    /// The result of a git command.
    struct Output: Sendable {
        /// The exit status.
        let status: Int32

        /// The standard output, as UTF-8 text.
        let output: String

        /// The standard error, as UTF-8 text.
        let errorOutput: String
    }

    /// Runs git in a directory, and waits until it exits.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git`.
    ///   - directory: The directory where git runs.
    /// - Returns: The exit status and the output of git.
    /// - Throws: ``BoardKeyError/gitUnavailable(message:)`` when git cannot start.
    static func run(withArguments arguments: [String], inDirectory directory: URL) throws(BoardKeyError) -> Output {
        let process = Process()
        process.executableURL = URL(filePath: launcherPath)
        process.arguments = [programName] + arguments
        process.currentDirectoryURL = directory
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            throw .gitUnavailable(message: error.localizedDescription)
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Output(
            status: process.terminationStatus,
            output: String(decoding: output, as: UTF8.self),
            errorOutput: String(decoding: errorOutput, as: UTF8.self)
        )
    }
}
