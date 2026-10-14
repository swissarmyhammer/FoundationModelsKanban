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
        let subscriber = Subscriber(owner: owner, filter: filter, continuation: continuation)
        let id = state.withLock { state -> Int? in
            guard case .open(var subscribers) = state else {
                return nil
            }
            let id = subscribers.add(subscriber)
            state = .open(subscribers)
            return id
        }
        guard let id else {
            continuation.finish()
            return events
        }
        continuation.onTermination = { [weak self] _ in
            self?.removeSubscriber(withID: id)
        }
        return events
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
        for subscriber in subscribers(ownedBy: owner) {
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
    /// - Returns: The subscribers. The list is empty when the feed is finished.
    private func subscribers(ownedBy owner: ObjectIdentifier) -> [Subscriber] {
        state.withLock { state in
            guard case .open(let subscribers) = state else {
                return [Subscriber]()
            }
            return subscribers.byID.values.filter { subscriber in subscriber.owner == owner }
        }
    }

    /// Sends the changes that the filter of one subscriber keeps to that subscriber.
    ///
    /// The subscription checked its filter against the board when it started, but a later change can make the filter
    /// fail: a merge can give a second task the short id of a `^id` value (`AMBIGUOUS_ID`). The stream of a subscriber
    /// has no error, so the feed writes the error to the log and ends the stream of the subscriber. The client then
    /// sees that the subscription ended, and can subscribe again with a full id.
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
        do {
            for change in try subscriber.filter.applied(to: changes, readingNodesOf: view) {
                subscriber.continuation.yield(ChangeEvent(change: change, board: board))
            }
        } catch {
            Log.kanban.error(
                "The filter of a subscription fails on the board now; the subscription ends",
                metadata: ["board": "\(view.boardKey)", "code": "\(error.code)", "message": "\(error.message)"]
            )
            subscriber.continuation.finish()
        }
    }

    /// Removes the subscriber of a stream that ended.
    ///
    /// - Parameter id: The id of the subscriber.
    private func removeSubscriber(withID id: Int) {
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

/// One subscriber of a ``ChangeFeed``: its owner, its filters, and the continuation of its events.
private struct Subscriber: Sendable {
    /// The session view that makes the events of the subscriber.
    let owner: ObjectIdentifier

    /// The filters of the subscriber.
    let filter: ChangeFilter

    /// The continuation of the events of the subscriber.
    let continuation: AsyncStream<ChangeEvent>.Continuation
}
