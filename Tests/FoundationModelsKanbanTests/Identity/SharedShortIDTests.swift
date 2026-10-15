import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests a board where two tasks have the same short id, as a merge can make (plan.md §3.2, divergence.md Q20).
///
/// A mutation or a query that names the shared short id uses the first match: a live task comes before a tombstone,
/// then the lowest ULID. The response gives a `SHARED_SHORT_ID` warning that lists the matches. A filter that names
/// the shared short id matches each task with that short id, and each task that depends on one of them.
@Suite("A short id that two tasks share", .watcherBudget)
struct SharedShortIDTests {
    /// The title of the second task with the shared short id.
    static let secondTitle = "Merge the branch"

    /// The title of the task whose short id no other task has.
    static let uniqueTitle = "Write the docs"

    /// The new title that the update tests give.
    static let newTitle = "Port the lexer"

    /// The number of tasks that the filter of the shared short id lists when the unique task depends on the second
    /// task: the two tasks with the shared short id, and the unique task.
    static let ownersAndDependentCount = 3

    /// The number of tasks with the shared short id.
    static let ownerCount = 2

    /// The repo directory of the board.
    let directory: TemporaryDirectory

    /// The fixture task of ``KanbanGraphTests``. Its short id is the shared short id.
    let first: ULID

    /// The second task. Its ULID is different from ``first``, but it ends with the same 7 characters.
    let second: ULID

    /// A task whose short id no other task has.
    let unique: ULID

    /// Writes the fixture logs of ``KanbanGraphTests``, then the second task and the unique task.
    init() throws {
        directory = try TemporaryDirectory()
        var fixture = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        first = fixture.task
        second = try Self.ulid(sharingShortIDOf: first)
        let log = EventLog(repositoryAt: directory.url)
        try KanbanGraphTests.writeTask(second, titled: Self.secondTitle, mintingFrom: &fixture.ids, to: log)
        unique = try KanbanGraphTests.writeTask(titled: Self.uniqueTitle, mintingFrom: &fixture.ids, to: log)
    }

    /// Makes a ULID that is different from a ULID, but has the same short id.
    ///
    /// - Parameter ulid: The ULID.
    /// - Returns: A ULID with a different start and the same last 7 characters.
    static func ulid(sharingShortIDOf ulid: ULID) throws -> ULID {
        let start = String(ShortIDTests.secondOwnerOf0123456.prefix(ShortID.ulidLength - ShortID.length))
        return try #require(ULID(ulidString: start + String(ulid.ulidString.suffix(ShortID.length))))
    }

    /// The shared short id with a leading ``ShortID/sigil``, as a caller writes it.
    var sharedReference: String {
        AddUpdateTaskTests.sigilRef(of: first)
    }

    /// The task with the shared short id and the lowest ULID: the first match of two live tasks.
    var lowest: ULID {
        min(first, second)
    }

    /// The task with the shared short id and the highest ULID.
    var highest: ULID {
        max(first, second)
    }

    /// Gives the `id` of the object of one root field of a response.
    ///
    /// - Parameters:
    ///   - field: The response key of the root field, for example `updateTask`.
    ///   - response: The response JSON text.
    /// - Returns: The full URI of the node.
    /// - Throws: An error when the response has no `data`, or the field has no `id`.
    static func id(ofField field: String, in response: String) throws -> String? {
        try KanbanGraphTests.object(named: field, in: response)["id"] as? String
    }

    /// Gives the full URI of a task of the board.
    ///
    /// - Parameter task: The ULID of the task.
    /// - Returns: The URI text.
    static func id(of task: ULID) -> String {
        ColumnActorTests.id(of: .task(task))
    }

    /// Expects that a response gives one `SHARED_SHORT_ID` warning that lists the ULIDs of the two owners.
    ///
    /// - Parameter response: The response JSON text.
    /// - Throws: An error when the response has no `extensions.warnings`.
    func expectSharedShortIDWarning(in response: String) throws {
        let warnings = try ResponseWarningsTests.warnings(of: response)
        #expect(warnings.map(\.code) == [RefResolver.sharedShortIDWarningCode])
        let message = try #require(warnings.first?.message)
        #expect(message.contains(first.ulidString))
        #expect(message.contains(second.ulidString))
    }

    // MARK: - Tests

    @Test("The two tasks have the same short id and different ULIDs")
    func fixtureSharesTheShortID() {
        #expect(ShortID(of: first) == ShortID(of: second))
        #expect(first != second)
    }

    @Test("updateTask with the shared short id changes the live task with the lowest ULID, and gives a warning")
    func mutationWithSharedShortIDChangesLowestULID() async throws {
        let field = AddUpdateTaskTests.updateTask(first, with: #"title: "\#(Self.newTitle)""#)
        let response = try await KanbanGraphTests.mutationResponse(of: field, inRepoAt: directory.url)
        #expect(try Self.id(ofField: MutationName.updateTask, in: response) == Self.id(of: lowest))
        try expectSharedShortIDWarning(in: response)
    }

    @Test("A query with the shared short id gives the task with the lowest ULID, and gives a warning")
    func queryWithSharedShortIDGivesLowestULID() async throws {
        let query = #"{ board { task(id: "\#(sharedReference)") { id } } }"#
        let response = try await KanbanGraphTests.response(to: query, inRepoAt: directory.url)
        let task = try KanbanGraphTests.object(named: "board", in: response)["task"] as? [String: Any]
        #expect(task?["id"] as? String == Self.id(of: lowest))
        try expectSharedShortIDWarning(in: response)
    }

    @Test("A tombstone with the shared short id comes after the live task, also when its ULID is lower")
    func tombstoneComesAfterLiveTask() async throws {
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let deletion = CommentTests.nodeField("deleteTask", naming: lowest.ulidString)
        _ = try await KanbanGraphTests.execute(AddUpdateTaskTests.mutation(of: deletion), on: graph)
        let field = CommentTests.nodeField("completeTask", naming: sharedReference)
        let response = try await KanbanGraphTests.execute(AddUpdateTaskTests.mutation(of: field), on: graph)
        #expect(try Self.id(ofField: "completeTask", in: response) == Self.id(of: highest))
        await graph.close()
    }

    @Test("A filter with the shared short id lists each task with it, and each task that depends on one of them")
    func filterWithSharedShortIDMatchesAll() async throws {
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let query = #"{ board { tasks(filter: "\#(sharedReference)") { totalCount } } }"#
        let owners = try await KanbanGraphTests.execute(query, on: graph)
        #expect(owners == Self.totalCountResponse(Self.ownerCount))
        let dependsOn = #"dependsOn: ["\#(second.ulidString)"]"#
        let link = CommentTests.nodeField("updateTask", naming: unique.ulidString, with: dependsOn)
        _ = try await KanbanGraphTests.execute(AddUpdateTaskTests.mutation(of: link), on: graph)
        let withDependent = try await KanbanGraphTests.execute(query, on: graph)
        #expect(withDependent == Self.totalCountResponse(Self.ownersAndDependentCount))
        await graph.close()
    }

    /// Gives the response of a `tasks` query of the board that selects only `totalCount`.
    ///
    /// - Parameter count: The number of tasks of the list.
    /// - Returns: The response JSON text.
    static func totalCountResponse(_ count: Int) -> String {
        #"{"data":{"board":{"tasks":{"totalCount":\#(count)}}}}"#
    }

    @Test("A subscription whose filter names the shared short id sends the change of each task with it")
    func subscriptionWithSharedShortIDSendsEachOwner() async throws {
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let document = SubscriptionTests.subscription(#"(filter: "\#(sharedReference)")"#)
        let stream = try await SubscriptionTests.subscribe(document, on: graph)
        for task in [second, first] {
            let rename = CommentTests.nodeField("updateTask", naming: task.ulidString, with: #"title: "x""#)
            _ = try await KanbanGraphTests.execute(AddUpdateTaskTests.mutation(of: rename), on: graph)
        }
        let events = try await SubscriptionTests.events(Self.ownerCount, of: stream)
        #expect(events.count == Self.ownerCount)
        #expect(events.first?.contains(Self.id(of: second)) == true)
        #expect(events.last?.contains(Self.id(of: first)) == true)
        await graph.close()
    }

    @Test("A subscription whose short id becomes shared after the start keeps going, and sends the new task")
    func subscriptionSendsTaskThatSharesItsShortIDLater() async throws {
        let board = try TemporaryDirectory()
        var fixture = try KanbanGraphTests.writeFixture(inRepoAt: board.url)
        let graph = try KanbanGraphTests.makeGraph(at: board.url)
        let filter = AddUpdateTaskTests.sigilRef(of: fixture.task)
        let stream = try await SubscriptionTests.subscribe(
            SubscriptionTests.subscription(#"(filter: "\#(filter)")"#),
            on: graph
        )
        let merged = try Self.ulid(sharingShortIDOf: fixture.task)
        let log = EventLog(repositoryAt: board.url)
        try KanbanGraphTests.writeTask(merged, titled: Self.secondTitle, mintingFrom: &fixture.ids, to: log)
        let events = try await SubscriptionTests.events(SubscriptionTests.oneEvent, of: stream)
        #expect(events.count == SubscriptionTests.oneEvent)
        #expect(events.first?.contains(Self.id(of: merged)) == true)
        await graph.close()
    }

    @Test("A short id that one task has still names that task, with no warning")
    func uniqueShortIDStillResolves() async throws {
        let query = CommentTests.taskQuery(of: unique, selecting: "{ title }")
        let expected = #"{"data":{"board":{"task":{"title":"\#(Self.uniqueTitle)"}}}}"#
        #expect(try await KanbanGraphTests.response(to: query, inRepoAt: directory.url) == expected)
    }

    @Test("The full id of a task with the shared short id still names that task")
    func fullIDOfSharedShortIDOwnerResolves() async throws {
        let query = #"{ board { task(id: "\#(second.ulidString)") { title } } }"#
        let expected = #"{"data":{"board":{"task":{"title":"\#(Self.secondTitle)"}}}}"#
        #expect(try await KanbanGraphTests.response(to: query, inRepoAt: directory.url) == expected)
    }
}
