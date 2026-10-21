import Foundation
import Synchronization

/// The change feeds that one session view uses: the feed of each board that the view loaded, by the canonical path of
/// its repo directory (plan.md §6.7, divergence.md §16).
///
/// Each board engine owns one ``ChangeFeed`` with the change log of its board. A view adds the feed of each board that
/// it reaches. Each subscriber that `Subscription.changes` adds through the view is owned by the view. ``finish()``
/// ends the subscribers of the view that run now: the subscribers of the other views of the same boards stay, and a
/// later subscriber of the view gets the changes again.
///
/// The view and the resolvers of its calls use the feeds, so the table is behind a lock.
final class SessionFeeds: Sendable {
    /// The feed of each board that the view loaded, by the canonical path of its repo directory, behind a lock.
    private let table = Mutex<[String: ChangeFeed]>([:])

    /// The owner of each subscriber of the view.
    private var owner: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    /// Adds the feed of a board that the view loaded. A second add of the same board does nothing.
    ///
    /// - Parameters:
    ///   - feed: The feed of the board.
    ///   - path: The canonical path of the repo directory of the board.
    func add(_ feed: ChangeFeed, forBoardAt path: String) {
        table.withLock { feeds in
            guard feeds[path] == nil else {
                return
            }
            feeds[path] = feed
        }
    }

    /// Puts the feed of a new board in the place of the feed of a board that the view loaded at the same path, for
    /// example when a new repo replaces the repo of a related board (divergence.md §16). Each subscriber of the view on
    /// the old feed moves to the new feed, so that its stream continues with the changes of the new board. The
    /// subscribers of the other views stay on the old feed.
    ///
    /// - Parameters:
    ///   - feed: The feed of the new board.
    ///   - path: The canonical path of the repo directory of the board.
    func replace(_ feed: ChangeFeed, forBoardAt path: String) async {
        let old = table.withLock { feeds in
            feeds.updateValue(feed, forKey: path)
        }
        await old?.moveSubscribers(ownedBy: owner, to: feed)
    }

    /// Takes away the feed of a board that the view does not hold any more, and ends the stream of each subscriber of
    /// the view on it, for example when the folder of a related board moved away from its path and no board can load
    /// at the path now (divergence.md §16, Gap 6). The subscribers of the other views stay.
    ///
    /// - Parameter path: The canonical path of the repo directory of the board.
    func remove(forBoardAt path: String) {
        let old = table.withLock { feeds in
            feeds.removeValue(forKey: path)
        }
        old?.finish(ownedBy: owner)
    }

    /// Adds a subscriber of the view to the feed of a board.
    ///
    /// - Parameters:
    ///   - path: The canonical path of the repo directory of the board that the subscriber observes.
    ///   - cursor: The cursor to resume after, or `nil` for the new changes only.
    ///   - filter: The filters of the subscriber.
    /// - Returns: The events of the subscriber. The stream ends with `RESYNC_REQUIRED` when the change log of the
    ///   board cannot resume after the cursor. The stream has ended when the view did not load the board, or when the
    ///   engine of the board is closed.
    func subscribe(
        toBoardAt path: String,
        after cursor: String?,
        filteredBy filter: ChangeFilter
    ) async -> AsyncThrowingStream<ChangeEvent, Error> {
        guard let feed = feeds[path] else {
            assertionFailure("A subscriber observes the board at \(path), and the view did not load it")
            Log.kanban.error("A subscriber observes a board that the view did not load", metadata: ["path": "\(path)"])
            return ChangeEvent.makeEndedStream()
        }
        return await feed.subscribe(after: cursor, filteredBy: filter, ownedBy: owner)
    }

    /// Ends the stream of each subscriber of the view that runs now (plan.md §7.2, `close()`). The feeds stay, so a
    /// later subscriber of the view gets the changes of its board.
    func finish() {
        for feed in feeds.values {
            feed.finish(ownedBy: owner)
        }
    }

    /// The feed of each board, by the canonical path of its repo directory.
    private var feeds: [String: ChangeFeed] {
        table.withLock { feeds in feeds }
    }
}
