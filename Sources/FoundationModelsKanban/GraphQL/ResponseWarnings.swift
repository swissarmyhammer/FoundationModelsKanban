import Synchronization

/// One warning of a response: an item of `extensions.warnings` (plan.md §4.4).
///
/// A warning tells the agent that the call did its work in a different way than the agent asked, for example that the
/// call ignored a parameter. A warning is not an error: the call ran, and its changes are written.
struct ResponseWarning: Encodable, Sendable {
    /// The text for the agent: what the call did, and how to make the call the correct way.
    let message: String

    /// A short stable name of the kind of the warning, or `nil` for a warning with no code. The encoder leaves out the
    /// key when the value is `nil`.
    // The synthesized `Encodable` conformance reads this property; periphery sees no reader.
    // periphery:ignore
    let code: String?
}

/// A fact about a board that the response of a run gives as one warning, for example a related board that cannot be
/// read, or a board ref with an old board name (divergence.md Q7, M9).
protocol BoardWarning: Sendable {
    /// The text of the warning for the agent.
    var warningMessage: String { get }

    /// The code of the warning, in `extensions.warnings` (plan.md §4.4).
    var warningCode: String { get }
}

extension BoardWarning {
    /// The warning of the response for this fact.
    var responseWarning: ResponseWarning {
        ResponseWarning(message: warningMessage, code: warningCode)
    }
}

/// The warnings of one run of a document: the one list that becomes `extensions.warnings` of the response (plan.md
/// §4.4).
///
/// Each ``KanbanContext`` has its own collector, and the engine makes a new context for each run of a call. Thus the
/// warnings of one call do not go into the response of a different call, also when the calls run at the same time,
/// and a run that the engine starts again does not repeat the warnings of the run before it.
///
/// A resolver adds a warning with `await context.warnings.add(…)`. The name rewrite runs in the same run, before the
/// engine runs the rewritten document, so it can add to the collector of the same context. The response reads the
/// list when it is encoded. A read does not empty the list, so that a call that fails as a whole after its run, for
/// example with `BOARD_BUSY`, gives the same warnings in its error response.
actor ResponseWarnings {
    /// The warnings that the run added, in the order of the adds.
    private(set) var list: [ResponseWarning] = []

    /// Adds one warning to the list.
    ///
    /// - Parameters:
    ///   - message: The text for the agent.
    ///   - code: The kind of the warning, or `nil` for a warning with no code.
    func add(_ message: String, code: String? = nil) {
        list.append(ResponseWarning(message: message, code: code))
    }

    /// Adds some warnings to the list, in their order.
    ///
    /// - Parameter added: The warnings, for example the warnings that one mutation field gave.
    func add(contentsOf added: [ResponseWarning]) {
        list.append(contentsOf: added)
    }
}

/// The warnings that the ref resolver gives in one run of a document, for example the pick of the first match of a
/// short id that two tasks share (divergence.md Q20).
///
/// The resolver is synchronous, and many resolvers of the schema make one, so it cannot `await` the actor
/// ``ResponseWarnings`` of the context. Thus the run binds a collector to ``current`` (a task local), the resolver
/// adds to it with no `await`, and the run then moves the list into the ``ResponseWarnings`` of its context
/// (``ResolverWarnings/collecting(into:during:)``). A `Mutex` guards the list, and not an actor, because each add is
/// synchronous. The GraphQL engine resolves the fields of one run in child tasks, and a child task reads the task
/// local of its parent, so each add of the run reaches the same collector.
///
/// A resolve with no bound collector, for example the resolve of a filter value, adds no warning.
final class ResolverWarnings: Sendable {
    /// The collector of the run that runs now, or `nil` when no run binds one.
    @TaskLocal static var current: ResolverWarnings?

    /// The warnings that the resolver added, in the order of the adds, with no repeat, behind a lock.
    private let warnings = Mutex<[ResponseWarning]>([])

    /// The warnings that the resolver added, in the order of the adds.
    var list: [ResponseWarning] {
        warnings.withLock { warnings in warnings }
    }

    /// Adds one warning. A warning with the same message as a warning of the list is not added again, because one run
    /// can resolve the same ref more than one time.
    ///
    /// - Parameter warning: The warning.
    func add(_ warning: ResponseWarning) {
        warnings.withLock { warnings in
            guard !warnings.contains(where: { added in added.message == warning.message }) else {
                return
            }
            warnings.append(warning)
        }
    }

    /// Runs a body with a new collector bound to ``current``, then adds the warnings of the collector to the warnings
    /// of a run.
    ///
    /// - Parameters:
    ///   - responseWarnings: The warnings of the run, for `extensions.warnings`.
    ///   - body: The work of the run, for example the execute of the document.
    /// - Returns: The value of the body.
    /// - Throws: The error of the body. The warnings that the body added before the error are then not moved.
    static func collecting<Value: Sendable>(
        into responseWarnings: ResponseWarnings,
        during body: () async throws -> Value
    ) async throws -> Value {
        let collector = ResolverWarnings()
        let value = try await $current.withValue(collector) {
            try await body()
        }
        await responseWarnings.add(contentsOf: collector.list)
        return value
    }
}
