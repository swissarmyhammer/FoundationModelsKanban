import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the undone state of the transactions of a board (plan.md §6.5): a transaction is undone when a later
/// transaction has `undoes` = its `txn`, and that later transaction is not itself undone. The state comes from the
/// global event list only, so it survives a git merge.
@Suite("Undone state")
struct UndoneStateTests {
    /// The steps of the transactions of the tests in one board, in time order.
    enum Step: Int {
        /// The original transaction.
        case original = 1

        /// The undo of the original transaction.
        case undo

        /// The redo: the undo of the undo.
        case redo
    }

    /// The steps of the merge test, in time order. The two branches take turns, so their events interleave in the
    /// merged log.
    enum MergeStep: Int {
        /// The original transaction of the main branch.
        case mainOriginal = 1

        /// The original transaction of the other branch.
        case branchOriginal

        /// The undo of the original transaction of the main branch.
        case mainUndo

        /// The undo of the original transaction of the other branch.
        case branchUndo

        /// The redo on the other branch: the undo of its undo.
        case branchRedo
    }

    /// Makes the one event of a transaction: a patch that changes the name of the board.
    ///
    /// - Parameters:
    ///   - step: The step of the transaction. A larger step gives a later transaction ULID and a later event id.
    ///   - actor: The local ref of the actor of the transaction. The default is the test actor.
    ///   - target: The transaction that this transaction reverses, or `nil` for an original transaction.
    /// - Returns: The event.
    static func transaction(
        atStep step: Int,
        by actor: LocalRef = ReplayTests.actor,
        undoing target: ULID? = nil
    ) throws -> Event {
        let date = ReplayTests.date(atStep: step)
        var ids = FixedULIDSource(at: date)
        let txn = ids.makeULID()
        let name = "\(KanbanGraphTests.boardName) \(step)"
        return Event(
            id: ids.makeULID(),
            txn: txn,
            ops: [MutationName.updateBoard],
            at: DateTime(date),
            actor: actor,
            undoes: target,
            patch: try PatchInput(node: .board, set: ["name": .json(.string(name))])
        )
    }

    /// Gives the undone state of each of some transactions, in the order of the transactions.
    ///
    /// - Parameters:
    ///   - transactions: The events of the transactions to read.
    ///   - events: The global event list of the board.
    /// - Returns: `true` for each transaction that is undone.
    static func undoneStates(of transactions: [Event], amongEvents events: [Event]) -> [Bool] {
        let state = UndoneState(of: events)
        return transactions.map { event in state.isUndone(txn: event.txn) }
    }

    @Test("A transaction that no later transaction reverses is not undone")
    func transactionWithNoUndoIsNotUndone() throws {
        let events = try [Step.original, Step.undo].map { step in try Self.transaction(atStep: step.rawValue) }
        #expect(Self.undoneStates(of: events, amongEvents: events) == [false, false])
    }

    @Test("An undo makes the transaction that it reverses undone, and the undo itself is not undone")
    func undoMakesTargetUndone() throws {
        let original = try Self.transaction(atStep: Step.original.rawValue)
        let undo = try Self.transaction(atStep: Step.undo.rawValue, undoing: original.txn)
        let events = [original, undo]
        #expect(Self.undoneStates(of: events, amongEvents: events) == [true, false])
    }

    @Test("A redo makes the undo undone, so the original transaction is not undone")
    func redoMakesUndoUndone() throws {
        let original = try Self.transaction(atStep: Step.original.rawValue)
        let undo = try Self.transaction(atStep: Step.undo.rawValue, undoing: original.txn)
        let redo = try Self.transaction(atStep: Step.redo.rawValue, undoing: undo.txn)
        let events = [original, undo, redo]
        #expect(Self.undoneStates(of: events, amongEvents: events) == [false, true, false])
    }

    @Test("An undo that names a later transaction does not make it undone")
    func undoOfLaterTransactionIsIgnored() throws {
        let later = try Self.transaction(atStep: Step.undo.rawValue)
        let earlier = try Self.transaction(atStep: Step.original.rawValue, undoing: later.txn)
        let events = [earlier, later]
        #expect(Self.undoneStates(of: events, amongEvents: events) == [false, false])
    }

    @Test("After a union merge of two branches, the undone state is correct for transactions from both branches")
    func mergeKeepsUndoneStateOfBothBranches() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let mainOriginal = try Self.transaction(atStep: MergeStep.mainOriginal.rawValue)
        let branchOriginal = try Self.transaction(atStep: MergeStep.branchOriginal.rawValue)
        let mainUndo = try Self.transaction(atStep: MergeStep.mainUndo.rawValue, undoing: mainOriginal.txn)
        let branchUndo = try Self.transaction(atStep: MergeStep.branchUndo.rawValue, undoing: branchOriginal.txn)
        let branchRedo = try Self.transaction(atStep: MergeStep.branchRedo.rawValue, undoing: branchUndo.txn)
        // The union merge keeps the lines of both sides in one file: the lines of the other branch come first.
        let mergedLines = [branchOriginal, branchUndo, branchRedo, mainOriginal, mainUndo]
        try log.append(contentsOf: mergedLines, toLogOf: .board)
        let loaded = try await LoaderTests.load(log, withWorkers: LoaderTests.singleWorker)
        let transactions = [mainOriginal, mainUndo, branchOriginal, branchUndo, branchRedo]
        let states = Self.undoneStates(of: transactions, amongEvents: loaded.events)
        #expect(states == [true, false, false, true, false])
    }
}
