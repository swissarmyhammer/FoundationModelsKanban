import FoundationModelsExtras
import FoundationModelsMetadataRegistry

/// The ranked search over the tasks of one board (plan.md §6.4, §12 item 6). The selection of the call
/// (``TaskSelection``) removes a tombstone from the hits unless the filter names `#DELETED`.
///
/// The search uses `MetadataSearcher` in `.retrieval` mode: BM25, trigram, and embedding cosine (only with an
/// embedder), fused with reciprocal rank fusion. `.selection` is not used, because it calls a language model and its
/// result changes from call to call. The searchers keep their indexes in memory only.
///
/// The search holds two searchers (divergence.md §16, L4). The keyword searcher has no embedder, so its update returns
/// as soon as its BM25 and trigram indexes are ready. With an embedder, the ``EmbeddedTaskCatalog`` updates a second
/// searcher in the background, and embeds again only the tasks that changed. A search uses the second searcher when
/// it holds the newest catalog. Until then, the search uses the keyword searcher, and each hit gives no cosine score.
///
/// ``KanbanGraph`` keeps one search for each board for its life. The commit session calls ``update(from:)`` after
/// the first load and after each change of the live graph.
///
/// When the embedder fails, the searcher falls back to BM25 and trigram, and it records the diagnostic with swift-log.
/// The search gives no error.
struct TaskSearch: Sendable {
    /// The searcher with no embedder over the catalog of the tasks, live and tombstoned.
    private let keywordSearcher: MetadataSearcher<TaskSearchItem>

    /// The searcher with the embedder and its background update loop, or `nil` for BM25 and trigram only.
    private let embeddedCatalog: EmbeddedTaskCatalog?

    /// Makes a search with an empty catalog. The search embeds nothing until the first update.
    ///
    /// - Parameter embedder: The embedder of the tasks and the queries, or `nil` for BM25 and trigram only.
    init(embeddingWith embedder: (any PooledEmbedding)?) {
        keywordSearcher = MetadataSearcher(items: [], mode: .retrieval)
        embeddedCatalog = embedder.map(EmbeddedTaskCatalog.init(embeddingWith:))
    }

    /// Replaces the catalog with the tasks of a board, live and tombstoned, so that a filter that names `#DELETED`
    /// can find a tombstone.
    ///
    /// The call returns when the BM25 and trigram indexes of the new catalog are ready. The embeddings of the tasks
    /// that changed are done in the background (``waitForEmbeddings()``). The catalog goes to the embedding loop
    /// first, so that no search uses the searcher with the embedder while it holds an older catalog.
    ///
    /// - Parameter view: The read view of the board.
    func update(from view: BoardView) async {
        let items = view.allTasks.map(TaskSearchItem.init(of:))
        await embeddedCatalog?.submit(items)
        await keywordSearcher.update(items: items)
    }

    /// Waits until the embeddings of the newest catalog are done, or until ``stopEmbedding()`` stopped them. A search
    /// with no embedder returns at once.
    func waitForEmbeddings() async {
        await embeddedCatalog?.waitForEmbeddings()
    }

    /// Cancels the embeddings in the background. After the call, each search uses the keyword searcher only. The
    /// engine calls it when it closes, so that no embedding runs after the host closed.
    func stopEmbedding() async {
        await embeddedCatalog?.stop()
    }

    /// Ranks the tasks for a query, and keeps the selected tasks only (plan.md §6.4, filter).
    ///
    /// `MetadataSearcher` has no filter. Thus the search asks for one match for each task of the board, and then
    /// removes each match whose task is not in `tasks`: a task that does not pass the filter, a tombstone when the
    /// filter does not name `#DELETED`, and a task that the view does not have.
    ///
    /// - Parameters:
    ///   - query: The search text.
    ///   - view: The read view of the board.
    ///   - tasks: The tasks that the selection of the call accepts.
    ///   - first: The largest number of hits. A negative value gives no hit.
    /// - Returns: The hits, in the order of the fused score, highest first.
    /// - Throws: An error of the searcher. The `.retrieval` mode gives none.
    func hits(
        for query: String,
        in view: BoardView,
        among tasks: [TaskObject],
        first: Int
    ) async throws -> [TaskHit] {
        let selected = Dictionary(uniqueKeysWithValues: tasks.map { task in (task.id.text, task) })
        let ranked = try await rankedMatches(for: query, limit: view.graph.taskCount)
        let hits = ranked.matches.compactMap { match in
            selected[match.id].map { task in
                TaskHit(
                    task: task,
                    score: match.score,
                    signals: match.signals.map { scores in Self.signals(of: scores, withCosine: ranked.hasCosine) }
                )
            }
        }
        return Array(hits.prefix(max(first, .zero)))
    }

    /// Ranks the tasks for a query: with the searcher with the embedder when it holds the newest catalog, or else
    /// with the keyword searcher.
    ///
    /// - Parameters:
    ///   - query: The search text.
    ///   - limit: The largest number of matches.
    /// - Returns: The matches, highest score first, and `true` when the searcher with the embedder ranked them.
    /// - Throws: An error of the searcher. The `.retrieval` mode gives none.
    private func rankedMatches(
        for query: String,
        limit: Int
    ) async throws -> (matches: [Match<TaskSearchItem>], hasCosine: Bool) {
        if let matches = try await embeddedCatalog?.matchesOfNewestCatalog(for: query, limit: limit) {
            return (matches, true)
        }
        return (try await keywordSearcher.search(intent: query, limit: limit), false)
    }

    /// Gives the scores of the signals of one match.
    ///
    /// - Parameters:
    ///   - scores: The raw scores of the searcher.
    ///   - hasCosine: `true` when the searcher with the embedder ranked the match.
    /// - Returns: The scores, with no cosine score when the keyword searcher ranked the match.
    private static func signals(of scores: Signals, withCosine hasCosine: Bool) -> SearchSignals {
        SearchSignals(bm25: scores.bm25, trigram: scores.trigram, cosine: hasCosine ? scores.cosine : nil)
    }
}

/// One task that a search found, as the GraphQL `TaskHit` type (plan.md §6.4, result).
struct TaskHit: Sendable {
    /// The task.
    let task: TaskObject

    /// The fused score, from 0 to 1.
    let score: Double

    /// The scores of each signal, or `nil` when the searcher gives none.
    let signals: SearchSignals?
}

/// The scores of each signal of one hit, as the GraphQL `SearchSignals` type (plan.md §6.4, result).
struct SearchSignals: Sendable {
    /// The BM25 score: the word match.
    let bm25: Double

    /// The trigram score: partial words and typing errors.
    let trigram: Double

    /// The embedding cosine score, or `nil` when the search has no embedder or the embeddings of the newest catalog
    /// are not done yet.
    let cosine: Double?
}

extension Graph {
    /// The number of task nodes of the graph, live and tombstoned. It is the largest number of matches that a search
    /// of the board can give.
    fileprivate var taskCount: Int {
        allSlots.count { slot in node(at: slot, as: TaskNode.self) != nil }
    }
}
