import Foundation
import Testing

/// Makes a new git repo in a temporary directory for one test, and removes it after the test.
///
/// The repo has no commit and no `origin` remote. Thus the key of its board comes from the name of the repo
/// directory, and a `KanbanGraph` on the repo gives an empty board with that name.
enum TemporaryGitRepo {
    /// The shared folder of the temporary repos of the integration tests.
    private static let parent = FileManager.default.temporaryDirectory.appending(
        path: "FoundationModelsKanbanIntegrationTests",
        directoryHint: .isDirectory
    )

    /// The program that finds `git` on the `PATH`.
    private static let launcherPath = "/usr/bin/env"

    /// The arguments that make a new repo with no output.
    private static let initArguments = ["git", "init", "--quiet"]

    /// The exit status of a git command that succeeds.
    private static let successStatus: Int32 = 0

    /// The longest time that `git init` can run before the test stops it. A local `git init` ends in much less time.
    private static let initTimeLimit = Duration.seconds(initTimeLimitSeconds)

    /// The number of seconds in ``initTimeLimit``.
    private static let initTimeLimitSeconds = 30

    /// Makes a new git repo, gives its root directory to `body`, and then removes the repo.
    ///
    /// The repo stays on disk until `body` returns or throws, so each `await` in `body` sees it.
    ///
    /// - Parameters:
    ///   - name: The name of the repo directory.
    ///   - body: The test code. It gets the root directory of the repo.
    /// - Returns: The value that `body` returns.
    /// - Throws: An error from `FileManager` when a directory cannot be made, an error from `Process` when git cannot
    ///   start, an `ExpectationFailedError` when `git init` fails, or the error that `body` throws.
    static func withRepo<Value>(
        named name: String,
        _ body: (URL) async throws -> Value
    ) async throws -> Value {
        let container = parent.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: container)
        }
        let root = container.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try await runGitInit(in: root)
        return try await body(root)
    }

    /// Runs `git init` in a directory, and requires that it succeeds.
    ///
    /// The wait for the end of git blocks no thread: the termination handler of the process gives the exit status to
    /// an async stream. When git does not end in ``initTimeLimit``, the test stops git and fails.
    ///
    /// - Parameter directory: The directory of the new repo.
    /// - Throws: An error from `Process` when git cannot start, or an `ExpectationFailedError` when git fails or does
    ///   not end in the time limit.
    private static func runGitInit(in directory: URL) async throws {
        let process = Process()
        process.executableURL = URL(filePath: launcherPath)
        process.arguments = initArguments
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        let (exits, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { ended in
            exitContinuation.yield(ended.terminationStatus)
            exitContinuation.finish()
        }
        try process.run()
        let status = try await firstValue(of: exits, within: initTimeLimit)
        if status == nil {
            process.terminate()
        }
        let exitStatus = try #require(status, "git init did not end in \(initTimeLimit) in \(directory.path)")
        try #require(exitStatus == successStatus, "git init failed in \(directory.path)")
    }

    /// Waits for the first value of a stream, but not longer than a time limit.
    ///
    /// - Parameters:
    ///   - values: The stream.
    ///   - limit: The time limit.
    /// - Returns: The first value, or `nil` when the stream ends with no value or the time limit ends first.
    /// - Throws: `CancellationError` when the test is cancelled during the wait.
    private static func firstValue(of values: AsyncStream<Int32>, within limit: Duration) async throws -> Int32? {
        try await withThrowingTaskGroup(of: Int32?.self) { group in
            group.addTask { await values.first { _ in true } }
            group.addTask {
                try await Task.sleep(for: limit)
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
