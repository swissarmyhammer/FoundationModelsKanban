import GraphQL

/// The `extensions.code` of each error of a response (plan.md §4.4).
///
/// Each error of a response gets the message and the code of one ``KanbanError``. The path, the locations, and the
/// nodes of the error do not change.
extension GraphQLError {
    /// Gives this error with the message and the code of a ``KanbanError``.
    ///
    /// - Parameter kanbanError: The error that gives the message and the code.
    /// - Returns: The error with the message of `kanbanError`, and its code in `extensions.code`. The other keys of
    ///   `extensions` do not change.
    func coded(as kanbanError: KanbanError) -> GraphQLError {
        let codeKey = KanbanError.ResponseError.Extensions.CodingKeys.code.stringValue
        let responseError = kanbanError.responseError()
        return GraphQLError(
            message: responseError.message,
            nodes: nodes,
            source: source,
            positions: positions,
            path: path,
            originalError: kanbanError,
            extensions: extensions.merging([codeKey: .string(responseError.extensions.code)]) { _, code in code }
        )
    }

    /// Gives an error of the parse of a document with its code: `GRAPHQL_PARSE_FAILED`, or the code of the
    /// ``KanbanError`` that the error already holds.
    ///
    /// - Returns: The coded error.
    func codedAsParseFailure() -> GraphQLError {
        coded(as: originalError as? KanbanError ?? .graphQLParseFailed(detail: message))
    }

    /// Gives an error of the validation or the execution of a document with its code.
    ///
    /// - A resolver error that is a ``KanbanError`` keeps the code of that error.
    /// - An error with no path and no original error comes from the request before execution: validation, the
    ///   values of the variables, or the choice of the operation. It gets `GRAPHQL_VALIDATION_FAILED`.
    /// - Each other error is a fault of the execution, for example an ``EventError`` of a resolver. It gets
    ///   `INTERNAL`.
    ///
    /// The message of the engine does not change, except for a ``KanbanError``.
    ///
    /// - Returns: The coded error.
    func codedAsResultError() -> GraphQLError {
        if let kanbanError = originalError as? KanbanError {
            return coded(as: kanbanError)
        }
        guard originalError != nil || !path.elements.isEmpty else {
            return coded(as: .graphQLValidationFailed(detail: message))
        }
        return coded(as: .internalFailure(detail: message))
    }
}
