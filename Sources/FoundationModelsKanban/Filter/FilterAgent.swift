import FoundationModels

/// The result of `Query.translateFilter`: the `FilterTranslation` type (divergence.md §17).
struct FilterTranslation: Codable, Sendable, Equatable {
    /// The number of attempts of a text that is already a filter of the board: the model gets no call.
    static let attemptsOfFilter = 0

    /// The filter statement, or `nil` when the filter agent wrote no statement that parses and names only nodes of the
    /// board.
    let filter: String?

    /// A message for the caller, or `nil` when there is nothing to tell.
    let message: String?

    /// The number of statements that the filter model wrote. A text that is already a filter of the board gives
    /// ``attemptsOfFilter``.
    let attempts: Int

    /// Gives back a text that is already a filter of the board, with no model call.
    ///
    /// - Parameter filter: The text, as the caller wrote it.
    /// - Returns: The translation of the text: the text itself.
    static func unchanged(_ filter: String) -> FilterTranslation {
        FilterTranslation(filter: filter, message: nil, attempts: attemptsOfFilter)
    }
}

/// The filter agent of the engine (divergence.md §17): it gives a filter statement of the board for a text, which is a
/// filter or English.
///
/// A text that parses and names only nodes of the board (``FilterNameCheck``) comes back as it is, and the filter
/// model gets no call. Each other text goes to the loop of the filter agent (``FilterAgentLoop``) with the filter
/// model. With no filter model, the agent gives `FILTER_MODEL_MISSING`. The agent writes nothing to the board.
struct FilterAgent: Sendable {
    /// The filter model that the host gave, or `nil` for no model.
    private let model: (any LanguageModel)?

    /// Makes the filter agent of a call.
    ///
    /// - Parameter model: The filter model that the host gave, or `nil` for no model.
    init(model: (any LanguageModel)?) {
        self.model = model
    }

    /// Gives a filter statement of the board for a text.
    ///
    /// - Parameters:
    ///   - text: The text, as the caller wrote it: a filter, or English.
    ///   - view: The read view of the board of the filter.
    ///   - caller: The session actor of the call.
    /// - Returns: The translation: the text itself with ``FilterTranslation/attemptsOfFilter`` when it is a filter of
    ///   the board, else the translation of the loop.
    /// - Throws: ``KanbanError/filterModelMissing(filterError:)`` when the text is not a filter of the board and the
    ///   agent has no filter model. ``KanbanError/filterAgentFailed(reason:)`` when the loop stops before the model
    ///   writes a statement. A `CancellationError`, unchanged, when the task of the call is cancelled.
    func translate(
        _ text: String,
        on view: BoardView,
        for caller: SessionActor
    ) async throws -> FilterTranslation {
        let check = FilterNameCheck(over: view.readiness, inBoard: view.boardKey, for: caller)
        let filterError: KanbanError
        do throws(KanbanError) {
            try check.check(text)
            return .unchanged(text)
        } catch {
            filterError = error
        }
        guard let model else {
            throw KanbanError.filterModelMissing(filterError: filterError)
        }
        return try await FilterAgentLoop(model: model, check: check).translate(text, on: view, for: caller)
    }
}
