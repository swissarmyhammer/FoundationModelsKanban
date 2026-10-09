import Foundation
import GraphQL
import Testing

@testable import FoundationModelsKanban

/// Tests the name rewrite of a parsed document (plan.md §4.5, §12 items 14 and 16): each position of a name, the
/// response key, ties, the root move, and the archive and restore verbs.
///
/// The position tests run the rewriter on the public schema and read the text that it gives. The other tests run the
/// document through the public schema or an engine.
@Suite("Name rewrite of a document")
struct NameRewriteTests {
    /// A forgiving ref of a task. The position tests do not run the document, so the ref names no task.
    private static let taskRef = "^aaaaaaa"

    /// The selection of the root query tests: the fields of a task list.
    private static let taskListSelection = " { totalCount edges { node { id title } } }"

    /// The key of the `board` field that the rewrite adds around the first moved root field.
    private static let firstMoveKey = "_kanbanRoot0"

    /// A query with the root field `tasks` in an inline fragment on the query type.
    private static let inlineFragmentQuery = "{ ... on Query { tasks { totalCount } } }"

    /// A query with the root field `tasks` in a fragment definition on the query type.
    private static let fragmentDefinitionQuery = "{ ...Q } fragment Q on Query { tasks { totalCount } }"

    /// A filter that does not parse.
    static let invalidFilter = "&&"

    /// The selection of a task field that gives the names of its tags.
    private static let tagNamesSelection = "{ tags { name } }"

    // MARK: - Helpers

    /// Gives the end of a response that has one rewrite in `extensions.rewrites`.
    ///
    /// - Parameter rewrite: The JSON object text of the rewrite.
    /// - Returns: The text after `data` in the response.
    private static func extensionsSuffix(rewrite: String) -> String {
        #","extensions":{"rewrites":[\#(rewrite)]}}"#
    }

    /// Runs the rewriter of the public schema on a document.
    ///
    /// - Parameter document: The GraphQL document.
    /// - Returns: The rewritten document.
    /// - Throws: A `GraphQLError` when the document does not parse.
    private static func rewritten(from document: String) throws -> RewrittenDocument {
        try DocumentRewriter(for: PublicSchema().schema.schema).rewrittenDocument(from: document)
    }

    /// Gives the text that the rewrite makes for one changed name of a selection field: the name of the caller as
    /// the alias, and the canonical name.
    ///
    /// - Parameters:
    ///   - written: The name that the caller wrote.
    ///   - canonical: The canonical name.
    /// - Returns: The field text, for example `taskAdd: addTask`.
    private static func aliased(_ written: String, as canonical: String) -> String {
        "\(written): \(canonical)"
    }

    /// Makes a mutation field that adds a task with ``AddUpdateTaskTests/title``, with a different mutation name.
    ///
    /// - Parameter name: The mutation name that the caller writes, for example `taskAdd`.
    /// - Returns: The field, with the selection ``AddUpdateTaskTests/idSelection``.
    private static func addTaskField(named name: String) -> String {
        name + AddUpdateTaskTests.addTask(with: "").dropFirst(MutationName.addTask.count)
    }

    /// Runs one `addTask` field with a mutation name on the fixture repo.
    ///
    /// - Parameter name: The mutation name that the caller writes.
    /// - Returns: The keys of `data` in the response, and the last patch of the added task.
    private static func addedTask(byMutationNamed name: String) async throws -> (keys: [String], patch: PatchInput?) {
        let directory = try TemporaryDirectory()
        let mutation = AddUpdateTaskTests.mutation(of: addTaskField(named: name))
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        let patch = try AddUpdateTaskTests.lastPatch(of: AddUpdateTaskTests.firstTask(in: response), in: directory)
        return (try data(of: response).keys.sorted(), patch)
    }

    /// Gives the `data` object of a response.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The `data` object.
    /// - Throws: An error when the response has no `data` object.
    static func data(of response: String) throws -> [String: Any] {
        try #require(KanbanGraphTests.object(of: response)["data"] as? [String: Any])
    }

    /// Gives the `errors` list of a response.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The errors.
    /// - Throws: An error when the response has no `errors` list.
    static func errors(of response: String) throws -> [[String: Any]] {
        try #require(KanbanGraphTests.object(of: response)["errors"] as? [[String: Any]])
    }

    /// Gives the message of the first error of a response.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The message.
    private static func firstErrorMessage(of response: String) throws -> String {
        try #require(errors(of: response).first?["message"] as? String)
    }

    /// Runs a document and a reference document on one ``QueryFixture``, and expects the same `data` from both.
    ///
    /// - Parameters:
    ///   - document: The document under test.
    ///   - reference: The document that gives the expected result.
    ///   - key: The key of the expected result in the `data` of the reference, or `nil` for all of `data`.
    /// - Returns: The `data` of the document under test.
    /// - Throws: An error when a response has no `data` object, or the reference has no object at `key`.
    @discardableResult
    private static func expectSameData(
        of document: String,
        as reference: String,
        under key: String? = nil
    ) async throws -> [String: Any] {
        let fixture = try QueryFixture()
        let actual = try await data(of: fixture.respond(to: document))
        var expected = try await data(of: fixture.respond(to: reference))
        if let key {
            expected = try #require(expected[key] as? [String: Any])
        }
        #expect(NSDictionary(dictionary: actual).isEqual(to: expected))
        return actual
    }

    /// Runs task mutations in sequence on the task of a fixture repo, through `execute`, and examines the delete
    /// flag of the last patch of the task.
    ///
    /// - Parameters:
    ///   - names: The mutation names, in the sequence that they run.
    ///   - isDelete: The delete flag that the last patch must have.
    /// - Returns: `true` when the last patch of the task has the delete flag `isDelete`.
    /// - Throws: An error when the fixture repo cannot be made, or a mutation cannot run.
    private static func lastPatch(afterRunning names: [String], isDelete: Bool) async throws -> Bool {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        for name in names {
            _ = try await CommentTests.run(TaskOperationTests.taskField(name, of: fixture.task), on: fixture.graph)
        }
        return try ColumnActorTests.lastPatch(of: .task(fixture.task), isDelete: isDelete, in: directory)
    }

    // MARK: - Top-level mutation

    @Test(
        "A top-level mutation name in a different case, style, number, word order, or spelling gets the canonical name",
        arguments: [("AddTask", "addTask"), ("add_task", "addTask"), ("addTasks", "addTask"), ("taskAdd", "addTask"),
                    ("addTsk", "addTask"), ("createTask", "addTask")]
    )
    func topLevelMutationGetsCanonicalName(written: String, canonical: String) throws {
        let rewritten = try Self.rewritten(from: #"mutation { \#(written)(input: { title: "t" }) { id } }"#)
        let field = Self.aliased(written, as: canonical)
        #expect(rewritten.text == #"mutation { \#(field)(input: { title: "t" }) { id } }"#)
        #expect(rewritten.rewrites == [NameRewrite(from: written, to: canonical, path: [written])])
    }

    @Test("A mutation that the caller gave an alias keeps the alias")
    func callerAliasIsKept() throws {
        let rewritten = try Self.rewritten(from: #"mutation { x: taskAdd(input: { title: "t" }) { id } }"#)
        #expect(rewritten.text == #"mutation { x: addTask(input: { title: "t" }) { id } }"#)
        #expect(rewritten.rewrites == [NameRewrite(from: "taskAdd", to: "addTask", path: ["x"])])
    }

    // MARK: - Field in a selection

    @Test(
        "A selection field in a different case, style, number, alias, or spelling gets the canonical name",
        arguments: [("Title", "title"), ("short_id", "shortId"), ("tag", "tags"), ("desc", "body"), ("titl", "title"),
                    ("label", "tags"), ("labels", "tags")]
    )
    func selectionFieldGetsCanonicalName(written: String, canonical: String) throws {
        let rewritten = try Self.rewritten(from: #"{ board { task(id: "\#(Self.taskRef)") { \#(written) } } }"#)
        let field = Self.aliased(written, as: canonical)
        #expect(rewritten.text == #"{ board { task(id: "\#(Self.taskRef)") { \#(field) } } }"#)
        #expect(rewritten.rewrites == [NameRewrite(from: written, to: canonical, path: ["board", "task", written])])
    }

    @Test("A selection field that the caller gave an alias keeps the alias")
    func selectionAliasIsKept() throws {
        let rewritten = try Self.rewritten(from: "{ board { label: Name } }")
        #expect(rewritten.text == "{ board { label: name } }")
        #expect(rewritten.rewrites == [NameRewrite(from: "Name", to: "name", path: ["board", "label"])])
    }

    @Test("A field in an inline fragment gets the canonical name of the type of the fragment")
    func inlineFragmentFieldGetsCanonicalName() throws {
        let rewritten = try Self.rewritten(from: #"{ node(id: "\#(Self.taskRef)") { ... on Task { Title } } }"#)
        #expect(rewritten.text == #"{ node(id: "\#(Self.taskRef)") { ... on Task { Title: title } } }"#)
    }

    // MARK: - Argument and input field

    @Test(
        "An argument in a different case, style, number, alias, or spelling gets the canonical name",
        arguments: [("tasks", "Filter", "filter"), ("task", "task_id", "id"), ("tasks", "filters", "filter"),
                    ("tasks", "filtr", "filter")]
    )
    func argumentGetsCanonicalName(field: String, written: String, canonical: String) throws {
        let rewritten = try Self.rewritten(from: #"{ board { \#(field)(\#(written): "x") { __typename } } }"#)
        #expect(rewritten.text == #"{ board { \#(field)(\#(canonical): "x") { __typename } } }"#)
        #expect(rewritten.rewrites == [NameRewrite(from: written, to: canonical, path: ["board", field, written])])
    }

    @Test(
        "An input field in a different case, style, number, alias, or spelling gets the canonical name",
        arguments: [("Title", "title"), ("depends_on", "dependsOn"), ("tag", "tags"), ("desc", "body"),
                    ("titl", "title"), ("label", "tags"), ("labels", "tags")]
    )
    func inputFieldGetsCanonicalName(written: String, canonical: String) throws {
        let rewritten = try Self.rewritten(from: #"mutation { addTask(input: { \#(written): "x" }) { id } }"#)
        #expect(rewritten.text == #"mutation { addTask(input: { \#(canonical): "x" }) { id } }"#)
        let path = ["addTask", "input", written]
        #expect(rewritten.rewrites == [NameRewrite(from: written, to: canonical, path: path)])
    }

    @Test("The task_id and status input fields of moveTask get id and column")
    func moveTaskInputAliases() throws {
        let rewritten = try Self.rewritten(
            from: #"mutation { moveTask(input: { task_id: "a", status: "b" }) { id } }"#
        )
        #expect(rewritten.text == #"mutation { moveTask(input: { id: "a", column: "b" }) { id } }"#)
    }

    // MARK: - Enum value

    @Test(
        "An enum value in a different case, number, or spelling gets the canonical value",
        arguments: [("task", "TASK"), ("Comment", "COMMENT"), ("Comments", "COMMENT"), ("COMENT", "COMMENT")]
    )
    func enumValueGetsCanonicalValue(written: String, canonical: String) throws {
        let rewriter = DocumentRewriter(for: try Self.enumArgumentSchema())
        let rewritten = try rewriter.rewrittenDocument(from: "fragment F on Query { nodes(type: [\(written)]) }")
        #expect(rewritten.text == "fragment F on Query { nodes(type: [\(canonical)]) }")
        let path = ["F", "nodes", "type", written]
        #expect(rewritten.rewrites == [NameRewrite(from: written, to: canonical, path: path)])
    }

    /// Makes a schema with one enum argument. The public schema has no enum argument, so the enum value test uses
    /// this schema: the query field `nodes` takes `type: [NodeType]`, with the values of the `NodeType` output enum.
    ///
    /// - Returns: The schema.
    /// - Throws: An error from GraphQL when a type is not valid.
    private static func enumArgumentSchema() throws -> GraphQLSchema {
        let nodeType = try GraphQLEnumType(
            name: "NodeType",
            values: [
                "BOARD": GraphQLEnumValue(value: "BOARD"),
                "COLUMN": GraphQLEnumValue(value: "COLUMN"),
                "TASK": GraphQLEnumValue(value: "TASK"),
                "TAG": GraphQLEnumValue(value: "TAG"),
                "ACTOR": GraphQLEnumValue(value: "ACTOR"),
                "COMMENT": GraphQLEnumValue(value: "COMMENT"),
            ]
        )
        let nodes = GraphQLField(type: GraphQLString, args: ["type": GraphQLArgument(type: GraphQLList(nodeType))])
        return try GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: ["nodes": nodes]))
    }

    // MARK: - Root query field

    @Test(
        "A root query field that only Board has moves into board",
        arguments: [("tasks", "tasks", " { totalCount }"), ("Tasks", "tasks", " { totalCount }"),
                    ("next_task", "nextTask", " { id }"), ("summaries", "summary", " { total }"),
                    ("description", "body", ""), ("columnz", "columns", " { name }"),
                    ("history", "history", " { txn }")]
    )
    func rootFieldMovesIntoBoard(written: String, canonical: String, selection: String) throws {
        let rewritten = try Self.rewritten(from: "{ \(written)\(selection) }")
        let field = written == canonical ? written : Self.aliased(written, as: canonical)
        #expect(rewritten.text == "{ \(Self.firstMoveKey): board { \(field)\(selection) } }")
        #expect(rewritten.rewrites == [NameRewrite(from: written, to: "board.\(canonical)", path: [written])])
    }

    @Test(
        "A root query field in an inline fragment or a fragment definition on the query type moves into board",
        arguments: [
            (Self.inlineFragmentQuery,
             "{ ... on Query { \(Self.firstMoveKey): board { tasks { totalCount } } } }", ["tasks"]),
            ("{ ... { tasks { totalCount } } }",
             "{ ... { \(Self.firstMoveKey): board { tasks { totalCount } } } }", ["tasks"]),
            (Self.fragmentDefinitionQuery,
             "{ ...Q } fragment Q on Query { \(Self.firstMoveKey): board { tasks { totalCount } } }", ["Q", "tasks"]),
        ]
    )
    func fragmentRootFieldMovesIntoBoard(document: String, text: String, path: [String]) throws {
        let rewritten = try Self.rewritten(from: document)
        #expect(rewritten.text == text)
        #expect(rewritten.rewrites == [NameRewrite(from: "tasks", to: "board.tasks", path: path)])
    }

    @Test(
        "A root query field in a fragment on the query type gives the same result as at the root, under data.tasks",
        arguments: [Self.inlineFragmentQuery, Self.fragmentDefinitionQuery]
    )
    func fragmentRootFieldGivesRootResult(document: String) async throws {
        let fragmentData = try await Self.expectSameData(of: document, as: "{ tasks { totalCount } }")
        #expect(fragmentData.keys.sorted() == ["tasks"])
    }

    @Test(
        "Two moved root fields with one response key give the merged result of board { tasks }, under data.tasks",
        arguments: ["{ tasks { totalCount } ... on Query { tasks { edges { node { id } } } } }",
                    "{ tasks { totalCount } tasks { edges { node { id } } } }"]
    )
    func sameKeyRootFieldsGiveMergedResult(document: String) async throws {
        try await Self.expectSameData(
            of: document,
            as: "{ board { tasks { totalCount edges { node { id } } } } }",
            under: "board"
        )
    }

    @Test("A root field of the query type stays at the root")
    func queryFieldStaysAtRoot() throws {
        let rewritten = try Self.rewritten(from: "{ Board { name } }")
        #expect(rewritten.text == "{ Board: board { name } }")
        #expect(rewritten.rewrites == [NameRewrite(from: "Board", to: "board", path: ["Board"])])
    }

    @Test("{ tasks } gives the same result as { board { tasks } }, under data.tasks")
    func rootTasksGivesBoardTasksResult() async throws {
        try await Self.expectSameData(
            of: "{ tasks\(Self.taskListSelection) }",
            as: "{ board { tasks\(Self.taskListSelection) } }",
            under: "board"
        )
    }

    @Test("The response of a root move has the move in extensions.rewrites")
    func rootMoveIsInExtensions() async throws {
        let response = try await QueryFixture().respond(to: "{ tasks { totalCount } }")
        let rewrites = #""extensions":{"rewrites":[{"from":"tasks","to":"board.tasks","path":["tasks"]}]}"#
        #expect(response == #"{"data":{"tasks":{"totalCount":\#(QueryResolverTests.taskCount)}},\#(rewrites)}"#)
    }

    @Test("An error in a moved root field has the path that the caller wrote")
    func movedFieldErrorHasCallerPath() async throws {
        let response = try await QueryFixture().respond(
            to: #"{ tasks(filter: "\#(Self.invalidFilter)") { totalCount } }"#
        )
        #expect(try Self.errors(of: response).first?["path"] as? [String] == ["tasks"])
        #expect(try Self.data(of: response) as? [String: NSNull] == ["tasks": NSNull()])
    }

    // MARK: - Ties and no match

    @Test("A tie gives an error that lists the matches, and the document does not run")
    func tieGivesErrorWithMatches() async throws {
        let response = try await QueryFixture().respond(to: "{ board { taskz } }")
        let message = #"The name "taskz" matches more than one name: task, tasks. Use one of these names."#
        #expect(try Self.firstErrorMessage(of: response) == message)
        #expect(try KanbanGraphTests.object(of: response)["data"] == nil)
    }

    @Test("A name with no match gives the did-you-mean error of validation")
    func noMatchGivesValidationError() async throws {
        let response = try await QueryFixture().respond(to: "{ board { nmae } }")
        let message = try Self.firstErrorMessage(of: response)
        #expect(message.hasPrefix(#"Cannot query field "nmae" on type "Board". Did you mean"#))
    }

    @Test("A validation error after a rewrite has the location in the text that the caller wrote")
    func validationErrorHasCallerLocation() async throws {
        let document = "{ board { Name nmae } }"
        let response = try await QueryFixture().respond(to: document)
        let location = try #require((Self.errors(of: response).first?["locations"] as? [[String: Int]])?.first)
        let column = try #require(document.range(of: "nmae")).lowerBound.utf16Offset(in: document) + 1
        #expect(location == ["line": 1, "column": column])
    }

    // MARK: - Through execute

    @Test("taskAdd, addTask, and createTask write the same patches, under the response key that the caller wrote")
    func mutationSpellingsWriteSamePatches() async throws {
        let taskAdd = try await Self.addedTask(byMutationNamed: "taskAdd")
        let addTask = try await Self.addedTask(byMutationNamed: "addTask")
        let createTask = try await Self.addedTask(byMutationNamed: "createTask")
        #expect([taskAdd.keys, addTask.keys, createTask.keys] == [["taskAdd"], ["addTask"], ["createTask"]])
        #expect(addTask.patch != nil)
        #expect(taskAdd.patch == addTask.patch)
        #expect(createTask.patch == addTask.patch)
    }

    @Test("The response of a rewritten mutation has the rewrite in extensions.rewrites")
    func mutationRewriteIsInExtensions() async throws {
        let response = try await ColumnActorTests.respond(
            to: AddUpdateTaskTests.mutation(of: Self.addTaskField(named: "taskAdd")),
            onFixtureIn: try TemporaryDirectory()
        )
        let rewrite = #"{"from":"taskAdd","path":["taskAdd"],"to":"addTask"}"#
        #expect(response.hasSuffix(Self.extensionsSuffix(rewrite: rewrite)))
    }

    @Test("tagTask with the input field label tags the task, and the response has label to tags in extensions.rewrites")
    func labelInputFieldIsInExtensions() async throws {
        let label = "label: \(AddUpdateTaskTests.list(of: [TagMutationTests.bug]))"
        let field = TaskOperationTests.taskField(
            MutationName.tagTask,
            of: try AddUpdateTaskTests.fixtureTask(),
            with: label,
            selecting: Self.tagNamesSelection
        )
        let response = try await ColumnActorTests.respond(
            to: AddUpdateTaskTests.mutation(of: field),
            onFixtureIn: try TemporaryDirectory()
        )
        let tagged = #"{"data":{"tagTask":{"tags":[{"name":"\#(TagMutationTests.bug)"}]}}"#
        let rewrite = #"{"from":"label","path":["tagTask","input","label"],"to":"tags"}"#
        #expect(response == tagged + Self.extensionsSuffix(rewrite: rewrite))
    }

    @Test("createBoard does not map to initBoard, and writes nothing")
    func createBoardDoesNotMapToInitBoard() async throws {
        let response = try await ColumnActorTests.respondWritingNothing(
            to: #"mutation { createBoard(input: { name: "x" }) { id } }"#,
            in: try TemporaryDirectory()
        )
        let message = try Self.firstErrorMessage(of: response)
        #expect(message.hasPrefix(#"Cannot query field "createBoard" on type "Mutation"."#))
    }

    @Test("archiveTask runs deleteTask through execute")
    func archiveTaskRunsDeleteTask() async throws {
        #expect(try await Self.lastPatch(afterRunning: ["archiveTask"], isDelete: true))
    }

    @Test("restoreTask runs undeleteTask through execute")
    func restoreTaskRunsUndeleteTask() async throws {
        #expect(try await Self.lastPatch(afterRunning: ["deleteTask", "restoreTask"], isDelete: false))
    }
}
