import Foundation
import FoundationModelsExtras
import Synchronization

// MARK: - Events

/// The board of one event of the change feed, as the resolvers of the event read it (plan.md §6.7, serial gate).
///
/// The engine reads the board through the serial gate when it logs the event. Thus, the resolvers of the event
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

    /// Gives this board as the board after the change of one cursor of the change log (KANBAN-7), so that
    /// `Board.cursor` in the event gives that cursor.
    ///
    /// - Parameter cursor: The cursor of the change.
    /// - Returns: The board with the cursor.
    func reading(atCursor cursor: String) -> EventBoard {
        EventBoard(work: work, key: key, source: source.reading(atCursor: cursor), related: related)
    }
}

/// One event of the change feed: the change of one transaction, and the board that its resolvers read.
struct ChangeEvent: Sendable {
    /// The change, with the updates that the filters of the subscriber keep, and its cursor.
    let change: Change

    /// The board that the resolvers of the change read.
    let board: EventBoard

    /// Gives a stream of events that has ended: the stream of a subscriber that gets no event.
    ///
    /// - Returns: The stream.
    static func makeEndedStream() -> AsyncThrowingStream<ChangeEvent, Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }
}

// MARK: - Log entries

/// The board after one round of changes of a change log (``ChangeRound``): the board that the resolvers of the
/// changes of the round read, and the read view whose nodes the filter of each subscriber tests.
struct RoundState: Sendable {
    /// The board that the resolvers of the changes read.
    let board: EventBoard

    /// The read view of the board after the round. The filter of each subscriber tests its nodes.
    let view: BoardView
}

/// The board after one round of a change log, until the feed releases it.
///
/// Each round holds a full copy of the graph and of the events of its board, so the feed keeps the board of the
/// newest rounds only (``ChangeFeed/heldRoundCount``). A change of a released round reads the board after the newest
/// round of the log.
final class RoundBoard: Sendable {
    /// The board after the round, or `nil` after ``release()``, behind a lock.
    private let held: Mutex<RoundState?>

    /// Holds the board after one round.
    ///
    /// - Parameter state: The board after the round.
    init(_ state: RoundState) {
        held = Mutex(state)
    }

    /// The board after the round, or `nil` when the feed released it.
    var state: RoundState? {
        held.withLock { state in state }
    }

    /// Lets go of the board after the round.
    func release() {
        held.withLock { state in state = nil }
    }
}

/// One change of the change log of a board: the change, and the board after its round.
struct LoggedChange: Sendable {
    /// The change, with each update of its round.
    let change: Change

    /// The board after the round of the change.
    let round: RoundBoard
}

// MARK: - Feed

/// The change log of one board, and the subscribers that read it (plan.md §6.7, KANBAN-7, divergence.md §16).
///
/// Each board engine has one feed, so each session view of the board reads the same log and the same cursors. Each
/// change of the board goes into the log one time (``append(_:readingNodesOf:resolvingIn:)``): a commit of a call, a
/// batch of the file watcher, and each transaction of a `git pull`. The log is the `ChangeLog` of the toolkit: it
/// gives each change an opaque cursor, and keeps the newest ``capacity`` changes.
///
/// `Subscription.changes` adds a subscriber with its filter and its owner: the session view that made it. The
/// subscriber gets the changes of the log after its cursor, then the new changes, in order, each change with the
/// updates that its filter keeps. A cursor that the log cannot resume ends the stream with `RESYNC_REQUIRED`.
/// ``moveSubscribers(ownedBy:to:)`` moves the subscribers of one owner to the feed of a new board at the same path.
/// ``finish(ownedBy:)`` ends the streams of one owner. ``finish()`` ends each stream, and a subscriber that comes later
/// gets a stream that has ended.
///
/// The engine and the resolvers of different calls use the feed, so its state is behind locks.
final class ChangeFeed: Sendable {
    /// The number of the newest rounds whose board the feed keeps for the resolvers of their changes.
    static let heldRoundCount = 16

    /// The reason of the `RESYNC_REQUIRED` of each subscriber when the feed starts a new log.
    static let restartReason = "The board changed, and the change log could not keep the changes."

    /// The reason of the `RESYNC_REQUIRED` of a subscriber whose stream holds more than ``capacity`` changes.
    static let fellBehindReason = "The subscriber fell more than the capacity of the change log behind."

    /// The number of the newest changes that the change log keeps.
    let capacity: Int

    /// The change log of the board, behind a lock, because ``restart()`` puts a new log in its place.
    private let log: Mutex<ChangeLog<LoggedChange>>

    /// The boards after the newest rounds, oldest first, behind a lock.
    private let heldRounds = Mutex<[RoundBoard]>([])

    /// The subscribers of the feed, behind a lock.
    private let state = Mutex(FeedState.open(Subscribers()))

    /// Makes a feed with an empty change log.
    ///
    /// - Parameter capacity: The number of the newest changes that the change log keeps. It must be at least 1.
    init(capacity: Int) {
        self.capacity = capacity
        log = Mutex(ChangeLog(capacity: capacity))
    }

    /// The cursor of the newest change of the log: the cursor of the board now.
    var cursor: String {
        get async {
            await currentLog.cursor
        }
    }

    /// Tells if an owner has a subscriber in this feed.
    ///
    /// - Parameter owner: The owner.
    /// - Returns: `true` when the owner has a subscriber.
    func hasSubscribers(ownedBy owner: ObjectIdentifier) -> Bool {
        !subscribers(ownedBy: owner).isEmpty
    }

    /// Appends the changes of one round to the change log, in order. A change with no update is not appended,
    /// because each filter leaves it out.
    ///
    /// - Parameters:
    ///   - changes: The changes, each of one transaction, in the order of their transactions.
    ///   - view: The read view of the board after the round. The filter of each subscriber tests its nodes.
    ///   - board: The board that the resolvers of the changes read.
    func append(_ changes: [Change], readingNodesOf view: BoardView, resolvingIn board: EventBoard) async {
        let kept = changes.filter { change in !change.nodeUpdates.isEmpty }
        guard !kept.isEmpty else {
            return
        }
        let round = hold(RoundState(board: board, view: view))
        let log = currentLog
        for change in kept {
            await log.append(LoggedChange(change: change, round: round))
        }
    }

    /// Puts a new, empty change log in the place of the log, with a new epoch, when the engine could not append the
    /// changes of a round. A cursor of the old log then gives `RESYNC_REQUIRED`, and each subscriber ends with
    /// `RESYNC_REQUIRED`, so that no client misses those changes with no word.
    func restart() {
        log.withLock { log in log = ChangeLog(capacity: capacity) }
        let released = heldRounds.withLock { rounds in
            defer { rounds = [] }
            return rounds
        }
        for round in released {
            round.release()
        }
        let ended = state.withLock { state in
            guard case .open(var subscribers) = state else {
                return [Subscriber]()
            }
            let ended = Array(subscribers.byID.values)
            subscribers.byID = [:]
            state = .open(subscribers)
            return ended
        }
        for subscriber in ended {
            subscriber.end(throwing: GraphQLToolkitError.resyncRequired(reason: Self.restartReason))
        }
    }

    /// Adds a subscriber.
    ///
    /// The subscriber reads the change log before the call returns, so it gets each change that the log takes after
    /// the call.
    ///
    /// - Parameters:
    ///   - cursor: The cursor to resume after, or `nil` for the new changes only.
    ///   - filter: The filters of the subscriber.
    ///   - owner: The session view that made the subscriber.
    /// - Returns: The events of the subscriber, in the order of the log. The stream ends with `RESYNC_REQUIRED` when
    ///   the log cannot give each change after the cursor. The stream has ended when the feed is finished.
    func subscribe(
        after cursor: String?,
        filteredBy filter: ChangeFilter,
        ownedBy owner: ObjectIdentifier
    ) async -> AsyncThrowingStream<ChangeEvent, Error> {
        let (events, continuation) = AsyncThrowingStream<ChangeEvent, Error>.makeStream(
            bufferingPolicy: .bufferingOldest(capacity)
        )
        let subscriber = Subscriber(
            owner: owner,
            filter: filter,
            continuation: continuation,
            route: SubscriberRoute(),
            relay: SubscriberRelay()
        )
        guard let id = insert(subscriber) else {
            continuation.finish()
            return events
        }
        subscriber.route.start(in: self, withID: id)
        continuation.onTermination = { _ in
            subscriber.route.end()
            subscriber.relay.stop()
        }
        await startRelay(of: subscriber, after: cursor)
        return events
    }

    /// Moves each subscriber of one owner to a different feed, for example when a new repo replaces the repo of a
    /// board at the same path, and the session view replaces the engine of that path (divergence.md §16). The streams
    /// of the subscribers continue with the new changes of the log of the new feed. A subscriber whose stream ends
    /// during the move goes away from the feed where it is. The new feed ends the stream of each moved subscriber when
    /// it is finished.
    ///
    /// - Parameters:
    ///   - owner: The owner of the subscribers to move.
    ///   - feed: The feed that gets the subscribers.
    func moveSubscribers(ownedBy owner: ObjectIdentifier, to feed: ChangeFeed) async {
        guard feed !== self else {
            return
        }
        for (id, subscriber) in subscribers(ownedBy: owner) {
            let outcome = subscriber.route.move(from: self, withID: id) { () -> SubscriberPlace? in
                self.removeSubscriber(withID: id)
                return feed.insert(subscriber).map { newID in SubscriberPlace(feed: feed, id: newID) }
            }
            switch outcome {
            case .moved:
                await feed.startRelay(of: subscriber, after: nil)
            case .refused:
                subscriber.end(throwing: nil)
            case .ended:
                break
            }
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
            subscriber.end(throwing: nil)
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
            subscriber.end(throwing: nil)
        }
    }

    /// The change log of the board now.
    private var currentLog: ChangeLog<LoggedChange> {
        log.withLock { log in log }
    }

    /// Keeps the board after a new round, and releases the board of each round that is older than the newest
    /// ``heldRoundCount`` rounds.
    ///
    /// - Parameter state: The board after the new round.
    /// - Returns: The held board of the new round.
    private func hold(_ state: RoundState) -> RoundBoard {
        let round = RoundBoard(state)
        let released = heldRounds.withLock { rounds in
            rounds.append(round)
            let overflow = max(rounds.count - Self.heldRoundCount, .zero)
            let released = rounds.prefix(overflow)
            rounds.removeFirst(overflow)
            return Array(released)
        }
        for old in released {
            old.release()
        }
        return round
    }

    /// The board after the newest round that the feed keeps, or `nil` when the log took no change yet.
    private var newestRoundState: RoundState? {
        heldRounds.withLock { rounds in rounds.last?.state }
    }

    /// Gives the board that a change of the log reads: the board after its round, or the board after the newest
    /// round when the feed released the board of its round.
    ///
    /// - Parameter logged: The change.
    /// - Returns: The board, or `nil` when the feed keeps no board.
    private func roundState(of logged: LoggedChange) -> RoundState? {
        logged.round.state ?? newestRoundState
    }

    /// Gives the event of one change of the log for a subscriber: the change with the updates that the filter keeps,
    /// with the cursor of the change, and the board of the change at that cursor.
    ///
    /// The filter gives no error on the board now. A merge that gives a second task the short id of a `^id` value
    /// does not stop the stream: the filter then matches each task with that short id (divergence.md Q20).
    ///
    /// - Parameters:
    ///   - entry: The entry of the change log.
    ///   - filter: The filter of the subscriber.
    /// - Returns: The event, or `nil` when the filter keeps no update of the change.
    private func event(of entry: ChangeLogEntry<LoggedChange>, filteredBy filter: ChangeFilter) -> ChangeEvent? {
        guard
            let state = roundState(of: entry.event),
            let change = filter.applied(to: [entry.event.change], readingNodesOf: state.view).first
        else {
            return nil
        }
        return ChangeEvent(
            change: change.reading(atCursor: entry.cursor),
            board: state.board.reading(atCursor: entry.cursor)
        )
    }

    /// Starts the relay of a subscriber on the change log of this feed: the relay reads the changes of the log after a
    /// cursor, and gives the subscriber each change that its filter keeps.
    ///
    /// - Parameters:
    ///   - subscriber: The subscriber.
    ///   - cursor: The cursor to resume after, or `nil` for the new changes only.
    private func startRelay(of subscriber: Subscriber, after cursor: String?) async {
        let filter = subscriber.filter
        let entries = await currentLog.changes(after: cursor) { [weak self] logged in
            guard let self, let state = roundState(of: logged) else {
                return false
            }
            return !filter.applied(to: [logged.change], readingNodesOf: state.view).isEmpty
        }
        subscriber.relay.start(reading: entries, into: subscriber.continuation) { [weak self] entry in
            self?.event(of: entry, filteredBy: filter)
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
            return subscribers.subscribers(ownedBy: owner)
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
    /// The feed gives the changes of its log to its subscribers.
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

    /// Gives the subscribers of one owner. This is the one place that tests the owner of a subscriber.
    ///
    /// - Parameter owner: The owner.
    /// - Returns: The subscribers of the owner, by their ids.
    func subscribers(ownedBy owner: ObjectIdentifier) -> [Int: Subscriber] {
        byID.filter { _, subscriber in subscriber.owner == owner }
    }

    /// Removes each subscriber of one owner.
    ///
    /// - Parameter owner: The owner.
    /// - Returns: The removed subscribers.
    mutating func remove(ownedBy owner: ObjectIdentifier) -> [Subscriber] {
        let removed = subscribers(ownedBy: owner)
        for id in removed.keys {
            byID[id] = nil
        }
        return Array(removed.values)
    }
}

/// One subscriber of a ``ChangeFeed``: its owner, its filters, the continuation of its events, the feed where it is
/// now, and the relay that reads the change log of that feed.
private struct Subscriber: Sendable {
    /// The session view that made the subscriber.
    let owner: ObjectIdentifier

    /// The filters of the subscriber.
    let filter: ChangeFilter

    /// The continuation of the events of the subscriber.
    let continuation: AsyncThrowingStream<ChangeEvent, Error>.Continuation

    /// The feed of the subscriber now, and its id there. The end of the stream removes the subscriber from that feed.
    let route: SubscriberRoute

    /// The task that gives the changes of the log of the feed of the subscriber to its stream.
    let relay: SubscriberRelay

    /// Stops the relay and ends the stream.
    ///
    /// - Parameter error: The error that ends the stream, or `nil` to end it with no error.
    func end(throwing error: (any Error)?) {
        relay.stop()
        continuation.finish(throwing: error)
    }
}

/// The feed where one subscriber is now, and the id of the subscriber in that feed. The feed holds it weakly, so that
/// the subscribers of a feed do not keep the feed alive.
private struct SubscriberPlace {
    /// The feed of the subscriber.
    weak var feed: ChangeFeed?

    /// The id of the subscriber in the feed.
    let id: Int
}

/// What a move of a subscriber to a new feed did.
private enum SubscriberMove {
    /// The subscriber is in the new feed now.
    case moved

    /// The new feed is finished and refused the subscriber: the caller ends its stream.
    case refused

    /// The stream of the subscriber ended before the move, so the subscriber did not move.
    case ended
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
    /// - Returns: What the move did.
    func move(
        from feed: ChangeFeed,
        withID id: Int,
        relocating relocate: () -> SubscriberPlace?
    ) -> SubscriberMove {
        place.withLock { place in
            guard let current = place, current.feed === feed, current.id == id else {
                return .ended
            }
            place = relocate()
            return place == nil ? .refused : .moved
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

/// The task that gives the changes of a change log to the stream of one subscriber, behind a lock (KANBAN-7).
///
/// A `ChangeLog` stream cannot be ended from outside, and a subscriber that moves to a new feed reads a new log. So
/// the stream of the subscriber is its own stream, and this relay reads the stream of the log into it. A new start
/// cancels the task that runs, and a stop cancels it for good.
///
/// A cancel does not stop a task at once: the task can still hold a change of the old log. So each task has a run
/// number, and a task gives the stream an event or an end only while its run is the run of the relay. The check and
/// the yield are under the lock, so after ``start(reading:into:mapping:)`` or ``stop()`` returns, the old task gives
/// the stream nothing more.
private final class SubscriberRelay: Sendable {
    /// The state of a relay.
    private enum State {
        /// No task runs yet.
        case idle

        /// The task of one run runs.
        case running(Task<Void, Never>, run: Int)

        /// ``stop()`` ended the relay. No task starts again.
        case stopped
    }

    /// The state of the relay, and the number of the last run, behind a lock.
    private let state = Mutex((relay: State.idle, lastRun: 0))

    /// Starts a task that reads the changes of a log and yields the event of each one, and cancels the task that ran
    /// before. A stopped relay starts no task, and the stream of the log then ends.
    ///
    /// The task starts under the lock, so it yields nothing before the relay records its run.
    ///
    /// - Parameters:
    ///   - entries: The stream of the changes of the log.
    ///   - continuation: The continuation of the stream of the subscriber.
    ///   - event: Gives the event of one change, or `nil` when the subscriber gets no event for it.
    func start(
        reading entries: ChangeLog<LoggedChange>.Changes,
        into continuation: AsyncThrowingStream<ChangeEvent, Error>.Continuation,
        mapping event: @escaping @Sendable (ChangeLogEntry<LoggedChange>) -> ChangeEvent?
    ) {
        let cancelled = state.withLock { state -> Task<Void, Never>? in
            let previous: Task<Void, Never>?
            switch state.relay {
            case .stopped:
                return nil
            case .idle:
                previous = nil
            case .running(let task, _):
                previous = task
            }
            state.lastRun += 1
            let run = state.lastRun
            let task = Task { [self] in
                await relay(entries, into: continuation, mapping: event, inRun: run)
            }
            state.relay = .running(task, run: run)
            return previous
        }
        cancelled?.cancel()
    }

    /// Cancels the task that runs, and starts no task again. A second call does nothing.
    func stop() {
        let task = state.withLock { state -> Task<Void, Never>? in
            defer { state.relay = .stopped }
            guard case .running(let task, _) = state.relay else {
                return nil
            }
            return task
        }
        task?.cancel()
    }

    /// Yields an event to the stream of the subscriber when a run is the run of the relay, under the lock.
    ///
    /// - Parameters:
    ///   - next: The event.
    ///   - continuation: The continuation of the stream of the subscriber.
    ///   - run: The run of the task that yields.
    /// - Returns: The result of the yield, or `nil` when the run is not the run of the relay.
    private func yield(
        _ next: ChangeEvent,
        to continuation: AsyncThrowingStream<ChangeEvent, Error>.Continuation,
        inRun run: Int
    ) -> AsyncThrowingStream<ChangeEvent, Error>.Continuation.YieldResult? {
        state.withLock { state in
            guard case .running(_, let matchedRun) = state.relay, matchedRun == run else {
                return nil
            }
            return continuation.yield(next)
        }
    }

    /// Tells if a run is the run of the relay.
    ///
    /// - Parameter run: The run.
    /// - Returns: `true` when the task of the run is the task of the relay.
    private func isCurrent(run: Int) -> Bool {
        state.withLock { state in
            guard case .running(_, let matchedRun) = state.relay, matchedRun == run else {
                return false
            }
            return true
        }
    }

    /// Reads the changes of a log, and yields the event of each one to the stream of the subscriber. A task whose
    /// run is no longer the run of the relay gives the stream nothing: the run that replaces it, or the stop, decides
    /// the end of the stream.
    ///
    /// - Parameters:
    ///   - entries: The stream of the changes of the log.
    ///   - continuation: The continuation of the stream of the subscriber.
    ///   - event: Gives the event of one change, or `nil` when the subscriber gets no event for it.
    ///   - run: The run of this task.
    private func relay(
        _ entries: ChangeLog<LoggedChange>.Changes,
        into continuation: AsyncThrowingStream<ChangeEvent, Error>.Continuation,
        mapping event: @Sendable (ChangeLogEntry<LoggedChange>) -> ChangeEvent?,
        inRun run: Int
    ) async {
        do {
            for try await entry in entries {
                guard let next = event(entry) else {
                    continue
                }
                switch yield(next, to: continuation, inRun: run) {
                case nil:
                    return
                case .dropped:
                    // The finish is outside the lock: it calls the termination handler, which stops this relay.
                    let reason = ChangeFeed.fellBehindReason
                    continuation.finish(throwing: GraphQLToolkitError.resyncRequired(reason: reason))
                    return
                default:
                    continue
                }
            }
        } catch {
            guard isCurrent(run: run) else {
                return
            }
            continuation.finish(throwing: error)
        }
    }
}
