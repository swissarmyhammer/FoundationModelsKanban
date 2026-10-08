import Foundation
import Testing

@testable import FoundationModelsKanban

/// The number of minutes of the time limit of each test of ``KanbanCLITests``. The constant is at file scope, because
/// the `@Suite` attribute of a type cannot read a member of the same type.
private let cliSuiteMinutes = 1

/// Tests the `kanban` command-line tool (plan.md §6.7, §7.2): each test runs the built executable as a child process in
/// a temporary git repo.
///
/// Each wait for the child has a time limit (``KanbanProcess``), and the child ends when the test ends.
@Suite("kanban CLI: execute, watch, schema", .timeLimit(.minutes(cliSuiteMinutes)))
struct KanbanCLITests {
    /// The name of the directory of the repo of each test. A board gets the name of its repo directory.
    private static let repoName = "CLIBoard"

    /// The query of the name of the board.
    private static let boardNameQuery = "{ board { name } }"

    /// A query with a variable that leaves out the name of the board when it is `false`.
    private static let variableQuery = "query($show: Boolean!) { board { name @include(if: $show) } }"

    /// The variables of ``variableQuery`` that leave out the name, as JSON text.
    private static let hideNameVariables = #"{"show": false}"#

    /// A query with a field that the schema does not have. The response has a GraphQL error.
    private static let unknownFieldQuery = "{ nope }"

    /// The option that prints the schema.
    private static let schemaOption = "--schema"

    /// The option that gives the variables.
    private static let variablesOption = "--variables"

    /// The subcommand that prints the events of a subscription.
    private static let watchCommand = "watch"

    /// The subscription of the tests: the operations of each change of a task.
    private static let taskOperations = "subscription { changes(type: [TASK]) { ops } }"

    /// The event line of a change that adds a task.
    private static let addTaskEvent = #"{"data":{"changes":{"ops":["addTask"]}}}"#

    /// The exit of a run with bad arguments: the `EX_USAGE` status of ArgumentParser.
    private static let usageExit = KanbanProcess.Exit(reason: .exit, status: EX_USAGE)

    /// The exit of a run with an I/O fault.
    private static let failureExit = KanbanProcess.Exit(reason: .exit, status: EXIT_FAILURE)

    /// The time between two commits of the second process in the `watch` test.
    private static let commitInterval = Duration.milliseconds(commitIntervalMilliseconds)

    /// The number of milliseconds of ``commitInterval``.
    private static let commitIntervalMilliseconds = 200

    // MARK: - Helpers

    /// Runs the executable in a directory until it ends.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `kanban`.
    ///   - directory: The current directory of the run.
    /// - Returns: The exit and the output of the run.
    /// - Throws: An error when the executable cannot start or does not end in the time limit.
    private static func run(_ arguments: [String], in directory: URL) async throws -> KanbanProcess.Result {
        try await KanbanProcess(withArguments: arguments, inDirectory: directory).result()
    }

    /// Makes a git repo with the name ``repoName`` in a sandbox.
    ///
    /// - Parameter sandbox: The sandbox of the test.
    /// - Returns: The root directory of the repo. It has no `.kanban/` directory.
    /// - Throws: An error when a git command fails.
    private static func makeRepo(in sandbox: GitSandbox) throws -> URL {
        try sandbox.makeRepo(named: repoName)
    }

    /// Waits for the first line of a `watch` run while a second engine adds a task again and again.
    ///
    /// The test cannot know when the child process subscribed, and a commit before the subscription gives no event.
    /// Thus the second engine adds one task each ``commitInterval`` until the first line comes. Each event is the event
    /// of a commit of the second engine.
    ///
    /// - Parameters:
    ///   - watch: The `watch` run.
    ///   - graph: The second engine on the same repo.
    /// - Returns: The first line, or `nil` when the time limit ends first.
    /// - Throws: An error from the wait, or an error of a commit of the second engine.
    private static func firstLine(of watch: KanbanProcess, committingWith graph: KanbanGraph) async throws -> String? {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await addTasksUntilCancelled(on: graph)
            }
            let line = try await watch.firstLine()
            group.cancelAll()
            try await group.waitForAll()
            return line
        }
    }

    /// Adds one task each ``commitInterval`` until the task of the call is cancelled.
    ///
    /// - Parameter graph: The engine that adds the tasks.
    /// - Throws: An error of a commit. The cancel is not an error: it ends the loop.
    private static func addTasksUntilCancelled(on graph: KanbanGraph) async throws {
        do {
            while true {
                _ = try await CrossRepoFixture.addTask(with: "", on: graph)
                try await Task.sleep(for: commitInterval)
            }
        } catch is CancellationError {
            return
        }
    }

    // MARK: - Execute

    @Test("kanban '<document>' prints the response with the name of the repo directory")
    func documentPrintsResponse() async throws {
        let sandbox = try GitSandbox()
        let result = try await Self.run([Self.boardNameQuery], in: try Self.makeRepo(in: sandbox))
        #expect(result.output == #"{"data":{"board":{"name":"\#(Self.repoName)"}}}"# + "\n")
        #expect(result.exit == .success)
    }

    @Test("kanban '<document>' --variables <json> runs the document with the variables")
    func variablesApplyToDocument() async throws {
        let sandbox = try GitSandbox()
        let arguments = [Self.variableQuery, Self.variablesOption, Self.hideNameVariables]
        let result = try await Self.run(arguments, in: try Self.makeRepo(in: sandbox))
        #expect(result.output == #"{"data":{"board":{}}}"# + "\n")
        #expect(result.exit == .success)
    }

    @Test("A response with a GraphQL error is the response of the engine, and the exit status is 0")
    func graphQLErrorExitsWithSuccess() async throws {
        let sandbox = try GitSandbox()
        let repo = try Self.makeRepo(in: sandbox)
        let graph = try GitGraphFixture.makeGraph(at: repo)
        let expected = try await KanbanGraphTests.execute(Self.unknownFieldQuery, on: graph)
        await graph.close()
        let result = try await Self.run([Self.unknownFieldQuery], in: repo)
        #expect(result.output == expected + "\n")
        #expect(result.exit == .success)
    }

    @Test("A directory that is not in a git repo is an I/O fault: the exit status is EXIT_FAILURE")
    func directoryOutsideRepoFails() async throws {
        let directory = try TemporaryDirectory()
        let result = try await Self.run([Self.boardNameQuery], in: directory.url)
        #expect(result.output.isEmpty)
        #expect(result.exit == Self.failureExit)
    }

    @Test("No document and no --schema are bad arguments: the exit status is EX_USAGE")
    func missingDocumentIsBadArguments() async throws {
        let sandbox = try GitSandbox()
        let result = try await Self.run([], in: try Self.makeRepo(in: sandbox))
        #expect(result.output.isEmpty)
        #expect(result.exit == Self.usageExit)
    }

    @Test("A document together with --schema is bad arguments: the exit status is EX_USAGE")
    func documentWithSchemaIsBadArguments() async throws {
        let sandbox = try GitSandbox()
        let result = try await Self.run([Self.boardNameQuery, Self.schemaOption], in: try Self.makeRepo(in: sandbox))
        #expect(result.output.isEmpty)
        #expect(result.exit == Self.usageExit)
    }

    // MARK: - Schema

    @Test("kanban --schema prints the generated SDL, which has type Task and no patch field")
    func schemaPrintsSDL() async throws {
        let sandbox = try GitSandbox()
        let result = try await Self.run([Self.schemaOption], in: try Self.makeRepo(in: sandbox))
        #expect(result.output == KanbanGraph.schemaSDL + "\n")
        #expect(result.output.contains("type Task "))
        #expect(!result.output.contains("patch"))
        #expect(result.exit == .success)
    }

    // MARK: - Watch

    @Test("kanban watch prints one line for a commit of a second process, and SIGINT ends it with the status 0")
    func watchPrintsCommitOfSecondProcess() async throws {
        let sandbox = try GitSandbox()
        let repo = try Self.makeRepo(in: sandbox)
        let watch = try KanbanProcess(withArguments: [Self.watchCommand, Self.taskOperations], inDirectory: repo)
        let second = try GitGraphFixture.makeGraph(at: repo, mintingFrom: GitGraphFixture.secondEngineIDs)
        let line = try await Self.firstLine(of: watch, committingWith: second)
        await second.close()
        #expect(line == Self.addTaskEvent)
        watch.interrupt()
        let result = try await watch.result()
        #expect(result.exit == .success)
    }
}
