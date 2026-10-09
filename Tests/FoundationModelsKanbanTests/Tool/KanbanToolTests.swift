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
        { board { tasks(first: $first) { edges { node { title } } totalCount } } }
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

    /// The selection set of each subscription of the tests.
    static let subscriptionSelection = "{ changes { txn } }"

    /// A subscription document. The tool does not run it.
    static let subscription = "subscription \(subscriptionSelection)"

    /// The name of the subscription of ``querySubscriptionDocument``.
    static let subscriptionName = "Changes"

    /// A document with two named operations: the board-name query and a subscription.
    static let querySubscriptionDocument = """
        query \(KanbanArgumentsTests.operationName) \(KanbanGraphTests.nameQuery) \
        subscription \(subscriptionName) \(subscriptionSelection)
        """

    /// The message of the GraphQL engine for a document with two or more operations and no operation name.
    static let operationNameRequired = "Must provide operation name if query contains multiple operations."

    /// Each document and `operationName` that selects a subscription. `nil` leaves out the key. No name and a blank
    /// name select the one operation of the document.
    static let subscriptionCalls: [(document: String, operationName: String?)] =
        [(subscription, nil), (querySubscriptionDocument, subscriptionName)]
        + KanbanArgumentsTests.blankOperationNames.map { blank in (subscription, blank) }

    /// Each document and `operationName` that selects the board-name query: the one operation with each blank name,
    /// and the query of ``querySubscriptionDocument`` by its name.
    static let nameQueryCalls: [(document: String, operationName: String)] =
        KanbanArgumentsTests.blankOperationNames.map { blank in (KanbanGraphTests.nameQuery, blank) }
        + [(querySubscriptionDocument, KanbanArgumentsTests.operationName)]

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
    ///   - operationName: The text of `operationName`, or `nil` to leave out the key.
    /// - Returns: The output of the tool: the GraphQL response JSON.
    static func call(
        query document: String,
        variables: String?,
        operationName: String? = nil
    ) async throws -> String {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let tool = try makeTool(inRepoAt: directory.url)
        let json = try KanbanArgumentsTests.argumentsJSON(
            query: document,
            variables: variables,
            operationName: operationName
        )
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

    @Test(
        "A selected subscription gives SUBSCRIPTION_NOT_IN_TOOL with its message",
        arguments: subscriptionCalls
    )
    func subscriptionNotInTool(document: String, operationName: String?) async throws {
        let response = try await Self.call(query: document, variables: nil, operationName: operationName)
        let error = try Self.onlyError(of: response)
        #expect(error.code == "SUBSCRIPTION_NOT_IN_TOOL")
        #expect(error.message == KanbanError.subscriptionNotInTool.message)
    }

    @Test(
        "A blank operation name runs the one operation, and a name selects the query of a mixed document",
        arguments: nameQueryCalls
    )
    func operationNameSelectsQuery(document: String, operationName: String) async throws {
        let response = try await Self.call(query: document, variables: nil, operationName: operationName)
        #expect(response == KanbanGraphTests.nameResponse)
    }

    @Test("A query and a subscription with no operation name give the operation-name error with its code")
    func mixedDocumentNeedsOperationName() async throws {
        let response = try await Self.call(query: Self.querySubscriptionDocument, variables: nil)
        let error = try Self.onlyError(of: response)
        #expect(error.code == "GRAPHQL_VALIDATION_FAILED")
        #expect(error.message == KanbanError.graphQLValidationFailed(detail: Self.operationNameRequired).message)
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

    @Test("The history example of the description runs, and its filter keeps only the task updates")
    func historyExampleRuns() async throws {
        #expect(try Self.makeTool(inRepoAt: TemporaryDirectory().url).description.contains(KanbanTool.historyExample))
        let response = try await Self.call(query: KanbanTool.historyExample, variables: nil)
        let object = try KanbanGraphTests.object(of: response)
        let board = try #require((object["data"] as? [String: Any])?["board"] as? [String: Any])
        let history = try #require(board["history"] as? [[String: Any]], "\(response)")
        let updates = history.flatMap { change in change["updates"] as? [[String: Any]] ?? [] }
        #expect(!updates.isEmpty)
        #expect(updates.allSatisfy { update in update["type"] as? String == NodeType.task.rawValue })
        #expect(object["errors"] == nil)
    }
}
