import Foundation
import FoundationModelsKanban
import Testing

/// The integration test of a dependency between two real git repos side by side (plan.md §6.6): a task of one repo
/// depends on a task of the repo beside it, and it becomes ready when that task is done.
///
/// The test uses only the public API of the library. Two sessions from `KanbanHost.shared` work in the two repos, and
/// the engine runs the real `git` to read the board keys and to find the repo beside the current repo.
@Suite("Integration: a task depends on a task of the repo beside it")
struct CrossRepoDependencyTests {
    /// The name of the repo of the dependent task.
    static let appName = "integration-app"

    /// The name of the repo of the task that the dependent task depends on.
    static let libName = "integration-lib"

    /// The name of the session actor of the sessions.
    static let actorName = "Integration Cross Repo"

    /// The `ready` value of the dependent task before and after the task of the repo beside it is done.
    static let readyBeforeAndAfter = [false, true]

    // MARK: - Helpers

    /// Runs one document on a session, and gives one named object of the `data` object of the response.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - key: The name of the object in the `data` object, for example `addTask`.
    ///   - session: The session.
    /// - Returns: The named object.
    /// - Throws: An error when the call fails, or when the response has no object with this name.
    static func object(
        named key: String,
        runningDocument document: String,
        on session: KanbanGraph
    ) async throws -> [String: Any] {
        let response = try await session.execute(query: document, variables: [:], operationName: nil)
        let json = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let data = try #require(json["data"] as? [String: Any], "\(response)")
        return try #require(data[key] as? [String: Any], "\(response)")
    }

    /// Adds a task with an `addTask` call.
    ///
    /// - Parameters:
    ///   - input: The fields of the `input` object after the title, or `""` for none.
    ///   - session: The session.
    /// - Returns: The full URI of the new task.
    /// - Throws: An error when the call fails.
    static func addTask(with input: String, on session: KanbanGraph) async throws -> String {
        let document = #"mutation { addTask(input: { title: "Integration task" \#(input) }) { id } }"#
        let task = try await object(named: "addTask", runningDocument: document, on: session)
        return try #require(task["id"] as? String)
    }

    /// Reads the `ready` field of a task.
    ///
    /// - Parameters:
    ///   - task: The full URI of the task.
    ///   - session: The session of the board of the task.
    /// - Returns: The value of `ready`.
    /// - Throws: An error when the call fails.
    static func isReady(_ task: String, on session: KanbanGraph) async throws -> Bool {
        let document = #"{ node(id: "\#(task)") { ... on Task { ready } } }"#
        let node = try await object(named: "node", runningDocument: document, on: session)
        return try #require(node["ready"] as? Bool)
    }

    // MARK: - Tests

    @Test("A task that depends on a task of the repo beside it becomes ready when that task is done")
    func dependencyOnRepoBesideIt() async throws {
        let readiness = try await TemporaryGitRepo.withRepos(named: [Self.appName, Self.libName]) { roots in
            let app = try await IntegrationHost.session(workingDirectory: roots[0], actor: Self.actorName)
            let lib = try await IntegrationHost.session(workingDirectory: roots[1], actor: Self.actorName)
            let target = try await Self.addTask(with: "", on: lib)
            let task = try await Self.addTask(with: #", dependsOn: ["\#(target)"]"#, on: app)
            let before = try await Self.isReady(task, on: app)
            let complete = #"mutation { completeTask(input: { id: "\#(target)" }) { id } }"#
            _ = try await Self.object(named: "completeTask", runningDocument: complete, on: app)
            let after = try await Self.isReady(task, on: app)
            await app.close()
            await lib.close()
            return [before, after]
        }

        #expect(readiness == Self.readyBeforeAndAfter)
    }
}
