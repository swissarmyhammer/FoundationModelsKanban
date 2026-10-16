import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the move of the subscribers of one owner from one ``ChangeFeed`` to a different feed (divergence.md §16): a
/// session view moves its subscribers when a new repo replaces the repo of a related board at the same path.
///
/// Each test uses feeds in memory only. No test reads a file.
@Suite("Change feed: move the subscribers of one owner to a different feed", .timeLimit(.minutes(1)))
struct ChangeFeedTests {
    /// The owner of the subscribers that a test moves.
    static let movedOwner = ObjectIdentifier(Int.self)

    /// The owner of the subscribers that stay in the old feed.
    static let otherOwner = ObjectIdentifier(String.self)

    /// Adds a subscriber with no filter to a feed.
    ///
    /// - Parameters:
    ///   - feed: The feed.
    ///   - owner: The owner of the subscriber.
    /// - Returns: The events of the subscriber.
    /// - Throws: An error when the empty filter does not parse.
    static func subscribe(to feed: ChangeFeed, ownedBy owner: ObjectIdentifier) throws -> AsyncStream<ChangeEvent> {
        feed.subscribe(filteredBy: try ChangeFilter(parsing: nil), ownedBy: owner)
    }

    /// Reads a stream until it ends, and counts its events.
    ///
    /// - Parameter stream: The stream.
    /// - Returns: The number of events.
    static func eventCount(of stream: AsyncStream<ChangeEvent>) async -> Int {
        await stream.reduce(0) { count, _ in count + 1 }
    }

    @Test("The moved subscribers of one owner leave the old feed, and the subscribers of other owners stay")
    func moveTakesOnlySubscribersOfOwner() throws {
        let (old, new) = (ChangeFeed(), ChangeFeed())
        let moved = try Self.subscribe(to: old, ownedBy: Self.movedOwner)
        let stays = try Self.subscribe(to: old, ownedBy: Self.otherOwner)
        old.moveSubscribers(ownedBy: Self.movedOwner, to: new)
        #expect(!old.hasSubscribers(ownedBy: Self.movedOwner))
        #expect(new.hasSubscribers(ownedBy: Self.movedOwner))
        #expect(old.hasSubscribers(ownedBy: Self.otherOwner))
        #expect(!new.hasSubscribers(ownedBy: Self.otherOwner))
        withExtendedLifetime((moved, stays)) {}
    }

    @Test("A moved subscriber whose stream ends goes away from the new feed")
    func endOfMovedStreamRemovesSubscriberFromNewFeed() async throws {
        let (old, new) = (ChangeFeed(), ChangeFeed())
        let stream = try Self.subscribe(to: old, ownedBy: Self.movedOwner)
        old.moveSubscribers(ownedBy: Self.movedOwner, to: new)
        let reader = Task { await Self.eventCount(of: stream) }
        reader.cancel()
        _ = await reader.value
        #expect(!new.hasSubscribers(ownedBy: Self.movedOwner))
    }

    @Test("A move to a finished feed ends the stream of each moved subscriber")
    func moveToFinishedFeedEndsStream() async throws {
        let (old, new) = (ChangeFeed(), ChangeFeed())
        let stream = try Self.subscribe(to: old, ownedBy: Self.movedOwner)
        new.finish()
        old.moveSubscribers(ownedBy: Self.movedOwner, to: new)
        #expect(await Self.eventCount(of: stream) == 0)
        #expect(!old.hasSubscribers(ownedBy: Self.movedOwner))
    }
}
