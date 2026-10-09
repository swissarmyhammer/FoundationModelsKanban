import Foundation
import Testing

@testable import FoundationModelsKanban

/// The shared parts of the cross-repo suites (plan.md §6.6): two real folders side by side (git repos or plain
/// folders) and the fields that add tasks. ``GitGraphFixture`` makes the engines that read the board keys from git.
enum CrossRepoFixture {
    /// The kind of the two folders of a ``SideBySide`` sandbox.
    enum FolderKind: CaseIterable, Sendable {
        /// Each folder is a git repo with an `origin` remote.
        case gitRepo

        /// Each folder is a plain folder with no `.git`. Its key is `local/<folder-name>`.
        case plainFolder

        /// Makes one folder of this kind in a sandbox.
        ///
        /// - Parameters:
        ///   - name: The name of the folder.
        ///   - origin: The `origin` remote of a git repo. A plain folder does not use it.
        ///   - sandbox: The sandbox that holds the folder.
        /// - Returns: The folder.
        /// - Throws: An error when the directory cannot be made, or when a git command fails.
        func makeFolder(named name: String, origin: String, in sandbox: GitSandbox) async throws -> URL {
            switch self {
            case .gitRepo: try await sandbox.makeRepo(named: name, origin: origin)
            case .plainFolder: try GitSandbox.makeFolder(named: name, in: sandbox.root)
            }
        }

        /// Gives the key of a folder of this kind (plan.md §6.6, scan).
        ///
        /// - Parameters:
        ///   - name: The name of the folder, without the names of its parent folders.
        ///   - origin: The `origin` remote of a git repo. A plain folder does not use it.
        /// - Returns: The key of the `origin` for a git repo, or `local/<name>` for a plain folder.
        /// - Throws: An error when the remote URL of a git repo is not valid.
        func key(ofFolderNamed name: String, origin: String) throws -> BoardKey {
            switch self {
            case .gitRepo: try BoardKey(remoteURL: origin)
            case .plainFolder: BoardKey(localDirectoryName: name)
            }
        }
    }

    /// The repos of a sandbox with the current repo and one related repo, side by side.
    struct SideBySide {
        /// The sandbox of the test. It removes the repos when the test ends.
        let sandbox: GitSandbox

        /// The current repo, ``BoardLocatorTests/appName``.
        let app: URL

        /// The related repo, ``BoardLocatorTests/libName``.
        let lib: URL

        /// Makes the sandbox and the two folders in it.
        ///
        /// - Parameter kind: The kind of the two folders. The default is ``FolderKind/gitRepo``.
        /// - Returns: The sandbox and its folders.
        /// - Throws: An error when a directory cannot be made, or when a git command fails.
        static func make(as kind: FolderKind = .gitRepo) async throws -> SideBySide {
            let sandbox = try GitSandbox()
            let app = try await kind.makeFolder(
                named: BoardLocatorTests.appName,
                origin: BoardLocatorTests.appOrigin,
                in: sandbox
            )
            let lib = try await kind.makeFolder(
                named: BoardLocatorTests.libName,
                origin: BoardLocatorTests.libOrigin,
                in: sandbox
            )
            return SideBySide(sandbox: sandbox, app: app, lib: lib)
        }
    }

    /// Adds a task with an `addTask` input, and gives its id.
    ///
    /// - Parameters:
    ///   - input: The fields of the input after the title, for example `dependsOn: [...]`.
    ///   - graph: The engine.
    /// - Returns: The full URI of the task.
    static func addTask(with input: String, on graph: KanbanGraph) async throws -> String {
        try await Design.PortabilityTests.id(
            runningField: AddUpdateTaskTests.addTask(with: input),
            named: MutationName.addTask,
            on: graph
        )
    }

    /// Adds a task that depends on a task, and gives its id.
    ///
    /// - Parameters:
    ///   - target: The full URI of the task that the new task depends on.
    ///   - graph: The engine.
    /// - Returns: The full URI of the new task.
    static func addTask(dependingOn target: String, on graph: KanbanGraph) async throws -> String {
        try await addTask(with: "dependsOn: \(AddUpdateTaskTests.list(of: [target]))", on: graph)
    }

    /// Gives the key of a remote URL as text.
    ///
    /// - Parameter origin: The remote URL.
    /// - Returns: The text of the key.
    /// - Throws: An error when the URL is not a valid remote.
    static func keyText(of origin: String) throws -> String {
        try BoardLocatorTests.key(of: origin).description
    }
}
