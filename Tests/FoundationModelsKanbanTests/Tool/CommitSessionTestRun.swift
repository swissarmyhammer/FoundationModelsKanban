@testable import FoundationModelsKanban

extension CommitSession {
    /// Runs one call on the session as the session actor of the tests, ``KanbanGraphTests/sessionActor``, with no
    /// related boards.
    ///
    /// A session has no actor of its own: each session view gives its actor to each run (divergence.md §16). The
    /// tests of one session use one actor, so this run gives it.
    ///
    /// - Parameter call: Runs the call against the store of the working copy, and gives the response.
    /// - Returns: The response of the run that committed, or of the run that kept no patch.
    /// - Throws: The error of ``run(actingAs:reaching:readingRelatedBoardsWith:storingRelatedBoardsWith:admittingCommitsWith:_:)``.
    mutating func run<Response: Sendable>(
        _ call: @Sendable (BoardStore) async throws -> Response
    ) async throws -> Response {
        try await run(actingAs: KanbanGraphTests.sessionActor, call)
    }
}
