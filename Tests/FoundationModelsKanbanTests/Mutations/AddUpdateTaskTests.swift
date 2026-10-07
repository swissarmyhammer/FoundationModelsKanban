import Foundation
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests `addTask` and `updateTask` (plan.md §4.2, §5.5, §6, §6.1, §3.3 rule 6).
///
/// These tests are the GraphQL form of the Rust add and update tests (`task/add.rs`, `task/update.rs`, and the task,
/// tag, collection, and short id dispatch tests): field clear and no change, assignees, tags, dependencies, and no
/// partial write. Each test uses the fixture logs of ``KanbanGraphTests``: the board, the column `todo` with order 0,
/// and one task in `todo`. The `todo` column is the terminal column, so a test that needs a task that is not done
/// first adds the column ``doneColumn``.
///
/// The Rust tests of the scalar-or-array list input and of the `project` field are not ported: GraphQL types replace
/// the list forms, and tags replace projects (plan.md §11, §12 item 1).
@Suite("addTask and updateTask")
struct AddUpdateTaskTests {
    /// The title of a task that a test adds.
    static let title = "Write the guide"

    /// The new title of the fixture task in an update test.
    private static let newTitle = "Port the lexer"

    /// The body that a test gives to a task.
    private static let body = "- [ ] draft the guide\n"

    /// The variables that give ``body`` to the variable `$body`.
    private static let bodyVariables: [String: Map] = ["body": .string(body)]

    /// The name of a column with a lower order than `todo`.
    private static let backlogName = "Backlog"

    /// The order of ``backlogName``: less than the order 0 of `todo`.
    private static let backlogOrder = -1

    /// The name of a column that a test adds after `todo`.
    private static let doingName = "Doing"

    /// The mutation field that adds a terminal column after `todo`, so that a task in `todo` is not done.
    private static let doneColumn = #"addColumn(input: { name: "Done" }) { id }"#

    /// The slug of the first actor that a test adds.
    private static let alice = "alice"

    /// The slug of the second actor that a test adds.
    private static let bob = "bob"

    /// The mutation fields that add the actors ``alice`` and ``bob``.
    private static let addActors = #"a: addActor(input: { name: "\#(alice)" }) { id } "#
        + #"b: addActor(input: { name: "\#(bob)" }) { id }"#

    /// A ref that names no actor.
    private static let unknownActor = "nobody"

    /// A tag name with a space and capitals.
    private static let tagName = "Bug Fix"

    /// The stored name of ``tagName``: the tag name rule changes the space to `_`.
    private static let storedTagName = "Bug_Fix"

    /// The slug of ``tagName``.
    private static let tagSlug = "bug-fix"

    /// The slug of a tag that only a body marker names.
    private static let markerSlug = "ui"

    /// The slug of a tombstoned tag of the fixture.
    private static let oldSlug = "old"

    /// The tag names of the tag replace test before the update.
    private static let firstTags = ["red", "green"]

    /// The tag names of the tag replace test after the update.
    private static let secondTags = ["green", "blue"]

    /// A name that gives an empty slug.
    private static let emptySlugName = "---"

    /// A text that is not a valid ordinal.
    private static let invalidOrdinal = "zz"

    /// The full URI of a task of a different board.
    private static let remoteTask = "kanban://github.com/o/other/task/01K6X2ABCDEFGHJKMNPQRSTVWX"

    /// A ref that names no task.
    private static let unknownTask = "^zzzzzzz"

    /// The selection of a mutation field that gives only the id.
    static let idSelection = "{ id }"

    /// The number of extra ULIDs that the scripted source of the mint test gives for the event ids.
    private static let spareULIDCount = 8

    /// The ordinal of a task that a test adds to `todo`: after the first ordinal of the fixture task.
    private static let nextOrdinal = Ordinal(after: .first)

    /// The `set` part of the patch of a task that a test adds to `todo` with no other field.
    private static let addedValues: [String: PatchValue] = [
        PropertyName.title: .string(title),
        PropertyName.column: .ref(.local(KanbanGraphTests.todoColumn)),
        PropertyName.ordinal: .string(nextOrdinal.value),
    ]

    // MARK: - Helpers

    /// Makes a mutation document from its fields.
    ///
    /// - Parameter fields: The mutation fields, each with its selection.
    /// - Returns: The document.
    static func mutation(of fields: String...) -> String {
        "mutation { \(fields.joined(separator: " ")) }"
    }

    /// Makes a mutation document with the variable `$body` from its fields.
    ///
    /// - Parameter fields: The mutation fields, each with its selection.
    /// - Returns: The document.
    static func bodyMutation(of fields: String...) -> String {
        "mutation($body: String) { \(fields.joined(separator: " ")) }"
    }

    /// Makes an `addTask` field with the title ``title``.
    ///
    /// - Parameters:
    ///   - input: The other fields of the `input` object, or `""` for none.
    ///   - selection: The selection of the field.
    /// - Returns: The field.
    static func addTask(with input: String, selecting selection: String = idSelection) -> String {
        #"addTask(input: { title: "\#(title)", \#(input) }) \#(selection)"#
    }

    /// Makes an `updateTask` field.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task. The field names it by `^` and the short id.
    ///   - input: The other fields of the `input` object, or `""` for none.
    ///   - selection: The selection of the field.
    /// - Returns: The field.
    private static func updateTask(
        _ task: ULID,
        with input: String,
        selecting selection: String = idSelection
    ) -> String {
        #"updateTask(input: { id: "\#(sigilRef(of: task))", \#(input) }) \#(selection)"#
    }

    /// Makes the `dependsOn` part of an `input` object with one task.
    ///
    /// - Parameter task: The ULID of the task. The input names it by `^` and the short id.
    /// - Returns: The `input` field.
    private static func dependsOn(_ task: ULID) -> String {
        #"dependsOn: ["\#(sigilRef(of: task))"]"#
    }

    /// Gives the `^` short id ref of a task or a comment.
    ///
    /// - Parameter task: The ULID of the task or the comment.
    /// - Returns: The ref, for example `^ajv8v4t`.
    static func sigilRef(of task: ULID) -> String {
        QueryFixture.sigilRef(of: task.ulidString)
    }

    /// Gives the full URI of a task of the fixture board.
    ///
    /// - Parameter task: The ULID of the task.
    /// - Returns: The URI text.
    private static func id(of task: ULID) -> String {
        ColumnActorTests.id(of: .task(task))
    }

    /// Gives the ULID of each task URI in a response, in the order of the response.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The ULIDs.
    private static func taskULIDs(in response: String) throws -> [ULID] {
        try response.matches(of: #/task\/([0-9A-Z]{26})/#).map { match in
            try #require(ULID(ulidString: String(match.output.1)))
        }
    }

    /// Gives the ULID of the first task URI in a response.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The ULID.
    static func firstTask(in response: String) throws -> ULID {
        try #require(try taskULIDs(in: response).first)
    }

    /// Gives the ULID of the fixture task. The fixture logs are deterministic, so a write to a new directory gives
    /// the same ULID as the fixture of each test.
    ///
    /// - Returns: The ULID.
    static func fixtureTask() throws -> ULID {
        try KanbanGraphTests.writeFixture(inRepoAt: TemporaryDirectory().url).task
    }

    /// Gives the last patch of the log of a task.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task.
    ///   - directory: The temporary repo directory.
    /// - Returns: The patch, or `nil` when the task has no log.
    private static func lastPatch(of task: ULID, in directory: TemporaryDirectory) throws -> PatchInput? {
        try ColumnActorTests.patches(of: .task(task), in: directory).last
    }

    /// Gives the stored refs of actors.
    ///
    /// - Parameter slugs: The slugs of the actors.
    /// - Returns: The local refs.
    private static func actorRefs(_ slugs: String...) -> [StoredRef] {
        slugs.map { slug in .local(.actor(slug: slug)) }
    }

    /// Gives the stored refs of tags.
    ///
    /// - Parameter slugs: The slugs of the tags.
    /// - Returns: The local refs.
    private static func tagRefs(_ slugs: String...) -> [StoredRef] {
        slugs.map { slug in .local(.tag(slug: slug)) }
    }

    /// Gives a GraphQL list of string values.
    ///
    /// - Parameter values: The values.
    /// - Returns: The list text, for example `["a", "b"]`.
    private static func list(of values: [String]) -> String {
        "[" + values.map { value in #""\#(value)""# }.joined(separator: ", ") + "]"
    }

    /// Runs a setup document that adds tasks on an engine, and gives the ULIDs of the added tasks.
    ///
    /// - Parameters:
    ///   - setup: The setup document.
    ///   - graph: The engine.
    /// - Returns: The ULID of each task URI of the response, in the order of the response.
    private static func addedTasks(by setup: String, on graph: KanbanGraph) async throws -> [ULID] {
        try taskULIDs(in: await KanbanGraphTests.execute(setup, on: graph))
    }

    /// Runs a dependency cycle test: the setup adds a task that depends on the fixture task, and the mutation that
    /// the closure makes from the added task closes the cycle.
    ///
    /// - Parameters:
    ///   - directory: The temporary repo directory.
    ///   - closeCycle: Gives the `updateTask` input of the fixture task from the added task.
    /// - Returns: The error of the mutation, and the path that the error must give.
    private static func cycleFailure(
        in directory: TemporaryDirectory,
        closingWith closeCycle: @escaping (ULID) -> String
    ) async throws -> (error: KanbanError, expected: KanbanError) {
        let task = try fixtureTask()
        let setup = mutation(of: addTask(with: dependsOn(task)))
        var dependent: ULID?
        let error = try await ColumnActorTests.failure(after: setup, in: directory) { setupResponse in
            let added = try firstTask(in: setupResponse)
            dependent = added
            return mutation(of: updateTask(task, with: closeCycle(added)))
        }
        let other = try #require(dependent)
        let path = [sigilRef(of: task), sigilRef(of: other), sigilRef(of: task)]
        return (error, .dependencyCycle(path: path))
    }

    // MARK: - addTask

    @Test("addTask returns the new task with id, shortId, ready, and blockedBy, and writes one task patch")
    func addTaskReturnsNewTask() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let selection = "{ id shortId title ordinal ready blockedBy { id } column { name } }"
        let response = try await KanbanGraphTests.execute(
            Self.mutation(of: Self.addTask(with: "", selecting: selection)),
            on: fixture.graph
        )
        let task = try Self.firstTask(in: response)
        #expect(ShortID(of: task) != ShortID(of: fixture.task))
        let json = #"{"blockedBy":[],"column":{"name":"\#(KanbanGraphTests.todoName)"},"#
            + #""id":"\#(Self.id(of: task))","ordinal":"\#(Self.nextOrdinal.value)","ready":true,"#
            + #""shortId":"\#(ShortID(of: task).value)","title":"\#(Self.title)"}"#
        #expect(response == #"{"data":{"addTask":\#(json)}}"#)
        let expected = try PatchInput(node: .task(task), set: Self.addedValues)
        #expect(try ColumnActorTests.patches(of: .task(task), in: directory) == [expected])
    }

    @Test("addTask with no column puts the task in the column with the minimum order")
    func addTaskUsesFirstColumn() async throws {
        let directory = try TemporaryDirectory()
        let backlog = #"addColumn(input: { name: "\#(Self.backlogName)", order: \#(Self.backlogOrder) }) "#
            + Self.idSelection
        let mutation = Self.mutation(of: backlog, Self.addTask(with: "", selecting: "{ column { name } }"))
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        #expect(response.hasSuffix(#""addTask":{"column":{"name":"\#(Self.backlogName)"}}}}"#))
    }

    @Test("addTask with a column puts the task in that column")
    func addTaskUsesGivenColumn() async throws {
        let directory = try TemporaryDirectory()
        let doing = #"addColumn(input: { name: "\#(Self.doingName)" }) { id }"#
        let add = Self.addTask(with: #"column: "doing""#, selecting: "{ column { name } }")
        let response = try await ColumnActorTests.respond(to: Self.mutation(of: doing, add), onFixtureIn: directory)
        #expect(response.hasSuffix(#""addTask":{"column":{"name":"\#(Self.doingName)"}}}}"#))
    }

    @Test("addTask with a column that does not exist gives NOT_FOUND and writes nothing")
    func addTaskUnknownColumn() async throws {
        let directory = try TemporaryDirectory()
        let error = try await ColumnActorTests.failure(
            of: Self.mutation(of: Self.addTask(with: #"column: "qa""#)),
            in: directory
        )
        #expect(error == .notFound(type: .column, reference: "qa"))
    }

    @Test("addTask on a board with no live column gives NOT_FOUND and writes no task")
    func addTaskOnBoardWithNoColumn() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        var ids = FixedULIDSource(at: ReplayTests.date(atStep: .zero))
        let board = try PatchInput(node: .board, set: [PropertyName.name: .string(KanbanGraphTests.boardName)])
        try KanbanGraphTests.append(board, mintingFrom: &ids, to: log)
        var session = try await CommitTests.makeSession(of: log)
        let add = Self.mutation(of: Self.addTask(with: ""))
        let result = try await ColumnActorTests.result(of: add, in: &session)
        #expect(result.errors.first?.originalError as? KanbanError == .notFound(type: .column, reference: ""))
        #expect(try BoardMutationTests.storedRefs(inRepoAt: directory.url) == [.board])
    }

    @Test("Two tasks added in one call get increasing ordinals at the end of the column")
    func addTasksAppendInOrder() async throws {
        let directory = try TemporaryDirectory()
        let mutation = Self.mutation(
            of: "first: " + Self.addTask(with: "", selecting: "{ ordinal }"),
            "second: " + Self.addTask(with: "", selecting: "{ ordinal }")
        )
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        let second = Ordinal(after: Self.nextOrdinal)
        let json = #"{"first":{"ordinal":"\#(Self.nextOrdinal.value)"},"#
            + #""second":{"ordinal":"\#(second.value)"}}"#
        #expect(response == #"{"data":\#(json)}"#)
    }

    @Test("addTask with an ordinal stores that ordinal")
    func addTaskWithOrdinal() async throws {
        let directory = try TemporaryDirectory()
        let ordinal = Ordinal(before: .first).value
        let add = Self.addTask(with: #"ordinal: "\#(ordinal)""#, selecting: "{ ordinal }")
        let response = try await ColumnActorTests.respond(to: Self.mutation(of: add), onFixtureIn: directory)
        #expect(response == #"{"data":{"addTask":{"ordinal":"\#(ordinal)"}}}"#)
    }

    @Test("addTask with an ordinal that is not valid gives INVALID_ORDINAL and writes nothing")
    func addTaskInvalidOrdinal() async throws {
        let directory = try TemporaryDirectory()
        let error = try await ColumnActorTests.failure(
            of: Self.mutation(of: Self.addTask(with: #"ordinal: "\#(Self.invalidOrdinal)""#)),
            in: directory
        )
        #expect(error == .invalidOrdinal(ordinal: Self.invalidOrdinal))
    }

    @Test("addTask with a body writes one edit patch with the diff from the empty text")
    func addTaskWithBody() async throws {
        let directory = try TemporaryDirectory()
        let response = try await ColumnActorTests.respond(
            to: Self.bodyMutation(of: Self.addTask(with: "body: $body")),
            with: Self.bodyVariables,
            onFixtureIn: directory
        )
        let task = try Self.firstTask(in: response)
        let edit = PatchEdit(body: ReplayTests.diff(from: "", to: Self.body))
        let expected = try PatchInput(node: .task(task), set: Self.addedValues, edit: edit)
        #expect(try ColumnActorTests.patches(of: .task(task), in: directory) == [expected])
    }

    // MARK: - addTask assignees

    @Test("addTask with assignees adds the assignee edges")
    func addTaskWithAssignees() async throws {
        let directory = try TemporaryDirectory()
        let input = "assignees: \(Self.list(of: [Self.alice, Self.bob]))"
        let mutation = Self.mutation(of: Self.addActors, Self.addTask(with: input))
        let task = try Self.firstTask(in: await ColumnActorTests.respond(to: mutation, onFixtureIn: directory))
        let expected = try PatchInput(
            node: .task(task),
            set: Self.addedValues,
            add: [PropertyName.assignees: Self.actorRefs(Self.alice, Self.bob)]
        )
        #expect(try Self.lastPatch(of: task, in: directory) == expected)
    }

    @Test("addTask with an assignee that is not an actor gives ACTOR_NOT_FOUND and writes nothing")
    func addTaskUnknownAssignee() async throws {
        let directory = try TemporaryDirectory()
        let input = "assignees: \(Self.list(of: [Self.alice, Self.unknownActor]))"
        let error = try await ColumnActorTests.failure(
            of: Self.mutation(of: Self.addTask(with: input)),
            after: Self.mutation(of: Self.addActors),
            in: directory
        )
        #expect(error == .actorNotFound(reference: Self.unknownActor))
    }

    @Test("addTask with no assignee and a session actor that the call makes assigns nobody")
    func addTaskSkipsNewSessionActor() async throws {
        let directory = try TemporaryDirectory()
        let mutation = Self.mutation(of: Self.addTask(with: "", selecting: "{ assignees { id } }"))
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        #expect(response == #"{"data":{"addTask":{"assignees":[]}}}"#)
        #expect(try BoardMutationTests.storedRefs(inRepoAt: directory.url).contains(ReplayTests.actor))
    }

    @Test("addTask with no assignee assigns the session actor when it was a known actor before the call")
    func addTaskAssignsKnownSessionActor() async throws {
        let directory = try TemporaryDirectory()
        let graph = try ColumnActorTests.makeFixtureGraph(in: directory).graph
        let actor = KanbanGraphTests.sessionActor
        let addActor = #"addActor(input: { id: "\#(actor.ref.localID ?? "")", name: "\#(actor.name)" }) { id }"#
        _ = try await KanbanGraphTests.execute(Self.mutation(of: addActor), on: graph)
        let mutation = Self.mutation(of: Self.addTask(with: "", selecting: "{ assignees { id } }"))
        let response = try await KanbanGraphTests.execute(mutation, on: graph)
        let assignee = ColumnActorTests.id(of: actor.ref)
        #expect(response == #"{"data":{"addTask":{"assignees":[{"id":"\#(assignee)"}]}}}"#)
    }

    // MARK: - addTask tags

    @Test("addTask with an unknown tag writes a tag set patch and adds the tag edge")
    func addTaskWithNewTag() async throws {
        let directory = try TemporaryDirectory()
        let add = Self.addTask(with: #"tags: ["\#(Self.tagName)"]"#, selecting: "{ id tags { name } }")
        let response = try await ColumnActorTests.respond(to: Self.mutation(of: add), onFixtureIn: directory)
        let task = try Self.firstTask(in: response)
        #expect(response.hasSuffix(#""tags":[{"name":"\#(Self.storedTagName)"}]}}}"#))
        let tag = LocalRef.tag(slug: Self.tagSlug)
        let tagPatch = try PatchInput(node: tag, set: [PropertyName.name: .string(Self.storedTagName)])
        #expect(try ColumnActorTests.patches(of: tag, in: directory) == [tagPatch])
        let expected = try PatchInput(
            node: .task(task),
            set: Self.addedValues,
            add: [PropertyName.tags: Self.tagRefs(Self.tagSlug)]
        )
        #expect(try Self.lastPatch(of: task, in: directory) == expected)
    }

    @Test("addTask with a tag that the board has writes no second tag patch")
    func addTaskWithKnownTag() async throws {
        let directory = try TemporaryDirectory()
        let mutation = Self.mutation(
            of: "first: " + Self.addTask(with: #"tags: ["\#(Self.tagName)"]"#),
            "second: " + Self.addTask(with: #"tags: ["\#(Self.storedTagName.uppercased())"]"#)
        )
        _ = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        #expect(try ColumnActorTests.patches(of: .tag(slug: Self.tagSlug), in: directory).count == 1)
    }

    @Test("addTask with a tag URI adds the edge of that tag")
    func addTaskWithTagURI() async throws {
        let directory = try TemporaryDirectory()
        let tagID = ColumnActorTests.id(of: .tag(slug: Self.tagSlug))
        let mutation = Self.mutation(
            of: "first: " + Self.addTask(with: #"tags: ["\#(Self.tagName)"]"#),
            "second: " + Self.addTask(with: #"tags: ["\#(tagID)"]"#)
        )
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        let second = try #require(try Self.taskULIDs(in: response).last)
        let added = [PropertyName.tags: Self.tagRefs(Self.tagSlug)]
        #expect(try Self.lastPatch(of: second, in: directory)?.add == added)
    }

    @Test("addTask with a tag name that gives an empty slug gives INVALID_TAG_NAME and writes nothing")
    func addTaskInvalidTagName() async throws {
        let directory = try TemporaryDirectory()
        let error = try await ColumnActorTests.failure(
            of: Self.mutation(of: Self.addTask(with: #"tags: ["\#(Self.emptySlugName)"]"#)),
            in: directory
        )
        #expect(error == .invalidTagName(name: Self.emptySlugName))
    }

    @Test("A new marker in the body writes a tag set patch, and the task has the tag with no tag edge")
    func addTaskBodyMarkerMakesTag() async throws {
        let directory = try TemporaryDirectory()
        let add = Self.addTask(with: #"body: "Fix #\#(Self.markerSlug)""#, selecting: "{ id tags { name } }")
        let response = try await ColumnActorTests.respond(to: Self.mutation(of: add), onFixtureIn: directory)
        let task = try Self.firstTask(in: response)
        #expect(response.hasSuffix(#""tags":[{"name":"\#(Self.markerSlug)"}]}}}"#))
        let tag = LocalRef.tag(slug: Self.markerSlug)
        let tagPatch = try PatchInput(node: tag, set: [PropertyName.name: .string(Self.markerSlug)])
        #expect(try ColumnActorTests.patches(of: tag, in: directory) == [tagPatch])
        #expect(try Self.lastPatch(of: task, in: directory)?.add.isEmpty == true)
    }

    @Test("A marker in the body to a tombstoned tag writes delete false for the tag")
    func addTaskBodyMarkerRevivesTag() async throws {
        let directory = try TemporaryDirectory()
        var ids = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).ids
        let log = EventLog(repositoryAt: directory.url)
        let tag = LocalRef.tag(slug: Self.oldSlug)
        let named = try PatchInput(node: tag, set: [PropertyName.name: .string(Self.oldSlug)])
        try KanbanGraphTests.append(named, mintingFrom: &ids, to: log)
        try KanbanGraphTests.append(PatchInput(node: tag, delete: true), mintingFrom: &ids, to: log)
        let add = Self.addTask(with: #"body: "See #\#(Self.oldSlug)""#, selecting: "{ tags { name } }")
        let response = try await KanbanGraphTests.execute(
            Self.mutation(of: add),
            on: KanbanGraphTests.makeGraph(at: directory.url)
        )
        #expect(response == #"{"data":{"addTask":{"tags":[{"name":"\#(Self.oldSlug)"}]}}}"#)
        #expect(try ColumnActorTests.patches(of: tag, in: directory).last == PatchInput(node: tag, delete: false))
    }

    // MARK: - addTask dependencies

    @Test("addTask with a dependsOn URI of this board stores a local ref, and the task is blocked")
    func addTaskDependsOnLocalTask() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let input = #"dependsOn: ["\#(Self.id(of: fixture.task))"]"#
        let add = Self.addTask(with: input, selecting: "{ id ready blockedBy { id } }")
        let mutation = Self.mutation(of: Self.doneColumn, add)
        let response = try await KanbanGraphTests.execute(mutation, on: fixture.graph)
        let task = try #require(try Self.taskULIDs(in: response).first { task in task != fixture.task })
        let json = #"{"blockedBy":[{"id":"\#(Self.id(of: fixture.task))"}],"#
            + #""id":"\#(Self.id(of: task))","ready":false}"#
        #expect(response.hasSuffix(#""addTask":\#(json)}}"#))
        let expected = try PatchInput(
            node: .task(task),
            set: Self.addedValues,
            add: [PropertyName.dependsOn: [.local(.task(fixture.task))]]
        )
        #expect(try Self.lastPatch(of: task, in: directory) == expected)
    }

    @Test("addTask with a dependsOn URI of a different board stores the full URI, and the task is blocked")
    func addTaskDependsOnRemoteTask() async throws {
        let directory = try TemporaryDirectory()
        let add = Self.addTask(with: #"dependsOn: ["\#(Self.remoteTask)"]"#, selecting: "{ id ready }")
        let response = try await ColumnActorTests.respond(to: Self.mutation(of: add), onFixtureIn: directory)
        let task = try Self.firstTask(in: response)
        #expect(response.hasSuffix(#""ready":false}}}"#))
        let remote = try StoredRef(parsing: Self.remoteTask)
        #expect(try Self.lastPatch(of: task, in: directory)?.add == [PropertyName.dependsOn: [remote]])
    }

    @Test("addTask with a dependsOn ref that names no task gives NOT_FOUND and writes nothing")
    func addTaskUnknownDependency() async throws {
        let directory = try TemporaryDirectory()
        let error = try await ColumnActorTests.failure(
            of: Self.mutation(of: Self.addTask(with: #"dependsOn: ["\#(Self.unknownTask)"]"#)),
            in: directory
        )
        #expect(error == .notFound(type: .task, reference: Self.unknownTask))
    }

    @Test(
        "A time value in the input is a validation error, and the call writes nothing",
        arguments: ["created", "due", "scheduled"]
    )
    func timeInputIsRefused(field: String) async throws {
        let directory = try TemporaryDirectory()
        let add = Self.addTask(with: #"\#(field): "2026-10-07T00:00:00Z""#)
        let response = try await ColumnActorTests.respondWritingNothing(to: Self.mutation(of: add), in: directory)
        #expect(response.hasPrefix(#"{"errors":"#))
        #expect(response.contains(field))
    }

    // MARK: - updateTask fields

    @Test("updateTask with a title writes a set of the title only")
    func updateTaskTitle() async throws {
        let directory = try TemporaryDirectory()
        let task = try Self.fixtureTask()
        let update = Self.updateTask(task, with: #"title: "\#(Self.newTitle)""#, selecting: "{ title }")
        let response = try await ColumnActorTests.respond(to: Self.mutation(of: update), onFixtureIn: directory)
        #expect(response == #"{"data":{"updateTask":{"title":"\#(Self.newTitle)"}}}"#)
        let expected = try PatchInput(node: .task(task), set: [PropertyName.title: .string(Self.newTitle)])
        #expect(try Self.lastPatch(of: task, in: directory) == expected)
    }

    @Test("updateTask with no field changes nothing and writes no patch")
    func updateTaskWithNoField() async throws {
        let directory = try TemporaryDirectory()
        let update = Self.updateTask(try Self.fixtureTask(), with: "", selecting: "{ title }")
        let response = try await ColumnActorTests.respondWritingNothing(to: Self.mutation(of: update), in: directory)
        #expect(response == #"{"data":{"updateTask":{"title":"\#(KanbanGraphTests.taskTitle)"}}}"#)
    }

    @Test("updateTask with a null title writes an unset of the title")
    func updateTaskNullTitle() async throws {
        let directory = try TemporaryDirectory()
        let task = try Self.fixtureTask()
        let update = Self.updateTask(task, with: "title: null", selecting: "{ title }")
        let response = try await ColumnActorTests.respond(to: Self.mutation(of: update), onFixtureIn: directory)
        #expect(response == #"{"data":{"updateTask":{"title":""}}}"#)
        let expected = try PatchInput(node: .task(task), unset: [PropertyName.title])
        #expect(try Self.lastPatch(of: task, in: directory) == expected)
    }

    @Test("updateTask with a null or an empty body writes the diff to the empty text", arguments: ["null", #""""#])
    func updateTaskClearsBody(emptyBody: String) async throws {
        let directory = try TemporaryDirectory()
        let task = try Self.fixtureTask()
        let mutation = Self.bodyMutation(
            of: "first: " + Self.updateTask(task, with: "body: $body"),
            "second: " + Self.updateTask(task, with: "body: \(emptyBody)", selecting: "{ body }")
        )
        let response = try await ColumnActorTests.respond(
            to: mutation,
            with: Self.bodyVariables,
            onFixtureIn: directory
        )
        #expect(response.hasSuffix(#""second":{"body":""}}}"#))
        let edit = PatchEdit(body: ReplayTests.diff(from: Self.body, to: ""))
        #expect(try Self.lastPatch(of: task, in: directory) == PatchInput(node: .task(task), edit: edit))
    }

    @Test("updateTask with an id that names no task gives NOT_FOUND and writes nothing")
    func updateTaskNotFound() async throws {
        let directory = try TemporaryDirectory()
        let update = #"updateTask(input: { id: "\#(Self.unknownTask)", title: "\#(Self.newTitle)" }) { id }"#
        let error = try await ColumnActorTests.failure(of: Self.mutation(of: update), in: directory)
        #expect(error == .notFound(type: .task, reference: Self.unknownTask))
    }

    // MARK: - updateTask lists

    @Test("updateTask with assignees writes the add and remove difference to the current list")
    func updateTaskReplacesAssignees() async throws {
        let directory = try TemporaryDirectory()
        let task = try Self.fixtureTask()
        let mutation = Self.mutation(
            of: Self.addActors,
            "first: " + Self.updateTask(task, with: "assignees: \(Self.list(of: [Self.alice]))"),
            "second: " + Self.updateTask(task, with: "assignees: \(Self.list(of: [Self.bob]))")
        )
        _ = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        let expected = try PatchInput(
            node: .task(task),
            add: [PropertyName.assignees: Self.actorRefs(Self.bob)],
            remove: [PropertyName.assignees: Self.actorRefs(Self.alice)]
        )
        #expect(try Self.lastPatch(of: task, in: directory) == expected)
    }

    @Test("updateTask with an empty or a null assignee list removes each assignee", arguments: ["[]", "null"])
    func updateTaskClearsAssignees(emptyList: String) async throws {
        let directory = try TemporaryDirectory()
        let task = try Self.fixtureTask()
        let clear = Self.updateTask(task, with: "assignees: \(emptyList)", selecting: "{ assignees { id } }")
        let mutation = Self.mutation(
            of: Self.addActors,
            "first: " + Self.updateTask(task, with: "assignees: \(Self.list(of: [Self.alice]))"),
            "second: " + clear
        )
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        #expect(response.hasSuffix(#""second":{"assignees":[]}}}"#))
        let removed = [PropertyName.assignees: Self.actorRefs(Self.alice)]
        #expect(try Self.lastPatch(of: task, in: directory) == PatchInput(node: .task(task), remove: removed))
    }

    @Test("updateTask with an assignee that is not an actor gives ACTOR_NOT_FOUND and keeps the list")
    func updateTaskUnknownAssignee() async throws {
        let directory = try TemporaryDirectory()
        let task = try Self.fixtureTask()
        let assign = Self.updateTask(task, with: "assignees: \(Self.list(of: [Self.alice]))")
        let input = "assignees: \(Self.list(of: [Self.bob, Self.unknownActor]))"
        let error = try await ColumnActorTests.failure(
            of: Self.mutation(of: Self.updateTask(task, with: input)),
            after: Self.mutation(of: Self.addActors, assign),
            in: directory
        )
        #expect(error == .actorNotFound(reference: Self.unknownActor))
    }

    @Test("updateTask with tags writes the add and remove difference, and a set patch for a new tag")
    func updateTaskReplacesTags() async throws {
        let directory = try TemporaryDirectory()
        let task = try Self.fixtureTask()
        let mutation = Self.mutation(
            of: "first: " + Self.updateTask(task, with: "tags: \(Self.list(of: Self.firstTags))"),
            "second: " + Self.updateTask(task, with: "tags: \(Self.list(of: Self.secondTags))")
        )
        _ = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        let added = try #require(Self.secondTags.last)
        let removed = try #require(Self.firstTags.first)
        let expected = try PatchInput(
            node: .task(task),
            add: [PropertyName.tags: Self.tagRefs(added)],
            remove: [PropertyName.tags: Self.tagRefs(removed)]
        )
        #expect(try Self.lastPatch(of: task, in: directory) == expected)
        #expect(try ColumnActorTests.patches(of: .tag(slug: added), in: directory).count == 1)
    }

    @Test("updateTask with an empty tag list removes the tag edges, and a marker in the body keeps its tag")
    func updateTaskClearsTagEdgesOnly() async throws {
        let directory = try TemporaryDirectory()
        let task = try Self.fixtureTask()
        let first = Self.updateTask(task, with: ##"body: "#\##(Self.markerSlug)", tags: ["\##(Self.tagSlug)"]"##)
        let mutation = Self.mutation(
            of: "first: " + first,
            "second: " + Self.updateTask(task, with: "tags: []", selecting: "{ tags { name } }")
        )
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        #expect(response.hasSuffix(#""second":{"tags":[{"name":"\#(Self.markerSlug)"}]}}}"#))
        let removed = [PropertyName.tags: Self.tagRefs(Self.tagSlug)]
        #expect(try Self.lastPatch(of: task, in: directory) == PatchInput(node: .task(task), remove: removed))
    }

    // MARK: - updateTask dependencies

    @Test("updateTask with dependsOn writes the add and remove difference to the current list")
    func updateTaskReplacesDependencies() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let setup = Self.mutation(of: "b: " + Self.addTask(with: ""), "c: " + Self.addTask(with: ""))
        let added = try await Self.addedTasks(by: setup, on: fixture.graph)
        let (second, third) = (try #require(added.first), try #require(added.last))
        let mutation = Self.mutation(
            of: "first: " + Self.updateTask(fixture.task, with: Self.dependsOn(second)),
            "second: " + Self.updateTask(fixture.task, with: Self.dependsOn(third))
        )
        _ = try await KanbanGraphTests.execute(mutation, on: fixture.graph)
        let expected = try PatchInput(
            node: .task(fixture.task),
            add: [PropertyName.dependsOn: [.local(.task(third))]],
            remove: [PropertyName.dependsOn: [.local(.task(second))]]
        )
        #expect(try Self.lastPatch(of: fixture.task, in: directory) == expected)
    }

    @Test("updateTask with dependsOn that removes a target also removes its URL from the body")
    func updateTaskRemovesDependencyMarker() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let added = try await Self.addedTasks(by: Self.mutation(of: Self.addTask(with: "")), on: fixture.graph)
        let target = try #require(added.first)
        let markedBody = "Needs \(Self.id(of: target))\n"
        let mark = Self.updateTask(fixture.task, with: "body: $body, \(Self.dependsOn(target))")
        _ = try await KanbanGraphTests.execute(
            Self.bodyMutation(of: mark),
            variables: ["body": .string(markedBody)],
            on: fixture.graph
        )
        let clear = Self.updateTask(fixture.task, with: "dependsOn: []", selecting: "{ dependsOn { id } }")
        let response = try await KanbanGraphTests.execute(Self.mutation(of: clear), on: fixture.graph)
        #expect(response == #"{"data":{"updateTask":{"dependsOn":[]}}}"#)
        let expected = try PatchInput(
            node: .task(fixture.task),
            remove: [PropertyName.dependsOn: [.local(.task(target))]],
            edit: PatchEdit(body: ReplayTests.diff(from: markedBody, to: "Needs\n"))
        )
        #expect(try Self.lastPatch(of: fixture.task, in: directory) == expected)
    }

    @Test("A dependsOn edge that makes a cycle gives DEPENDENCY_CYCLE, and nothing of the field is written")
    func dependencyEdgeCycleIsRefused() async throws {
        let directory = try TemporaryDirectory()
        let (error, expected) = try await Self.cycleFailure(in: directory) { added in Self.dependsOn(added) }
        #expect(error == expected)
    }

    @Test("A dependency marker in the body that makes a cycle gives DEPENDENCY_CYCLE, and nothing is written")
    func dependencyMarkerCycleIsRefused() async throws {
        let directory = try TemporaryDirectory()
        let (error, expected) = try await Self.cycleFailure(in: directory) { added in
            #"body: "Needs \#(Self.id(of: added))""#
        }
        #expect(error == expected)
    }

    // MARK: - Mint and concurrency

    @Test("addTask mints a new ULID when the first ULID has the short id of a task of the board")
    func addTaskMintsUniqueShortID() async throws {
        let directory = try TemporaryDirectory()
        let fixtureTask = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        var source = FixedULIDSource(at: ReplayTests.date(atStep: CommitTests.callStep))
        let transaction = source.makeULID()
        let prefix = source.makeULID().ulidString.prefix(ShortID.ulidLength - ShortID.length)
        let colliding = try #require(ULID(ulidString: String(prefix + fixtureTask.ulidString.suffix(ShortID.length))))
        let spare = (0..<Self.spareULIDCount).map { _ in source.makeULID() }
        let minted = try #require(spare.first)
        var session = try await CommitTests.makeSession(
            of: EventLog(repositoryAt: directory.url),
            mintingFrom: ScriptedULIDSource(candidates: [transaction, colliding] + spare)
        )
        let result = try await ColumnActorTests.result(of: Self.mutation(of: Self.addTask(with: "")), in: &session)
        #expect(result.errors.isEmpty)
        let stored = try BoardMutationTests.storedRefs(inRepoAt: directory.url)
        #expect(stored.contains(.task(minted)))
        #expect(!stored.contains(.task(colliding)))
    }

    @Test("Two processes add a task at the same time: both tasks are written, and the short ids are unique")
    func twoProcessesAddTasks() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let other = try KanbanGraphTests.makeGraph(at: directory.url)
        _ = try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: other)
        let add = Self.mutation(of: Self.addTask(with: ""))
        let first = try #require(try await Self.addedTasks(by: add, on: fixture.graph).first)
        let second = try #require(try await Self.addedTasks(by: add, on: other).first)
        let tasks = [fixture.task, first, second]
        #expect(Set(tasks.map(ShortID.init(of:))).count == tasks.count)
        #expect(try BoardMutationTests.events(of: .task(first), inRepoAt: directory.url).count == 1)
        let stored = try BoardMutationTests.storedRefs(inRepoAt: directory.url)
        #expect(stored.isSuperset(of: [.task(first), .task(second)]))
        let listed = try await KanbanGraphTests.execute(KanbanGraphTests.boardQuery, on: other)
        #expect(Set(try Self.taskULIDs(in: listed)) == Set(tasks))
    }
}
