import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the title slug of a task as a ref (divergence.md Q25, C3, and E4).
///
/// A filter `^<title-slug>` matches each task whose title has that slug, and each task that depends on one of them. A
/// task field takes a title slug after the ULID forms, and uses the first match: a live task comes before a
/// tombstone, then the lowest ULID. A field that takes each node type, for example `node(id:)`, tries a title slug
/// after each other slug, so a column slug wins. A filter also takes `^^short`.
@Suite("The title slug of a task as a ref", .watcherBudget)
struct TitleSlugRefTests {
    /// The title of the two tasks that share a title slug.
    static let sharedTitle = "Fix login bug"

    /// The slug of ``sharedTitle``.
    static let sharedSlug = "fix-login-bug"

    /// The slug of the title of the fixture task of ``KanbanGraphTests``.
    static let fixtureSlug = "port-the-parser"

    /// The title of the task that depends on the second task with the shared title slug.
    static let dependentTitle = "Write the docs"

    /// The title of the task whose title slug is the slug of the fixture column.
    static let columnTitle = KanbanGraphTests.todoName

    /// The new title that the update tests give.
    static let newTitle = "Port the lexer"

    /// The number of tasks with the shared title slug.
    static let ownerCount = 2

    /// The number of tasks that the filter of the shared title slug lists when the dependent task depends on the
    /// second task: the two tasks with the shared title slug, and the dependent task.
    static let ownersAndDependentCount = 3

    /// The number of tasks that a filter of one task with no dependent task lists.
    static let oneTask = 1

    /// The repo directory of the board.
    let directory: TemporaryDirectory

    /// The fixture task of ``KanbanGraphTests``.
    let fixtureTask: ULID

    /// The first task with the shared title slug. Its ULID is the lower one.
    let first: ULID

    /// The second task with the shared title slug.
    let second: ULID

    /// A task with no shared title slug. The dependency tests make it depend on ``second``.
    let dependent: ULID

    /// The ULID source after the fixture, for more writes.
    let ids: FixedULIDSource

    /// Writes the fixture logs of ``KanbanGraphTests``, the two tasks with the shared title slug, the dependent task,
    /// and a task whose title is the name of the fixture column.
    init() throws {
        directory = try TemporaryDirectory()
        var fixture = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        fixtureTask = fixture.task
        let log = EventLog(repositoryAt: directory.url)
        first = try KanbanGraphTests.writeTask(titled: Self.sharedTitle, mintingFrom: &fixture.ids, to: log)
        second = try KanbanGraphTests.writeTask(titled: Self.sharedTitle, mintingFrom: &fixture.ids, to: log)
        dependent = try KanbanGraphTests.writeTask(titled: Self.dependentTitle, mintingFrom: &fixture.ids, to: log)
        _ = try KanbanGraphTests.writeTask(titled: Self.columnTitle, mintingFrom: &fixture.ids, to: log)
        ids = fixture.ids
    }

    /// Runs one document on a new engine of the board.
    ///
    /// - Parameter document: The GraphQL document.
    /// - Returns: The response JSON text.
    func response(to document: String) async throws -> String {
        try await KanbanGraphTests.execute(document, on: KanbanGraphTests.makeGraph(at: directory.url))
    }

    /// Makes a query of the tasks of the board with a filter that selects only `totalCount`.
    ///
    /// - Parameter filter: The filter.
    /// - Returns: The GraphQL document.
    static func countQuery(filter: String) -> String {
        #"{ board { tasks(filter: "\#(filter)") { totalCount } } }"#
    }

    /// Makes a query of one task of the board that selects its id.
    ///
    /// - Parameter reference: The ref of the task.
    /// - Returns: The GraphQL document.
    static func taskQuery(naming reference: String) -> String {
        #"{ board { task(id: "\#(reference)") { id } } }"#
    }

    /// Gives the id of the task of a response to ``taskQuery(naming:)``.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The full URI of the task, or `nil` when the response has no task.
    static func taskID(in response: String) throws -> String? {
        let task = try KanbanGraphTests.object(named: "board", in: response)["task"] as? [String: Any]
        return task?["id"] as? String
    }

    /// Gives the type name of the node of a `node(id:)` query.
    ///
    /// - Parameter reference: The ref of the node.
    /// - Returns: The `__typename` of the node, or `nil` when the response has no node.
    func nodeTypeName(naming reference: String) async throws -> String? {
        let response = try await response(to: #"{ node(id: "\#(reference)") { __typename } }"#)
        return try KanbanGraphTests.object(named: "node", in: response)["__typename"] as? String
    }

    /// Makes the dependent task depend on the second task with the shared title slug.
    ///
    /// - Parameter graph: The engine.
    func linkDependent(on graph: KanbanGraph) async throws {
        let link = CommentTests.nodeField(
            "updateTask",
            naming: dependent.ulidString,
            with: #"dependsOn: ["\#(second.ulidString)"]"#
        )
        _ = try await KanbanGraphTests.execute(AddUpdateTaskTests.mutation(of: link), on: graph)
    }

    // MARK: - Filter

    @Test("A filter ^<title-slug> lists each task with that title slug, and each task that depends on one of them")
    func filterWithSharedTitleSlugMatchesAll() async throws {
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let query = Self.countQuery(filter: "^\(Self.sharedSlug)")
        let owners = try await KanbanGraphTests.execute(query, on: graph)
        #expect(owners == SharedShortIDTests.totalCountResponse(Self.ownerCount))
        try await linkDependent(on: graph)
        let withDependent = try await KanbanGraphTests.execute(query, on: graph)
        #expect(withDependent == SharedShortIDTests.totalCountResponse(Self.ownersAndDependentCount))
        await graph.close()
    }

    @Test("A filter ^<title-slug> of one task lists only that task")
    func filterWithTitleSlugMatchesTask() async throws {
        let response = try await response(to: Self.countQuery(filter: "^\(Self.fixtureSlug)"))
        #expect(response == SharedShortIDTests.totalCountResponse(Self.oneTask))
    }

    @Test("A filter ^^<short> lists the task with that short id")
    func filterWithDoubleSigilMatchesTask() async throws {
        let filter = "^\(AddUpdateTaskTests.sigilRef(of: fixtureTask))"
        let response = try await response(to: Self.countQuery(filter: filter))
        #expect(response == SharedShortIDTests.totalCountResponse(Self.oneTask))
    }

    // MARK: - Task fields

    @Test("updateTask with a shared title slug changes the task with the lowest ULID, and gives a warning")
    func mutationWithTitleSlugChangesFirstMatch() async throws {
        let field = CommentTests.nodeField("updateTask", naming: Self.sharedSlug, with: #"title: "\#(Self.newTitle)""#)
        let response = try await response(to: AddUpdateTaskTests.mutation(of: field))
        let updated = try SharedShortIDTests.id(ofField: MutationName.updateTask, in: response)
        #expect(updated == SharedShortIDTests.id(of: first))
        let warnings = try ResponseWarningsTests.warnings(of: response)
        #expect(warnings.map(\.code) == [RefResolver.sharedTitleSlugWarningCode])
        let message = try #require(warnings.first?.message)
        #expect(message.contains(first.ulidString))
        #expect(message.contains(second.ulidString))
    }

    @Test("A tombstone with the shared title slug comes after the live task, also when its ULID is lower")
    func tombstoneComesAfterLiveTask() async throws {
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let deletion = CommentTests.nodeField("deleteTask", naming: first.ulidString)
        _ = try await KanbanGraphTests.execute(AddUpdateTaskTests.mutation(of: deletion), on: graph)
        let field = CommentTests.nodeField("completeTask", naming: Self.sharedSlug)
        let response = try await KanbanGraphTests.execute(AddUpdateTaskTests.mutation(of: field), on: graph)
        #expect(try SharedShortIDTests.id(ofField: "completeTask", in: response) == SharedShortIDTests.id(of: second))
        await graph.close()
    }

    @Test("A task field takes a title slug, or a title, of one task, with no warning", arguments: [
        TitleSlugRefTests.fixtureSlug, KanbanGraphTests.taskTitle,
    ])
    func taskFieldWithTitleSlug(reference: String) async throws {
        let response = try await response(to: Self.taskQuery(naming: reference))
        #expect(try Self.taskID(in: response) == SharedShortIDTests.id(of: fixtureTask))
        #expect(!response.contains(#""warnings""#))
    }

    @Test("A short id or a full ULID wins over a title slug that is the same text", arguments: [true, false])
    func ulidFormWinsOverTitleSlug(usesShortID: Bool) async throws {
        let reference = usesShortID ? ShortID(of: fixtureTask).value : fixtureTask.ulidString
        var ids = ids
        let log = EventLog(repositoryAt: directory.url)
        _ = try KanbanGraphTests.writeTask(titled: reference, mintingFrom: &ids, to: log)
        let response = try await response(to: Self.taskQuery(naming: reference))
        #expect(try Self.taskID(in: response) == SharedShortIDTests.id(of: fixtureTask))
    }

    // MARK: - Fields of each node type

    @Test("node(id:) with a slug of a column and of the title of a task gives the column")
    func nodeWithColumnSlugGivesColumn() async throws {
        #expect(try await nodeTypeName(naming: KanbanGraphTests.todoColumn.localID ?? "") == "Column")
    }

    @Test("node(id:) with a title slug that no other node has gives the task")
    func nodeWithTitleSlugGivesTask() async throws {
        #expect(try await nodeTypeName(naming: Self.fixtureSlug) == "Task")
    }
}
