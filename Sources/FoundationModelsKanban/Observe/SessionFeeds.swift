import Foundation
import Synchronization

/// The change feeds that one session view uses: the feed of each board that the view loaded, by the canonical path of
/// its repo directory (plan.md §6.7, divergence.md §16).
///
/// Each board engine owns one ``ChangeFeed``. A view adds the feed of each board that it reaches. Each subscriber that
/// `Subscription.changes` adds through the view is owned by the view, so the view sends the events of its own
/// subscribers, read from its own current board. ``finish()`` ends the subscribers of the view only: the subscribers
/// of the other views of the same boards stay.
///
/// The view and the resolvers of its calls use the feeds, so the table is behind a lock.
final class SessionFeeds: Sendable {
    /// The state of the feeds, behind a lock.
    private let state = Mutex(SessionFeedsState.open([:]))

    /// The owner of each subscriber of the view.
    private var owner: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    /// The canonical paths of the repo directories of the boards where the view has a subscriber.
    var subscribedBoards: Set<String> {
        Set(feeds.filter { _, feed in feed.hasSubscribers(ownedBy: owner) }.keys)
    }

    /// Adds the feed of a board that the view loaded. A second add of the same board does nothing.
    ///
    /// - Parameters:
    ///   - feed: The feed of the board.
    ///   - path: The canonical path of the repo directory of the board.
    func add(_ feed: ChangeFeed, forBoardAt path: String) {
        state.withLock { state in
            guard case .open(var feeds) = state, feeds[path] == nil else {
                return
            }
            feeds[path] = feed
            state = .open(feeds)
        }
    }

    /// Adds a subscriber of the view to the feed of a board.
    ///
    /// - Parameters:
    ///   - path: The canonical path of the repo directory of the board that the subscriber observes.
    ///   - filter: The filters of the subscriber.
    /// - Returns: The events of the subscriber. The stream has ended when the view is closed, or when the view did not
    ///   load the board.
    func subscribe(toBoardAt path: String, filteredBy filter: ChangeFilter) -> AsyncStream<ChangeEvent> {
        guard isOpen else {
            return Self.endedEvents()
        }
        guard let feed = feeds[path] else {
            assertionFailure("A subscriber observes the board at \(path), and the view did not load it")
            Log.kanban.error("A subscriber observes a board that the view did not load", metadata: ["path": "\(path)"])
            return Self.endedEvents()
        }
        return feed.subscribe(filteredBy: filter, ownedBy: owner)
    }

    /// Gives a stream of events that has ended.
    ///
    /// - Returns: The stream.
    private static func endedEvents() -> AsyncStream<ChangeEvent> {
        AsyncStream { continuation in continuation.finish() }
    }

    /// Sends the changes of one board to each subscriber of the view on that board.
    ///
    /// - Parameters:
    ///   - changes: The changes, each of one transaction, in the order of their transactions.
    ///   - path: The canonical path of the repo directory of the board.
    ///   - view: The read view of the board now. The filter of each subscriber tests its nodes.
    ///   - board: The board that the resolvers of the changes read.
    func publish(
        _ changes: [Change],
        toBoardAt path: String,
        readingNodesOf view: BoardView,
        resolvingIn board: EventBoard
    ) {
        feeds[path]?.publish(changes, to: owner, readingNodesOf: view, resolvingIn: board)
    }

    /// Ends the stream of each subscriber of the view, and refuses each later subscriber of the view (plan.md §7.2,
    /// `close()`). A second call does nothing.
    func finish() {
        let ended = state.withLock { state in
            guard case .open(let feeds) = state else {
                return [ChangeFeed]()
            }
            state = .closed
            return Array(feeds.values)
        }
        for feed in ended {
            feed.finish(ownedBy: owner)
        }
    }

    /// `true` until ``finish()``.
    private var isOpen: Bool {
        state.withLock { state in
            guard case .open = state else {
                return false
            }
            return true
        }
    }

    /// The feed of each board, or no feed after ``finish()``.
    private var feeds: [String: ChangeFeed] {
        state.withLock { state in
            guard case .open(let feeds) = state else {
                return [:]
            }
            return feeds
        }
    }
}

/// The state of a ``SessionFeeds``.
private enum SessionFeedsState {
    /// The view uses the feed of each board, by the canonical path of its repo directory.
    case open([String: ChangeFeed])

    /// ``SessionFeeds/finish()`` ended the subscribers of the view. No subscriber of the view comes again.
    case closed
}
