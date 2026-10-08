import Foundation
import FoundationModels
import FoundationModelsExtras
import FoundationModelsKanban
import Metal
import Testing

/// Tests that Qwen 3.8 sends the values of the variables when it calls the `kanban` tool with a GraphQL document that
/// has variables (plan.md §7.1).
///
/// The schema of `variables` is `anyOf` a string and an object with no properties. The decode of `KanbanArguments`
/// accepts both forms. Thus the test accepts the string form (one JSON object in text) and an object, but each form
/// must hold the value of the variable. An empty object, `{}`, fails the test. With the on-device
/// `SystemLanguageModel`, guided generation sent `"variables": {}` in 3 of 3 runs, thus the user chose Qwen 3.8 for
/// this test.
///
/// The model is `mlx-community/Qwen3.8-27B-mxfp4`, the standard model of the sibling packages. `PooledModel` of
/// FoundationModelsExtras gives it to a `LanguageModelSession` as a FoundationModels `LanguageModel`. The first
/// generation call loads it with `MLXModelLoader` from the Hugging Face cache, and downloads it (about 14 GB) when the
/// cache does not hold it. The test uses a real model, so it is in this package and not in the unit target of the root
/// package.
///
/// As in the sibling packages, the test does not skip: a machine with no Metal device fails it. A skip gives a green
/// run that measured nothing.
@Suite("Qwen 3.8: the kanban tool gets the values of the variables")
struct ModelVariablesTests {
    /// The longest time in minutes that the test can run before Swift Testing stops it. This is a hang guard, not a
    /// speed check. It is the value of `IntegrationHangGuard` of FoundationModelsMultitool, which runs the same model:
    /// far above the slowest model load and model turn seen on a busy machine, and long enough for the first download.
    private static let timeLimitMinutes = 30

    /// The real model: Qwen 3.8 27B in the `mxfp4` quantization, the same reference as the Qwen 3.8 tests of
    /// FoundationModelsRouter and FoundationModelsMultitool.
    private static let model: ModelRef = "mlx-community/Qwen3.8-27B-mxfp4"

    /// The most tokens of one model answer. Qwen 3.8 writes its reasoning before the tool call, and the reasoning
    /// counts in this limit.
    private static let maximumResponseTokens = 4096

    /// The name of the repo directory.
    private static let repoName = "model-variables-repo"

    /// The name of the session actor of the engine.
    private static let actorName = "Integration Model"

    /// The title of the task that the model adds through the variable.
    private static let taskTitle = "Write the release notes"

    /// The name of the variable of ``document``.
    private static let variableName = "title"

    /// The key of the variables in the arguments of the `kanban` tool.
    private static let variablesKey = "variables"

    /// A mutation document with one variable: the title of the task to add.
    private static let document =
        "mutation($\(variableName): String!) { addTask(input: { title: $\(variableName) }) { id title } }"

    /// The request to the model. It gives the document and the value of its variable, and it does not tell the model
    /// how to send the variables. The schema of the tool decides that.
    private static let prompt = """
        Call the kanban tool one time. Use this GraphQL document as the query, with no change: \(document)
        Give the variable \(variableName) the value "\(taskTitle)".
        """

    /// A query that reads the title of the next task of the board.
    private static let nextTaskQuery = "{ board { nextTask { title } } }"

    // MARK: - Helpers

    /// Gives the calls of one tool in the entries of a transcript, in the order of the transcript.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool.
    ///   - entries: The entries of the transcript.
    /// - Returns: The tool calls.
    private static func calls(of toolName: String, in entries: ArraySlice<Transcript.Entry>) -> [Transcript.ToolCall] {
        entries.flatMap { entry -> [Transcript.ToolCall] in
            if case .toolCalls(let calls) = entry {
                calls.filter { call in call.toolName == toolName }
            } else {
                []
            }
        }
    }

    /// Gives the value of ``variableName`` in the `variables` argument of a tool call. The argument can be in the
    /// string form, one JSON object in text, or an object.
    ///
    /// - Parameter arguments: The arguments of the tool call.
    /// - Returns: The value of the variable.
    /// - Throws: An error from `GeneratedContent` when the arguments have no `variables`, when the text of the string
    ///   form is not JSON, or when the variables have no string value for ``variableName``, for example `{}`.
    private static func variableValue(in arguments: GeneratedContent) throws -> String {
        let variables = try arguments.value(GeneratedContent.self, forProperty: variablesKey)
        let object = if case .string(let text) = variables.kind { try GeneratedContent(json: text) } else { variables }
        return try object.value(String.self, forProperty: variableName)
    }

    // MARK: - Tests

    @Test(
        "Qwen 3.8 sends variables that hold the value, and the task is added",
        .timeLimit(.minutes(timeLimitMinutes))
    )
    func modelSendsTheValuesOfTheVariables() async throws {
        try #require(MTLCreateSystemDefaultDevice() != nil, "This machine has no Metal device, thus MLX cannot run.")
        let started = ContinuousClock.now
        let turn = try await TemporaryGitRepo.withRepo(named: Self.repoName) { root in
            let graph = try KanbanGraph(root: root, actor: Self.actorName)
            let tool = KanbanTool(graph: graph)
            let session = LanguageModelSession(model: PooledModel(ref: Self.model, pool: ModelPool()), tools: [tool])
            let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: Self.maximumResponseTokens)
            let response = try await session.respond(to: Self.prompt, options: options)
            let board = try await graph.execute(query: Self.nextTaskQuery, variables: [:], operationName: nil)
            await graph.close()
            return (calls: Self.calls(of: tool.name, in: response.transcriptEntries), board: board)
        }

        let call = try #require(turn.calls.first, "The model did not call the kanban tool.")
        // The record of the run: what the model sent, and the time of the load and the answer.
        print("QWEN38 arguments: \(call.arguments.jsonString) time: \(ContinuousClock.now - started)")
        #expect(try Self.variableValue(in: call.arguments) == Self.taskTitle)
        #expect(turn.board.contains(Self.taskTitle), "\(turn.board)")
    }
}
