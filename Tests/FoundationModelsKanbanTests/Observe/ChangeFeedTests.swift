import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the move of the subscribers of one owner from one ``ChangeFeed`` to a different feed (divergence.md §16): a
/// session view moves its subscribers when a new repo replaces the repo of a related board at the same path.
///
/// Each test uses feeds in memory only. No test reads a file.
@Suite("Change feed: move the subscribers of one owner to a different feed")
struct ChangeFeedTests {
    /// The owner of the subscribers that a test moves.
    static let movedOwner = ObjectIdentifier(Int.self)

    /// The owner of the subscribers that stay in the old feed.
    static let otherOwner = ObjectIdentifier(String.self)

    /// The number of changes that the change log of each feed of the tests keeps.
    static let capacity = 8

    /// Makes two feeds: the old feed and the new feed of a move.
    ///
    /// - Returns: The old feed and the new feed.
    static func makeFeeds() -> (old: ChangeFeed, new: ChangeFeed) {
        (ChangeFeed(capacity: capacity), ChangeFeed(capacity: capacity))
    }

    /// Adds a subscriber with no filter to a feed, for the new changes only.
    ///
    /// - Parameters:
    ///   - feed: The feed.
    ///   - owner: The owner of the subscriber.
    /// - Returns: The events of the subscriber.
    /// - Throws: An error when the empty filter does not parse.
    static func subscribe(
        to feed: ChangeFeed,
        ownedBy owner: ObjectIdentifier
    ) async throws -> AsyncThrowingStream<ChangeEvent, Error> {
        await feed.subscribe(after: nil, filteredBy: try ChangeFilter(parsing: nil), ownedBy: owner)
    }

    /// Reads a stream until it ends, and counts its events.
    ///
    /// - Parameter stream: The stream.
    /// - Returns: The number of events.
    /// - Throws: The error that ends the stream.
    static func eventCount(of stream: AsyncThrowingStream<ChangeEvent, Error>) async throws -> Int {
        try await stream.reduce(0) { count, _ in count + 1 }
    }

    /// Reads the first event of a stream, and gives its transaction.
    ///
    /// - Parameter stream: The stream.
    /// - Returns: The transaction of the first event, or `nil` when the stream ends with no event.
    /// - Throws: The error that ends the stream.
    static func firstTransaction(of stream: AsyncThrowingStream<ChangeEvent, Error>) async throws -> NodeID? {
        try await stream.first { _ in true }?.change.txn
    }

    /// Appends one change of the board node to the change log of a feed. The change has no field change, and the
    /// empty filter keeps it, because the fixture graph has a board node that is not a tombstone.
    ///
    /// - Parameters:
    ///   - txn: The transaction of the change.
    ///   - feed: The feed.
    /// - Throws: An error when a ULID text of the fixture graph is not valid.
    static func appendBoardChange(inTransaction txn: NodeID, to feed: ChangeFeed) async throws {
        let graph = try QueryFixture().graph
        let key = DependencyMarkersTests.boardKey
        let view = BoardView(of: graph, inBoard: key)
        let update = NodeUpdate(
            ref: .board,
            id: view.id(of: .board),
            type: .board,
            kind: .updated,
            fields: [],
            boardKey: key
        )
        let change = Change(
            txn: txn,
            at: DependencyMarkersTests.time,
            actorRef: ReplayTests.actor,
            ops: [MutationName.updateBoard],
            boards: [key],
            undone: false,
            undoes: nil,
            nodeUpdates: [update],
            logCursor: nil
        )
        let stamp = EventStamp(
            actingAs: ReplayTests.actor,
            mintingFrom: FixedULIDSource(at: ReplayTests.date(atStep: .zero)),
            after: nil
        )
        let board = EventBoard(
            work: WorkingCopy(graph: graph, events: [], stamp: stamp, after: nil),
            key: key,
            source: BoardSource(
                directory: FileManager.default.temporaryDirectory,
                search: TaskSearch(embeddingWith: nil),
                events: [],
                readiness: ReadinessCache(),
                cursor: nil
            ),
            related: .unavailable
        )
        await feed.append([change], readingNodesOf: view, resolvingIn: board)
    }

    @Test("The moved subscribers of one owner leave the old feed, and the subscribers of other owners stay")
    func moveTakesOnlySubscribersOfOwner() async throws {
        let (old, new) = Self.makeFeeds()
        let moved = try await Self.subscribe(to: old, ownedBy: Self.movedOwner)
        let stays = try await Self.subscribe(to: old, ownedBy: Self.otherOwner)
        await old.moveSubscribers(ownedBy: Self.movedOwner, to: new)
        #expect(!old.hasSubscribers(ownedBy: Self.movedOwner))
        #expect(new.hasSubscribers(ownedBy: Self.movedOwner))
        #expect(old.hasSubscribers(ownedBy: Self.otherOwner))
        #expect(!new.hasSubscribers(ownedBy: Self.otherOwner))
        withExtendedLifetime((moved, stays)) {}
    }

    @Test("A moved subscriber gets only the changes of the new feed; other owners keep the old feed")
    func movedSubscriberGetsEventsOfNewFeed() async throws {
        let (old, new) = Self.makeFeeds()
        let (oldTxn, newTxn) = (NodeID(text: ReadinessFixture.first), NodeID(text: ReadinessFixture.second))
        let moved = try await Self.subscribe(to: old, ownedBy: Self.movedOwner)
        let stays = try await Self.subscribe(to: old, ownedBy: Self.otherOwner)
        await old.moveSubscribers(ownedBy: Self.movedOwner, to: new)
        try await Self.appendBoardChange(inTransaction: oldTxn, to: old)
        try await Self.appendBoardChange(inTransaction: newTxn, to: new)
        #expect(try await Self.firstTransaction(of: moved) == newTxn)
        #expect(try await Self.firstTransaction(of: stays) == oldTxn)
        old.finish()
        new.finish()
    }

    @Test("A moved subscriber whose stream ends goes away from the new feed")
    func endOfMovedStreamRemovesSubscriberFromNewFeed() async throws {
        let (old, new) = Self.makeFeeds()
        let stream = try await Self.subscribe(to: old, ownedBy: Self.movedOwner)
        await old.moveSubscribers(ownedBy: Self.movedOwner, to: new)
        let reader = Task { try await Self.eventCount(of: stream) }
        reader.cancel()
        _ = try await reader.value
        #expect(!new.hasSubscribers(ownedBy: Self.movedOwner))
    }

    @Test("A move to a finished feed ends the stream of each moved subscriber")
    func moveToFinishedFeedEndsStream() async throws {
        let (old, new) = Self.makeFeeds()
        let stream = try await Self.subscribe(to: old, ownedBy: Self.movedOwner)
        new.finish()
        await old.moveSubscribers(ownedBy: Self.movedOwner, to: new)
        #expect(try await Self.eventCount(of: stream) == 0)
        #expect(!old.hasSubscribers(ownedBy: Self.movedOwner))
    }
}
