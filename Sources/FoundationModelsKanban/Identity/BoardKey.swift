import Foundation
import Synchronization

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
        description = Self.normalizedText(ofSegments: [String(host)] + pathSegments)
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
    static func read(fromRepoAt directory: URL) async throws(BoardKeyError) -> BoardKey {
        if let url = try await originURL(ofRepoAt: directory) {
            return try BoardKey(remoteURL: url)
        }
        return BoardKey(localDirectoryName: try await mainCloneName(ofRepoAt: directory))
    }

    /// Reads the URL of the `origin` remote with `git config --get remote.origin.url`.
    ///
    /// - Parameter directory: A directory in the repo.
    /// - Returns: The URL, or `nil` when the repo has no `origin` remote.
    /// - Throws: A ``BoardKeyError`` when git cannot start or fails.
    private static func originURL(ofRepoAt directory: URL) async throws(BoardKeyError) -> String? {
        let arguments = ["config", "--get", originConfigKey]
        let result = try await Git.run(withArguments: arguments, inDirectory: directory)
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
    private static func mainCloneName(ofRepoAt directory: URL) async throws(BoardKeyError) -> String {
        let arguments = ["rev-parse", "--path-format=absolute", "--git-common-dir"]
        let result = try await Git.run(withArguments: arguments, inDirectory: directory)
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
    ///   - limit: The longest time that git can run. When this time ends, git is stopped.
    /// - Returns: The exit status and the output of git.
    /// - Throws: ``BoardKeyError/gitUnavailable(message:)`` when git cannot start.
    ///   ``BoardKeyError/gitTimedOut(arguments:)`` when git does not end in the time limit.
    ///   ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled before git ends.
    static func run(
        withArguments arguments: [String],
        inDirectory directory: URL,
        timeLimit limit: Duration = defaultTimeLimit
    ) async throws(BoardKeyError) -> Output {
        let record = GitRecord()
        let process = makeProcess(withArguments: arguments, inDirectory: directory, recordingTo: record)
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
