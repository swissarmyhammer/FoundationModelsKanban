/// One warning of a response: an item of `extensions.warnings` (plan.md §4.4).
///
/// A warning tells the agent that the call did its work in a different way than the agent asked, for example that the
/// call ignored a parameter. A warning is not an error: the call ran, and its changes are written.
struct ResponseWarning: Encodable, Sendable {
    /// The text for the agent: what the call did, and how to make the call the correct way.
    // The synthesized `Encodable` conformance reads this property; periphery sees no reader.
    // periphery:ignore
    let message: String

    /// A short stable name of the kind of the warning, or `nil` for a warning with no code. The encoder leaves out the
    /// key when the value is `nil`.
    // The synthesized `Encodable` conformance reads this property; periphery sees no reader.
    // periphery:ignore
    let code: String?
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
