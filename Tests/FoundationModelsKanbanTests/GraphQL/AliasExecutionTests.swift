import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// The fixture board of one ``AliasExecutionTests`` test, in a temporary repo.
private struct AliasFixture {
    /// The temporary repo directory.
    let directory: TemporaryDirectory

    /// The engine of the repo.
    let graph: KanbanGraph

    /// The `^` ref of the fixture task.
    let task: String
}

/// Tests the Rust names of divergence.md table 4.2 and the three E5 rows through `execute`: each name does the work
/// of its canonical name on a fixture board in a temporary repo.
///
/// Each test uses the fixture logs of ``KanbanGraphTests``: the board, the column `todo`, and one task in `todo`.
@Suite("Rust names through execute", .watcherBudget)
struct AliasExecutionTests {
    /// The slug of the actor that a test adds.
    private static let alice = "alice"

    /// The mutation field that adds the actor ``alice``.
    private static let addAlice = #"addActor(input: { name: "\#(alice)" }) { id }"#

    /// The selection of a task field that gives the names of its assignees.
    private static let assigneesSelection = "{ assignees { name } }"

    /// The name of the column that a test adds.
    private static let doingName = "Doing"

    /// The slug of ``doingName``.
    private static let doingSlug = "doing"

    /// The mutation field that adds the column ``doingName``.
    private static let addDoing = #"addColumn(input: { name: "\#(doingName)" }) { id }"#

    /// The new name of the column ``doingName`` in the column test.
    private static let reviewName = "Review"

    /// The title of the second task that a test adds.
    private static let secondTitle = "Second task"

    /// The mutation field that adds a task with the title ``secondTitle`` to the default column.
    private static let addSecond = #"addTask(input: { title: "\#(secondTitle)" }) { id }"#

    /// The new title of the fixture task in the `updateTask` test.
    private static let newTitle = "New title"

    /// The body of a comment that a test adds.
    private static let commentBody = "x"

    /// The query that gives the name of each live column and the ids of its tasks, in the order of the board.
    private static let columnOrderQuery = "{ board { columns { name tasks { id } } } }"

    // MARK: - Helpers

    /// Runs a test body on the fixture board in a new temporary repo. The repo stays until the body ends.
    ///
    /// - Parameter body: The test body. It gets the fixture.
    /// - Throws: An error when the fixture cannot be made, or the error of the body.
    private static func withFixture(_ body: (AliasFixture) async throws -> Void) async throws {
        let directory = try TemporaryDirectory()
        let made = try ColumnActorTests.makeFixtureGraph(in: directory)
        let fixture = AliasFixture(
            directory: directory,
            graph: made.graph,
            task: AddUpdateTaskTests.sigilRef(of: made.task)
        )
        try await body(fixture)
        withExtendedLifetime(directory) {}
    }

    /// Runs a mutation document with some fields on an engine.
    ///
    /// - Parameters:
    ///   - fields: The mutation fields, each with its selection.
    ///   - graph: The engine.
    /// - Returns: The response JSON text.
    private static func run(_ fields: String..., on graph: KanbanGraph) async throws -> String {
        try await KanbanGraphTests.execute("mutation { \(fields.joined(separator: " ")) }", on: graph)
    }

    /// Gives the value at a path of keys in the `data` object of a response, and expects that the response has no
    /// error.
    ///
    /// - Parameters:
    ///   - keys: The keys from `data` to the value.
    ///   - response: The response JSON text.
    /// - Returns: The value.
    /// - Throws: An error when the response has no value at the path.
    private static func value(at keys: String..., in response: String) throws -> Any {
        try value(atPath: keys, in: response)
    }

    /// Gives the text at a path of keys in the `data` object of a response, and expects that the response has no
    /// error.
    ///
    /// - Parameters:
    ///   - keys: The keys from `data` to the text.
    ///   - response: The response JSON text.
    /// - Returns: The text, or `nil` when the value is not a text.
    /// - Throws: An error when the response has no value at the path.
    private static func text(at keys: String..., in response: String) throws -> String? {
        try value(atPath: keys, in: response) as? String
    }

    /// Gives the value at a path of keys in the `data` object of a response, and expects that the response has no
    /// error.
    ///
    /// - Parameters:
    ///   - keys: The keys from `data` to the value.
    ///   - response: The response JSON text.
    /// - Returns: The value.
    /// - Throws: An error when the response has no value at the path.
    private static func value(atPath keys: [String], in response: String) throws -> Any {
        #expect(try KanbanGraphTests.object(of: response)["errors"] == nil, "\(response)")
        var value: Any = try KanbanGraphTests.data(of: response)
        for key in keys {
            value = try #require((value as? [String: Any])?[key], "\(response)")
        }
        return value
    }

    /// Gives the `^` ref of the first comment in a response.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The ref.
    private static func commentRef(in response: String) throws -> String {
        let match = try #require(response.firstMatch(of: #/comment\/([0-9A-Z]{26})/#))
        return AddUpdateTaskTests.sigilRef(of: try #require(ULID(ulidString: String(match.output.1))))
    }

    /// Gives the live columns of the board, each with its name and the ids of its tasks, in the order of the board.
    ///
    /// - Parameter graph: The engine.
    /// - Returns: The column objects of the response.
    private static func columns(on graph: KanbanGraph) async throws -> [[String: Any]] {
        let response = try await KanbanGraphTests.execute(columnOrderQuery, on: graph)
        return try #require(try value(at: "board", "columns", in: response) as? [[String: Any]])
    }

    /// Gives the names of the live columns of the board, in the order of the board.
    ///
    /// - Parameter graph: The engine.
    /// - Returns: The names.
    private static func columnNames(on graph: KanbanGraph) async throws -> [String] {
        try await columns(on: graph).compactMap { column in column["name"] as? String }
    }

    /// Gives the ids of the tasks of a column, in the order of the column.
    ///
    /// - Parameters:
    ///   - name: The name of the column.
    ///   - graph: The engine.
    /// - Returns: The full ids of the tasks.
    private static func taskIDs(inColumnNamed name: String, on graph: KanbanGraph) async throws -> [String] {
        let boardColumns = try await columns(on: graph)
        let column = try #require(boardColumns.first { column in column["name"] as? String == name })
        let tasks = try #require(column["tasks"] as? [[String: Any]])
        return tasks.compactMap { task in task["id"] as? String }
    }

    /// Gives the number of live comments of a task of the fixture board.
    ///
    /// - Parameters:
    ///   - ref: The `^` ref of the task.
    ///   - graph: The engine.
    /// - Returns: The number of comments that `Task.comments` lists.
    private static func commentCount(ofTask ref: String, on graph: KanbanGraph) async throws -> Int {
        let query = #"{ board { task(id: "\#(ref)") { comments { id } } } }"#
        let response = try await KanbanGraphTests.execute(query, on: graph)
        return try #require(try value(at: "board", "task", "comments", in: response) as? [Any]).count
    }

    /// Gives the full id of a task of the fixture board from its `^` ref.
    ///
    /// - Parameters:
    ///   - ref: The `^` ref of the task.
    ///   - graph: The engine.
    /// - Returns: The full id.
    private static func id(ofTask ref: String, on graph: KanbanGraph) async throws -> String {
        let response = try await KanbanGraphTests.execute(#"{ board { task(id: "\#(ref)") { id } } }"#, on: graph)
        return try #require(try text(at: "board", "task", "id", in: response))
    }

    // MARK: - Table 4.2

    @Test("assignTask with task and assignee assigns the actor, and remove_assignee unassigns it")
    func assigneeAssignsAndRemoveAssigneeUnassigns() async throws {
        try await Self.withFixture { fixture in
            let input = #"input: { task: "\#(fixture.task)", assignee: "\#(Self.alice)" }"#
            let assign = "assignTask(\(input)) \(Self.assigneesSelection)"
            let assigned = try await Self.run(Self.addAlice, assign, on: fixture.graph)
            let names = try Self.value(at: "assignTask", "assignees", in: assigned) as? [[String: String]]
            #expect(names == [["name": Self.alice]])
            let unassign = "remove_assignee(\(input)) \(Self.assigneesSelection)"
            let removed = try await Self.run(unassign, on: fixture.graph)
            #expect((try Self.value(at: "remove_assignee", "assignees", in: removed) as? [Any])?.isEmpty == true)
        }
    }

    @Test("addTask with col adds the task to the column, and moveTask with before_id and after_id moves it")
    func colAndNeighborNamesPlaceTheTask() async throws {
        try await Self.withFixture { fixture in
            let first = try await Self.id(ofTask: fixture.task, on: fixture.graph)
            let add = #"addTask(input: { title: "\#(Self.secondTitle)", col: "todo" }) { id }"#
            let added = try await Self.run(add, on: fixture.graph)
            let second = try #require(try Self.text(at: "addTask", "id", in: added))
            let todo = KanbanGraphTests.todoName
            #expect(try await Self.taskIDs(inColumnNamed: todo, on: fixture.graph) == [first, second])
            let moved = #"task: "\#(try AddUpdateTaskTests.firstTaskRef(in: added))", col: "todo""#
            let before = #"moveTask(input: { \#(moved), before_id: "\#(fixture.task)" }) { id }"#
            _ = try Self.value(at: "moveTask", in: try await Self.run(before, on: fixture.graph))
            #expect(try await Self.taskIDs(inColumnNamed: todo, on: fixture.graph) == [second, first])
            let after = #"moveTask(input: { \#(moved), after_id: "\#(fixture.task)" }) { id }"#
            _ = try Self.value(at: "moveTask", in: try await Self.run(after, on: fixture.graph))
            #expect(try await Self.taskIDs(inColumnNamed: todo, on: fixture.graph) == [first, second])
        }
    }

    @Test("Board.task with the argument task gives the task, and after deleteTask with task it gives null")
    func taskNamesTheTask() async throws {
        try await Self.withFixture { fixture in
            let query = #"{ board { task(task: "\#(fixture.task)") { title } } }"#
            let response = try await KanbanGraphTests.execute(query, on: fixture.graph)
            #expect(try Self.text(at: "board", "task", "title", in: response) == KanbanGraphTests.taskTitle)
            let delete = #"deleteTask(input: { task: "\#(fixture.task)" }) { deleted }"#
            let deleted = try await Self.run(delete, on: fixture.graph)
            #expect(try Self.text(at: "deleteTask", "deleted", in: deleted) != nil)
            let reread = try await KanbanGraphTests.execute(query, on: fixture.graph)
            try SingleItemFieldTests.expectNullWithoutErrors(at: ["board", "task"], in: reread)
        }
    }

    @Test("updateColumn and deleteColumn with column in place of id change and delete the column")
    func columnNamesTheColumn() async throws {
        try await Self.withFixture { fixture in
            let input = #"column: "\#(Self.doingSlug)", name: "\#(Self.reviewName)""#
            let update = "updateColumn(input: { \(input) }) { name }"
            let updated = try await Self.run(Self.addDoing, update, on: fixture.graph)
            #expect(try Self.text(at: "updateColumn", "name", in: updated) == Self.reviewName)
            #expect(try await Self.columnNames(on: fixture.graph).contains(Self.reviewName))
            let delete = #"deleteColumn(input: { column: "\#(Self.doingSlug)" }) { deleted }"#
            let deleted = try await Self.run(delete, on: fixture.graph)
            #expect(try Self.text(at: "deleteColumn", "deleted", in: deleted) != nil)
            #expect(try await Self.columnNames(on: fixture.graph).contains(Self.reviewName) == false)
        }
    }

    @Test("addComment with task_id or taskId adds the comment to the task", arguments: ["task_id", "taskId"])
    func taskIDAddsTheComment(name: String) async throws {
        try await Self.withFixture { fixture in
            let add = #"addComment(input: { \#(name): "\#(fixture.task)", body: "\#(Self.commentBody)" })"#
            let response = try await Self.run("\(add) { task { title } }", on: fixture.graph)
            #expect(try Self.text(at: "addComment", "task", "title", in: response) == KanbanGraphTests.taskTitle)
        }
    }

    @Test("tasks with page_size or top_k gives that number of tasks", arguments: ["page_size", "top_k"])
    func pageSizeLimitsTheTasks(name: String) async throws {
        try await Self.withFixture { fixture in
            _ = try await Self.run(Self.addSecond, on: fixture.graph)
            let query = "{ board { tasks(\(name): 1) { edges { node { id } } } } }"
            let response = try await KanbanGraphTests.execute(query, on: fixture.graph)
            #expect((try Self.value(at: "board", "tasks", "edges", in: response) as? [Any])?.count == 1)
        }
    }

    // MARK: - E5: comment operations with the task

    @Test(
        "updateComment and deleteComment with id and the task of the comment change the comment",
        arguments: ["task_id", "task"]
    )
    func commentOperationWithItsTaskRuns(name: String) async throws {
        try await Self.withFixture { fixture in
            let add = #"addComment(input: { task: "\#(fixture.task)", body: "\#(Self.commentBody)" }) { id }"#
            let comment = try Self.commentRef(in: try await Self.run(add, on: fixture.graph))
            let input = #"id: "\#(comment)", \#(name): "\#(fixture.task)""#
            let update = #"updateComment(input: { \#(input), body: "\#(CommentTests.editedBody)" }) { body }"#
            let updated = try await Self.run(update, on: fixture.graph)
            #expect(try Self.text(at: "updateComment", "body", in: updated) == CommentTests.editedBody)
            #expect(try await Self.commentCount(ofTask: fixture.task, on: fixture.graph) == 1)
            let deleted = try await Self.run("deleteComment(input: { \(input) }) { deleted }", on: fixture.graph)
            #expect(try Self.text(at: "deleteComment", "deleted", in: deleted) != nil)
            #expect(try await Self.commentCount(ofTask: fixture.task, on: fixture.graph) == 0)
        }
    }

    @Test(
        "A comment operation with a task that is not the task of the comment gives NOT_FOUND and writes nothing",
        arguments: ["updateComment", "deleteComment", "undeleteComment"]
    )
    func commentOperationWithOtherTaskIsNotFound(mutation: String) async throws {
        let directory = try TemporaryDirectory()
        let task = AddUpdateTaskTests.sigilRef(of: try AddUpdateTaskTests.fixtureTask())
        let setup = AddUpdateTaskTests.mutation(
            of: #"addComment(input: { task: "\#(task)", body: "\#(Self.commentBody)" }) { id }"#,
            Self.addSecond
        )
        var comment = ""
        let error = try await ColumnActorTests.failure(after: setup, in: directory) { setupResponse in
            comment = try Self.commentRef(in: setupResponse)
            let other = try #require(AddUpdateTaskTests.taskULIDs(in: setupResponse).last)
            // The commit session runs the schema with no name rewrite, so the input uses the canonical name `task`.
            let input = #"id: "\#(comment)", task: "\#(AddUpdateTaskTests.sigilRef(of: other))""#
            return AddUpdateTaskTests.mutation(of: "\(mutation)(input: { \(input) }) { id }")
        }
        #expect(error == .notFound(type: .comment, reference: comment))
    }

    // MARK: - E5: updateTask with column

    @Test("updateTask with column moves the task to the end of that column, in the patch of the update")
    func updateTaskWithColumnMovesTheTask() async throws {
        try await Self.withFixture { fixture in
            let first = try await Self.id(ofTask: fixture.task, on: fixture.graph)
            let add = #"addTask(input: { title: "\#(Self.secondTitle)", column: "\#(Self.doingSlug)" }) { id }"#
            let added = try await Self.run(Self.addDoing, add, on: fixture.graph)
            let second = try #require(try Self.text(at: "addTask", "id", in: added))
            let input = #"id: "\#(fixture.task)", title: "\#(Self.newTitle)", column: "\#(Self.doingSlug)""#
            let update = "updateTask(input: { \(input) }) { column { name } }"
            let updated = try await Self.run(update, on: fixture.graph)
            #expect(try Self.text(at: "updateTask", "column", "name", in: updated) == Self.doingName)
            #expect(try await Self.taskIDs(inColumnNamed: Self.doingName, on: fixture.graph) == [second, first])
            let task = try AddUpdateTaskTests.fixtureTask()
            let patch = try #require(try AddUpdateTaskTests.lastPatch(of: task, in: fixture.directory))
            #expect(Set(patch.set.keys) == [PropertyName.title, PropertyName.column, PropertyName.ordinal])
        }
    }

    @Test("updateTask with status in place of column moves the task")
    func updateTaskWithStatusMovesTheTask() async throws {
        try await Self.withFixture { fixture in
            let update = #"updateTask(input: { task: "\#(fixture.task)", status: "\#(Self.doingSlug)" })"#
            let response = try await Self.run(Self.addDoing, "\(update) { column { name } }", on: fixture.graph)
            #expect(try Self.text(at: "updateTask", "column", "name", in: response) == Self.doingName)
        }
    }
}
