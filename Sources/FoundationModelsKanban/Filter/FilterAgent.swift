import FoundationModels

/// The result of `Query.translateFilter`: the `FilterTranslation` type (divergence.md §17).
struct FilterTranslation: Codable, Sendable {
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

/// Writes a filter of the board from English text with the filter model: the seam that the loop of the filter agent
/// fills (divergence.md §17, "The loop").
protocol FilterTranslator: Sendable {
    /// Writes a filter of the board from a text that is not a filter of the board.
    ///
    /// - Parameters:
    ///   - text: The text, as the caller wrote it.
    ///   - filterError: The `INVALID_FILTER` error of the text: the parse error, or the first name that names nothing.
    ///   - view: The read view of the board of the filter.
    ///   - caller: The session actor of the call: "me" in the text names this actor.
    ///   - model: The filter model.
    /// - Returns: The translation.
    /// - Throws: A ``KanbanError`` when the translator cannot write a filter.
    func translate(
        _ text: String,
        notAFilterBecause filterError: KanbanError,
        on view: BoardView,
        for caller: SessionActor,
        using model: any LanguageModel
    ) async throws(KanbanError) -> FilterTranslation
}

/// The translator until the loop of the filter agent fills the seam (divergence.md §17): it calls no model, and gives
/// `FILTER_MODEL_MISSING` with the filter error of the text.
struct PendingFilterTranslator: FilterTranslator {
    /// Gives `FILTER_MODEL_MISSING`, because no loop writes a filter yet.
    ///
    /// - Parameters:
    ///   - text: The text. The translator does not read it.
    ///   - filterError: The `INVALID_FILTER` error of the text.
    ///   - view: The read view of the board. The translator does not read it.
    ///   - caller: The session actor of the call. The translator does not read it.
    ///   - model: The filter model. The translator does not call it.
    /// - Returns: Never.
    /// - Throws: ``KanbanError/filterModelMissing(filterError:)`` with the filter error.
    func translate(
        _ text: String,
        notAFilterBecause filterError: KanbanError,
        on view: BoardView,
        for caller: SessionActor,
        using model: any LanguageModel
    ) async throws(KanbanError) -> FilterTranslation {
        throw .filterModelMissing(filterError: filterError)
    }
}

/// The filter agent of the engine (divergence.md §17): it gives a filter statement of the board for a text, which is a
/// filter or English.
///
/// A text that parses and names only nodes of the board (``FilterNameCheck``) comes back as it is, and the filter
/// model gets no call. Each other text goes to the translator with the filter model. With no filter model, the agent
/// gives `FILTER_MODEL_MISSING`. The agent writes nothing to the board.
struct FilterAgent: Sendable {
    /// The filter model that the host gave, or `nil` for no model.
    private let model: (any LanguageModel)?

    /// The translator of a text that is not a filter of the board.
    private let translator: any FilterTranslator = PendingFilterTranslator()

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
    ///   the board, else the translation of the translator.
    /// - Throws: ``KanbanError/filterModelMissing(filterError:)`` when the text is not a filter of the board and the
    ///   agent has no filter model. An error of the translator.
    func translate(
        _ text: String,
        on view: BoardView,
        for caller: SessionActor
    ) async throws(KanbanError) -> FilterTranslation {
        let filterError: KanbanError
        do throws(KanbanError) {
            try FilterNameCheck(over: view.readiness, inBoard: view.boardKey).check(text)
            return .unchanged(text)
        } catch {
            filterError = error
        }
        guard let model else {
            throw .filterModelMissing(filterError: filterError)
        }
        return try await translator.translate(text, notAFilterBecause: filterError, on: view, for: caller, using: model)
    }
}
