import Foundation
import FoundationModelsExtras
import Testing

@testable import FoundationModelsKanban

/// A test board for the GraphQL query tests: a board node, the default columns, one actor, one tag, three tasks, and
/// one comment (plan.md §4.1).
///
/// - The first task is in `doing`. It has the actor as assignee, the tag, a checklist in its body, and the comment.
/// - The second task is in `todo`. It depends on the first task.
/// - The third task is in `done`.
///
/// The columns, the ULIDs, and the time values come from ``ReadinessFixture``. The board key is the key of
/// ``DependencyMarkersTests``.
struct QueryFixture {
    /// The name of the board.
    static let boardName = "Kanban"

    /// The name of the actor.
    static let actorName = "Claude Code"

    /// The slug of the tag.
    static let tagSlug = "bug"

    /// The title of the first task.
    static let firstTitle = "Port the parser"

    /// The title of the second task.
    static let secondTitle = "Write the tests"

    /// The title of the third task.
    static let thirdTitle = "Ship it"

    /// The body of the first task: a checklist with one checked item of two.
    static let firstBody = "- [x] Read the grammar\n- [ ] Write the parser\n"

    /// The body of the comment.
    static let commentBody = "Looks good."

    /// The filter of a task list that lists each live task, open or done. A list leaves out the done tasks unless its
    /// filter names `#DONE` (plan.md §6.3).
    static let liveTasksFilter = "#DONE || !#DONE"

    /// The arguments of a task list that lists each live task, open or done: the filter ``liveTasksFilter``.
    static let liveTasksArguments = #"filter: "\#(liveTasksFilter)""#

    /// The graph of the board.
    var graph: Graph

    /// Makes the board.
    ///
    /// - Throws: An error when a ULID text of ``ReadinessFixture`` is not valid.
    init() throws {
        graph = ReadinessFixture().graph
        let fields = ReadinessFixture.fields()
        graph.update(with: .board(BoardNode(fields: fields, name: Self.boardName)))
        graph.update(with: .actor(ActorNode(slug: ReadinessFixture.author, fields: fields, name: Self.actorName)))
        graph.update(with: .tag(TagNode(slug: Self.tagSlug, fields: fields, name: Self.tagSlug)))
        let firstTask = TaskNode(
            id: try DependencyMarkersTests.ulid(of: ReadinessFixture.first),
            fields: ReadinessFixture.fields(body: Self.firstBody),
            title: Self.firstTitle,
            column: Self.edge(to: .column(slug: ReadinessFixture.doing)),
            assignees: [Self.edge(to: .actor(slug: ReadinessFixture.author))],
            tags: [Self.edge(to: .tag(slug: Self.tagSlug))]
        )
        let secondTask = TaskNode(
            id: try DependencyMarkersTests.ulid(of: ReadinessFixture.second),
            fields: fields,
            title: Self.secondTitle,
            column: Self.edge(to: .column(slug: ReadinessFixture.todo)),
            dependsOn: [try ReadinessFixture.edge(toTask: ReadinessFixture.first)]
        )
        let thirdTask = TaskNode(
            id: try DependencyMarkersTests.ulid(of: ReadinessFixture.third),
            fields: fields,
            title: Self.thirdTitle,
            column: Self.edge(to: .column(slug: ReadinessFixture.done))
        )
        let comment = CommentNode(
            id: try DependencyMarkersTests.ulid(of: ReadinessFixture.firstComment),
            fields: ReadinessFixture.fields(body: Self.commentBody),
            task: try ReadinessFixture.edge(toTask: ReadinessFixture.first),
            author: Self.edge(to: .actor(slug: ReadinessFixture.author))
        )
        for node in [Node.task(firstTask), .task(secondTask), .task(thirdTask), .comment(comment)] {
            graph.update(with: node)
        }
    }

    /// Makes a context that reads a fixture graph in the board of ``DependencyMarkersTests``, with the fixed clock
    /// ``DependencyMarkersTests/time``.
    ///
    /// - Parameters:
    ///   - graph: The fixture graph.
    ///   - search: The task search of the call. The default search has no task.
    /// - Returns: The context.
    static func context(
        reading graph: Graph,
        searchingWith search: TaskSearch = TaskSearch(embeddingWith: nil)
    ) -> KanbanContext {
        CommitTests.callContext(
            of: BoardStore.fixture(of: graph, inBoard: DependencyMarkersTests.boardKey),
            timedBy: { DependencyMarkersTests.time },
            searchingWith: search
        )
    }

    /// Runs one GraphQL document against the board through the public schema.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - search: The task search of the call. The default search has no task.
    /// - Returns: The response as JSON text.
    /// - Throws: An error that is not a GraphQL error.
    func respond(
        to document: String,
        searchingWith search: TaskSearch = TaskSearch(embeddingWith: nil)
    ) async throws -> String {
        try await PublicSchema().respond(to: document, context: Self.context(reading: graph, searchingWith: search))
    }

    /// Makes a task search that indexes the live tasks of the board.
    ///
    /// - Parameter embedder: The embedder of the search, or `nil` for no embedder.
    /// - Returns: The search.
    func makeSearch(embeddingWith embedder: (any PooledEmbedding)? = nil) async -> TaskSearch {
        let search = TaskSearch(embeddingWith: embedder)
        await search.update(from: BoardView(of: graph, inBoard: DependencyMarkersTests.boardKey))
        return search
    }

    /// Gives the unresolved edge to a node of the board, as replay gives it.
    ///
    /// - Parameter ref: The local ref of the target.
    /// - Returns: The edge.
    static func edge(to ref: LocalRef) -> EdgeTarget {
        .unresolved(.local(ref))
    }

    /// Gives the full URI of a node of the board, as the GraphQL `ID` shows it.
    ///
    /// - Parameter ref: The text of the local ref of the node, for example `column/doing`.
    /// - Returns: The URI text, for example `kanban://<board-key>/column/doing`.
    static func id(of ref: String) -> String {
        "\(NodeURI.scheme)\(DependencyMarkersTests.boardKey)/\(ref)"
    }

    /// Gives the full URI of a task of the board.
    ///
    /// - Parameter text: The ULID text of the task.
    /// - Returns: The URI text.
    static func id(ofTask text: String) -> String {
        id(of: "task/\(text)")
    }

    /// Gives the short id of a ULID with the leading sigil, as a forgiving ref.
    ///
    /// - Parameter text: The ULID text.
    /// - Returns: The ref, for example `^ajv8v4t`.
    static func sigilRef(of text: String) -> String {
        "\(ShortID.sigil)\(ShortID(ofULIDString: text).value)"
    }
}

extension BoardStore {
    /// Makes a store whose working copy holds a fixture graph with no events. The test actor and a fixed ULID source
    /// stamp the events of a mutation.
    ///
    /// A mutation folds a node again from its events, so a mutation of a fixture node starts from the empty state of
    /// the node.
    ///
    /// - Parameters:
    ///   - graph: The fixture graph.
    ///   - key: The current key of the board.
    /// - Returns: The store.
    static func fixture(of graph: Graph, inBoard key: String) -> BoardStore {
        let stamp = EventStamp(
            actingAs: ReplayTests.actor,
            mintingFrom: FixedULIDSource(at: ReplayTests.date(atStep: .zero))
        )
        return BoardStore(
            working: WorkingCopy(graph: graph, events: [], stamp: stamp),
            boardKey: key,
            actingAs: KanbanGraphTests.sessionActor
        )
    }
}
