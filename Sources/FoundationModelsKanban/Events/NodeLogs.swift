import Foundation
import OrderedCollections
import ULID

/// Reads the events of the log of one node of a board in memory, and the undone state of the transactions of the
/// board (divergence.md §23). `Task.timeline` reads the logs of a task and of its comments through it. A test gives a
/// reader that records each read.
protocol NodeLogReading {
    /// The undone state of the transactions of the board.
    var undoneState: UndoneState { get }

    /// Gives the events of the log of one node.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The events of the node, in the order of their ids. A node with no event gives no events.
    func events(of ref: LocalRef) -> [Event]
}

/// The events of each node of one board, and the target of each undo and redo transaction of the board
/// (divergence.md §23).
///
/// Each node has its own log file (plan.md §5.2), and the global event list merges the files (plan.md §5.3). This
/// value holds the same events by node, so that a read of the history of one node does not walk the global event
/// list. The live graph keeps it with the global event list (``LiveGraph/logs``): a load groups the events, a commit
/// merges its new events, and an apply of changed files groups the events again.
struct NodeLogs: NodeLogReading, Equatable, Sendable {
    /// The events of each node, in the order of their ids. A node with no event has no entry.
    private var eventsByNode: [LocalRef: [Event]]

    /// The transaction that each undo or redo transaction reverses, by the transaction ULID of the undo or the redo.
    private var reversals: [ULID: ULID]

    /// Groups the events of a board by node.
    ///
    /// - Parameter events: The events of the board, in the order of their ids: the global event list.
    init(of events: [Event]) {
        eventsByNode = Dictionary(grouping: events, by: \.patch.node)
        reversals = UndoneState.targets(of: events)
    }

    /// The undone state of the transactions of the board.
    var undoneState: UndoneState {
        UndoneState(reversing: reversals)
    }

    /// Gives the events of the log of one node.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The events of the node, in the order of their ids. A node with no event gives no events.
    func events(of ref: LocalRef) -> [Event] {
        eventsByNode[ref] ?? []
    }

    /// Adds new events, for example the events that a commit appended. The events of each node stay in the order of
    /// their ids.
    ///
    /// - Parameter events: The new events, in the order of their ids. None of them is in the logs yet.
    mutating func merge(_ events: [Event]) {
        for (ref, added) in OrderedDictionary(grouping: events, by: \.patch.node) {
            eventsByNode[ref] = EventMerge.merged([eventsByNode[ref] ?? [], added])
        }
        reversals.merge(UndoneState.targets(of: events)) { first, _ in first }
    }
}
