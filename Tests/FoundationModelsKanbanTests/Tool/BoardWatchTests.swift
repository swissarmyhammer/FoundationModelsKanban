import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the one initializer that makes the watch of a started watcher for an owner: the engine of a board, or the
/// host. The watch gives each batch to its receiver with the owner, and it holds the owner weakly.
///
/// Each test watches its own temporary folder and ends its watch, so that its file watcher stops.
@Suite("BoardWatch: the batches of a started watcher go to a weak owner", .watcherBudget)
struct BoardWatchTests {
    /// The name of the file that a test writes into the watched folder.
    static let fileName = "changed.txt"

    @Test("A watch gives a batch of its watcher to the receiver, with the owner")
    func watchSendsBatchToOwner() async throws {
        let directory = try TemporaryDirectory()
        let owner = BatchOwner()
        let started = try await StartedWatcher(watching: directory.url, in: FolderStreams())
        let watch = BoardWatch(of: started, heldWeaklyBy: owner) { owner, paths in
            await owner.record(paths)
        }
        let file = directory.url.appendingPathComponent(Self.fileName)
        try Data().write(to: file)
        let isFound = try await BoardWatcherTests.hasBatch(in: owner.batches, holding: file)
        await watch.end()
        #expect(isFound)
    }

    @Test("A watch holds its owner weakly, so the watch does not keep the owner alive")
    func watchHoldsOwnerWeakly() async throws {
        let directory = try TemporaryDirectory()
        var owner: BatchOwner? = BatchOwner()
        weak let released = owner
        let watch = BoardWatch(
            of: try await StartedWatcher(watching: directory.url, in: FolderStreams()),
            heldWeaklyBy: try #require(owner)
        ) { owner, paths in
            await owner.record(paths)
        }
        owner = nil
        #expect(released == nil)
        await watch.end()
    }
}

/// The owner of a watch in a test. It records each batch that its watch gives it, so that a test can wait for one.
private actor BatchOwner {
    /// The batches, in the order that the watch gave them.
    nonisolated let batches: AsyncStream<[URL]>

    /// The continuation of ``batches``.
    private let continuation: AsyncStream<[URL]>.Continuation

    /// Makes an owner with no batches.
    init() {
        (batches, continuation) = AsyncStream.makeStream()
    }

    /// Records one batch of the watch.
    ///
    /// - Parameter paths: The changed paths of the batch.
    func record(_ paths: [URL]) {
        continuation.yield(paths)
    }
}
