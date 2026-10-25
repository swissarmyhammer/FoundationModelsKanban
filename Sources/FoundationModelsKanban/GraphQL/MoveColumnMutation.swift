import FoundationModelsExtras
import Graphiti
import GraphQL

// MARK: - Names

extension MutationName {
    /// The mutation that moves a column to a place next to its neighbor columns, in one transaction (divergence.md
    /// §25).
    static let moveColumn = "moveColumn"
}

// MARK: - Arguments

/// The `input` object of `moveColumn` (divergence.md §25): the column, and the neighbor columns of its new place. Each
/// field takes the forgiving column refs of ``RefResolver``.
private struct MoveColumnInput: Codable, Sendable {
    /// The column to move: a full URI, the stored form `column/<slug>`, the slug, or a name that gives the slug.
    let id: NodeID

    /// The column that comes directly after the moved column, or `nil` for no `before` field.
    let before: NodeID?

    /// The column that comes directly before the moved column, or `nil` for no `after` field.
    let after: NodeID?

    /// Gives the place of the moved column in the board order of the other columns (divergence.md §25). `before` and
    /// `after` together must name two neighbors. When one of the two refs names no live column, the call uses the
    /// other ref, with a warning (divergence.md P1). The call never puts a column after the terminal column when the
    /// input does not ask for it, because a task in the terminal column is done.
    ///
    /// - Parameters:
    ///   - column: The local ref of the moved column.
    ///   - others: The local refs of the other live columns, in board order.
    ///   - resolver: The resolver of the forgiving refs of the board.
    /// - Returns: The index of the moved column in `others` after the move, or `nil` when a ref names the moved column
    ///   itself, so that the call writes nothing.
    /// - Throws: ``KanbanError/missingColumnPlacement(column:)`` when the input gives no `before` and no `after`.
    ///   ``KanbanError/notFound(type:reference:)`` when the one given ref names no live column, and
    ///   ``KanbanError/nodesNotFound(type:references:)`` when the two given refs name no live column.
    ///   ``KanbanError/conflictingColumnPlacement(after:before:)`` when `after` and `before` name columns that are not
    ///   neighbors. The other errors of ``RefResolver/nodeRef(for:ofType:includingTombstones:)``, for example
    ///   ``KanbanError/ambiguousID(reference:matches:)``.
    func index(
        of column: LocalRef,
        among others: [LocalRef],
        resolvingWith resolver: RefResolver
    ) throws(KanbanError) -> Int? {
        let previous = try resolver.columnNeighbor(after)
        let next = try resolver.columnNeighbor(before)
        guard !previous.names(column), !next.names(column) else {
            return nil
        }
        switch (previous, next) {
        case (.unset, .unset):
            throw .missingColumnPlacement(column: id.text)
        case (.missing(let previousID), .missing(let nextID)):
            throw .nodesNotFound(type: .column, references: [previousID.text, nextID.text])
        case (.missing(let written), .unset), (.unset, .missing(let written)):
            throw .notFound(type: .column, reference: written.text)
        case (.column(let ref, let written), .unset):
            return try others.position(of: ref, writtenAs: written) + 1
        case (.unset, .column(let ref, let written)):
            return try others.position(of: ref, writtenAs: written)
        case (.column(let ref, let written), .missing(let unknown)):
            Self.warnOfMissingNeighbor(unknown, on: .before, using: .after)
            return try others.position(of: ref, writtenAs: written) + 1
        case (.missing(let unknown), .column(let ref, let written)):
            Self.warnOfMissingNeighbor(unknown, on: .after, using: .before)
            return try others.position(of: ref, writtenAs: written)
        case (.column(let previousRef, let previousText), .column(let nextRef, let nextText)):
            let index = try others.position(of: previousRef, writtenAs: previousText) + 1
            guard others.indices.contains(index), others[index] == nextRef else {
                throw .conflictingColumnPlacement(after: previousText, before: nextText)
            }
            return index
        }
    }

    /// Adds the warning for a `before` or `after` ref that names no live column to the response, when the call puts
    /// the column by its other ref (divergence.md P1, §25).
    ///
    /// - Parameters:
    ///   - neighbor: The ref that names no column, as the input writes it.
    ///   - side: The place field of that ref.
    ///   - used: The place field of the ref that the call uses.
    private static func warnOfMissingNeighbor(
        _ neighbor: NodeID,
        on side: NeighborSide,
        using used: NeighborSide
    ) {
        let outcome = "The call put the column by the \(used.rawValue) ref only."
        let warning = Placement.neighborNotFoundWarning(for: neighbor, on: side, moving: .column, outcome: outcome)
        ResolverWarnings.current?.add(warning)
    }
}

/// The neighbor column that a `before` or an `after` field of a `moveColumn` input names.
private enum ColumnNeighbor {
    /// The input does not give the field.
    case unset

    /// The ref names no live column. The value is the ref as the input writes it.
    case missing(NodeID)

    /// The ref names a live column.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the column.
    ///   - written: The ref as the input writes it.
    case column(LocalRef, written: String)

    /// Tells if this neighbor is a column.
    ///
    /// - Parameter column: The local ref of a column.
    /// - Returns: `true` when this neighbor is that column.
    func names(_ column: LocalRef) -> Bool {
        guard case .column(let ref, _) = self else {
            return false
        }
        return ref == column
    }
}

// MARK: - Resolver

extension KanbanResolver {
    /// Resolves `Mutation.moveColumn`: changes the orders of the columns so that the column is at the place of the
    /// input, in one transaction (divergence.md §25). One `undoChange` reverses all the order changes of the move.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The column, and the neighbor columns of its new place.
    /// - Returns: The column after the move. The GraphQL field is nullable, so that an error gives `null` for this
    ///   field only.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live column has the id. The errors of
    ///   ``WorkingCopy/move(column:to:resolvingWith:at:)``.
    fileprivate func moveColumn(
        context: KanbanContext,
        arguments: InputArguments<MoveColumnInput>
    ) async throws -> ColumnObject? {
        let input = arguments.input
        let board = MutationBoard.holding(input.id)
        return try await context.changeNode(named: MutationName.moveColumn, on: board) { work, resolver, time in
            let ref = try resolver.nodeRef(for: input.id, ofType: .column)
            try work.move(column: ref, to: input, resolvingWith: resolver, at: time)
            return ref
        }
    }
}

// MARK: - Patches

extension WorkingCopy {
    /// Writes the order patches of a move of a column (divergence.md §25): one `set` of the order for each column
    /// whose order changes (``ColumnRenumber``). A move that does not change the board order writes nothing.
    ///
    /// - Parameters:
    ///   - column: The local ref of the live column to move.
    ///   - input: The input of the move, with its place fields.
    ///   - resolver: The resolver of the forgiving refs of the board.
    ///   - time: The time of the change.
    /// - Throws: The errors of ``MoveColumnInput/index(of:among:resolvingWith:)``. An ``EventError`` when a patch
    ///   breaks a rule of the log.
    fileprivate mutating func move(
        column: LocalRef,
        to input: MoveColumnInput,
        resolvingWith resolver: RefResolver,
        at time: DateTime
    ) throws {
        let columns = graph.liveColumns
        let others = columns.filter { node in node.ref != column }
        let index = try input.index(of: column, among: others.map(\.ref), resolvingWith: resolver)
        guard let index, let moved = columns.first(where: { node in node.ref == column }) else {
            return
        }
        var placed = others
        placed.insert(moved, at: index)
        guard placed.map(\.ref) != columns.map(\.ref) else {
            return
        }
        let orders = ColumnRenumber(orders: placed.map(\.order), moving: index).orders
        for (node, order) in zip(placed, orders) where node.order != order {
            let values = [PropertyName.order: FieldUpdate.changed(PatchValue.integer(order))]
            try updateNode(node.ref, updating: values, body: .unchanged, at: time)
        }
    }
}

// MARK: - Renumber

/// The orders of the columns of a board after a move of a column (divergence.md §25).
///
/// The input is the column orders in the new board order, with the moved column at its new place. The result keeps the
/// orders of as many columns as possible, and gives each other column an order that keeps the board order strict: no
/// two columns have the same order. When an integer is between the orders of the two new neighbors, only the moved
/// column changes, and it gets an order between them.
///
/// A set of columns can keep their orders when, for each two of them, the difference of the orders is at least the
/// difference of their places, so that the columns between them get different integers. That is, the order minus the
/// place does not go down. The kept set is the longest such set; of two sets with the same size, the set without the
/// moved column wins, so that its neighbors keep their orders.
private struct ColumnRenumber {
    /// The difference between the order of a column at an end of the board and the order of the column next to it, the
    /// same step as ``Graph/nextColumnOrder``.
    static let endStep = 1

    /// The new order of each column, in board order.
    let orders: [Int]

    /// Gives the new orders of the columns.
    ///
    /// - Parameters:
    ///   - current: The current order of each column, in the new board order.
    ///   - moved: The index of the moved column in `current`.
    init(orders current: [Int], moving moved: Int) {
        let kept = Self.keptIndices(of: current, moving: moved)
        orders = current.indices.map { index in Self.order(at: index, of: current, keeping: kept) }
    }

    /// A set of columns that keep their orders, in board order.
    private struct Chain {
        /// The indices of the columns, in increasing order.
        let indices: [Int]

        /// `true` when the set holds the moved column.
        let keepsMoved: Bool

        /// The set with no column.
        static let empty = Chain(indices: [], keepsMoved: false)

        /// The rank of the set: the size first, then a set without the moved column above a set with it.
        var rank: (Int, Int) {
            (indices.count, keepsMoved ? .zero : 1)
        }

        /// Gives the set of the higher rank: this set, or a different set. Of two sets of the same rank, this set
        /// wins, so that the first set in board order wins.
        ///
        /// - Parameter other: The different set.
        /// - Returns: The set of the higher rank.
        func ranked(against other: Chain) -> Chain {
            other.rank > rank ? other : self
        }

        /// Gives the set with one more column at its end.
        ///
        /// - Parameters:
        ///   - index: The index of the column.
        ///   - isMoved: `true` when the column is the moved column.
        /// - Returns: The longer set.
        func adding(_ index: Int, isMoved: Bool) -> Chain {
            Chain(indices: indices + [index], keepsMoved: keepsMoved || isMoved)
        }
    }

    /// Gives the indices of the columns that keep their orders (see ``ColumnRenumber``).
    ///
    /// - Parameters:
    ///   - orders: The current order of each column, in the new board order.
    ///   - moved: The index of the moved column.
    /// - Returns: The indices, in increasing order.
    private static func keptIndices(of orders: [Int], moving moved: Int) -> [Int] {
        let slack = orders.indices.map { index in orders[index] - index }
        let ending = orders.indices.reduce(into: [Chain]()) { chains, index in
            let fitting = zip(chains, slack).filter { _, earlierSlack in earlierSlack <= slack[index] }
                .map { chain, _ in chain }
            let longest = fitting.reduce(Chain.empty) { best, chain in best.ranked(against: chain) }
            chains.append(longest.adding(index, isMoved: index == moved))
        }
        return ending.reduce(Chain.empty) { best, chain in best.ranked(against: chain) }.indices
    }

    /// Gives the new order of one column. A kept column keeps its order. A column between two kept columns gets an
    /// order that spreads the columns between them evenly. A column before the first kept column, or after the last
    /// one, gets an order one ``endStep`` away for each place.
    ///
    /// - Parameters:
    ///   - index: The index of the column.
    ///   - orders: The current order of each column.
    ///   - kept: The indices of the kept columns, in increasing order.
    /// - Returns: The new order.
    private static func order(at index: Int, of orders: [Int], keeping kept: [Int]) -> Int {
        guard !kept.contains(index) else {
            return orders[index]
        }
        let previous = kept.last { keptIndex in keptIndex < index }
        let next = kept.first { keptIndex in keptIndex > index }
        switch (previous, next) {
        case (.some(let previous), .some(let next)):
            return orders[previous] + (orders[next] - orders[previous]) * (index - previous) / (next - previous)
        case (.some(let previous), .none):
            return orders[previous] + (index - previous) * endStep
        case (.none, .some(let next)):
            return orders[next] - (next - index) * endStep
        case (.none, .none):
            return orders[index]
        }
    }
}

// MARK: - Graph

extension Graph {
    /// The live columns, in board order (``ColumnOrder``).
    fileprivate var liveColumns: [ColumnNode] {
        ColumnOrder(of: self).slots.compactMap { slot in node(at: slot, as: ColumnNode.self) }
    }
}

extension RefResolver {
    /// Changes the `before` or the `after` ref of a `moveColumn` input to a live column of this board.
    ///
    /// - Parameter id: The ref as the input writes it, or `nil` for no field.
    /// - Returns: The neighbor: ``ColumnNeighbor/missing(_:)`` when the ref names no live column.
    /// - Throws: The errors of ``nodeRef(for:ofType:includingTombstones:)`` other than
    ///   ``KanbanError/notFound(type:reference:)``, for example ``KanbanError/ambiguousID(reference:matches:)``.
    fileprivate func columnNeighbor(_ id: NodeID?) throws(KanbanError) -> ColumnNeighbor {
        guard let id else {
            return .unset
        }
        do {
            return .column(try nodeRef(for: id, ofType: .column), written: id.text)
        } catch .notFound {
            return .missing(id)
        }
    }
}

extension [LocalRef] {
    /// Gives the place of a neighbor column in the board order of the other columns.
    ///
    /// - Parameters:
    ///   - column: The local ref of the neighbor column.
    ///   - written: The ref of the neighbor as the input writes it, for an error.
    /// - Returns: The index of the column.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the list does not have the column.
    fileprivate func position(of column: LocalRef, writtenAs written: String) throws(KanbanError) -> Int {
        guard let index = firstIndex(of: column) else {
            throw .notFound(type: .column, reference: written)
        }
        return index
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `moveColumn` mutation and its `input` type (divergence.md §25).
    ///
    /// - Returns: This builder, for method chaining.
    func addMoveColumnMutation() -> Self {
        add {
            Input(MoveColumnInput.self) {
                InputField("id", at: \.id).description(SchemaDescription.columnReference)
                InputField("before", at: \.before).description(SchemaDescription.columnBefore)
                InputField("after", at: \.after).description(SchemaDescription.columnAfter)
            }
            .description(SchemaDescription.moveColumnInput)
        }
        .addMutation {
            Self.mutationField(
                MutationName.moveColumn,
                at: KanbanResolver.moveColumn,
                description: SchemaDescription.moveColumn
            )
        }
    }
}
