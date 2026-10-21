import FoundationModelsExtras

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
