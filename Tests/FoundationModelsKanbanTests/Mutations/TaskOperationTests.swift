import Foundation
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the task operation mutations (plan.md §4.2, §6, §6.1): `moveTask`, `completeTask`, `assignTask`,
/// `unassignTask`, `tagTask`, `untagTask`, `deleteTask`, and `undeleteTask`.
///
/// These tests are the GraphQL form of the Rust tests of `task/mv.rs`, `task/complete.rs`, `task/assign.rs`,
/// `task/unassign.rs`, `task/tag.rs`, `task/untag.rs`, `task/delete.rs`, and `task/archive.rs`, and of the task and tag
/// dispatch tests (`dispatch/tests/tasks.rs`, `dispatch/tests/tags.rs`, `dispatch/tests/basics.rs`). The Rust archive
/// tests are the delete tests here, because a delete makes a tombstone (plan.md §12, item 21). Each test uses the
/// fixture logs of ``KanbanGraphTests``: the board, the column `todo` with order 0, and one task in `todo`.
///
/// Three rules are different from Rust. A `before` or `after` ref that names no task gives `NOT_FOUND`; the Rust code
/// put the task at the end of the column. A neighbor in a different column still puts the task at the end of the
/// column, the same as Rust. `tagTask` and `untagTask` with an empty list write nothing; the Rust code gave an error,
/// but the error catalog has no code for it, and the field returns the task. `tagTask` adds an edge and does not
/// change the body; the Rust code wrote a `#tag` marker (plan.md §6.1).
@Suite("Task operation mutations")
struct TaskOperationTests {
    /// The slug of the fixture column.
    static let todoSlug = "todo"

    /// The slug of a column that only a `moveTask` names.
    static let newColumnSlug = "in-review"

    /// The name that `moveTask` gives to the column ``newColumnSlug``: the words of the slug in title case.
    private static let newColumnName = "In Review"

    /// The order of a column that the call adds after `todo`: one more than the order 0 of `todo`.
    private static let nextColumnOrder = 1

    /// The slug of the column that ``AddUpdateTaskTests/doneColumn`` adds.
    static let doneSlug = "done"

    /// The name of the column that ``AddUpdateTaskTests/doneColumn`` adds.
    private static let doneName = "Done"

    /// The slug of a column that a test adds and then deletes.
    private static let deletedColumnSlug = "qa"

    /// The slug of a tag that a test adds.
    static let feature = "feature"

    /// The slug of a second tag that a test adds.
    private static let bug = "bug"

    /// The slug of the rename target of ``bug``.
    private static let defect = "defect"

    /// A slug that names no tag.
    private static let ghost = "ghost"

    /// The body of a task with a marker of ``AddUpdateTaskTests/markerSlug`` between two words.
    private static let markedBody = "Fix #\(AddUpdateTaskTests.markerSlug) now\n"

    /// ``markedBody`` after the remove of the marker and its adjacent space.
    private static let unmarkedBody = "Fix now\n"

    /// The variables that give ``markedBody`` to the variable `$body`.
    private static let markedBodyVariables: [String: Map] = ["body": .string(markedBody)]

    /// The selection of a task field that gives the name of each tag.
    private static let tagsSelection = "{ tags { name } }"

    /// The selection of a task field that gives the id of each assignee.
    private static let assigneesSelection = "{ assignees { id } }"

    /// The selection of a task field that gives the column name and the ordinal.
    private static let positionSelection = "{ column { name } ordinal }"

    /// The selection of a task field that gives the ordinal.
    private static let ordinalSelection = "{ ordinal }"

    /// The ordinal of the second task that ``threeTasks(in:)`` adds to `todo`.
    private static let thirdOrdinal = Ordinal(after: Ordinal(after: .first))

    /// A query that lists the tombstoned tasks of the board.
    private static let deletedTasksQuery =
        "{ board { tasks(deleted: true, excludeDone: false) { edges { node { id } } } } }"

    /// The `input` field that names the actor ``AddUpdateTaskTests/alice``.
    static let aliceInput = actorInput(naming: AddUpdateTaskTests.alice)

    /// Each mutation of this suite, with the other fields of its `input` object, for the not-found test.
    private static let mutationInputs = [
        ("moveTask", #"column: "\#(todoSlug)""#),
        ("completeTask", ""),
        ("assignTask", aliceInput),
        ("unassignTask", aliceInput),
        ("tagTask", #"tags: ["\#(bug)"]"#),
        ("untagTask", #"tags: ["\#(bug)"]"#),
        ("deleteTask", ""),
        ("undeleteTask", ""),
    ]

    // MARK: - Helpers

    /// Makes a field of a task mutation.
    ///
    /// - Parameters:
    ///   - name: The name of the mutation, for example `moveTask`.
    ///   - task: The ULID of the task. The field names it by `^` and the short id.
    ///   - input: The other fields of the `input` object, or `""` for none.
    ///   - selection: The selection of the field.
    /// - Returns: The field.
    static func taskField(
        _ name: String,
        of task: ULID,
        with input: String = "",
        selecting selection: String = AddUpdateTaskTests.idSelection
    ) -> String {
        CommentTests.nodeField(name, naming: AddUpdateTaskTests.sigilRef(of: task), with: input, selecting: selection)
    }

    /// Makes a field of a task mutation on the fixture task.
    ///
    /// - Parameters:
    ///   - name: The name of the mutation, for example `moveTask`.
    ///   - input: The other fields of the `input` object, or `""` for none.
    ///   - selection: The selection of the field.
    /// - Returns: The field.
    private static func fixtureField(
        _ name: String,
        with input: String = "",
        selecting selection: String = AddUpdateTaskTests.idSelection
    ) throws -> String {
        taskField(name, of: try AddUpdateTaskTests.fixtureTask(), with: input, selecting: selection)
    }

    /// Makes the `input` part of a `moveTask` field.
    ///
    /// - Parameters:
    ///   - column: The column ref.
    ///   - placement: The other fields of the `input` object, or `""` for none.
    /// - Returns: The `input` fields.
    static func moveInput(to column: String = todoSlug, placing placement: String = "") -> String {
        #"column: "\#(column)" \#(placement)"#
    }

    /// Makes a `before` or an `after` part of a `moveTask` input.
    ///
    /// - Parameters:
    ///   - side: `before` or `after`.
    ///   - task: The neighbor task ref as the input writes it.
    /// - Returns: The `input` field.
    private static func neighbor(_ side: String, naming task: String) -> String {
        #"\#(side): "\#(task)""#
    }

    /// Makes a `before` or an `after` part of a `moveTask` input that names a task by `^` and the short id.
    ///
    /// - Parameters:
    ///   - side: `before` or `after`.
    ///   - task: The ULID of the neighbor task.
    /// - Returns: The `input` field.
    private static func neighbor(_ side: String, of task: ULID) -> String {
        neighbor(side, naming: AddUpdateTaskTests.sigilRef(of: task))
    }

    /// Makes the `actor` part of an `assignTask` or an `unassignTask` input.
    ///
    /// - Parameter actor: The actor ref, for example the slug.
    /// - Returns: The `input` field.
    static func actorInput(naming actor: String) -> String {
        #"actor: "\#(actor)""#
    }

    /// Makes the `tags` part of a `tagTask` or an `untagTask` input.
    ///
    /// - Parameter tags: The tag refs.
    /// - Returns: The `input` field.
    static func tagsInput(_ tags: String...) -> String {
        "tags: \(AddUpdateTaskTests.list(of: tags))"
    }

    /// Adds two tasks to `todo` after the fixture task, on a new engine of the fixture repo.
    ///
    /// - Parameter directory: The temporary repo directory. The result holds it, so that the repo stays on disk while
    ///   the test uses the engine.
    /// - Returns: The directory, the engine, and the ULIDs of the three tasks, in the order of their ordinals.
    private static func threeTasks(
        in directory: TemporaryDirectory
    ) async throws -> (directory: TemporaryDirectory, graph: KanbanGraph, first: ULID, second: ULID, third: ULID) {
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let setup = AddUpdateTaskTests.mutation(
            of: "b: " + AddUpdateTaskTests.addTask(with: ""),
            "c: " + AddUpdateTaskTests.addTask(with: "")
        )
        let added = try await AddUpdateTaskTests.addedTasks(by: setup, on: fixture.graph)
        return (directory, fixture.graph, fixture.task, try #require(added.first), try #require(added.last))
    }

    /// Gives the tasks that a query of the board lists.
    ///
    /// - Parameters:
    ///   - query: The query. The default lists the live tasks in board order: column order, then ordinal.
    ///   - graph: The engine.
    /// - Returns: The ULID of each task of the response, in the order of the response.
    private static func listedTasks(
        by query: String = KanbanGraphTests.boardQuery,
        on graph: KanbanGraph
    ) async throws -> [ULID] {
        try AddUpdateTaskTests.taskULIDs(in: await KanbanGraphTests.execute(query, on: graph))
    }

    /// Runs one `moveTask` field on an engine, and gives the order of the live tasks of the board after it.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task to move.
    ///   - placement: The `before`, `after`, or `ordinal` field of the `input` object.
    ///   - graph: The engine.
    /// - Returns: The ULID of each live task of the board, in board order.
    private static func boardOrder(
        afterMoving task: ULID,
        placing placement: String,
        on graph: KanbanGraph
    ) async throws -> [ULID] {
        _ = try await CommentTests.run(taskField("moveTask", of: task, with: moveInput(placing: placement)), on: graph)
        return try await listedTasks(on: graph)
    }

    /// Runs a mutation document with fields on a new engine of the fixture repo.
    ///
    /// - Parameters:
    ///   - fields: The mutation fields, each with its selection.
    ///   - variables: The values of the variables of the document. The default is no variables.
    ///   - directory: The temporary repo directory.
    /// - Returns: The response JSON text.
    private static func respond(
        toFields fields: String...,
        with variables: [String: Map] = [:],
        in directory: TemporaryDirectory
    ) async throws -> String {
        let document = variables.isEmpty
            ? AddUpdateTaskTests.mutation(of: fields.joined(separator: " "))
            : AddUpdateTaskTests.bodyMutation(of: fields.joined(separator: " "))
        return try await ColumnActorTests.respond(to: document, with: variables, onFixtureIn: directory)
    }

    /// Runs a mutation document with one field on the fixture repo, and expects that it writes no log file.
    ///
    /// - Parameters:
    ///   - field: The mutation field, with its selection.
    ///   - setup: A document that runs before it, on the same engine, or `nil` for none.
    ///   - directory: The temporary repo directory.
    /// - Returns: The response JSON text of the field document.
    private static func respondWritingNothing(
        toField field: String,
        after setup: String? = nil,
        in directory: TemporaryDirectory
    ) async throws -> String {
        try await ColumnActorTests.respondWritingNothing(
            to: AddUpdateTaskTests.mutation(of: field),
            after: setup,
            in: directory
        )
    }

    /// Gives the response of a document with one field.
    ///
    /// - Parameter field: The JSON text of the field: its name and its value.
    /// - Returns: The response JSON text.
    private static func dataResponse(of field: String) -> String {
        #"{"data":{\#(field)}}"#
    }

    /// Gives the response of one task field that selects ``tagsSelection``.
    ///
    /// - Parameters:
    ///   - field: The name of the mutation field.
    ///   - names: The names of the tags.
    /// - Returns: The response JSON text.
    private static func tagsResponse(of field: String, named names: String...) -> String {
        let tags = names.map { name in #"{"name":"\#(name)"}"# }.joined(separator: ",")
        return dataResponse(of: #""\#(field)":{"tags":[\#(tags)]}"#)
    }

    /// Gives the JSON text of one task field that selects ``assigneesSelection``.
    ///
    /// - Parameters:
    ///   - field: The name of the mutation field.
    ///   - slugs: The slugs of the assignees.
    /// - Returns: The JSON text of the field: its name and its value.
    private static func assigneesField(of field: String, assigning slugs: String...) -> String {
        let ids = slugs.map { slug in #"{"id":"\#(ColumnActorTests.id(of: .actor(slug: slug)))"}"# }
        return #""\#(field)":{"assignees":[\#(ids.joined(separator: ","))]}"#
    }

    /// Gives a body as a JSON string value shows it, with each line end escaped.
    ///
    /// - Parameter body: The body.
    /// - Returns: The JSON text of the body, without the quotes.
    private static func jsonText(of body: String) -> String {
        body.replacingOccurrences(of: "\n", with: "\\n")
    }

    // MARK: - moveTask

    @Test("moveTask to an empty column puts the task in that column with the first ordinal")
    func moveTaskToColumn() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let input = Self.moveInput(to: Self.doneSlug)
        let move = Self.taskField("moveTask", of: fixture.task, with: input, selecting: Self.positionSelection)
        let response = try await KanbanGraphTests.execute(
            AddUpdateTaskTests.mutation(of: AddUpdateTaskTests.doneColumn, move),
            on: fixture.graph
        )
        let json = #"{"column":{"name":"\#(Self.doneName)"},"ordinal":"\#(Ordinal.first.value)"}"#
        #expect(response.hasSuffix(#""moveTask":\#(json)}}"#))
        let expected = try PatchInput(
            node: .task(fixture.task),
            set: [
                PropertyName.column: .ref(.local(.column(slug: Self.doneSlug))),
                PropertyName.ordinal: .string(Ordinal.first.value),
            ]
        )
        #expect(try AddUpdateTaskTests.lastPatch(of: fixture.task, in: directory) == expected)
    }

    @Test("moveTask with no placement puts the task after the last task of the column")
    func moveTaskAppends() async throws {
        let directory = try TemporaryDirectory()
        let tasks = try await Self.threeTasks(in: directory)
        let order = try await Self.boardOrder(afterMoving: tasks.first, placing: "", on: tasks.graph)
        #expect(order == [tasks.second, tasks.third, tasks.first])
    }

    @Test("moveTask before the first task puts the task first, and the other tasks keep their order")
    func moveTaskBeforeFirst() async throws {
        let directory = try TemporaryDirectory()
        let tasks = try await Self.threeTasks(in: directory)
        let placement = Self.neighbor("before", of: tasks.first)
        let order = try await Self.boardOrder(afterMoving: tasks.third, placing: placement, on: tasks.graph)
        #expect(order == [tasks.third, tasks.first, tasks.second])
    }

    @Test("moveTask before a task in the middle puts the task between that task and the task before it")
    func moveTaskBeforeMiddle() async throws {
        let directory = try TemporaryDirectory()
        let tasks = try await Self.threeTasks(in: directory)
        let placement = Self.neighbor("before", of: tasks.second)
        let order = try await Self.boardOrder(afterMoving: tasks.third, placing: placement, on: tasks.graph)
        #expect(order == [tasks.first, tasks.third, tasks.second])
    }

    @Test("moveTask after the last task puts the task last")
    func moveTaskAfterLast() async throws {
        let tasks = try await Self.threeTasks(in: try TemporaryDirectory())
        let placement = Self.neighbor("after", of: tasks.third)
        let order = try await Self.boardOrder(afterMoving: tasks.first, placing: placement, on: tasks.graph)
        #expect(order == [tasks.second, tasks.third, tasks.first])
    }

    @Test("moveTask after a task in the middle puts the task between that task and the task after it")
    func moveTaskAfterMiddle() async throws {
        let tasks = try await Self.threeTasks(in: try TemporaryDirectory())
        let placement = Self.neighbor("after", of: tasks.first)
        let order = try await Self.boardOrder(afterMoving: tasks.third, placing: placement, on: tasks.graph)
        #expect(order == [tasks.first, tasks.third, tasks.second])
    }

    @Test("moveTask before a task of a different column puts the task at the end of the target column")
    func moveTaskNeighborInOtherColumnAppends() async throws {
        let tasks = try await Self.threeTasks(in: try TemporaryDirectory())
        let toDone = Self.taskField("moveTask", of: tasks.third, with: Self.moveInput(to: Self.doneSlug))
        _ = try await KanbanGraphTests.execute(
            AddUpdateTaskTests.mutation(of: AddUpdateTaskTests.doneColumn, toDone),
            on: tasks.graph
        )
        let placement = Self.neighbor("before", of: tasks.third)
        let order = try await Self.boardOrder(afterMoving: tasks.first, placing: placement, on: tasks.graph)
        #expect(order == [tasks.second, tasks.first, tasks.third])
    }

    @Test("moveTask with an ordinal and a neighbor uses the ordinal")
    func moveTaskOrdinalTakesPrecedence() async throws {
        let tasks = try await Self.threeTasks(in: try TemporaryDirectory())
        let ordinal = Ordinal(after: Self.thirdOrdinal).value
        let placement = #"ordinal: "\#(ordinal)" \#(Self.neighbor("before", of: tasks.second))"#
        let input = Self.moveInput(placing: placement)
        let move = Self.taskField("moveTask", of: tasks.first, with: input, selecting: Self.ordinalSelection)
        let response = try await CommentTests.run(move, on: tasks.graph)
        #expect(response == #"{"data":{"moveTask":{"ordinal":"\#(ordinal)"}}}"#)
        #expect(try await Self.listedTasks(on: tasks.graph) == [tasks.second, tasks.third, tasks.first])
    }

    @Test("moveTask with an ordinal that is not valid gives INVALID_ORDINAL and writes nothing")
    func moveTaskInvalidOrdinal() async throws {
        let invalid = "zz"
        let move = try Self.fixtureField("moveTask", with: Self.moveInput(placing: #"ordinal: "\#(invalid)""#))
        let error = try await CommentTests.failure(of: move, in: try TemporaryDirectory())
        #expect(error == .invalidOrdinal(ordinal: invalid))
    }

    @Test("moveTask with a neighbor that names no task gives NOT_FOUND and writes nothing")
    func moveTaskUnknownNeighbor() async throws {
        let unknown = AddUpdateTaskTests.unknownTask
        let input = Self.moveInput(placing: Self.neighbor("before", naming: unknown))
        let move = try Self.fixtureField("moveTask", with: input)
        let error = try await CommentTests.failure(of: move, in: try TemporaryDirectory())
        #expect(error == .notFound(type: .task, reference: unknown))
    }

    @Test("moveTask to a slug that no column has makes the column with the slug words in title case")
    func moveTaskMakesColumn() async throws {
        let directory = try TemporaryDirectory()
        let input = Self.moveInput(to: Self.newColumnSlug)
        let move = try Self.fixtureField("moveTask", with: input, selecting: "{ column { id name order } }")
        let response = try await Self.respond(toFields: move, in: directory)
        let column = LocalRef.column(slug: Self.newColumnSlug)
        let json = #"{"id":"\#(ColumnActorTests.id(of: column))","name":"\#(Self.newColumnName)","#
            + #""order":\#(Self.nextColumnOrder)}"#
        #expect(response == #"{"data":{"moveTask":{"column":\#(json)}}}"#)
        let columnPatch = try PatchInput(
            node: column,
            set: [
                PropertyName.name: .string(Self.newColumnName),
                PropertyName.order: .json(.number(Number(Self.nextColumnOrder))),
            ]
        )
        #expect(try ColumnActorTests.patches(of: column, in: directory) == [columnPatch])
    }

    @Test("moveTask to a tombstoned column gives NOT_FOUND and writes nothing")
    func moveTaskToTombstonedColumn() async throws {
        let slug = Self.deletedColumnSlug
        let setup = AddUpdateTaskTests.mutation(
            of: #"addColumn(input: { id: "\#(slug)", name: "QA" }) { id }"#,
            CommentTests.nodeField("deleteColumn", naming: slug)
        )
        let move = AddUpdateTaskTests.mutation(of: try Self.fixtureField("moveTask", with: Self.moveInput(to: slug)))
        let error = try await ColumnActorTests.failure(of: move, after: setup, in: try TemporaryDirectory())
        #expect(error == .notFound(type: .column, reference: slug))
    }

    // MARK: - completeTask

    @Test("completeTask moves the task to the terminal column with the first ordinal of an empty column")
    func completeTaskMovesToTerminalColumn() async throws {
        let directory = try TemporaryDirectory()
        let complete = try Self.fixtureField("completeTask", selecting: Self.positionSelection)
        let response = try await Self.respond(toFields: AddUpdateTaskTests.doneColumn, complete, in: directory)
        let json = #"{"column":{"name":"\#(Self.doneName)"},"ordinal":"\#(Ordinal.first.value)"}"#
        #expect(response.hasSuffix(#""completeTask":\#(json)}}"#))
    }

    @Test("Two tasks completed one after the other are in the terminal column in that order")
    func completeTasksKeepOrder() async throws {
        let tasks = try await Self.threeTasks(in: try TemporaryDirectory())
        let mutation = AddUpdateTaskTests.mutation(
            of: AddUpdateTaskTests.doneColumn,
            "first: " + Self.taskField("completeTask", of: tasks.third, selecting: Self.ordinalSelection),
            "second: " + Self.taskField("completeTask", of: tasks.first, selecting: Self.ordinalSelection)
        )
        let response = try await KanbanGraphTests.execute(mutation, on: tasks.graph)
        let json = #""first":{"ordinal":"\#(Ordinal.first.value)"},"#
            + #""second":{"ordinal":"\#(Ordinal(after: .first).value)"}}}"#
        #expect(response.hasSuffix(json))
        #expect(try await Self.listedTasks(on: tasks.graph) == [tasks.second, tasks.third, tasks.first])
    }

    // MARK: - assignTask and unassignTask

    @Test("assignTask adds the assignee edge and returns the task with the assignee")
    func assignTask() async throws {
        let directory = try TemporaryDirectory()
        let task = try AddUpdateTaskTests.fixtureTask()
        let assign = Self.taskField("assignTask", of: task, with: Self.aliceInput, selecting: Self.assigneesSelection)
        let response = try await Self.respond(toFields: AddUpdateTaskTests.addActors, assign, in: directory)
        #expect(response.contains(Self.assigneesField(of: "assignTask", assigning: AddUpdateTaskTests.alice)))
        let added = [PropertyName.assignees: AddUpdateTaskTests.actorRefs(AddUpdateTaskTests.alice)]
        let expected = try PatchInput(node: .task(task), add: added)
        #expect(try AddUpdateTaskTests.lastPatch(of: task, in: directory) == expected)
    }

    @Test("assignTask of an actor that the task has writes nothing")
    func assignTaskIsIdempotent() async throws {
        let assign = try Self.fixtureField("assignTask", with: Self.aliceInput, selecting: Self.assigneesSelection)
        let response = try await Self.respondWritingNothing(
            toField: assign,
            after: AddUpdateTaskTests.mutation(of: AddUpdateTaskTests.addActors, assign),
            in: try TemporaryDirectory()
        )
        let assigned = Self.assigneesField(of: "assignTask", assigning: AddUpdateTaskTests.alice)
        #expect(response == Self.dataResponse(of: assigned))
    }

    @Test("assignTask with an actor that names no actor gives ACTOR_NOT_FOUND and writes nothing")
    func assignTaskUnknownActor() async throws {
        let unknown = AddUpdateTaskTests.unknownActor
        let assign = try Self.fixtureField("assignTask", with: #"actor: "\#(unknown)""#)
        let error = try await CommentTests.failure(of: assign, in: try TemporaryDirectory())
        #expect(error == .actorNotFound(reference: unknown))
    }

    @Test("unassignTask removes one assignee edge and keeps the other assignees")
    func unassignTaskKeepsOthers() async throws {
        let directory = try TemporaryDirectory()
        let task = try AddUpdateTaskTests.fixtureTask()
        let names = AddUpdateTaskTests.list(of: [AddUpdateTaskTests.alice, AddUpdateTaskTests.bob])
        let response = try await Self.respond(
            toFields: AddUpdateTaskTests.addActors,
            AddUpdateTaskTests.updateTask(task, with: "assignees: \(names)"),
            Self.taskField("unassignTask", of: task, with: Self.aliceInput, selecting: Self.assigneesSelection),
            in: directory
        )
        #expect(response.contains(Self.assigneesField(of: "unassignTask", assigning: AddUpdateTaskTests.bob)))
        let removed = [PropertyName.assignees: AddUpdateTaskTests.actorRefs(AddUpdateTaskTests.alice)]
        let expected = try PatchInput(node: .task(task), remove: removed)
        #expect(try AddUpdateTaskTests.lastPatch(of: task, in: directory) == expected)
    }

    @Test("unassignTask of an actor that the task does not have writes nothing")
    func unassignTaskIsIdempotent() async throws {
        let unassign = try Self.fixtureField("unassignTask", with: Self.aliceInput, selecting: Self.assigneesSelection)
        let response = try await Self.respondWritingNothing(
            toField: unassign,
            after: AddUpdateTaskTests.mutation(of: AddUpdateTaskTests.addActors),
            in: try TemporaryDirectory()
        )
        #expect(response == Self.dataResponse(of: Self.assigneesField(of: "unassignTask")))
    }

    // MARK: - tagTask

    @Test("tagTask with an unknown tag writes a tag set patch and adds the tag edge, and the body does not change")
    func tagTaskWithNewTag() async throws {
        let directory = try TemporaryDirectory()
        let task = try AddUpdateTaskTests.fixtureTask()
        let tag = Self.taskField("tagTask", of: task, with: Self.tagsInput(Self.feature), selecting: Self.tagsSelection)
        let response = try await Self.respond(toFields: tag, in: directory)
        #expect(response == Self.tagsResponse(of: "tagTask", named: Self.feature))
        let tagRef = LocalRef.tag(slug: Self.feature)
        let tagPatch = try PatchInput(node: tagRef, set: [PropertyName.name: .string(Self.feature)])
        #expect(try ColumnActorTests.patches(of: tagRef, in: directory) == [tagPatch])
        let added = [PropertyName.tags: AddUpdateTaskTests.tagRefs(Self.feature)]
        let expected = try PatchInput(node: .task(task), add: added)
        #expect(try AddUpdateTaskTests.lastPatch(of: task, in: directory) == expected)
    }

    @Test("tagTask with two tags adds one edge for each tag")
    func tagTaskWithTwoTags() async throws {
        let input = Self.tagsInput(Self.feature, Self.bug)
        let tag = try Self.fixtureField("tagTask", with: input, selecting: Self.tagsSelection)
        let response = try await Self.respond(toFields: tag, in: try TemporaryDirectory())
        #expect(response == Self.tagsResponse(of: "tagTask", named: Self.feature, Self.bug))
    }

    @Test("tagTask with a tag that the task has writes nothing")
    func tagTaskIsIdempotent() async throws {
        let tag = try Self.fixtureField("tagTask", with: Self.tagsInput(Self.feature), selecting: Self.tagsSelection)
        let response = try await Self.respondWritingNothing(
            toField: tag,
            after: AddUpdateTaskTests.mutation(of: tag),
            in: try TemporaryDirectory()
        )
        #expect(response == Self.tagsResponse(of: "tagTask", named: Self.feature))
    }

    @Test("tagTask with a tag URI that names no tag gives NOT_FOUND and applies none of its tags")
    func tagTaskUnknownTagURI() async throws {
        let uri = ColumnActorTests.id(of: .tag(slug: Self.ghost))
        let tag = try Self.fixtureField("tagTask", with: Self.tagsInput(Self.bug, uri))
        let error = try await CommentTests.failure(of: tag, in: try TemporaryDirectory())
        #expect(error == .notFound(type: .tag, reference: uri))
    }

    @Test("tagTask and untagTask with an empty list write nothing", arguments: ["tagTask", "untagTask"])
    func emptyTagListWritesNothing(name: String) async throws {
        let field = try Self.fixtureField(name, with: "tags: []", selecting: Self.tagsSelection)
        let response = try await Self.respondWritingNothing(toField: field, in: try TemporaryDirectory())
        #expect(response == Self.tagsResponse(of: name))
    }

    // MARK: - untagTask

    @Test("untagTask removes the tag edge that tagTask added")
    func untagTaskRemovesEdge() async throws {
        let directory = try TemporaryDirectory()
        let task = try AddUpdateTaskTests.fixtureTask()
        let input = Self.tagsInput(Self.feature)
        let response = try await Self.respond(
            toFields: Self.taskField("tagTask", of: task, with: input),
            Self.taskField("untagTask", of: task, with: input, selecting: Self.tagsSelection),
            in: directory
        )
        #expect(response.contains(#""untagTask":{"tags":[]}"#))
        let removed = [PropertyName.tags: AddUpdateTaskTests.tagRefs(Self.feature)]
        let expected = try PatchInput(node: .task(task), remove: removed)
        #expect(try AddUpdateTaskTests.lastPatch(of: task, in: directory) == expected)
    }

    @Test("untagTask on a marker tag removes the marker from the body with an edit patch")
    func untagTaskRemovesMarker() async throws {
        let directory = try TemporaryDirectory()
        let task = try AddUpdateTaskTests.fixtureTask()
        let input = Self.tagsInput(AddUpdateTaskTests.markerSlug)
        let response = try await Self.respond(
            toFields: AddUpdateTaskTests.updateTask(task, with: "body: $body"),
            Self.taskField("untagTask", of: task, with: input, selecting: "{ body tags { name } }"),
            with: Self.markedBodyVariables,
            in: directory
        )
        #expect(response.contains(#""untagTask":{"body":"\#(Self.jsonText(of: Self.unmarkedBody))","tags":[]}"#))
        let edit = PatchEdit(body: ReplayTests.diff(from: Self.markedBody, to: Self.unmarkedBody))
        let expected = try PatchInput(node: .task(task), edit: edit)
        #expect(try AddUpdateTaskTests.lastPatch(of: task, in: directory) == expected)
    }

    @Test("A tag on an edge and in a marker stays when the marker goes, and untagTask then removes the edge")
    func edgeAndMarkerTagStaysUntilBothGo() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let marker = AddUpdateTaskTests.markerSlug
        let both = AddUpdateTaskTests.updateTask(fixture.task, with: "body: $body, \(Self.tagsInput(marker))")
        _ = try await KanbanGraphTests.execute(
            AddUpdateTaskTests.bodyMutation(of: both),
            variables: Self.markedBodyVariables,
            on: fixture.graph
        )
        let unmark = AddUpdateTaskTests.updateTask(
            fixture.task,
            with: #"body: "\#(Self.jsonText(of: Self.unmarkedBody))""#,
            selecting: Self.tagsSelection
        )
        let unmarked = try await CommentTests.run(unmark, on: fixture.graph)
        #expect(unmarked == Self.tagsResponse(of: "updateTask", named: marker))
        let input = Self.tagsInput(marker)
        let untag = Self.taskField("untagTask", of: fixture.task, with: input, selecting: Self.tagsSelection)
        #expect(try await CommentTests.run(untag, on: fixture.graph) == Self.tagsResponse(of: "untagTask"))
    }

    @Test("untagTask on a tag on an edge and in a marker removes the two in one patch")
    func untagTaskRemovesEdgeAndMarker() async throws {
        let directory = try TemporaryDirectory()
        let task = try AddUpdateTaskTests.fixtureTask()
        let input = Self.tagsInput(AddUpdateTaskTests.markerSlug)
        let response = try await Self.respond(
            toFields: AddUpdateTaskTests.updateTask(task, with: "body: $body, \(input)"),
            Self.taskField("untagTask", of: task, with: input, selecting: Self.tagsSelection),
            with: Self.markedBodyVariables,
            in: directory
        )
        #expect(response.contains(#""untagTask":{"tags":[]}"#))
        let expected = try PatchInput(
            node: .task(task),
            remove: [PropertyName.tags: AddUpdateTaskTests.tagRefs(AddUpdateTaskTests.markerSlug)],
            edit: PatchEdit(body: ReplayTests.diff(from: Self.markedBody, to: Self.unmarkedBody))
        )
        #expect(try AddUpdateTaskTests.lastPatch(of: task, in: directory) == expected)
    }

    @Test("untagTask with the new slug of a renamed tag removes the edge that holds the old slug")
    func untagTaskFollowsRedirect() async throws {
        let directory = try TemporaryDirectory()
        let task = try AddUpdateTaskTests.fixtureTask()
        let response = try await Self.respond(
            toFields: Self.taskField("tagTask", of: task, with: Self.tagsInput(Self.bug)),
            #"renameTag(input: { from: "\#(Self.bug)", to: "\#(Self.defect)" }) { id }"#,
            Self.taskField("untagTask", of: task, with: Self.tagsInput(Self.defect), selecting: Self.tagsSelection),
            in: directory
        )
        #expect(response.hasSuffix(#""untagTask":{"tags":[]}}}"#))
        let removed = [PropertyName.tags: AddUpdateTaskTests.tagRefs(Self.bug)]
        let expected = try PatchInput(node: .task(task), remove: removed)
        #expect(try AddUpdateTaskTests.lastPatch(of: task, in: directory) == expected)
    }

    @Test("untagTask with a tag that the task does not have writes nothing")
    func untagTaskAbsentTag() async throws {
        let untag = try Self.fixtureField("untagTask", with: Self.tagsInput(Self.ghost), selecting: Self.tagsSelection)
        let response = try await Self.respondWritingNothing(toField: untag, in: try TemporaryDirectory())
        #expect(response == Self.tagsResponse(of: "untagTask"))
    }

    // MARK: - deleteTask and undeleteTask

    @Test("deleteTask writes delete true, the board lists do not show the task, and tasks(deleted: true) does")
    func deleteTaskHidesTask() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let delete = Self.taskField("deleteTask", of: fixture.task, selecting: "{ deleted }")
        let response = try await CommentTests.run(delete, on: fixture.graph)
        #expect(response == #"{"data":{"deleteTask":{"deleted":"\#(KanbanGraphTests.time.rfc3339)"}}}"#)
        #expect(try ColumnActorTests.lastPatch(of: .task(fixture.task), isDelete: true, in: directory))
        #expect(try await Self.listedTasks(on: fixture.graph).isEmpty)
        #expect(try await Self.listedTasks(by: Self.deletedTasksQuery, on: fixture.graph) == [fixture.task])
    }

    @Test("undeleteTask on a tombstone writes delete false, and the board lists the task again")
    func undeleteTaskRestoresTask() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let mutation = AddUpdateTaskTests.mutation(
            of: Self.taskField("deleteTask", of: fixture.task),
            Self.taskField("undeleteTask", of: fixture.task, selecting: "{ deleted }")
        )
        let response = try await KanbanGraphTests.execute(mutation, on: fixture.graph)
        #expect(response.hasSuffix(#""undeleteTask":{"deleted":null}}}"#))
        #expect(try ColumnActorTests.lastPatch(of: .task(fixture.task), isDelete: false, in: directory))
        #expect(try await Self.listedTasks(on: fixture.graph) == [fixture.task])
    }

    @Test("undeleteTask on a live task writes nothing and returns the task")
    func undeleteLiveTask() async throws {
        let undelete = try Self.fixtureField("undeleteTask", selecting: "{ title deleted }")
        let response = try await Self.respondWritingNothing(toField: undelete, in: try TemporaryDirectory())
        let json = #"{"deleted":null,"title":"\#(KanbanGraphTests.taskTitle)"}"#
        #expect(response == #"{"data":{"undeleteTask":\#(json)}}"#)
    }

    @Test("After deleteTask, a task that depends on the deleted task has no dependency and is ready")
    func deleteTaskRemovesDependency() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let setup = AddUpdateTaskTests.mutation(
            of: AddUpdateTaskTests.doneColumn,
            AddUpdateTaskTests.addTask(with: AddUpdateTaskTests.dependsOn(fixture.task))
        )
        let dependent = try #require(try await AddUpdateTaskTests.addedTasks(by: setup, on: fixture.graph).first)
        _ = try await CommentTests.run(Self.taskField("deleteTask", of: fixture.task), on: fixture.graph)
        let response = try await CommentTests.respond(
            toQueryOf: dependent,
            selecting: "{ ready dependsOn { id } }",
            on: fixture.graph
        )
        #expect(response == #"{"data":{"board":{"task":{"dependsOn":[],"ready":true}}}}"#)
    }

    // MARK: - Not found

    @Test(
        "Each task operation on a task that does not exist gives NOT_FOUND and writes nothing",
        arguments: mutationInputs
    )
    func taskOperationNotFound(name: String, input: String) async throws {
        let unknown = AddUpdateTaskTests.unknownTask
        let field = CommentTests.nodeField(name, naming: unknown, with: input)
        let error = try await CommentTests.failure(of: field, in: try TemporaryDirectory())
        #expect(error == .notFound(type: .task, reference: unknown))
    }
}
