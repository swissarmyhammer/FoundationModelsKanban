import Foundation
import Graphiti

// MARK: - Resolver

/// The events of one `Subscription.changes` field: the changes of the feed, each after the store of the subscription
/// reads the board of the change.
typealias ChangeEvents = AsyncMapSequence<AsyncStream<ChangeEvent>, Change>

extension KanbanResolver {
    /// Resolves the source of `Subscription.changes`: a new subscriber of the change feed (plan.md §6.7).
    ///
    /// The subscriber observes the current board, or the board that `board` names. Its filter tests the nodes of each
    /// change in the board after the change. GraphQLSwift runs each event with the context of this call, so before an
    /// event runs, the store of the context gets the board of the event: the board as the engine read it through the
    /// serial gate.
    ///
    /// - Parameters:
    ///   - context: The context of the `subscribe` call. Its store is the store of each event.
    ///   - arguments: The board and the filter.
    /// - Returns: The changes. In a run that the engine runs again after it loads the board, the stream has ended
    ///   and the subscriber is not added.
    /// - Throws: ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board for `board`. An
    ///   error of ``ChangeFilter/init(parsing:)`` or of ``ChangeFilter/check(against:)``.
    ///   ``KanbanError/notFound(type:reference:)`` when the board has no repo directory to watch.
    func changes(context: KanbanContext, arguments: ChangesArguments) async throws(KanbanError) -> ChangeEvents {
        let store = context.store
        let events = try await Self.events(of: arguments, readIn: store, from: context.feed)
        return events.map { event in
            await store.replace(with: event.board)
            return event.change
        }
    }

    /// Adds a subscriber to the change feed for the board and the filter of a `changes` field.
    ///
    /// - Parameters:
    ///   - arguments: The board and the filter.
    ///   - store: The store of the `subscribe` call. It resolves the board.
    ///   - feed: The change feed.
    /// - Returns: The events of the subscriber, or a stream that has ended when the engine did not load the board
    ///   yet. The engine then runs the call again after the load.
    /// - Throws: An error of ``BoardStore/view(ofBoard:)``, of ``ChangeFilter/init(parsing:)``, or of
    ///   ``ChangeFilter/check(against:)`` on the board now, for example `AMBIGUOUS_ID` for a `^id` value that is a
    ///   short id of two or more tasks.
    ///   ``KanbanError/notFound(type:reference:)`` for the board when the board has no repo directory to watch, for
    ///   example a board in memory only. The subscription then gives one response with the error, and ends.
    private static func events(
        of arguments: ChangesArguments,
        readIn store: BoardStore,
        from feed: ChangeFeed
    ) async throws(KanbanError) -> AsyncStream<ChangeEvent> {
        guard let view = try await store.view(ofBoard: arguments.board) else {
            return endedEvents()
        }
        let filter = try ChangeFilter(parsing: arguments.filter)
        try filter.check(against: view)
        guard let directory = view.source?.directory else {
            Log.kanban.error(
                "A subscription names a board in memory only; the subscription ends",
                metadata: ["board": "\(view.boardKey)"]
            )
            throw .notFound(type: .board, reference: view.boardKey)
        }
        return feed.subscribe(toBoardAt: directory.canonicalPath, filteredBy: filter)
    }

    /// Gives a stream of events that has ended.
    ///
    /// - Returns: The stream.
    private static func endedEvents() -> AsyncStream<ChangeEvent> {
        AsyncStream { continuation in continuation.finish() }
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `Subscription` type with its one field, `changes` (plan.md §4.1, §6.7).
    ///
    /// - Returns: This builder, for method chaining.
    func addChangesSubscription() -> Self {
        addSubscription {
            SubscriptionField("changes", as: Change.self, atSub: KanbanResolver.changes) {
                Argument("board", at: \.board)
                Argument("filter", at: \.filter)
            }
        }
    }
}
