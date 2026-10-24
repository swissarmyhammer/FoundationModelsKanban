import Graphiti

/// The arguments of `Query.translateFilter` (divergence.md §17).
struct TranslateFilterArguments: Codable, Sendable {
    /// The board of the filter: a board key, a repo directory name, a path, or the URI of a board (plan.md §6.6). No
    /// value gives the current board.
    let board: NodeID?

    /// The text to translate: a filter statement, or English.
    let text: String
}

extension KanbanResolver {
    /// Resolves `Query.translateFilter`: a filter statement of the board for a text (divergence.md §17). The field is a
    /// query: it writes no event, so it pushes no undo entry.
    ///
    /// - Parameters:
    ///   - context: The context of the call. It holds the filter agent.
    ///   - arguments: The board and the text.
    /// - Returns: The translation.
    /// - Throws: An error of ``BoardStore/loadedView(ofBoard:)``. An error of ``FilterAgent/translate(_:on:for:)``, for
    ///   example ``KanbanError/filterModelMissing(filterError:)``, or the `CancellationError` of a cancelled call,
    ///   unchanged (divergence.md §17, "The loop").
    func translateFilter(
        context: KanbanContext,
        arguments: TranslateFilterArguments
    ) async throws -> FilterTranslation {
        let view = try await context.store.loadedView(ofBoard: arguments.board?.text)
        return try await context.filterAgent.translate(arguments.text, on: view, for: context.store.sessionActor)
    }
}

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `FilterTranslation` type of `Query.translateFilter` (divergence.md §17).
    ///
    /// - Returns: This builder, for method chaining.
    func addFilterTranslationTypes() -> Self {
        add {
            Type(FilterTranslation.self) {
                Field("filter", at: \.filter).description(SchemaDescription.translationFilter)
                Field("message", at: \.message).description(SchemaDescription.translationMessage)
                Field("attempts", at: \.attempts).description(SchemaDescription.translationAttempts)
            }
            .description(SchemaDescription.filterTranslation)
        }
    }
}
