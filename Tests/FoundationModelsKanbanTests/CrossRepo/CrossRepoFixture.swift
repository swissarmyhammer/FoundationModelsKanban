import Foundation
import Testing

@testable import FoundationModelsKanban

/// The shared parts of the cross-repo suites (plan.md §6.6): two real git repos side by side and the fields that add
/// tasks. ``GitGraphFixture`` makes the engines that read the board keys from git.
enum CrossRepoFixture {
    /// The repos of a sandbox with the current repo and one related repo, side by side.
    struct SideBySide {
        /// The sandbox of the test. It removes the repos when the test ends.
        let sandbox: GitSandbox

        /// The current repo, ``BoardLocatorTests/appName``.
        let app: URL

        /// The related repo, ``BoardLocatorTests/libName``.
        let lib: URL

        /// Makes the sandbox, and runs git to make the repos in it.
        ///
        /// - Returns: The sandbox and its repos.
        /// - Throws: An error when the sandbox directory cannot be made, or when a git command fails.
        static func make() async throws -> SideBySide {
            let sandbox = try GitSandbox()
            let app = try await sandbox.makeRepo(named: BoardLocatorTests.appName, origin: BoardLocatorTests.appOrigin)
            let lib = try await sandbox.makeRepo(named: BoardLocatorTests.libName, origin: BoardLocatorTests.libOrigin)
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
