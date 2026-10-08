import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the filter on the task queries (plan.md §6.3, §11 "Filter compatibility" and "Column atom").
///
/// Each filter example of the Rust kanban tool description
/// (`swissarmyhammer-tools/src/mcp/tools/kanban/description.md`) and of the `kanban` and `finish` skills
/// (`../skills/skills/`) is one test case. Each gives the tasks that the Rust `list tasks` gives on the same board,
/// except a `$project` example, which gives `INVALID_FILTER`. The Rust arguments `tag`, `assignee`, `column`, and
/// `excludeDone` are not in the schema: the filter selects the tasks, and a list leaves out the done tasks unless the
/// filter names `#DONE` or a column.
@Suite("Filter compatibility")
struct FilterCompatibilityTests {
    /// The ULID text of a task in `todo` with the tag `bug`, assigned to `alice`.
    static let fixLogin = "01KT7A00000000000000000001"

    /// The ULID text of a task in `todo` with the tag `feature`.
    static let addSearch = "01KT7A00000000000000000002"

    /// The ULID text of a task in `doing` with the tag `bug`, assigned to `bob`.
    static let crashOnSave = "01KT7A00000000000000000003"

    /// The ULID text of a task in `review` with the tag `feature`, assigned to `alice`.
    static let polishUI = "01KT7A00000000000000000004"

    /// The ULID text of a task in `done` with the tag `bug`, assigned to `alice`.
    static let oldBug = "01KT7A00000000000000000005"

    /// The ULID text of a task in `todo` with the tag `bug`, assigned to `alice`. It depends on ``crashOnSave``, which
    /// is not done, so it is blocked.
    static let blockedBug = "01KT7A00000000000000000006"

    /// The ULID text of a task in `todo` with the marker `#regression` in its body, and no tag edge.
    static let slowQuery = "01KT7A00000000000000000007"

    /// The slug of the first actor.
    static let alice = "alice"

    /// The slug of the second actor. Its name has a space, so the slug of the name is `bob-smith`.
    static let bob = "bob"

    /// The name of the second actor.
    static let bobName = "Bob Smith"

    /// The slug of the bug tag.
    static let bug = "bug"

    /// The slug of the feature tag.
    static let feature = "feature"

    /// The slug of the regression tag.
    static let regression = "regression"

    /// The names of the default columns, in the order of ``ReadinessFixture/defaultColumns``.
    static let columnNames = ["To Do", "Doing", "Review", "Done"]

    /// The tasks that are not done, in board order: by column, then by ULID.
    static let openTasks = [fixLogin, addSearch, blockedBug, slowQuery, crashOnSave, polishUI]

    /// The tasks of the board, in board order.
    static let allTasks = openTasks + [oldBug]

    /// The open tasks that are ready, in board order. ``blockedBug`` is blocked.
    static let readyTasks = [fixLogin, addSearch, slowQuery, crashOnSave, polishUI]

    /// The open tasks with the tag `bug`, in board order.
    static let openBugs = [fixLogin, blockedBug, crashOnSave]

    /// The tasks of `todo`, in board order.
    static let todoTasks = [fixLogin, addSearch, blockedBug, slowQuery]

    /// The filter examples of the Rust tool description and of the `kanban` and `finish` skills, each with the
    /// tasks that the Rust `list tasks` gives on the test board, in board order.
    static let listExamples: [(filter: String, tasks: [String])] = [
        ("#bug", openBugs),
        ("@alice", [fixLogin, blockedBug, polishUI]),
        ("#bug && @alice", [fixLogin, blockedBug]),
        ("#READY", readyTasks),
        ("#bug || #feature", [fixLogin, addSearch, blockedBug, crashOnSave, polishUI]),
        ("!#done && #READY", readyTasks),
        ("#bug || #regression", [fixLogin, blockedBug, slowQuery, crashOnSave]),
        ("!#done", openTasks),
    ]

    /// The `next task` examples of the `kanban` skill, each with the task that the Rust `next task` gives.
    static let nextExamples: [(filter: String, task: String)] = [
        ("#bug", fixLogin),
        ("@alice", fixLogin),
        ("#bug && @alice", fixLogin),
    ]

    /// The `$project` examples of the `kanban` skill, each with the name after its first `$`.
    static let projectExamples: [(filter: String, name: String)] = [
        ("$auth-migration", "auth-migration"),
        ("$auth-migration && @alice", "auth-migration"),
        ("$auth-migration && #bug", "auth-migration"),
        ("$auth-migration || $frontend", "auth-migration"),
        ("!$auth-migration", "auth-migration"),
    ]

    /// The `finish` skill scoped-batch calls, as filters: `%review && (<scope>)`, and
    /// `%todo && #READY && (<scope>)`. Each has the scope and the tasks of the two calls.
    static let finishExamples: [(scope: String, review: [String], todo: [String])] = [
        ("#feature", [polishUI], [addSearch]),
        ("#bug", [], [fixLogin]),
        ("#bug || #feature", [polishUI], [fixLogin, addSearch]),
    ]

    /// The arguments that a task list does not have. The filter selects the tasks (plan.md §6.3).
    static let removedArguments = [#"tag: "bug""#, #"assignee: "alice""#, #"column: "done""#, "excludeDone: false"]

    /// Each filter that names `#DONE`, with the tasks that it lists, in board order.
    static let doneExamples: [(filter: String, tasks: [String])] = [
        ("#DONE", [oldBug]),
        ("#DONE || #feature", [addSearch, polishUI, oldBug]),
        ("!#DONE", openTasks),
        ("#bug && (\(QueryFixture.liveTasksFilter))", openBugs + [oldBug]),
        ("%done && !#DONE", []),
        (QueryFixture.liveTasksFilter, allTasks),
    ]

    /// The test board: the default columns with names, two actors, three tags, and seven tasks.
    let fixture: TaskQueryFixture

    /// Makes the test board.
    ///
    /// - Throws: An error when a ULID text is not valid.
    init() throws {
        var fixture = TaskQueryFixture()
        for (order, (slug, name)) in zip(ReadinessFixture.defaultColumns, Self.columnNames).enumerated() {
            fixture.board.addColumn(withSlug: slug, named: name, order: order)
        }
        fixture.board.addActor(withSlug: Self.alice, named: "Alice")
        fixture.board.addActor(withSlug: Self.bob, named: Self.bobName)
        for tag in [Self.bug, Self.feature, Self.regression] {
            fixture.board.addTag(withSlug: tag)
        }
        try Self.addTasks(to: &fixture.board)
        self.fixture = fixture
    }

    /// Adds the seven tasks of the test board.
    ///
    /// - Parameter board: The board.
    /// - Throws: An error when a ULID text is not valid.
    private static func addTasks(to board: inout ReadinessFixture) throws {
        let todo = ReadinessFixture.todo
        let doing = ReadinessFixture.doing
        let done = ReadinessFixture.done
        try board.addTask(withULID: fixLogin, inColumn: todo, taggedWith: [bug], assignedTo: [alice])
        try board.addTask(withULID: addSearch, inColumn: todo, taggedWith: [feature])
        try board.addTask(withULID: crashOnSave, inColumn: doing, taggedWith: [bug], assignedTo: [bob])
        try board.addTask(withULID: polishUI, inColumn: "review", taggedWith: [feature], assignedTo: [alice])
        try board.addTask(withULID: oldBug, inColumn: done, taggedWith: [bug], assignedTo: [alice])
        try board.addTask(
            withULID: blockedBug,
            inColumn: todo,
            taggedWith: [bug],
            assignedTo: [alice],
            dependingOn: [crashOnSave]
        )
        let markerBody = ReadinessFixture.fields(body: "#\(regression)")
        try board.addTask(withULID: slowQuery, inColumn: todo, fields: markerBody)
    }

    // MARK: - Examples

    @Test("Each list example gives the same tasks as the Rust list tasks", arguments: listExamples)
    func listExample(filter: String, tasks: [String]) async throws {
        #expect(try await fixture.taskULIDs(selectedBy: #"filter: "\#(filter)""#) == tasks)
    }

    @Test("Each next task example gives the same task as the Rust next task", arguments: nextExamples)
    func nextExample(filter: String, task: String) async throws {
        #expect(try await fixture.nextTaskULID(withFilter: filter) == task)
    }

    @Test("Each $project example gives INVALID_FILTER that names # and %", arguments: projectExamples)
    func projectExample(filter: String, name: String) async throws {
        let error = try await fixture.kanbanError(of: #"{ board { tasks(filter: "\#(filter)") { totalCount } } }"#)
        #expect(error.code == "INVALID_FILTER")
        #expect(error.message.contains("#\(name)"))
        #expect(error.message.contains("%\(name)"))
    }

    @Test("A $project example in nextTask gives INVALID_FILTER", arguments: projectExamples)
    func projectExampleInNextTask(filter: String, name _: String) async throws {
        let error = try await fixture.kanbanError(of: #"{ board { nextTask(filter: "\#(filter)") { id } } }"#)
        #expect(error.code == "INVALID_FILTER")
    }

    @Test("%todo lists the tasks of todo, as column: \"todo\" in the kanban skill")
    func columnExample() async throws {
        #expect(try await fixture.taskULIDs(selectedBy: #"filter: "%todo""#) == Self.todoTasks)
    }

    @Test("The finish skill calls give the review and the ready todo tasks of the scope", arguments: finishExamples)
    func finishExample(scope: String, review: [String], todo: [String]) async throws {
        let reviewArguments = #"filter: "%review && (\#(scope))""#
        let todoArguments = ##"filter: "%todo && #READY && (\##(scope))""##
        #expect(try await fixture.taskULIDs(selectedBy: reviewArguments) == review)
        #expect(try await fixture.taskULIDs(selectedBy: todoArguments) == todo)
    }

    @Test("The finish skill call with no scope gives the ready todo tasks")
    func finishExampleWithNoScope() async throws {
        let ready = try await fixture.taskULIDs(selectedBy: ##"filter: "%todo && #READY""##)
        #expect(ready == [Self.fixLogin, Self.addSearch, Self.slowQuery])
        #expect(try await fixture.taskULIDs(selectedBy: #"filter: "%review""#) == [Self.polishUI])
    }

    // MARK: - Only the filter

    @Test("A task list has no scoping or excludeDone argument", arguments: removedArguments)
    func removedArgumentIsUnknown(argument: String) async throws {
        let response = try await fixture.respond(to: "{ board { tasks(\(argument)) { totalCount } } }")
        #expect(response.contains("does not have argument"))
        #expect(!response.contains(#""totalCount""#))
    }

    @Test("An OR filter ANDed with an atom keeps the parentheses of the OR")
    func orFilterAndsAsOneGroup() async throws {
        let tasks = try await fixture.taskULIDs(selectedBy: ##"filter: "(#bug || #feature) && @alice""##)
        #expect(tasks == [Self.fixLogin, Self.blockedBug, Self.polishUI])
    }

    @Test("An empty atom gives INVALID_FILTER", arguments: ["#", "@", "%"])
    func emptyAtom(sigil: String) async throws {
        let error = try await fixture.kanbanError(of: #"{ board { tasks(filter: "\#(sigil)  ") { totalCount } } }"#)
        #expect(error.code == "INVALID_FILTER")
    }

    @Test("A tag URL of the wrong type gives INVALID_FILTER")
    func tagURLOfWrongType() async throws {
        let url = QueryFixture.id(ofTask: Self.fixLogin)
        let error = try await fixture.kanbanError(of: ##"{ board { tasks(filter: "#\##(url)") { totalCount } } }"##)
        #expect(error.code == "INVALID_FILTER")
    }

    // MARK: - DONE

    @Test("With no filter, or a filter that names no column and not #DONE, the list has no done task")
    func doneTasksAreOutByDefault() async throws {
        let noFilter = "first: \(TasksArguments.defaultPageSize)"
        #expect(try await fixture.taskULIDs(selectedBy: noFilter) == Self.openTasks)
        #expect(try await fixture.taskULIDs(selectedBy: ##"filter: "#bug""##) == Self.openBugs)
    }

    @Test("A filter that names #DONE selects from the done tasks too, and the filter decides", arguments: doneExamples)
    func doneFilter(filter: String, tasks: [String]) async throws {
        #expect(try await fixture.taskULIDs(selectedBy: #"filter: "\#(filter)""#) == tasks)
    }

    @Test("nextTask with #DONE gives no task, because a done task is not READY")
    func nextTaskWithDoneFilter() async throws {
        #expect(try await fixture.nextTaskULID(withFilter: "#DONE") == nil)
        #expect(try await fixture.nextTaskULID(withFilter: "#DONE || @alice") == Self.fixLogin)
    }

    // MARK: - Column atom

    @Test("%done lists the done tasks, because a % atom names a column")
    func doneColumnAtomListsDoneTasks() async throws {
        #expect(try await fixture.taskULIDs(selectedBy: #"filter: "%done""#) == [Self.oldBug])
    }

    @Test("A column URL in the filter also names a column")
    func columnURLNamesColumn() async throws {
        let url = QueryFixture.id(of: "column/\(ReadinessFixture.done)")
        #expect(try await fixture.taskULIDs(selectedBy: #"filter: "\#(url)""#) == [Self.oldBug])
    }

    @Test("%review || (%todo && #READY) gives the tasks of both parts")
    func columnAtomsInOneFilter() async throws {
        let tasks = try await fixture.taskULIDs(selectedBy: #"filter: "%review || (%todo && #READY)""#)
        #expect(tasks == [Self.fixLogin, Self.addSearch, Self.slowQuery, Self.polishUI])
    }

    @Test("A % atom matches the column by slug and by name, in any case", arguments: ["%doing", "%DOING", "%Doing"])
    func columnAtomIgnoresCase(filter: String) async throws {
        #expect(try await fixture.taskULIDs(selectedBy: #"filter: "\#(filter)""#) == [Self.crashOnSave])
    }

    // MARK: - Other fields

    @Test("The tasks field of a column, an actor, and a tag takes a filter")
    func nodeTaskFieldsTakeFilter() async throws {
        let response = try await fixture.respond(
            to: ##"{ board { columns { tasks(filter: "#bug") { shortId } } "##
                + ##"actors { tasks(filter: "#bug") { shortId } } tags { tasks(filter: "@alice") { shortId } } } }"##
        )
        let columns = Self.taskLists(of: [[Self.fixLogin, Self.blockedBug], [Self.crashOnSave], [], [Self.oldBug]])
        let aliceBugs = [Self.fixLogin, Self.blockedBug]
        let actors = Self.taskLists(of: [aliceBugs, [Self.crashOnSave]])
        let tags = Self.taskLists(of: [aliceBugs, [Self.polishUI], []])
        let expected = #"{"data":{"board":{"columns":\#(columns),"actors":\#(actors),"tags":\#(tags)}}}"#
        #expect(response == expected)
    }

    @Test("The tasks field of an actor and a tag lists the done tasks only when the filter names #DONE")
    func nodeTaskFieldsNameDone() async throws {
        let response = try await fixture.respond(
            to: ##"{ board { actors { tasks(filter: "#DONE") { shortId } } "##
                + ##"tags { tasks(filter: "#DONE") { shortId } } } }"##
        )
        let actors = Self.taskLists(of: [[Self.oldBug], []])
        let tags = Self.taskLists(of: [[Self.oldBug], [], []])
        #expect(response == #"{"data":{"board":{"actors":\#(actors),"tags":\#(tags)}}}"#)
    }

    /// Gives the JSON of a list of nodes, each with a `tasks` list of short ids.
    ///
    /// - Parameter lists: The ULID texts of the tasks of each node, in the order of the nodes.
    /// - Returns: The JSON text, for example `[{"tasks":[{"shortId":"…"}]}]`.
    private static func taskLists(of lists: [[String]]) -> String {
        let nodes = lists.map { tasks in
            let shortIDs = tasks.map { text in #"{"shortId":"\#(ShortID(ofULIDString: text).value)"}"# }
            return #"{"tasks":[\#(shortIDs.joined(separator: ","))]}"#
        }
        return "[\(nodes.joined(separator: ","))]"
    }

    @Test("A filter that does not parse gives null for Board.tasks, and the board keeps its other fields")
    func invalidFilterKeepsBoard() async throws {
        let response = try await fixture.respond(to: ##"{ board { name tasks(filter: "#") { totalCount } } }"##)
        #expect(response.hasPrefix(#"{"data":{"board":{"name":"\#(QueryFixture.boardName)","tasks":null}},"#))
        #expect(response.contains(#""path":["board","tasks"]"#))
    }

    @Test("A filter that does not parse gives null for the tasks of a column, and the board keeps its other fields")
    func invalidFilterKeepsColumns() async throws {
        let response = try await fixture.respond(to: #"{ board { name columns { tasks(filter: "&&") { id } } } }"#)
        let nullTasks = Array(repeating: #"{"tasks":null}"#, count: ReadinessFixture.defaultColumns.count)
        let expected = #"{"data":{"board":{"name":"\#(QueryFixture.boardName)","#
            + #""columns":[\#(nullTasks.joined(separator: ","))]}},"#
        #expect(response.hasPrefix(expected))
        let error = try await fixture.kanbanError(of: #"{ board { columns { tasks(filter: "&&") { id } } } }"#)
        #expect(error.code == "INVALID_FILTER")
    }
}
