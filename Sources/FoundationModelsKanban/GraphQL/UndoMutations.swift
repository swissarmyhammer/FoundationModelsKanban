import Graphiti
import GraphQL
import ULID

// MARK: - Names

extension MutationName {
    /// The mutation that reverses a transaction.
    static let undo = "undo"

    /// The mutation that reverses an undo transaction.
    static let redo = "redo"
}

extension ReverseDirection {
    /// The name of the public mutation of the direction, for the `ops` of the events.
    fileprivate var operation: String {
        switch self {
        case .undo: MutationName.undo
        case .redo: MutationName.redo
        }
    }
}

// MARK: - Arguments

/// The `input` object of `undo` and `redo` (plan.md §4.2, §6.5).
private struct UndoInput: Decodable, Sendable {
    /// The transaction to reverse for `undo`, or the original transaction whose undo `redo` reverses, or `nil` for
    /// the newest target of the session actor.
    let txn: NodeID?

    /// `true` to write the inverse also when a later transaction conflicts with it.
    let force: Bool?

    /// The board to search for the transaction: a board key, a repo directory name, or a path, or `nil` for the
    /// current board and the loaded related boards (plan.md §6.5, scope). The engine loads a board that this field
    /// names.
    let board: String?

    /// The copies of the other boards of the transaction that the field can also reverse: board refs, for example the
    /// path of a second worktree of a repo (divergence.md S8). The `boards` value of the events holds only the key of
    /// each other board, and each worktree has its own board with the same key, so a path is the way to name one
    /// copy. The engine loads each board that this list names, and the field reverses the transaction in each named
    /// copy that holds events of it. `nil` names no copy.
    let boards: [String]?
}

// MARK: - Resolvers

extension KanbanResolver {
    /// Resolves `Mutation.undo`: reverses a transaction with inverse patches (plan.md §6.5).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The transaction, the force flag, the board, and the named copies. The `input` argument is
    ///     optional, because ``UndoInput`` has no required field (plan.md §4.2). No `input` gives the newest target
    ///     and no force.
    /// - Returns: The change that the undo wrote. The GraphQL field is nullable, so that an error gives `null` for this
    ///   field only, and the other fields of the call keep their data.
    /// - Throws: An error of ``BoardStore/reverse(_:with:at:)``.
    fileprivate func undo(
        context: KanbanContext,
        arguments: OptionalInputArguments<UndoInput>
    ) async throws -> Change? {
        try await context.store.reverse(.undo, with: arguments.input, at: context.clock())
    }

    /// Resolves `Mutation.redo`: reverses an undo transaction with inverse patches (plan.md §6.5).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The transaction, the force flag, the board, and the named copies. The `input` argument is
    ///     optional, the same as for `undo`.
    /// - Returns: The change that the redo wrote. The GraphQL field is nullable, so that an error gives `null` for this
    ///   field only, and the other fields of the call keep their data.
    /// - Throws: An error of ``BoardStore/reverse(_:with:at:)``.
    fileprivate func redo(
        context: KanbanContext,
        arguments: OptionalInputArguments<UndoInput>
    ) async throws -> Change? {
        try await context.store.reverse(.redo, with: arguments.input, at: context.clock())
    }
}

// MARK: - Store

extension BoardStore {
    /// Runs one `undo` or `redo` field: finds the target transaction, checks the conflicts, writes the inverse
    /// patches with `undoes` = the target in each board that the transaction changed, and gives the change that the
    /// field wrote (plan.md §6.5, many boards).
    ///
    /// The field searches the board that the input names, else the current board and the loaded related boards. A
    /// transaction that spans boards names the keys of the other boards in `boards`. The field finds each copy of
    /// those boards that holds events of the transaction (divergence.md X5), and it reverses the transaction in each
    /// of these boards, or in no board when one of them fails or cannot be reached. Each board obeys the rules of
    /// ``runMutation(named:on:at:_:)``.
    ///
    /// - Parameters:
    ///   - direction: `undo` or `redo`.
    ///   - input: The transaction, the force flag, the board, and the named copies, or `nil`.
    ///   - time: The time of the change.
    /// - Returns: The change of the patches that the field kept, with the updates of each board, or `nil` when the
    ///   engine did not load a board yet. The store then records the request, and the call runs again after the load.
    /// - Throws: ``KanbanError/nothingToUndo`` when no searched board has a target, or the inverse changes nothing.
    ///   ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board for the `board` field, for
    ///   a ref of the `boards` field, or for a board of the transaction that no copy reaches.
    ///   ``KanbanError/transactionBoardNotLoaded(transaction:board:)`` when no loaded copy of a board of the
    ///   transaction holds its events. ``KanbanError/undoConflict(transaction:laterTransactions:)`` when a later
    ///   transaction conflicts and the call does not force: also a later transaction of a different loaded board that
    ///   refers to a node that the undo makes a tombstone (divergence.md X6). An error of a graph rule (plan.md §3.3).
    ///   An ``EventError`` when a patch breaks a rule of the log.
    fileprivate func reverse(
        _ direction: ReverseDirection,
        with input: UndoInput?,
        at time: DateTime
    ) throws -> Change? {
        let searched = try searchedBoards(namedBy: input?.board)
        let named = try targets(namedBy: input?.boards ?? [])
        guard let searched, let named else {
            return nil
        }
        let found = try newestTarget(of: direction, named: input?.txn?.text, in: searched)
        guard let boards = try boards(of: found.txn, foundIn: found.board, among: named) else {
            return nil
        }
        let (actor, isForced) = (sessionActor, input?.force == true)
        let references = isForced ? [] : try laterReferences(to: found.txn, tombstonedIn: boards)
        let changes = try runField(as: direction.operation, inEach: boards) { work, key in
            try work.applyMutationRules(actingAs: actor, at: time) { work in
                try work.reverse(found.txn, forcing: isForced, alsoConflictingWith: references, inBoard: key, at: time)
            }
        }
        .filter { board in !board.events.isEmpty }
        guard let first = changes.first else {
            throw KanbanError.nothingToUndo
        }
        return change(of: first, along: changes.dropFirst(), changing: changes.map(\.key))
    }

    /// Gives the boards that a reverse field searches for its target (plan.md §6.5, scope).
    ///
    /// - Parameter reference: The board ref of the `board` field, or `nil` for no `board` field.
    /// - Returns: The board that the ref names, or the current board and each loaded related board when the field
    ///   has no ref. `nil` when the engine did not load the board of the ref yet.
    /// - Throws: ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board for the ref.
    private func searchedBoards(namedBy reference: String?) throws(KanbanError) -> [MutationTarget]? {
        guard let reference else {
            return loadedTargets
        }
        return try target(of: .named(reference)).map { board in [board] }
    }

    /// Finds the newest target transaction of a reverse field in some boards.
    ///
    /// - Parameters:
    ///   - direction: `undo` or `redo`.
    ///   - text: The `txn` of the input, or `nil` for the newest target of the session actor.
    ///   - boards: The boards to search.
    /// - Returns: The transaction, and a board whose log has it.
    /// - Throws: ``KanbanError/nothingToUndo`` when no board has a target. Each other error of
    ///   ``UndoLog/target(of:named:by:)``, unchanged.
    private func newestTarget(
        of direction: ReverseDirection,
        named text: String?,
        in boards: [MutationTarget]
    ) throws(KanbanError) -> (txn: ULID, board: MutationTarget) {
        let found = try boards.map { board throws(KanbanError) in
            try reverseTarget(of: direction, named: text, in: board).map { txn in (txn: txn, board: board) }
        }
        guard let newest = found.compactMap(\.self).max(by: { lhs, rhs in lhs.txn < rhs.txn }) else {
            throw .nothingToUndo
        }
        return newest
    }

    /// Finds the target transaction of a reverse field in the log of one board.
    ///
    /// - Parameters:
    ///   - direction: `undo` or `redo`.
    ///   - text: The `txn` of the input, or `nil` for the newest target of the session actor.
    ///   - board: The board to search.
    /// - Returns: The transaction, or `nil` when the log of the board has no target. A board with no target is not an
    ///   error: the search goes on in the next board.
    /// - Throws: Each error of ``UndoLog/target(of:named:by:)`` other than ``KanbanError/nothingToUndo``, unchanged.
    private func reverseTarget(
        of direction: ReverseDirection,
        named text: String?,
        in board: MutationTarget
    ) throws(KanbanError) -> ULID? {
        let log = UndoLog(of: workingCopy(of: board).liveEvents)
        do throws(KanbanError) {
            return try log.target(of: direction, named: text, by: sessionActor.ref)
        } catch .nothingToUndo {
            return nil
        }
    }

    /// Gives the boards that the `boards` field of a reverse field names (divergence.md S8).
    ///
    /// - Parameter references: The board refs of the `boards` field.
    /// - Returns: The boards, in the order of the refs, or `nil` when the engine did not load a board yet.
    /// - Throws: ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board for a ref. Each
    ///   other error of ``target(of:)``, unchanged.
    private func targets(namedBy references: [String]) throws(KanbanError) -> [MutationTarget]? {
        let targets = try references.map { reference throws(KanbanError) in try target(of: .named(reference)) }
        let loaded = targets.compactMap(\.self)
        return loaded.count == targets.count ? loaded : nil
    }

    /// Gives each board that a transaction changed: the board where the field found it, and each copy of a board that
    /// its `boards` value names and that holds events of the transaction (plan.md §5.1, §6.5; divergence.md X5).
    ///
    /// - Parameters:
    ///   - txn: The transaction.
    ///   - home: The board whose log has the transaction.
    ///   - named: The boards that the `boards` field of the input names.
    /// - Returns: The boards, `home` first, each one time. `nil` when the engine did not load a board yet.
    /// - Throws: An error of ``copies(ofKey:holding:among:)`` for a key that no copy reaches.
    private func boards(
        of txn: ULID,
        foundIn home: MutationTarget,
        among named: [MutationTarget]
    ) throws(KanbanError) -> [MutationTarget]? {
        let events = workingCopy(of: home).liveEvents.filter { event in event.txn == txn }
        let keys = events.lazy.compactMap(\.boards).first ?? []
        let found = try keys.map { key throws(KanbanError) in
            try copies(ofKey: key, holding: txn, among: named)
        }
        let reached = found.compactMap(\.self)
        guard reached.count == found.count else {
            return nil
        }
        return eachOnce([home] + reached.joined())
    }

    /// Gives each board of a list one time.
    ///
    /// - Parameter boards: The boards. The same board can be in the list more than one time.
    /// - Returns: The boards, in the order of their first place in the list.
    private func eachOnce(_ boards: [MutationTarget]) -> [MutationTarget] {
        var seen: Set<String?> = []
        return boards.filter { board in seen.insert(board.relatedPath).inserted }
    }

    /// Lists the later transactions of each loaded board that refer to a node of a different board that the undo of
    /// a transaction makes a tombstone (plan.md §6.5, conflict; divergence.md X6 and R13). Each one is a conflict,
    /// the same as a later edge in the board of the node.
    ///
    /// The boards to read are the current board, each loaded related board, and each board of the transaction. A
    /// board reads only the nodes of the other boards: the check in one board finds a later edge to a node of the
    /// board itself (``UndoLog/conflicts(with:of:readingBodiesWith:)``).
    ///
    /// - Parameters:
    ///   - txn: The transaction that the undo reverses.
    ///   - boards: The boards that the transaction changed.
    /// - Returns: The later transactions, in the order of the boards, and in the order of their ULIDs in each board.
    /// - Throws: An ``EventError`` from ``UndoLog/inverses(of:)``. A valid log gives no error.
    private func laterReferences(to txn: ULID, tombstonedIn boards: [MutationTarget]) throws -> [ULID] {
        let tombstoned = try boards.flatMap { board in try tombstonedURIs(of: txn, in: board) }
        return eachOnce(loadedTargets + boards).flatMap { board in
            let key = BoardKey.normalizedText(of: self.key(of: board))
            let others = Set(tombstoned.filter { uri in uri.boardKey != key })
            return UndoLog(of: workingCopy(of: board).liveEvents).references(to: others, after: txn)
        }
    }

    /// Gives the full URI of each node that the undo of a transaction makes a tombstone in one board: each node that
    /// the transaction made, or made live again.
    ///
    /// - Parameters:
    ///   - txn: The transaction that the undo reverses.
    ///   - board: A board that the transaction changed.
    /// - Returns: The URIs, with the key of the board.
    /// - Throws: An ``EventError`` from ``UndoLog/inverses(of:)``. A valid log gives no error.
    private func tombstonedURIs(of txn: ULID, in board: MutationTarget) throws(EventError) -> [NodeURI] {
        let key = BoardKey.normalizedText(of: key(of: board))
        return try UndoLog(of: workingCopy(of: board).liveEvents).inverses(of: txn)
            .filter(\.makesTombstone)
            .map { inverse in NodeURI(boardKey: key, ref: inverse.node) }
    }

    /// Gives each copy of one board of a transaction that holds events of the transaction (divergence.md X5). The
    /// copies to look in are the copy that the key names in the scan, each copy with the key that the table of the
    /// host has loaded, and each board of the `boards` field with the key. The `boards` value of an event holds the
    /// key only, and each worktree of a repo has its own board with the same key.
    ///
    /// - Parameters:
    ///   - storedKey: The key of the board, as the `boards` value of the events holds it.
    ///   - txn: The transaction.
    ///   - named: The boards that the `boards` field of the input names.
    /// - Returns: The copies, or `nil` when the engine did not load a copy yet.
    /// - Throws: ``KanbanError/transactionBoardNotLoaded(transaction:board:)`` when no copy holds events of the
    ///   transaction. ``KanbanError/boardNotFound(reference:searchRoots:)`` instead when also the scan finds no board
    ///   for the key. Each other error of ``target(of:)``, unchanged.
    private func copies(
        ofKey storedKey: String,
        holding txn: ULID,
        among named: [MutationTarget]
    ) throws(KanbanError) -> [MutationTarget]? {
        let key = BoardKey.normalizedText(of: storedKey)
        var missing = KanbanError.transactionBoardNotLoaded(transaction: txn.ulidString, board: key)
        let scanned: [MutationTarget]?
        do throws(KanbanError) {
            scanned = try target(of: .named(key)).map { board in [board] }
        } catch .boardNotFound(let reference, let searchRoots) {
            missing = .boardNotFound(reference: reference, searchRoots: searchRoots)
            scanned = []
        }
        let loaded = loadedTargets(withKey: key)
        guard let scanned, let loaded else {
            return nil
        }
        let candidates = scanned + loaded + named.filter { board in self.key(of: board) == key }
        let holding = candidates.filter { board in
            workingCopy(of: board).liveEvents.contains { event in event.txn == txn }
        }
        guard !holding.isEmpty else {
            throw missing
        }
        return holding
    }

    /// Makes the change that a reverse field gives: the change of its first board, with the updates of the other
    /// boards.
    ///
    /// - Parameters:
    ///   - first: The change of the field in its first board.
    ///   - others: The change of the field in each other board that it changed.
    ///   - keys: The keys of all boards that the field changed.
    /// - Returns: The change.
    private func change(
        of first: BoardFieldChange,
        along others: ArraySlice<BoardFieldChange>,
        changing keys: [String]
    ) -> Change? {
        let operations = Array(work.operations)
        let changes = ([first] + others).compactMap { board in
            let events = board.events.map { event in
                event.recording(operations: operations, changing: keys, inBoard: board.key)
            }
            return ChangeBuilder(from: board.before, to: board.after).change(of: events, markingUndone: false)
        }
        return changes.first.map { change in change.adding(updatesOf: changes.dropFirst()) }
    }
}

extension Change {
    /// Gives this change with the node updates of the same transaction in other boards.
    ///
    /// - Parameter others: The changes of the transaction in the other boards.
    /// - Returns: The change, with the updates of this board first.
    fileprivate func adding(updatesOf others: ArraySlice<Change>) -> Change {
        replacingNodeUpdates(nodeUpdates + others.flatMap(\.nodeUpdates))
    }
}

// MARK: - Patches

extension WorkingCopy {
    /// Writes the inverse patches of a transaction to the board of this working copy (plan.md §6.5).
    ///
    /// The patches of a column tombstone come last, so that the inverse moves its tasks out first. Then the graph
    /// rules of plan.md §3.3 apply: a column tombstone needs an empty column, and the restored edges must make no
    /// `dependsOn` cycle and no rename cycle. A board where the transaction made only nodes that the undo keeps (the
    /// board, the default columns, and the session actor) gets no patch.
    ///
    /// - Parameters:
    ///   - target: The transaction to reverse. The log of the board has it.
    ///   - isForced: `true` to write the inverse also when a later transaction conflicts with it.
    ///   - otherBoardConflicts: The later transactions of other boards that conflict with the undo: each one refers
    ///     to a node that the undo makes a tombstone (divergence.md X6). The list is empty when the field forces.
    ///   - key: The current key of the board.
    ///   - time: The time of the change.
    /// - Throws: ``KanbanError/undoConflict(transaction:laterTransactions:)`` when a later transaction of this board or
    ///   of `otherBoardConflicts` conflicts and the field does not force. The error lists each one time, in the order
    ///   of their ULIDs. An error of a graph rule. An ``EventError`` when a patch breaks a rule of the log.
    fileprivate mutating func reverse(
        _ target: ULID,
        forcing isForced: Bool,
        alsoConflictingWith otherBoardConflicts: [ULID],
        inBoard key: String,
        at time: DateTime
    ) throws {
        let log = UndoLog(of: liveEvents)
        let inverses = try log.inverses(of: target)
        if !isForced {
            let graph = graph
            let later = log.conflicts(with: inverses, of: target) { ref in graph.body(of: ref) }
            guard later.isEmpty, otherBoardConflicts.isEmpty else {
                throw KanbanError.undoConflict(
                    transaction: target.ulidString,
                    laterTransactions: Set(later + otherBoardConflicts).sorted().map(\.ulidString)
                )
            }
        }
        let ordered = inverses.filter { inverse in !inverse.makesColumnTombstone }
            + inverses.filter(\.makesColumnTombstone)
        for inverse in ordered {
            if inverse.makesColumnTombstone {
                try checkEmpty(column: inverse.node, inBoard: key)
            }
            try apply(inverse.patch(onBody: graph.body(of: inverse.node)), at: time, undoing: target)
        }
        try checkCycles(after: inverses, inBoard: key)
    }

    /// Checks that the inverse patches make no `dependsOn` cycle and no rename cycle (plan.md §3.3, rule 6, §6.2).
    ///
    /// A task gets the cycle check when its inverse changes the body, adds a `dependsOn` edge, or makes a tombstone
    /// live again: the edges of a tombstone do not count, so a task that is live again can close a cycle
    /// (divergence.md X7).
    ///
    /// - Parameters:
    ///   - inverses: The inverse patches that the working copy applied.
    ///   - key: The current key of the board.
    /// - Throws: ``KanbanError/dependencyCycle(path:)`` or ``KanbanError/tagRenameCycle(path:)``.
    private mutating func checkCycles(after inverses: [NodeInverse], inBoard key: String) throws(KanbanError) {
        for inverse in inverses {
            let node = inverse.node
            if node.nodeType == .task, inverse.canCloseCycle {
                try checkNoCycle(throughTask: node, inBoard: key)
            }
            if node.nodeType == .tag, inverse.parts.set[PropertyName.renamedTo] != nil {
                try checkNoRenameCycle(fromTagAt: graph.slot(for: node))
            }
        }
    }
}

extension NodeInverse {
    /// `true` when the inverse can close a `dependsOn` cycle through its task: it changes the body, which can hold
    /// dependency markers, it adds a `dependsOn` edge, or it makes a tombstone live again (`delete: false`), so that
    /// the edges of the task count again.
    fileprivate var canCloseCycle: Bool {
        bodyChange != nil || parts.add[PropertyName.dependsOn] != nil || parts.delete == false
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `undo` and `redo` mutations and their `input` type (plan.md §4.2, §6.5). Each one gives the `Change`
    /// that it wrote.
    ///
    /// - Returns: This builder, for method chaining.
    func addUndoMutations() -> Self {
        add {
            Input(UndoInput.self) {
                InputField("txn", at: \.txn)
                InputField("force", at: \.force)
                InputField("board", at: \.board)
                InputField("boards", at: \.boards)
            }
        }
        .addMutation {
            Field(MutationName.undo, at: KanbanResolver.undo) { Argument("input", at: \.input) }
            Field(MutationName.redo, at: KanbanResolver.redo) { Argument("input", at: \.input) }
        }
    }
}
