import Foundation

/// Gets the canonical paths of the repo directories of the boards of a commit attempt, before the attempt, and throws
/// when the caller cannot commit to these boards now (divergence.md §16, locks across boards).
typealias CommitAdmission = @Sendable (Set<String>) async throws -> Void

/// The serial gates that one call of a session view holds: the gate of each board that the call can commit to
/// (divergence.md §16, locks across boards).
///
/// A call takes the gates in the sort order of the identity of their boards. Two calls that need the same boards thus
/// take the gates in the same order, and they cannot wait for each other. A call that finds that it needs one more
/// board throws ``GateShortfall`` before it writes, gives back each gate, and takes the larger set in order.
struct HeldGates: Sendable {
    /// The engines whose gates the call holds, in the sort order of their identity.
    let engines: [BoardEngine]

    /// Makes a set of gates.
    ///
    /// - Parameter engines: The engines. The order and repeats do not matter.
    init(of engines: some Sequence<BoardEngine>) {
        let unique = Dictionary(engines.map { engine in (engine.identity, engine) }) { first, _ in first }
        self.engines = unique.keys.sorted().compactMap { identity in unique[identity] }
    }

    /// Tells if the call holds the gate of an engine.
    ///
    /// - Parameter engine: The engine.
    /// - Returns: `true` when the call holds the gate.
    func holds(_ engine: BoardEngine) -> Bool {
        engines.contains { held in held.identity == engine.identity }
    }

    /// Gives this set with more engines.
    ///
    /// - Parameter more: The engines to add.
    /// - Returns: The larger set.
    func adding(_ more: [BoardEngine]) -> HeldGates {
        HeldGates(of: engines + more)
    }

    /// Runs an operation while it holds the gate of each engine of the set. The gates are taken in the sort order of
    /// the identities.
    ///
    /// - Parameter operation: The operation. It gets this set.
    /// - Returns: The value of the operation.
    /// - Throws: The error of the operation. Each gate is given back.
    func run<Value: Sendable>(_ operation: @Sendable (HeldGates) async throws -> Value) async throws -> Value {
        try await run(from: engines[...], operation)
    }

    /// Takes the gate of the first engine of a list, and then the gates of the rest of the list, and runs the
    /// operation inside all of them.
    ///
    /// - Parameters:
    ///   - remaining: The engines whose gates are not taken yet, in order.
    ///   - operation: The operation.
    /// - Returns: The value of the operation.
    /// - Throws: The error of the operation.
    private func run<Value: Sendable>(
        from remaining: ArraySlice<BoardEngine>,
        _ operation: @Sendable (HeldGates) async throws -> Value
    ) async throws -> Value {
        guard let first = remaining.first else {
            return try await operation(self)
        }
        return try await first.gate.run {
            try await self.run(from: remaining.dropFirst(), operation)
        }
    }
}

/// A call needs the gates of boards that it does not hold. The call wrote nothing; it gives back each gate, takes the
/// larger set in order, and runs again (divergence.md §16, locks across boards).
struct GateShortfall: Error {
    /// The engines whose gates the call needs and does not hold.
    let engines: [BoardEngine]
}
