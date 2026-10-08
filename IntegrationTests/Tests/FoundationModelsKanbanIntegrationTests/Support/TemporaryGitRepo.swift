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
        try runGitInit(in: root)
        return try await body(root)
    }

    /// Runs `git init` in a directory, and requires that it succeeds.
    ///
    /// - Parameter directory: The directory of the new repo.
    /// - Throws: An error from `Process` when git cannot start, or an `ExpectationFailedError` when git fails.
    private static func runGitInit(in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: launcherPath)
        process.arguments = initArguments
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == successStatus, "git init failed in \(directory.path)")
    }
}
