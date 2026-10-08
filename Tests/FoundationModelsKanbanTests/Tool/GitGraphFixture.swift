import Foundation

@testable import FoundationModelsKanban

/// The engines of the suites that use real git repos, for example the portability and cross-repo suites. Each engine
/// reads the board keys from git, not from the fake key reader of ``KanbanGraphTests``.
enum GitGraphFixture {
    /// The time step of the ULIDs of a second engine on the same repos. It is after the step of
    /// ``KanbanGraphTests/mutationIDs``, so the ids of the second engine sort after the ids of the first engine.
    static let secondEngineStep = 2

    /// The ULID source of a second engine on the same repos, for example a different process. Two engines with one
    /// fixed source would mint the same ids.
    static let secondEngineIDs = FixedULIDSource(at: ReplayTests.date(atStep: secondEngineStep))

    /// The time step of the ULIDs of a third engine on the same repos. It is after ``secondEngineStep``, so the ids of
    /// the third engine sort after the ids of the second engine.
    private static let thirdEngineStep = secondEngineStep + 1

    /// The ULID source of a third engine on the same repos, for example a third process.
    static let thirdEngineIDs = FixedULIDSource(at: ReplayTests.date(atStep: thirdEngineStep))

    /// Makes an engine for a repo that reads the board keys from git.
    ///
    /// - Parameters:
    ///   - root: The root directory of the repo.
    ///   - ids: The source of the transaction ULIDs and the event ids. The default is
    ///     ``KanbanGraphTests/mutationIDs``.
    ///   - locator: Finds the related boards. The default looks only in the parent directory of the repo.
    ///   - recorder: Records each batch that the file watchers apply, or `nil` for no record.
    /// - Returns: The engine.
    static func makeGraph(
        at root: URL,
        mintingFrom ids: FixedULIDSource = KanbanGraphTests.mutationIDs,
        locatedBy locator: BoardLocator = .default,
        recordedBy recorder: BatchRecorder? = nil
    ) throws -> KanbanGraph {
        try KanbanGraphTests.makeGraph(
            at: root,
            readingKeyWith: BoardKey.read(fromRepoAt:),
            mintingFrom: ids,
            locatedBy: locator,
            observingBatchesWith: recorder
        )
    }
}
