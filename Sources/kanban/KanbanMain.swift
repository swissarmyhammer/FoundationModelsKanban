import ArgumentParser
import Foundation
import FoundationModels
import FoundationModelsKanban

/// The `kanban` command-line tool (plan.md §6.7, §7.2).
///
/// The tool is a thin layer over the public API of the library. It runs against the board of the repo in the current
/// directory:
///
/// - `kanban '<document>' [--variables <json>]` runs one GraphQL document and prints the response JSON.
/// - `kanban watch '<subscription>'` prints one JSON line for each event, until SIGINT.
/// - `kanban --schema` prints the generated SDL.
///
/// A response is a success (exit status 0), also when it has GraphQL errors. Only bad arguments (`EX_USAGE`) and an
/// I/O fault (`EXIT_FAILURE`) give a different exit status.
@main
struct KanbanMain: AsyncParsableCommand {
    /// The command name, the usage text, and the subcommands. With no subcommand name, `run` gets the arguments.
    static let configuration = CommandConfiguration(
        commandName: "kanban",
        abstract: "Read and change the kanban board of the current repo with GraphQL.",
        subcommands: [RunCommand.self, WatchCommand.self],
        defaultSubcommand: RunCommand.self
    )
}

/// `kanban [run] '<document>' [--variables <json>]` and `kanban --schema`.
struct RunCommand: AsyncParsableCommand {
    /// The name and the usage text of the subcommand.
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run one GraphQL document against the board of the current directory, and print the response JSON."
    )

    /// The key of the GraphQL document in the arguments of the `kanban` tool (plan.md §7.1).
    private static let queryKey = "query"

    /// The key of the variables in the arguments of the `kanban` tool (plan.md §7.1).
    private static let variablesKey = "variables"

    /// The GraphQL document: a query or a mutation.
    @Argument(help: "The GraphQL document: a query or a mutation.")
    var document: String?

    /// The values of the variables of the document, as the text of one JSON object.
    @Option(help: "The values of the variables of the document, as one JSON object.")
    var variables: String?

    /// `true` to print the schema and to run no document.
    @Flag(help: "Print the schema in the GraphQL schema definition language (SDL).")
    var schema = false

    /// Requires one document or `--schema`, and no `--variables` without a document.
    ///
    /// - Throws: A `ValidationError` when the arguments do not give exactly one of the two.
    func validate() throws {
        guard schema != (document != nil) else {
            throw ValidationError("Give one GraphQL document, or --schema.")
        }
        guard document != nil || variables == nil else {
            throw ValidationError("--variables needs a GraphQL document.")
        }
    }

    /// Prints the schema, or runs the document through the `kanban` tool and prints the response.
    ///
    /// The tool decodes `--variables` with the forgiving decode of the tool arguments. Variables that are not one
    /// JSON object give a response with the error `INVALID_VARIABLES` (plan.md §7.1).
    ///
    /// - Throws: An I/O fault of the engine, or an error when the standard output cannot be written.
    func run() async throws {
        guard let document else {
            try StandardOutput.write(line: KanbanGraph.schemaSDL)
            return
        }
        let content = GeneratedContent(properties: [Self.queryKey: document, Self.variablesKey: variables])
        let arguments = try KanbanArguments(content)
        let response = try await CurrentBoard.withGraph { graph in
            try await KanbanTool(graph: graph).call(arguments: arguments)
        }
        try StandardOutput.write(line: response)
    }
}

/// `kanban watch '<subscription>'`.
struct WatchCommand: AsyncParsableCommand {
    /// The name and the usage text of the subcommand.
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Print one JSON line for each event of a GraphQL subscription, until SIGINT (Control-C)."
    )

    /// The GraphQL subscription document. The help gives an example with the filter of the change feed.
    @Argument(
        help: """
            The GraphQL subscription document, for example: subscription { changes(filter: "~task") { txn ops } }. \
            The filter keeps the updates whose node matches: ~type for a node type, ^id for one node, #tag for a task.
            """
    )
    var subscription: String

    /// Prints each event of the subscription as one line, until the stream ends or SIGINT comes.
    ///
    /// SIGINT closes the engine. The close ends the stream, and the command then exits with the status 0.
    ///
    /// - Throws: An I/O fault of the engine, or an error when the standard output cannot be written.
    func run() async throws {
        let interrupts = Interrupts()
        try await CurrentBoard.withGraph { graph in
            let events = try await graph.subscribe(query: subscription, variables: [:], operationName: nil)
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    await interrupts.waitForFirst()
                    await graph.close()
                }
                for try await event in events {
                    try StandardOutput.write(line: event)
                }
                group.cancelAll()
            }
        }
    }
}

/// The engine of the board of the current directory.
enum CurrentBoard {
    /// Makes an engine for the current directory, runs an operation with it, and closes it.
    ///
    /// The session actor is the OS user.
    ///
    /// - Parameter operation: The work with the engine.
    /// - Returns: The value of the operation.
    /// - Throws: An error when the engine cannot start, or the error of the operation. The engine closes also then.
    static func withGraph<Value: Sendable>(
        _ operation: (KanbanGraph) async throws -> Value
    ) async throws -> Value {
        let graph = try KanbanGraph(root: URL.currentDirectory(), actor: nil)
        do {
            let value = try await operation(graph)
            await graph.close()
            return value
        } catch {
            await graph.close()
            throw error
        }
    }
}

/// The SIGINT signals of the process, as an async stream.
///
/// A dispatch source gets each signal, and the stream gives it to a task. The value turns off the default action of
/// SIGINT for the process, which ends the process at once. Thus the command can close the engine and exit normally.
struct Interrupts: Sendable {
    /// One element for each SIGINT.
    private let signals: AsyncStream<Void>

    /// Turns off the default action of SIGINT, and starts the dispatch source.
    init() {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        source.setEventHandler {
            continuation.yield()
        }
        continuation.onTermination = { _ in
            source.cancel()
        }
        source.resume()
        signals = stream
    }

    /// Waits for the first SIGINT. A cancel of the task also ends the wait.
    func waitForFirst() async {
        var iterator = signals.makeAsyncIterator()
        await iterator.next()
    }
}

/// The standard output of the tool.
enum StandardOutput {
    /// Writes one line of text to the standard output at once, with no buffer, so that a reader sees each event when
    /// it comes.
    ///
    /// - Parameter text: The text of the line, without the end of line.
    /// - Throws: An error when the standard output cannot be written, for example a closed pipe.
    static func write(line text: String) throws {
        try FileHandle.standardOutput.write(contentsOf: Data((text + "\n").utf8))
    }
}
