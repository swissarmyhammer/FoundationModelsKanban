import Foundation
import FoundationModelsExtras
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the ranked search over the tasks of a board: `Board.searchTasks` with `MetadataSearcher` (plan.md §6.4, §12
/// item 6).
///
/// Most tests search the board of ``QueryFixture``: "Port the parser" in `doing` with the tag `bug`, "Write the tests"
/// in `todo`, and "Ship it" in the terminal column `done`. The body of the first task holds the word "Write".
@Suite("Search: searchTasks with MetadataSearcher")
struct TaskSearchTests {
    /// A word of the title of the second task only.
    static let titleWord = "tests"

    /// A word of the title of the second task and of the body of the first task.
    static let sharedWord = "write"

    /// A word of the title of the done third task only.
    static let doneWord = "ship"

    /// A word of ``AddUpdateTaskTests/title``, the title of the task that the `addTask` test adds. No task of the
    /// engine fixture has the word.
    static let addedWord = "guide"

    /// The ref of the column that the engine test adds after the `todo` column, so that `todo` is not the terminal
    /// column and its tasks are not done.
    static let doneColumn = LocalRef.column(slug: ReadinessFixture.done)

    /// The sort key of ``doneColumn``: after the `todo` column of the engine fixture, whose order is 0.
    static let doneColumnOrder = 1

    /// The `first` argument of the paging test: fewer than the hits of ``sharedWord``.
    static let limitedHitCount = 1

    /// The selection of each hit of a `searchTasks` query.
    static let hitSelection = "{ task { id } score signals { bm25 trigram cosine } }"

    // MARK: - Response

    /// The `data` part of a response to a `searchTasks` query: `{ board { searchTasks { … } } }`.
    struct SearchResponse: Decodable {
        /// The `data` object.
        struct DataObject: Decodable {
            /// The `board` object.
            let board: BoardObject
        }

        /// The `board` object.
        struct BoardObject: Decodable {
            /// The hits, or `nil` when the field has an error.
            let searchTasks: [Hit]?
        }

        /// The `data` object.
        let data: DataObject
    }

    /// One hit of a response.
    struct Hit: Decodable {
        /// The task of the hit.
        let task: TaskID

        /// The fused score of the hit.
        let score: Double

        /// The scores of each signal.
        let signals: Signals
    }

    /// A task in a response: its `id`.
    struct TaskID: Decodable {
        /// The full URI of the task.
        let id: String
    }

    /// The scores of each signal of a hit.
    struct Signals: Decodable {
        /// The BM25 score.
        let bm25: Double

        /// The trigram score.
        let trigram: Double

        /// The cosine score, or `nil` when the search has no embedder.
        let cosine: Double?
    }

    // MARK: - Fake embedders

    /// An embedder that gives the same vector length for each text: the length of the text and a constant.
    struct FakeEmbedder: PooledEmbedding {
        /// The second value of each vector.
        static let constant: Float = 1

        /// Embeds each text.
        ///
        /// - Parameter texts: The texts.
        /// - Returns: One vector for each text.
        func embed(texts: [String]) async throws -> [[Float]] {
            texts.map { text in [Float(text.count), Self.constant] }
        }
    }

    /// An embedder that always fails.
    struct FailingEmbedder: PooledEmbedding {
        /// The error of each embed.
        struct EmbedFailure: Error {}

        /// Throws the error of each embed.
        ///
        /// - Parameter texts: The texts.
        /// - Returns: No value.
        /// - Throws: ``EmbedFailure``.
        func embed(texts: [String]) async throws -> [[Float]] {
            throw EmbedFailure()
        }
    }

    // MARK: - Fixture

    /// Gives the `searchTasks` document with some arguments.
    ///
    /// - Parameter arguments: The text of the arguments, for example `query: "tests"`.
    /// - Returns: The document.
    static func document(searchingWith arguments: String) -> String {
        "{ board { name searchTasks(\(arguments)) \(hitSelection) } }"
    }

    /// Reads the hits of a response.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The hits, or `nil` when the field is `null`.
    /// - Throws: An error when the response is not the expected JSON.
    static func hits(of response: String) throws -> [Hit]? {
        try JSONDecoder().decode(SearchResponse.self, from: Data(response.utf8)).data.board.searchTasks
    }

    /// Searches the board of a fixture.
    ///
    /// - Parameters:
    ///   - arguments: The text of the arguments of `searchTasks`.
    ///   - fixture: The board that the call reads.
    ///   - search: The task search of the call.
    /// - Returns: The hits.
    /// - Throws: An error when the response is not the expected JSON, or when the field is `null`.
    static func hits(
        searchingWith arguments: String,
        in fixture: QueryFixture,
        using search: TaskSearch
    ) async throws -> [Hit] {
        let response = try await fixture.respond(to: document(searchingWith: arguments), searchingWith: search)
        return try #require(try hits(of: response))
    }

    /// Searches the board of ``QueryFixture`` with a search that indexes the same board.
    ///
    /// - Parameters:
    ///   - arguments: The text of the arguments of `searchTasks`.
    ///   - embedder: The embedder of the search, or `nil` for no embedder.
    /// - Returns: The hits.
    /// - Throws: An error when the response is not the expected JSON, or when the field is `null`.
    static func hits(
        searchingWith arguments: String,
        embeddingWith embedder: (any PooledEmbedding)? = nil
    ) async throws -> [Hit] {
        let fixture = try QueryFixture()
        let search = await fixture.makeSearch(embeddingWith: embedder)
        return try await hits(searchingWith: arguments, in: fixture, using: search)
    }

    /// Searches the board of an engine.
    ///
    /// - Parameters:
    ///   - arguments: The text of the arguments of `searchTasks`.
    ///   - graph: The engine.
    /// - Returns: The hits.
    /// - Throws: An error when the response is not the expected JSON, or when the field is `null`.
    static func hits(searchingWith arguments: String, on graph: KanbanGraph) async throws -> [Hit] {
        let response = try await KanbanGraphTests.execute(document(searchingWith: arguments), on: graph)
        return try #require(try hits(of: response))
    }

    /// Gives the URI of a task of ``QueryFixture``.
    ///
    /// - Parameter text: The ULID text of the task.
    /// - Returns: The URI text.
    static func id(ofTask text: String) -> String {
        QueryFixture.id(ofTask: text)
    }

    /// Gives the `query` argument of a word.
    ///
    /// - Parameter word: The word.
    /// - Returns: The argument text, for example `query: "tests"`.
    static func query(_ word: String) -> String {
        #"query: "\#(word)""#
    }

    // MARK: - Ranking

    @Test("With no embedder, a search for a word in the title ranks that task first, and cosine is null")
    func titleWordRanksTaskFirst() async throws {
        let hits = try await Self.hits(searchingWith: Self.query(Self.titleWord))
        #expect(hits.first?.task.id == Self.id(ofTask: ReadinessFixture.second))
        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { hit in hit.signals.cosine == nil })
    }

    @Test("With a fake embedder, cosine is set on each hit")
    func fakeEmbedderSetsCosine() async throws {
        let hits = try await Self.hits(searchingWith: Self.query(Self.titleWord), embeddingWith: FakeEmbedder())
        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { hit in hit.signals.cosine != nil })
    }

    @Test("With a failing embedder, the search still returns results and gives no error")
    func failingEmbedderStillReturnsResults() async throws {
        let hits = try await Self.hits(searchingWith: Self.query(Self.titleWord), embeddingWith: FailingEmbedder())
        #expect(hits.first?.task.id == Self.id(ofTask: ReadinessFixture.second))
    }

    // MARK: - Selection

    @Test("The filter removes the tasks that do not match it")
    func filterApplies() async throws {
        let arguments = ##"\##(Self.query(Self.sharedWord)), filter: "#\##(QueryFixture.tagSlug)""##
        let hits = try await Self.hits(searchingWith: arguments)
        #expect(hits.map(\.task.id) == [Self.id(ofTask: ReadinessFixture.first)])
    }

    @Test("A done task is not a hit when the filter names no column")
    func doneTaskIsExcluded() async throws {
        let hits = try await Self.hits(searchingWith: Self.query(Self.doneWord))
        #expect(!hits.map(\.task.id).contains(Self.id(ofTask: ReadinessFixture.third)))
    }

    @Test("A filter that names a column keeps the done tasks, the same as Board.tasks")
    func columnFilterKeepsDoneTask() async throws {
        let arguments = #"\#(Self.query(Self.doneWord)), filter: "%\#(ReadinessFixture.done)""#
        let hits = try await Self.hits(searchingWith: arguments)
        #expect(hits.map(\.task.id) == [Self.id(ofTask: ReadinessFixture.third)])
    }

    @Test("A task that is deleted after the index update is not a hit")
    func deletedTaskIsExcluded() async throws {
        var fixture = try QueryFixture()
        let search = await fixture.makeSearch()
        let deleted = Self.id(ofTask: ReadinessFixture.second)
        let before = try await Self.hits(searchingWith: Self.query(Self.titleWord), in: fixture, using: search)
        #expect(before.map(\.task.id).contains(deleted))
        let ref = LocalRef.task(try DependencyMarkersTests.ulid(of: ReadinessFixture.second))
        var task = try LiveGraphApplyTests.task(ref, in: fixture.graph)
        task.fields.deleted = DependencyMarkersTests.time
        fixture.graph.update(with: .task(task))
        let after = try await Self.hits(searchingWith: Self.query(Self.titleWord), in: fixture, using: search)
        #expect(!after.map(\.task.id).contains(deleted))
    }

    @Test("A deleted task is a hit only when the filter names #DELETED, and after an undelete only when it does not")
    func deletedTaskIsHitOnlyForDeletedFilter() async throws {
        var fixture = try QueryFixture()
        let ref = LocalRef.task(try DependencyMarkersTests.ulid(of: ReadinessFixture.second))
        try fixture.delete(nodeAt: ref)
        let search = await fixture.makeSearch()
        let task = Self.id(ofTask: ReadinessFixture.second)
        let plain = Self.query(Self.titleWord)
        let deletedFilter = ##"\##(plain), filter: "#DELETED""##
        let live = try await Self.hits(searchingWith: plain, in: fixture, using: search)
        #expect(!live.map(\.task.id).contains(task))
        let tombstones = try await Self.hits(searchingWith: deletedFilter, in: fixture, using: search)
        #expect(tombstones.map(\.task.id) == [task])
        try fixture.undelete(nodeAt: ref)
        let restored = try await Self.hits(searchingWith: plain, in: fixture, using: search)
        #expect(restored.first?.task.id == task)
        let noTombstones = try await Self.hits(searchingWith: deletedFilter, in: fixture, using: search)
        #expect(noTombstones.isEmpty)
    }

    @Test("The first argument keeps only the first hits")
    func firstLimitsHits() async throws {
        let all = try await Self.hits(searchingWith: Self.query(Self.sharedWord))
        let arguments = "\(Self.query(Self.sharedWord)), first: \(Self.limitedHitCount)"
        let limited = try await Self.hits(searchingWith: arguments)
        #expect(all.count > limited.count)
        #expect(limited.map(\.task.id) == Array(all.map(\.task.id).prefix(Self.limitedHitCount)))
    }

    @Test("A filter that does not parse gives null for searchTasks, and the other fields keep their data")
    func invalidFilterGivesNullField() async throws {
        let fixture = try QueryFixture()
        let arguments = #"\#(Self.query(Self.titleWord)), filter: "&&""#
        let response = try await fixture.respond(
            to: Self.document(searchingWith: arguments),
            searchingWith: fixture.makeSearch()
        )
        #expect(response.hasPrefix(#"{"data":{"board":{"name":"\#(QueryFixture.boardName)","searchTasks":null}},"#))
        #expect(response.contains(#""path":["board","searchTasks"]"#))
    }

    // MARK: - Engine and commit

    @Test("After the addTask mutation commits a task, searchTasks on the same engine finds the new task")
    func addTaskUpdatesSearch() async throws {
        let directory = try TemporaryDirectory()
        _ = try Self.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let add = AddUpdateTaskTests.mutation(of: AddUpdateTaskTests.addTask(with: ""))
        let task = try AddUpdateTaskTests.firstTask(in: await KanbanGraphTests.execute(add, on: graph))
        let hits = try await Self.hits(searchingWith: Self.query(Self.addedWord), on: graph)
        #expect(hits.map(\.task.id) == [ColumnActorTests.id(of: .task(task))])
    }

    @Test("The engine indexes the board at the first load, and searchTasks finds a task of the logs")
    func engineSearchesLoadedBoard() async throws {
        let directory = try TemporaryDirectory()
        let task = try Self.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let word = try #require(KanbanGraphTests.taskTitle.split(separator: " ").last.map(String.init))
        let hits = try await Self.hits(searchingWith: Self.query(word), on: graph)
        #expect(hits.first?.task.id == ColumnActorTests.id(of: .task(task)))
    }

    /// Writes the fixture logs of the engine tests, plus a terminal column after the `todo` column, so that the task
    /// of the fixture is not done.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The ULID of the task of the fixture.
    static func writeFixture(inRepoAt root: URL) throws -> ULID {
        var (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: root)
        let column = try PatchInput(
            node: doneColumn,
            set: ["name": .json(.string(ReadinessFixture.done)), "order": .json(.number(Number(doneColumnOrder)))]
        )
        try KanbanGraphTests.append(column, mintingFrom: &ids, to: EventLog(repositoryAt: root))
        return task
    }
}
