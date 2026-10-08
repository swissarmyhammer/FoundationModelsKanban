import Foundation
import FoundationModels
import Testing

@testable import FoundationModelsKanban

/// Tests the `FoundationModels` tool: each test calls the tool with `GeneratedContent` arguments and compares the
/// JSON output (plan.md §7.1, §7.2, §11 "Tool test").
///
/// Each test uses the fixture repo of ``KanbanGraphTests``: one board, one terminal column, and one task.
@Suite("KanbanTool: calls with GeneratedContent arguments")
struct KanbanToolTests {
    /// The selection of a page of the tasks whose size is the variable `first`.
    static let pageSelection = """
        { board { tasks(first: $first, excludeDone: false) { edges { node { title } } totalCount } } }
        """

    /// A page of the tasks whose size is the required variable `first`.
    static let requiredPageQuery = "query($first: Int!) \(pageSelection)"

    /// The same page, whose variable `first` has the default value 0.
    static let defaultPageQuery = "query($first: Int = 0) \(pageSelection)"

    /// The `variables` of ``requiredPageQuery`` as a JSON object: a page of zero tasks.
    static let pageVariables = #"{"first": 0}"#

    /// The response to a page of zero tasks on the fixture board.
    static let emptyPageResponse = #"{"data":{"board":{"tasks":{"edges":[],"totalCount":1}}}}"#

    /// The `variables` JSON values that hold ``pageVariables``: an object, a JSON string, and JSON in a code fence.
    static let variablesForms = [
        pageVariables,
        #""{\"first\": 0}""#,
        #""```json\n{\"first\": 0}\n```""#,
    ]

    /// A subscription document. The tool does not run it.
    static let subscription = "subscription { changes { txn } }"

    // MARK: - Helpers

    /// Makes a tool over a test engine for a repo.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The tool.
    static func makeTool(inRepoAt root: URL) throws -> KanbanTool {
        KanbanTool(graph: try KanbanGraphTests.makeGraph(at: root))
    }

    /// Calls the tool on the fixture repo with arguments as JSON text.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - variables: The JSON value of `variables`, or `nil` to leave out the key.
    /// - Returns: The output of the tool: the GraphQL response JSON.
    static func call(query document: String, variables: String?) async throws -> String {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let tool = try makeTool(inRepoAt: directory.url)
        let json = try KanbanArgumentsTests.argumentsJSON(query: document, variables: variables)
        return try await tool.call(arguments: KanbanArguments(GeneratedContent(json: json)))
    }

    /// Reads the one error of a response that holds only errors.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The code and the message of the error.
    static func onlyError(of response: String) throws -> (code: String?, message: String?) {
        let object = try KanbanGraphTests.object(of: response)
        #expect(object["data"] == nil)
        let errors = try #require(object["errors"] as? [[String: Any]])
        let error = try #require(errors.first)
        #expect(errors.count == 1)
        return ((error["extensions"] as? [String: Any])?["code"] as? String, error["message"] as? String)
    }

    // MARK: - Tests

    @Test("The tool has the name kanban")
    func name() throws {
        #expect(try Self.makeTool(inRepoAt: TemporaryDirectory().url).name == "kanban")
    }

    @Test(
        "variables as an object, a JSON string, and JSON in a code fence reach the document",
        arguments: variablesForms
    )
    func variablesReachDocument(variables: String) async throws {
        let response = try await Self.call(query: Self.requiredPageQuery, variables: variables)
        #expect(response == Self.emptyPageResponse)
    }

    @Test(
        "variables as null, as an empty string, and as no key give the same result",
        arguments: KanbanArgumentsTests.noVariableForms
    )
    func noVariables(variables: String?) async throws {
        let response = try await Self.call(query: Self.defaultPageQuery, variables: variables)
        #expect(response == Self.emptyPageResponse)
    }

    @Test("A string that is not a JSON object gives INVALID_VARIABLES with the two correct forms")
    func invalidVariables() async throws {
        let response = try await Self.call(query: Self.requiredPageQuery, variables: #""[0]""#)
        let error = try Self.onlyError(of: response)
        #expect(error.code == "INVALID_VARIABLES")
        #expect(error.message == KanbanError.invalidVariables(received: "text that holds a list").message)
    }

    @Test("A subscription gives SUBSCRIPTION_NOT_IN_TOOL, and the message names history(since:)")
    func subscriptionNotInTool() async throws {
        let response = try await Self.call(query: Self.subscription, variables: nil)
        let error = try Self.onlyError(of: response)
        #expect(error.code == "SUBSCRIPTION_NOT_IN_TOOL")
        #expect(error.message?.contains("history(since:") == true)
    }

    @Test("The example query of the description runs and returns data")
    func exampleQueryRuns() async throws {
        #expect(try Self.makeTool(inRepoAt: TemporaryDirectory().url).description.contains(KanbanTool.exampleQuery))
        let response = try await Self.call(query: KanbanTool.exampleQuery, variables: nil)
        let object = try KanbanGraphTests.object(of: response)
        let board = try #require((object["data"] as? [String: Any])?["board"] as? [String: Any])
        #expect(board["name"] as? String == KanbanGraphTests.boardName)
        #expect(object["errors"] == nil)
    }
}
