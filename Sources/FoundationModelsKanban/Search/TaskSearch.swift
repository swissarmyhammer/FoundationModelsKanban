import FoundationModelsExtras
import FoundationModelsMetadataRegistry

/// The ranked search over the live tasks of one board (plan.md §6.4, §12 item 6).
///
/// The search holds one `MetadataSearcher` in `.retrieval` mode: BM25, trigram, and embedding cosine (only with an
/// embedder), fused with reciprocal rank fusion. `.selection` is not used, because it calls a language model and its
/// result changes from call to call. The searcher keeps its index in memory only.
///
/// ``KanbanGraph`` keeps one search for each board for its life. The commit session calls ``update(from:)`` after
/// the first load and after each change of the live graph, and the searcher embeds again only the tasks that changed.
///
/// When the embedder fails, the searcher falls back to BM25 and trigram, and it records the diagnostic with swift-log.
/// The search gives no error.
struct TaskSearch: Sendable {
    /// The searcher over the catalog of the live tasks.
    private let searcher: MetadataSearcher<TaskSearchItem>

    /// `true` when the search has an embedder. Without one, each hit gives no cosine score.
    private let hasEmbedder: Bool

    /// Makes a search with an empty catalog. The search embeds nothing until the first update.
    ///
    /// - Parameter embedder: The embedder of the tasks and the queries, or `nil` for BM25 and trigram only.
    init(embeddingWith embedder: (any PooledEmbedding)?) {
        searcher = MetadataSearcher(items: [], mode: .retrieval, embedder: embedder)
        hasEmbedder = embedder != nil
    }

    /// Replaces the catalog with the live tasks of a board. A task that did not change keeps its embedding.
    ///
    /// - Parameter view: The read view of the board.
    func update(from view: BoardView) async {
        await searcher.update(items: view.orderedTasks().map(TaskSearchItem.init(of:)))
    }

    /// Ranks the tasks for a query, and keeps the selected tasks only (plan.md §6.4, filter).
    ///
    /// `MetadataSearcher` has no filter. Thus the search asks for one match for each task of the board, and then
    /// removes each match whose task is not in `tasks`: a task that does not pass the filter, a done task, and a task
    /// that the view does not show live.
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
        let matches = try await searcher.search(intent: query, limit: view.graph.taskCount)
        let hits = matches.compactMap { match in
            selected[match.id].map { task in
                TaskHit(task: task, score: match.score, signals: match.signals.map(signals(of:)))
            }
        }
        return Array(hits.prefix(max(first, .zero)))
    }

    /// Gives the scores of the signals of one match.
    ///
    /// - Parameter scores: The raw scores of the searcher.
    /// - Returns: The scores, with no cosine score when the search has no embedder.
    private func signals(of scores: Signals) -> SearchSignals {
        SearchSignals(bm25: scores.bm25, trigram: scores.trigram, cosine: hasEmbedder ? scores.cosine : nil)
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

    /// The embedding cosine score, or `nil` when the search has no embedder.
    let cosine: Double?
}

extension Graph {
    /// The number of task nodes of the graph, live and tombstoned. It is the largest number of matches that a search
    /// of the board can give.
    fileprivate var taskCount: Int {
        allSlots.count { slot in node(at: slot, as: TaskNode.self) != nil }
    }
}
