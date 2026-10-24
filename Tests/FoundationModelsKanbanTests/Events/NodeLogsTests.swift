import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the events of each node of a board in memory (divergence.md §23): ``NodeLogs`` groups the global event list
/// by node, so that `Task.timeline` reads only the logs of a task and of its comments. ``LiveGraphApplyTests`` checks
/// that the live graph keeps its node logs equal to the grouping of its events after each load, commit, and apply.
@Suite("Node logs")
struct NodeLogsTests {
    /// The title that the task events of the tests set.
    private static let title = "Port the parser"

    /// Makes the events of the tests: two board transactions, with one task transaction between them.
    ///
    /// - Parameter task: The local ref of the task.
    /// - Returns: The events, in the order of their ids.
    private static func events(ofTask task: LocalRef) throws -> (first: Event, title: Event, last: Event) {
        let first = try UndoneStateTests.transaction(atStep: UndoneStateTests.Step.original.rawValue)
        let title = try UndoneStateTests.transaction(
            atStep: UndoneStateTests.Step.undo.rawValue,
            patching: ReplayTests.titlePatch(setting: Self.title, of: task)
        )
        let last = try UndoneStateTests.transaction(atStep: UndoneStateTests.Step.redo.rawValue)
        return (first, title, last)
    }

    @Test("NodeLogs gives the events of each node in the order of their ids, and no event for a node with no log")
    func nodeLogsGroupEventsByNode() throws {
        let task = LocalRef.task(ULID())
        let events = try Self.events(ofTask: task)
        let logs = NodeLogs(of: [events.first, events.title, events.last])
        #expect(logs.events(of: .board) == [events.first, events.last])
        #expect(logs.events(of: task) == [events.title])
        #expect(logs.events(of: .task(ULID())).isEmpty)
    }

    @Test("merge puts each new event in the log of its node in id order, the same as a grouping of all events")
    func mergeKeepsIDOrder() throws {
        let task = LocalRef.task(ULID())
        let events = try Self.events(ofTask: task)
        var logs = NodeLogs(of: [events.title, events.last])
        logs.merge([events.first])
        #expect(logs == NodeLogs(of: [events.first, events.title, events.last]))
        #expect(logs.events(of: .board) == [events.first, events.last])
    }

    @Test("The undone state of the node logs is the undone state of the global event list, also after a merge")
    func undoneStateFollowsUndoTransactions() throws {
        let original = try UndoneStateTests.transaction(atStep: UndoneStateTests.Step.original.rawValue)
        let undo = try UndoneStateTests.transaction(atStep: UndoneStateTests.Step.undo.rawValue, undoing: original.txn)
        let redo = try UndoneStateTests.transaction(atStep: UndoneStateTests.Step.redo.rawValue, undoing: undo.txn)
        let transactions = [original, undo, redo]
        var logs = NodeLogs(of: [original, undo])
        let beforeRedo = transactions.map { event in logs.undoneState.isUndone(txn: event.txn) }
        #expect(beforeRedo == UndoneStateTests.undoneStates(of: transactions, amongEvents: [original, undo]))
        logs.merge([redo])
        let afterRedo = transactions.map { event in logs.undoneState.isUndone(txn: event.txn) }
        #expect(afterRedo == UndoneStateTests.undoneStates(of: transactions, amongEvents: transactions))
    }
}
