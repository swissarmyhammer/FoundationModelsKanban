import Foundation
import Graphiti

// MARK: - Resolver

/// The events of one `Subscription.changes` field: the changes of the change log of the board, each after the store
/// of the subscription reads the board of the change.
typealias ChangeEvents = AsyncMapSequence<AsyncThrowingStream<ChangeEvent, Error>, Change>

extension KanbanResolver {
    /// Resolves the source of `Subscription.changes`: a new subscriber of the change log of a board (plan.md §6.7,
    /// KANBAN-7).
    ///
    /// The subscriber observes the current board, or the board that `board` names. It gets the changes of the log
    /// after `after`, then the new changes, in order. Its filter tests the nodes of each change in the board after the
    /// change. GraphQLSwift runs each event with the context of this call, so before an event runs, the store of the
    /// context gets the board of the event: the board as the engine read it through the serial gate.
    ///
    /// - Parameters:
    ///   - context: The context of the `subscribe` call. Its store is the store of each event.
    ///   - arguments: The cursor, the board, and the filter.
    /// - Returns: The changes. The stream ends with `RESYNC_REQUIRED` when the log cannot resume after the cursor. In a
    ///   run that the engine runs again after it loads the board, the stream has ended and the subscriber is not added.
    /// - Throws: ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board for `board`. An
    ///   error of ``ChangeFilter/init(parsing:)``.
    ///   ``KanbanError/notFound(type:reference:)`` when the board has no repo directory to watch, or cannot be read.
    func changes(context: KanbanContext, arguments: ChangesArguments) async throws(KanbanError) -> ChangeEvents {
        let store = context.store
        let events = try await Self.events(of: arguments, readIn: store, from: context.feed)
        return events.map { event in
            await store.replace(with: event.board)
            return event.change
        }
    }

    /// Adds a subscriber to the change log of the board of a `changes` field, with its cursor and its filter.
    ///
    /// - Parameters:
    ///   - arguments: The cursor, the board, and the filter.
    ///   - store: The store of the `subscribe` call. It resolves the board.
    ///   - feed: The change feeds of the session view.
    /// - Returns: The events of the subscriber, or a stream that has ended when the engine did not load the board
    ///   yet. The engine then runs the call again after the load.
    /// - Throws: An error of ``BoardStore/view(ofBoard:)`` or of ``ChangeFilter/init(parsing:)``. A `^id` value that
    ///   is a short id of two or more tasks gives no error: it matches each of these tasks (divergence.md Q20).
    ///   ``KanbanError/notFound(type:reference:)`` for the board when the board has no repo directory to watch, for
    ///   example a board in memory only, or when the board is a related board that cannot be read (divergence.md Q7).
    ///   The subscription then gives one response with the error, and ends.
    private static func events(
        of arguments: ChangesArguments,
        readIn store: BoardStore,
        from feed: SessionFeeds
    ) async throws(KanbanError) -> AsyncThrowingStream<ChangeEvent, Error> {
        guard let view = try await store.view(ofBoard: arguments.board) else {
            if let reference = arguments.board, await store.isUnreadable(board: reference) {
                throw .notFound(type: .board, reference: reference)
            }
            return ChangeEvent.endedStream()
        }
        let filter = try ChangeFilter(parsing: arguments.filter)
        guard let directory = view.source?.directory else {
            Log.kanban.error(
                "A subscription names a board in memory only; the subscription ends",
                metadata: ["board": "\(view.boardKey)"]
            )
            throw .notFound(type: .board, reference: view.boardKey)
        }
        return await feed.subscribe(toBoardAt: directory.canonicalPath, after: arguments.after, filteredBy: filter)
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `Subscription` type with its one field, `changes` (plan.md §4.1, §6.7, KANBAN-7).
    ///
    /// - Returns: This builder, for method chaining.
    func addChangesSubscription() -> Self {
        addSubscription {
            SubscriptionField("changes", as: Change.self, atSub: KanbanResolver.changes) {
                Argument("after", at: \.after).description(SchemaDescription.changesAfter)
                Argument("board", at: \.board).description(SchemaDescription.boardToObserve)
                Argument("filter", at: \.filter).description(SchemaDescription.updateFilter)
            }
            .description(SchemaDescription.changesSubscription)
        }
    }
}
