import Foundation
import FoundationModelsExtras
import Synchronization
import Testing

@testable import FoundationModelsKanban

/// Tests that a session is ready before the embeddings of its board finish (divergence.md §16, L4).
///
/// The search update starts when the task nodes exist, at the same time as the merge of the event lists.
/// `host.session` waits for the keyword index (BM25 and trigram), and not for the embeddings. Until the embeddings
/// finish, `searchTasks` gives keyword hits with no cosine score. Each test uses a board in a temporary directory.
@Suite("Search: the session is ready before the embeddings finish", .watcherBudget)
struct SearchReadinessTests {
    /// Gives the `query` argument of a word of the title of the fixture task.
    ///
    /// - Returns: The argument text.
    /// - Throws: An error when the title of the fixture task has no word.
    static func titleQuery() throws -> String {
        TaskSearchTests.query(try #require(KanbanGraphTests.taskTitle.split(separator: " ").last.map(String.init)))
    }

    @Test("The search update starts before the merge of the event lists of the load ends")
    func searchUpdateStartsBeforeMergeEnds() async throws {
        let directory = try TemporaryDirectory()
        _ = try TaskSearchTests.writeFixture(inRepoAt: directory.url)
        let embedder = GatedEmbedder()
        let probe = MergeProbe(waitingFor: embedder)
        let host = HostFixture.makeHost(observingLoadsWith: probe, embeddingWith: embedder)
        _ = try await host.session(workingDirectory: directory.url, actor: KanbanHostTests.firstActor)
        embedder.release()
        #expect(probe.embedStartedBeforeMerge == [true])
        await host.close()
    }

    @Test("host.session returns before a slow embedder finishes, and searchTasks gives keyword hits at once")
    func sessionIsReadyBeforeEmbeddings() async throws {
        let directory = try TemporaryDirectory()
        let task = try TaskSearchTests.writeFixture(inRepoAt: directory.url)
        let embedder = GatedEmbedder()
        let host = HostFixture.makeHost(embeddingWith: embedder)
        let session = try await host.session(workingDirectory: directory.url, actor: KanbanHostTests.firstActor)
        let finishedEmbeds = embedder.finishCount
        let hits = try await TaskSearchTests.hits(searchingWith: Self.titleQuery(), on: session)
        embedder.release()
        #expect(finishedEmbeds == 0)
        #expect(hits.map(\.task.id) == [ColumnActorTests.id(of: .task(task))])
        #expect(hits.allSatisfy { hit in hit.signals.cosine == nil })
        await host.close()
    }

    @Test("When the embeddings finish, searchTasks gives cosine scores, and the board does not load again")
    func searchUsesEmbeddingsWhenTheyFinish() async throws {
        let directory = try TemporaryDirectory()
        let task = try TaskSearchTests.writeFixture(inRepoAt: directory.url)
        let embedder = GatedEmbedder()
        let recorder = LoadRecorder()
        let host = HostFixture.makeHost(observingLoadsWith: recorder, embeddingWith: embedder)
        let session = try await host.session(workingDirectory: directory.url, actor: KanbanHostTests.firstActor)
        let keywordHits = try await TaskSearchTests.hits(searchingWith: Self.titleQuery(), on: session)
        embedder.release()
        let engine = try await host.engine(ofBoardAt: directory.url)
        await engine.session.source.search.waitForEmbeddings()
        let hits = try await TaskSearchTests.hits(searchingWith: Self.titleQuery(), on: session)
        #expect(!keywordHits.isEmpty)
        #expect(keywordHits.allSatisfy { hit in hit.signals.cosine == nil })
        #expect(hits.first?.task.id == ColumnActorTests.id(of: .task(task)))
        #expect(!hits.isEmpty && hits.allSatisfy { hit in hit.signals.cosine != nil })
        #expect(recorder.loadStarts == [directory.url])
        await host.close()
    }
}

// MARK: - Gated embedder

/// An embedder that holds each embed until the test releases it. The hold has no time limit. It counts the embeds
/// that started and the embeds that finished.
final class GatedEmbedder: PooledEmbedding {
    /// The counts and the release of the embedder.
    private struct State {
        /// `true` after ``release()``.
        var isReleased = false

        /// The number of embeds that started.
        var startCount = 0

        /// The number of embeds that finished.
        var finishCount = 0
    }

    /// The state, behind a lock, because the embeds run on different threads.
    private let state = Mutex(State())

    /// Makes an embedder that holds each embed until ``release()``.
    init() {}

    /// The number of embeds that started.
    var startCount: Int {
        state.withLock { state in state.startCount }
    }

    /// The number of embeds that finished.
    var finishCount: Int {
        state.withLock { state in state.finishCount }
    }

    /// Lets each held embed and each later embed finish at once.
    func release() {
        state.withLock { state in state.isReleased = true }
    }

    /// Waits until the release, and then gives the vectors of ``TaskSearchTests/FakeEmbedder``.
    ///
    /// - Parameter texts: The texts.
    /// - Returns: One vector for each text.
    /// - Throws: `CancellationError` when the task of the embed is cancelled.
    func embed(texts: [String]) async throws -> [[Float]] {
        state.withLock { state in state.startCount += 1 }
        try await EventLogTests.waitUntil { self.state.withLock { state in state.isReleased } }
        state.withLock { state in state.finishCount += 1 }
        return try await TaskSearchTests.FakeEmbedder().embed(texts: texts)
    }

    /// Waits until the first embed starts. The wait has no time limit. A cancel of the task ends the wait.
    func waitForStart() async {
        try? await EventLogTests.waitUntil { self.startCount > 0 }
    }
}

// MARK: - Merge probe

/// Holds the merge of the event lists of each board load until an embed starts, and records whether an embed
/// started first. The hold has no time limit.
final class MergeProbe: BoardLoadObserver {
    /// The embedder of the search of the host.
    private let embedder: GatedEmbedder

    /// The recorded answers, behind a lock, because the loads run on different threads.
    private let answers = Mutex<[Bool]>([])

    /// Makes a probe.
    ///
    /// - Parameter embedder: The embedder of the search of the host.
    init(waitingFor embedder: GatedEmbedder) {
        self.embedder = embedder
    }

    /// The answer of each merge, in order: `true` when an embed started before the merge.
    var embedStartedBeforeMerge: [Bool] {
        answers.withLock { answers in answers }
    }

    /// Does nothing: the probe holds only the merge.
    ///
    /// - Parameter root: The root folder of the board.
    func boardLoadDidStart(at root: URL) async {}

    /// Does nothing: the probe holds only the merge.
    ///
    /// - Parameter root: The root folder of the board.
    func boardLoadDidFinish(at root: URL) {}

    /// Holds the merge until an embed starts, and records whether an embed started.
    ///
    /// - Parameter root: The root folder of the board.
    func boardEventsWillMerge(at root: URL) async {
        await embedder.waitForStart()
        answers.withLock { answers in answers.append(embedder.startCount > 0) }
    }
}
