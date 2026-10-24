/// The descriptions of `Query.translateFilter` and the `FilterTranslation` type (divergence.md §17, EXTRAS-9 rule
/// 11).
extension SchemaDescription {
    // MARK: - Query.translateFilter

    /// The `Query.translateFilter` field (``KanbanResolver/translateFilter(context:arguments:)``).
    static let queryTranslateFilter = """
        Gives a filter statement of the board for a text. A text that is already a filter of the board comes back \
        with attempts \(FilterTranslation.attemptsOfFilter), and the filter model gets no call. Each other text, for \
        example English, goes to the filter model of the host. With no filter model, the call gives \
        FILTER_MODEL_MISSING. The call writes nothing.
        """

    /// The `text` argument of `Query.translateFilter`.
    static let translationText = """
        The text: a filter statement, or English, for example bugs that alice has not finished.
        """

    // MARK: - FilterTranslation

    /// The `FilterTranslation` type.
    static let filterTranslation = "The result of translateFilter: a filter statement of the board for a text."

    /// The `FilterTranslation.filter` field.
    static let translationFilter = """
        The filter statement. Give it as filter to tasks. Null when the filter agent wrote no statement that parses \
        and names only nodes of the board.
        """

    /// The `FilterTranslation.message` field.
    static let translationMessage = """
        A message for the caller, for example the last error when the filter agent wrote no filter. Null when there \
        is nothing to tell.
        """

    /// The `FilterTranslation.attempts` field.
    static let translationAttempts = """
        The number of statements that the filter model wrote. \(FilterTranslation.attemptsOfFilter) when the text is \
        already a filter of the board.
        """
}
