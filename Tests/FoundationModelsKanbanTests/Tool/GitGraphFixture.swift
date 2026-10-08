import Foundation

@testable import FoundationModelsKanban

/// The engines of the suites that use real git repos, for example the portability and cross-repo suites. Each engine
/// reads the board keys from git, not from the fake key reader of ``KanbanGraphTests``.
enum GitGraphFixture {
    /// Makes an engine for a repo that reads the board keys from git.
    ///
    /// - Parameters:
    ///   - root: The root directory of the repo.
    ///   - locator: Finds the related boards. The default looks only in the parent directory of the repo.
    ///   - recorder: Records each batch that the file watchers apply, or `nil` for no record.
    /// - Returns: The engine.
    static func makeGraph(
        at root: URL,
        locatedBy locator: BoardLocator = .default,
        recordedBy recorder: BatchRecorder? = nil
    ) throws -> KanbanGraph {
        try KanbanGraphTests.makeGraph(
            at: root,
            readingKeyWith: BoardKey.read(fromRepoAt:),
            locatedBy: locator,
            observingBatchesWith: recorder
        )
    }
}
