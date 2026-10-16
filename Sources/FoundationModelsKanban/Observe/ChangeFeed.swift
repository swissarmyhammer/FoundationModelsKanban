import Foundation
import Synchronization

// MARK: - Events

/// The board of one event of the change feed, as the resolvers of the event read it (plan.md §6.7, serial gate).
///
/// The engine reads the board through the serial gate when it sends the event. Thus, the resolvers of the event
/// never see a half-applied batch or a half-written commit.
struct EventBoard: Sendable {
    /// A working copy of the live graph of the board. The resolvers of a subscription only read it.
    let work: WorkingCopy

    /// The current key of the board.
    let key: String

    /// The directory, the search, and the events of the board.
    let source: BoardSource

    /// The related boards that the cross-board dependencies of the board read.
    let related: RelatedBoards
}

/// One event of the change feed: the change of one transaction, and the board that its resolvers read.
struct ChangeEvent: Sendable {
    /// The change, with the updates that the filters of the subscriber keep.
    let change: Change

    /// The board that the resolvers of the change read.
    let board: EventBoard

    /// Gives a stream of events that has ended: the stream of a subscriber that gets no event.
    ///
    /// - Returns: The stream.
    static func endedStream() -> AsyncStream<ChangeEvent> {
        AsyncStream { continuation in continuation.finish() }
    }
}

// MARK: - Feed

/// The subscribers of the change feed of one board (plan.md §6.7, divergence.md §16).
///
/// Each board engine has one feed. `Subscription.changes` adds a subscriber with its filters and its owner, and gets
/// one stream of events. The owner is the session view that made the subscriber: a session view reads the board keys
/// from its own current board, so each view makes the events of its own subscribers. Each subscriber gets only the
/// changes that keep an update after its filters. A subscriber goes away when its stream ends.
/// ``finish(ownedBy:)`` ends the streams of one owner. ``finish()`` ends each stream, and a subscriber that comes
/// later gets a stream that has ended.
///
/// The engine and the resolvers of different calls use the feed, so the subscribers are behind a lock.
final class ChangeFeed: Sendable {
    /// The state of the feed, behind a lock.
    private let state = Mutex(FeedState.open(Subscribers()))

    /// Tells if an owner has a subscriber in this feed.
    ///
    /// - Parameter owner: The owner.
    /// - Returns: `true` when the owner has a subscriber.
    func hasSubscribers(ownedBy owner: ObjectIdentifier) -> Bool {
        !subscribers(ownedBy: owner).isEmpty
    }

    /// Adds a subscriber.
    ///
    /// - Parameters:
    ///   - filter: The filters of the subscriber.
    ///   - owner: The session view that makes the events of the subscriber.
    /// - Returns: The events of the subscriber, in the order that the owner sends them. The stream has ended when
    ///   the feed is finished.
    func subscribe(filteredBy filter: ChangeFilter, ownedBy owner: ObjectIdentifier) -> AsyncStream<ChangeEvent> {
        let (events, continuation) = AsyncStream<ChangeEvent>.makeStream()
        let route = SubscriberRoute()
        let subscriber = Subscriber(owner: owner, filter: filter, continuation: continuation, route: route)
        guard let id = insert(subscriber) else {
            continuation.finish()
            return events
        }
        route.start(in: self, withID: id)
        continuation.onTermination = { _ in
            route.end()
        }
        return events
    }

    /// Moves each subscriber of one owner to a different feed, for example when a new repo replaces the repo of a
    /// board at the same path, and the session view replaces the engine of that path (divergence.md §16). The streams
    /// of the subscribers continue: they get the events that the owner sends to the new feed. A subscriber whose
    /// stream ends during the move goes away from the feed where it is. The new feed ends the stream of each moved
    /// subscriber when it is finished.
    ///
    /// - Parameters:
    ///   - owner: The owner of the subscribers to move.
    ///   - feed: The feed that gets the subscribers.
    func moveSubscribers(ownedBy owner: ObjectIdentifier, to feed: ChangeFeed) {
        guard feed !== self else {
            return
        }
        for (id, subscriber) in subscribers(ownedBy: owner) {
            let isRefused = subscriber.route.move(from: self, withID: id) { () -> SubscriberPlace? in
                self.removeSubscriber(withID: id)
                return feed.insert(subscriber).map { newID in SubscriberPlace(feed: feed, id: newID) }
            }
            if isRefused {
                subscriber.continuation.finish()
            }
        }
    }

    /// Sends the changes of the board to each subscriber of one owner.
    ///
    /// - Parameters:
    ///   - changes: The changes, each of one transaction, in the order of their transactions.
    ///   - owner: The session view that made the changes.
    ///   - view: The read view of the board now. The filter of each subscriber tests its nodes.
    ///   - board: The board that the resolvers of the changes read.
    func publish(
        _ changes: [Change],
        to owner: ObjectIdentifier,
        readingNodesOf view: BoardView,
        resolvingIn board: EventBoard
    ) {
        for subscriber in subscribers(ownedBy: owner).values {
            send(changes, to: subscriber, readingNodesOf: view, resolvingIn: board)
        }
    }

    /// Ends the stream of each subscriber of one owner, for example when its session view closes. The other
    /// subscribers stay.
    ///
    /// - Parameter owner: The owner.
    func finish(ownedBy owner: ObjectIdentifier) {
        let ended = state.withLock { state in
            guard case .open(var subscribers) = state else {
                return [Subscriber]()
            }
            let ended = subscribers.remove(ownedBy: owner)
            state = .open(subscribers)
            return ended
        }
        for subscriber in ended {
            subscriber.continuation.finish()
        }
    }

    /// Ends the stream of each subscriber, and refuses each later subscriber (plan.md §7.2, `close()`). A second
    /// call does nothing.
    func finish() {
        let subscribers = state.withLock { state in
            guard case .open(let subscribers) = state else {
                return [Subscriber]()
            }
            state = .closed
            return Array(subscribers.byID.values)
        }
        for subscriber in subscribers {
            subscriber.continuation.finish()
        }
    }

    /// Gives the subscribers of one owner.
    ///
    /// - Parameter owner: The owner.
    /// - Returns: The subscribers, by their ids. The table is empty when the feed is finished.
    private func subscribers(ownedBy owner: ObjectIdentifier) -> [Int: Subscriber] {
        state.withLock { state in
            guard case .open(let subscribers) = state else {
                return [:]
            }
            return subscribers.byID.filter { _, subscriber in subscriber.owner == owner }
        }
    }

    /// Adds a subscriber with a new id.
    ///
    /// - Parameter subscriber: The subscriber.
    /// - Returns: The id of the subscriber, or `nil` when the feed is finished.
    private func insert(_ subscriber: Subscriber) -> Int? {
        state.withLock { state in
            guard case .open(var subscribers) = state else {
                return nil
            }
            let id = subscribers.add(subscriber)
            state = .open(subscribers)
            return id
        }
    }

    /// Sends the changes that the filter of one subscriber keeps to that subscriber.
    ///
    /// The filter gives no error on the board now. A merge that gives a second task the short id of a `^id` value
    /// does not stop the stream: the filter then matches each task with that short id (divergence.md Q20).
    ///
    /// - Parameters:
    ///   - changes: The changes, each of one transaction, in the order of their transactions.
    ///   - subscriber: The subscriber.
    ///   - view: The read view of the board now. The filter of the subscriber tests its nodes.
    ///   - board: The board that the resolvers of the changes read.
    private func send(
        _ changes: [Change],
        to subscriber: Subscriber,
        readingNodesOf view: BoardView,
        resolvingIn board: EventBoard
    ) {
        for change in subscriber.filter.applied(to: changes, readingNodesOf: view) {
            subscriber.continuation.yield(ChangeEvent(change: change, board: board))
        }
    }

    /// Removes a subscriber: the subscriber of a stream that ended, or a subscriber that moves to a different feed.
    ///
    /// - Parameter id: The id of the subscriber.
    fileprivate func removeSubscriber(withID id: Int) {
        state.withLock { state in
            guard case .open(var subscribers) = state else {
                return
            }
            subscribers.byID[id] = nil
            state = .open(subscribers)
        }
    }
}

/// The state of a ``ChangeFeed``.
private enum FeedState {
    /// The feed sends events to its subscribers.
    case open(Subscribers)

    /// ``ChangeFeed/finish()`` ended each stream. No subscriber comes again.
    case closed
}

/// The subscribers of an open ``ChangeFeed``, each by its id.
private struct Subscribers {
    /// The id of the next subscriber.
    private var nextID = 0

    /// The subscribers, by their ids.
    var byID: [Int: Subscriber] = [:]

    /// Adds a subscriber with a new id.
    ///
    /// - Parameter subscriber: The subscriber.
    /// - Returns: The id of the subscriber.
    mutating func add(_ subscriber: Subscriber) -> Int {
        let id = nextID
        nextID += 1
        byID[id] = subscriber
        return id
    }

    /// Removes each subscriber of one owner.
    ///
    /// - Parameter owner: The owner.
    /// - Returns: The removed subscribers.
    mutating func remove(ownedBy owner: ObjectIdentifier) -> [Subscriber] {
        let removed = byID.filter { _, subscriber in subscriber.owner == owner }
        byID = byID.filter { _, subscriber in subscriber.owner != owner }
        return Array(removed.values)
    }
}

/// One subscriber of a ``ChangeFeed``: its owner, its filters, the continuation of its events, and the feed where it
/// is now.
private struct Subscriber: Sendable {
    /// The session view that makes the events of the subscriber.
    let owner: ObjectIdentifier

    /// The filters of the subscriber.
    let filter: ChangeFilter

    /// The continuation of the events of the subscriber.
    let continuation: AsyncStream<ChangeEvent>.Continuation

    /// The feed of the subscriber now, and its id there. The end of the stream removes the subscriber from that feed.
    let route: SubscriberRoute
}

/// The feed where one subscriber is now, and the id of the subscriber in that feed. The feed holds it weakly, so that
/// the subscribers of a feed do not keep the feed alive.
private struct SubscriberPlace {
    /// The feed of the subscriber.
    weak var feed: ChangeFeed?

    /// The id of the subscriber in the feed.
    let id: Int
}

/// The place of one subscriber, behind a lock (divergence.md §16).
///
/// The termination handler of the stream of a subscriber is set one time, and calls ``end()``. A move of the
/// subscriber to a different feed changes the place under the same lock. Thus a stream that ends during a move
/// removes the subscriber from the feed where it is: the old feed before the move, or the new feed after it.
private final class SubscriberRoute: Sendable {
    /// The place of the subscriber, or `nil` before the start and after the end.
    private let place = Mutex<SubscriberPlace?>(nil)

    /// Records the first place of the subscriber.
    ///
    /// - Parameters:
    ///   - feed: The feed of the subscriber.
    ///   - id: The id of the subscriber in the feed.
    func start(in feed: ChangeFeed, withID id: Int) {
        place.withLock { place in
            place = SubscriberPlace(feed: feed, id: id)
        }
    }

    /// Moves the subscriber from one place to a new place, when the subscriber is still at the old place.
    ///
    /// - Parameters:
    ///   - feed: The feed of the old place.
    ///   - id: The id of the subscriber in that feed.
    ///   - relocate: Removes the subscriber from the old place, and gives the new place, or `nil` when the new feed
    ///     refuses the subscriber.
    /// - Returns: `true` when the new feed refused the subscriber: the caller then ends its stream. `false` when the
    ///   subscriber moved, or when its stream ended before the move.
    func move(from feed: ChangeFeed, withID id: Int, relocating relocate: () -> SubscriberPlace?) -> Bool {
        place.withLock { place in
            guard let current = place, current.feed === feed, current.id == id else {
                return false
            }
            place = relocate()
            return place == nil
        }
    }

    /// Removes the subscriber from the feed where it is, when its stream ends.
    func end() {
        place.withLock { place in
            if let current = place {
                current.feed?.removeSubscriber(withID: current.id)
            }
            place = nil
        }
    }
}
