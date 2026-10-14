import FoundationModelsExtras
import FoundationModelsMetadataRegistry

/// The search of one board with embeddings, and the loop that updates it in the background (divergence.md §16, L4).
///
/// `MetadataSearcher.update(items:)` returns only when the embeddings of the new catalog are done. Thus the loop calls
/// it in a background task, and ``TaskSearch`` does not wait for it. The loop updates the searcher with the newest
/// catalog only: a catalog that a newer catalog replaced before the loop took it is never embedded.
///
/// The searcher answers a search only when it holds the newest catalog (``matchesOfNewestCatalog(for:limit:)``).
/// Until then, ``TaskSearch`` answers with its keyword searcher.
actor EmbeddedTaskCatalog {
    /// The state of the update loop.
    private enum UpdateLoop {
        /// No loop runs, and the searcher holds the newest catalog.
        case idle

        /// A loop runs `task`. It updates the searcher until no newer catalog waits.
        case running(Task<Void, Never>)

        /// ``stop()`` cancelled the loop. The searcher gets no more catalogs, and it answers no search.
        case stopped
    }

    /// The searcher with the embedder: BM25, trigram, and cosine.
    private let searcher: MetadataSearcher<TaskSearchItem>

    /// The state of the update loop.
    private var loop = UpdateLoop.idle

    /// The newest catalog that the loop did not take yet, or `nil` when no catalog waits.
    private var newestItems: [TaskSearchItem]?

    /// Makes a catalog with no task. The searcher embeds nothing until the first catalog.
    ///
    /// - Parameter embedder: The embedder of the tasks and of the queries.
    init(embeddingWith embedder: any PooledEmbedding) {
        searcher = MetadataSearcher(items: [], mode: .retrieval, embedder: embedder)
    }

    /// Gives a new catalog to the loop, and starts the loop when it does not run. The call does not wait for the
    /// embeddings. A stopped catalog ignores the call.
    ///
    /// - Parameter items: The tasks of the board, live and tombstoned.
    func submit(_ items: [TaskSearchItem]) {
        switch loop {
        case .stopped:
            return
        case .running:
            newestItems = items
        case .idle:
            newestItems = items
            loop = .running(Task { await self.runLoop() })
        }
    }

    /// Ranks the tasks for a query with the searcher, when the searcher holds the newest catalog.
    ///
    /// - Parameters:
    ///   - query: The search text.
    ///   - limit: The largest number of matches.
    /// - Returns: The matches, highest score first, or `nil` when the embeddings of the newest catalog are not done.
    /// - Throws: An error of the searcher. The `.retrieval` mode gives none.
    func matchesOfNewestCatalog(for query: String, limit: Int) async throws -> [Match<TaskSearchItem>]? {
        guard case .idle = loop else {
            return nil
        }
        return try await searcher.search(intent: query, limit: limit)
    }

    /// Waits until the loop ends: the searcher then holds the newest catalog, or the catalog is stopped.
    func waitForEmbeddings() async {
        while case .running(let task) = loop {
            await task.value
        }
    }

    /// Cancels the loop. The searcher gets no more catalogs, and it answers no search. A second call does nothing.
    ///
    /// `MetadataSearcher` runs its embed in a task of its own, so an embed that is in flight can still run to its end.
    /// The loop then takes no next catalog.
    func stop() {
        if case .running(let task) = loop {
            task.cancel()
        }
        loop = .stopped
        newestItems = nil
    }

    /// Updates the searcher with the newest catalog until no newer catalog waits, and then marks the loop idle.
    ///
    /// No `await` stands between the last take of a catalog and the mark, so a catalog that comes later starts a new
    /// loop and is never lost.
    private func runLoop() async {
        while let items = takeNewestItems() {
            await searcher.update(items: items)
        }
        guard case .running = loop else {
            return
        }
        loop = .idle
    }

    /// Takes the newest catalog that waits, while the loop runs.
    ///
    /// - Returns: The catalog, or `nil` when no catalog waits or the catalog is stopped.
    private func takeNewestItems() -> [TaskSearchItem]? {
        guard case .running = loop else {
            return nil
        }
        return newestItems.take()
    }
}
