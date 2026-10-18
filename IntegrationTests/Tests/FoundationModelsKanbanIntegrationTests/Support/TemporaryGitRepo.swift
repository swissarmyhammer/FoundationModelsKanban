import Foundation
import Testing

/// Makes new git repos in a temporary directory for one test, and removes them after the test.
///
/// Each repo has one empty root commit and no `origin` remote when `body` starts. The message of the root commit is
/// the name of the repo directory. Thus each repo has a different root commit, also when two repos are made in the
/// same second with the same author, and the key of each board, `local/<root commit>`, is different. The repo has a
/// local identity of the author, and no commit signatures. A `KanbanGraph` on the repo gives an empty board with the
/// name of the repo directory.
enum TemporaryGitRepo {
    /// The base folder of the run folders of the tests. It is not in the temporary folder of the user
    /// (`/var/folders/…/T`), because FSEvents can give the events of that folder 60 s or more late. The path starts
    /// with the symbolic link `/tmp`, the form of each path that the package gives (`/private` removed). The unit
    /// tests of the root package use the same base folder (`TestFolderRoot`).
    private static let basePath = "/tmp/fmk-tests"

    /// The prefix of the name of the run folder of this package. The rest of the name is the run id.
    private static let runFolderPrefix = "integration-"

    /// The run folder of this test process, the shared folder of its temporary repos, or the error that stopped its
    /// make. The folder is made at the first use.
    private static let parent = Result { try makeRunFolder() }

    /// The program that finds `git` on the `PATH`.
    private static let launcherPath = "/usr/bin/env"

    /// The name of the git program that the launcher finds.
    private static let gitProgram = "git"

    /// The git arguments that make a new repo with no output.
    private static let initArguments = ["init", "--quiet"]

    /// The git command that sets one value of the local config of the repo.
    private static let configCommand = "config"

    /// The name of the author of the root commit.
    private static let userName = "Integration Tests"

    /// The email of the author of the root commit.
    private static let userEmail = "integration-tests@example.invalid"

    /// The local config of each new repo: the name and the email of the author, and no commit signatures. Thus the
    /// root commit can be made also on a machine with no global git identity and no signing key.
    private static let identityConfig = [
        ("user.name", userName),
        ("user.email", userEmail),
        ("commit.gpgsign", "false"),
    ]

    /// The git arguments that make the empty root commit, before the message. The message follows the last argument.
    private static let rootCommitArguments = ["commit", "--quiet", "--allow-empty", "--message"]

    /// The exit status of a git command that succeeds.
    private static let successStatus: Int32 = 0

    /// Makes a new git repo, gives its root directory to `body`, and then removes the repo.
    ///
    /// The repo stays on disk until `body` returns or throws, so each `await` in `body` sees it.
    ///
    /// - Parameters:
    ///   - name: The name of the repo directory.
    ///   - body: The test code. It gets the root directory of the repo.
    /// - Returns: The value that `body` returns.
    /// - Throws: An error from `FileManager` when a directory cannot be made, an error from `Process` when git cannot
    ///   start, an `ExpectationFailedError` when `git init`, `git config`, or `git commit` fails, or the error that
    ///   `body` throws.
    static func withRepo<Value>(
        named name: String,
        _ body: (URL) async throws -> Value
    ) async throws -> Value {
        try await withRepos(named: [name]) { roots in
            try await body(roots[0])
        }
    }

    /// Makes new git repos side by side in one folder, gives their root directories to `body`, and then removes the
    /// repos.
    ///
    /// The repos are siblings, so the scan of each engine finds the boards of the other repos as related boards. Each
    /// repo has its own root commit and no `origin` remote, so the key of each board is `local/<root commit>`, and no
    /// two boards have the same key.
    ///
    /// - Parameters:
    ///   - names: The names of the repo directories. Each name must be different.
    ///   - body: The test code. It gets the root directory of each repo, in the order of `names`.
    /// - Returns: The value that `body` returns.
    /// - Throws: The errors of ``withRepo(named:_:)``.
    static func withRepos<Value>(
        named names: [String],
        _ body: ([URL]) async throws -> Value
    ) async throws -> Value {
        let container = try parent.get().appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: container)
        }
        let roots = names.map { name in container.appending(path: name, directoryHint: .isDirectory) }
        for root in roots {
            try await makeRepo(at: root)
        }
        return try await body(roots)
    }

    /// Makes the run folder of this test process, and removes it at the exit of the process when it is empty.
    ///
    /// - Returns: The run folder.
    /// - Throws: An error from `FileManager` when the folder cannot be made.
    private static func makeRunFolder() throws -> URL {
        let folder = URL(filePath: basePath, directoryHint: .isDirectory).appending(
            path: runFolderPrefix + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        atexit { TemporaryGitRepo.removeRunFolderIfEmpty() }
        return folder
    }

    /// Removes the run folder when it is empty. `rmdir(2)` removes no folder that holds an entry.
    private static func removeRunFolderIfEmpty() {
        guard case .success(let folder) = parent else {
            return
        }
        rmdir(folder.path)
    }

    /// Makes one new git repo with the local identity of ``identityConfig``, and with an empty root commit whose
    /// message is the name of the repo directory.
    ///
    /// - Parameter root: The root directory of the new repo.
    /// - Throws: An error from `FileManager` when the directory cannot be made, an error from `Process` when git
    ///   cannot start, or an `ExpectationFailedError` when `git init`, `git config`, or `git commit` fails.
    private static func makeRepo(at root: URL) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try await runGit(initArguments, in: root)
        for (key, value) in identityConfig {
            try await runGit([configCommand, key, value], in: root)
        }
        try await runGit(rootCommitArguments + [root.lastPathComponent], in: root)
    }

    /// Runs one git command in a directory, and requires that it succeeds.
    ///
    /// The wait for the end of git has no time limit. The wait blocks no thread: the termination handler of the
    /// process gives the exit status to an async stream.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git`.
    ///   - directory: The directory where git runs.
    /// - Throws: An error from `Process` when git cannot start, or an `ExpectationFailedError` when git fails or ends
    ///   with no exit status.
    private static func runGit(_ arguments: [String], in directory: URL) async throws {
        let process = Process()
        process.executableURL = URL(filePath: launcherPath)
        process.arguments = [gitProgram] + arguments
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        let (exits, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { ended in
            exitContinuation.yield(ended.terminationStatus)
            exitContinuation.finish()
        }
        try process.run()
        let status = await exits.first { _ in true }
        let command = "git \(arguments.joined(separator: " "))"
        let exitStatus = try #require(status, "\(command) ended with no exit status in \(directory.path)")
        try #require(exitStatus == successStatus, "\(command) failed in \(directory.path)")
    }
}
