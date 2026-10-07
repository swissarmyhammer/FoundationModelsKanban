import Foundation
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
    private static let taskListSelection = "(excludeDone: false) { totalCount edges { node { id title } } }"

    /// The key of the `board` field that the rewrite adds around the first moved root field.
    private static let firstMoveKey = "_kanbanRoot0"

    /// A filter that does not parse.
    private static let invalidFilter = "&&"

    // MARK: - Helpers

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
        let data = try #require(KanbanGraphTests.object(of: response)["data"] as? [String: Any])
        let patch = try AddUpdateTaskTests.lastPatch(of: AddUpdateTaskTests.firstTask(in: response), in: directory)
        return (data.keys.sorted(), patch)
    }

    /// Gives the message of the first error of a response.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The message.
    private static func firstErrorMessage(of response: String) throws -> String {
        let errors = try #require(KanbanGraphTests.object(of: response)["errors"] as? [[String: Any]])
        return try #require(errors.first?["message"] as? String)
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
        arguments: [("Title", "title"), ("short_id", "shortId"), ("tag", "tags"), ("desc", "body"), ("titl", "title")]
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
        arguments: [("Filter", "filter"), ("exclude_done", "excludeDone"), ("filters", "filter"), ("label", "tag"),
                    ("filtr", "filter")]
    )
    func argumentGetsCanonicalName(written: String, canonical: String) throws {
        let rewritten = try Self.rewritten(from: #"{ board { tasks(\#(written): "x") { totalCount } } }"#)
        #expect(rewritten.text == #"{ board { tasks(\#(canonical): "x") { totalCount } } }"#)
        #expect(rewritten.rewrites == [NameRewrite(from: written, to: canonical, path: ["board", "tasks", written])])
    }

    @Test(
        "An input field in a different case, style, number, alias, or spelling gets the canonical name",
        arguments: [("Title", "title"), ("depends_on", "dependsOn"), ("tag", "tags"), ("desc", "body"),
                    ("titl", "title")]
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
        let rewritten = try Self.rewritten(from: "fragment F on Change { updates(type: [\(written)]) { id } }")
        #expect(rewritten.text == "fragment F on Change { updates(type: [\(canonical)]) { id } }")
        let path = ["F", "updates", "type", written]
        #expect(rewritten.rewrites == [NameRewrite(from: written, to: canonical, path: path)])
    }

    // MARK: - Root query field

    @Test(
        "A root query field that only Board has moves into board",
        arguments: [("tasks", "tasks", " { totalCount }"), ("Tasks", "tasks", " { totalCount }"),
                    ("next_task", "nextTask", " { id }"), ("summaries", "summary", " { total }"),
                    ("description", "body", ""), ("columnz", "columns", " { name }")]
    )
    func rootFieldMovesIntoBoard(written: String, canonical: String, selection: String) throws {
        let rewritten = try Self.rewritten(from: "{ \(written)\(selection) }")
        let field = written == canonical ? written : Self.aliased(written, as: canonical)
        #expect(rewritten.text == "{ \(Self.firstMoveKey): board { \(field)\(selection) } }")
        #expect(rewritten.rewrites == [NameRewrite(from: written, to: "board.\(canonical)", path: [written])])
    }

    @Test("A root field of the query type stays at the root")
    func queryFieldStaysAtRoot() throws {
        let rewritten = try Self.rewritten(from: "{ Board { name } }")
        #expect(rewritten.text == "{ Board: board { name } }")
        #expect(rewritten.rewrites == [NameRewrite(from: "Board", to: "board", path: ["Board"])])
    }

    @Test("{ tasks } gives the same result as { board { tasks } }, under data.tasks")
    func rootTasksGivesBoardTasksResult() async throws {
        let fixture = try QueryFixture()
        let moved = try await fixture.respond(to: "{ tasks\(Self.taskListSelection) }")
        let nested = try await fixture.respond(to: "{ board { tasks\(Self.taskListSelection) } }")
        let movedData = try #require(KanbanGraphTests.object(of: moved)["data"] as? [String: Any])
        let nestedData = try #require(KanbanGraphTests.object(of: nested)["data"] as? [String: Any])
        #expect(NSDictionary(dictionary: movedData).isEqual(to: try #require(nestedData["board"] as? [String: Any])))
    }

    @Test("The response of a root move has the move in extensions.rewrites")
    func rootMoveIsInExtensions() async throws {
        let response = try await QueryFixture().respond(to: "{ tasks { totalCount } }")
        let rewrites = #""extensions":{"rewrites":[{"from":"tasks","to":"board.tasks","path":["tasks"]}]}"#
        #expect(response == #"{"data":{"tasks":{"totalCount":2}},\#(rewrites)}"#)
    }

    @Test("An error in a moved root field has the path that the caller wrote")
    func movedFieldErrorHasCallerPath() async throws {
        let response = try await QueryFixture().respond(
            to: #"{ tasks(filter: "\#(Self.invalidFilter)") { totalCount } }"#
        )
        let object = try KanbanGraphTests.object(of: response)
        let errors = try #require(object["errors"] as? [[String: Any]])
        #expect(errors.first?["path"] as? [String] == ["tasks"])
        #expect(object["data"] as? [String: NSNull] == ["tasks": NSNull()])
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
        let errors = try #require(KanbanGraphTests.object(of: response)["errors"] as? [[String: Any]])
        let location = try #require((errors.first?["locations"] as? [[String: Int]])?.first)
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
        #expect(response.hasSuffix(#","extensions":{"rewrites":[\#(rewrite)]}}"#))
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
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        _ = try await CommentTests.run(TaskOperationTests.taskField("archiveTask", of: fixture.task), on: fixture.graph)
        #expect(try ColumnActorTests.lastPatch(of: .task(fixture.task), isDelete: true, in: directory))
    }

    @Test("restoreTask runs undeleteTask through execute")
    func restoreTaskRunsUndeleteTask() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        _ = try await CommentTests.run(TaskOperationTests.taskField("deleteTask", of: fixture.task), on: fixture.graph)
        _ = try await CommentTests.run(TaskOperationTests.taskField("restoreTask", of: fixture.task), on: fixture.graph)
        #expect(try ColumnActorTests.lastPatch(of: .task(fixture.task), isDelete: false, in: directory))
    }
}
