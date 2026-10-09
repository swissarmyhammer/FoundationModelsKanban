import Foundation
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests a board where two tasks have the same short id, as a merge can make (plan.md §3.2). A short id is a unique
/// ULID prefix (git style), so the shared short id names no task: a mutation and a filter that use it give
/// `AMBIGUOUS_ID` with the full ids of the two tasks, and write nothing.
@Suite("A short id that two tasks share")
struct SharedShortIDTests {
    /// The title of the second task with the shared short id.
    static let secondTitle = "Merge the branch"

    /// The title of the task whose short id no other task has.
    static let uniqueTitle = "Write the docs"

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

    /// The `AMBIGUOUS_ID` error of the shared short id: the full ids of the two tasks, in board order. The loader
    /// puts the nodes in the order of their refs, so the board order of the two tasks is the order of their ULIDs.
    var sharedError: KanbanError {
        .sharedShortID(reference: sharedReference, ids: [first.ulidString, second.ulidString].sorted())
    }

    /// Runs one document in a commit session of the board, and expects that it writes no log file.
    ///
    /// - Parameter document: The GraphQL document.
    /// - Returns: The error of the first GraphQL error of the response, or `nil` when the response has no error.
    func error(of document: String) async throws -> KanbanError? {
        let log = EventLog(repositoryAt: directory.url)
        let before = try log.nodeFileSignatures()
        var session = try await CommitTests.makeSession(of: log)
        let result = try await ColumnActorTests.result(of: document, in: &session)
        #expect(try log.nodeFileSignatures() == before)
        return result.errors.first?.originalError as? KanbanError
    }

    /// Runs one document on a new engine of the board.
    ///
    /// - Parameter document: The GraphQL document.
    /// - Returns: The response JSON text.
    func response(to document: String) async throws -> String {
        try await KanbanGraphTests.execute(document, on: KanbanGraphTests.makeGraph(at: directory.url))
    }

    // MARK: - Tests

    @Test("The two tasks have the same short id and different ULIDs")
    func fixtureSharesTheShortID() {
        #expect(ShortID(of: first) == ShortID(of: second))
        #expect(first != second)
    }

    @Test("A mutation that names the shared short id gives AMBIGUOUS_ID with the full ids, and writes nothing")
    func mutationWithSharedShortIDIsAmbiguous() async throws {
        let field = CommentTests.nodeField("deleteTask", naming: sharedReference)
        let failure = try await error(of: AddUpdateTaskTests.mutation(of: field))
        #expect(failure == sharedError)
    }

    @Test("A tombstone with the shared short id also makes the short id name no task")
    func tombstoneSharesTheShortID() async throws {
        let deletion = CommentTests.nodeField("deleteTask", naming: second.ulidString)
        let deleted = #"{"data":{"deleteTask":{"id":"\#(ColumnActorTests.id(of: .task(second)))"}}}"#
        #expect(try await response(to: AddUpdateTaskTests.mutation(of: deletion)) == deleted)
        let field = CommentTests.nodeField("completeTask", naming: sharedReference)
        let failure = try await error(of: AddUpdateTaskTests.mutation(of: field))
        #expect(failure == sharedError)
    }

    @Test("A filter that names the shared short id gives AMBIGUOUS_ID with the full ids, and writes nothing")
    func filterWithSharedShortIDIsAmbiguous() async throws {
        let query = #"{ board { tasks(filter: "\#(sharedReference)") { totalCount } } }"#
        let failure = try await error(of: query)
        #expect(failure == sharedError)
    }

    @Test("A subscription whose filter names the shared short id gives one response with AMBIGUOUS_ID, and ends")
    func subscriptionWithSharedShortIDIsAmbiguous() async throws {
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let document = SubscriptionTests.subscription(#"(filter: "\#(sharedReference)")"#)
        let stream = try await SubscriptionTests.subscribe(document, on: graph)
        let (eventCount, code) = try await SubscriptionTests.errorCode(of: stream)
        #expect(eventCount == SubscriptionTests.oneEvent)
        #expect(code == "AMBIGUOUS_ID")
        await graph.close()
    }

    @Test("A subscription whose short id becomes shared after the start ends, and sends no change")
    func subscriptionEndsWhenItsShortIDBecomesShared() async throws {
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
        #expect(try await SubscriptionTests.allEvents(of: stream) == [])
        await graph.close()
    }

    @Test("A short id that one task has still names that task")
    func uniqueShortIDStillResolves() async throws {
        let query = CommentTests.taskQuery(of: unique, selecting: "{ title }")
        let expected = #"{"data":{"board":{"task":{"title":"\#(Self.uniqueTitle)"}}}}"#
        #expect(try await response(to: query) == expected)
    }

    @Test("The full id of a task with the shared short id still names that task")
    func fullIDOfSharedShortIDOwnerResolves() async throws {
        let query = #"{ board { task(id: "\#(second.ulidString)") { title } } }"#
        let expected = #"{"data":{"board":{"task":{"title":"\#(Self.secondTitle)"}}}}"#
        #expect(try await response(to: query) == expected)
    }
}
