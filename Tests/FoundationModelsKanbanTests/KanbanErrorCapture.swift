import Testing

@testable import FoundationModelsKanban

/// Catches the ``KanbanError`` of a call that must throw one, for the tests that check the error.
enum KanbanErrorCapture {
    /// Runs a call that must throw a ``KanbanError``, and gives the error.
    ///
    /// The test fails at the location of the caller when the call throws no error or a different error.
    ///
    /// - Parameters:
    ///   - sourceLocation: The location that a failure shows. The default is the location of the call.
    ///   - call: The call that must throw.
    /// - Returns: The error.
    /// - Throws: An error of `#require` when the call throws no ``KanbanError``.
    static func error<Result>(
        sourceLocation: SourceLocation = #_sourceLocation,
        of call: () throws -> Result
    ) throws -> KanbanError {
        let error = #expect(throws: KanbanError.self, sourceLocation: sourceLocation, performing: call)
        return try #require(error, sourceLocation: sourceLocation)
    }
}
