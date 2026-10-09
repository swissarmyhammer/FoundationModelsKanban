import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// The number of minutes of the time limit of each test of ``ChangeFilterTests``. The constant is at file scope,
/// because the `@Suite` attribute of a type cannot read a member of the same type.
private let changeFilterSuiteMinutes = 1

/// Tests the "hidden unless named" rule of a tombstone in the change feed: `history` and `Subscription.changes`
/// (plan.md §3.3 rule 3, §6.7).
///
/// Each case runs its steps on an engine with a subscription, reads the events of the subscription, and then reads
/// `history` with the same filter. The two lists must be equal, and each must give the expected updates.
@Suite("Change feed: tombstones with no filter and with #DELETED", .timeLimit(.minutes(changeFilterSuiteMinutes)))
struct ChangeFilterTests {
    /// One step of a case.
    enum Step: Sendable {
        /// Runs one mutation field. The closure gives the field from the ULID of the fixture task.
        case mutation(@Sendable (ULID) -> String)

        /// Appends a patch line of a different process that sets ``KanbanGraphTests/laterTitle`` on the fixture task,
        /// and waits until the engine applies the line. On a deleted task, the line is a later update of the
        /// tombstone.
        case laterTitleLine
    }

    /// One case: the filter, the steps, and the expected updates.
    struct FeedCase: Sendable, CustomTestStringConvertible {
        /// The name of the case in the test output.
        let testDescription: String

        /// The filter of the subscription and of `history`, or `nil` for no filter.
        let filter: String?

        /// The steps, in order.
        let steps: [Step]

        /// Gives the text of each update of each expected change, oldest change first, from the ULID of the
        /// fixture task. ``ChangeFilterTests/updateText(_:_:_:)`` gives the text of one update.
        let expected: @Sendable (ULID) -> [[String]]
    }

    /// One update of a response, with ``selection``.
    struct UpdateRow: Decodable, Equatable {
        /// The node type, for example `TASK`.
        let type: String

        /// The kind of the update, for example `DELETED`.
        let kind: String

        /// The full URI of the node.
        let id: String
    }

    /// One change of a response, with ``selection``.
    struct ChangeRow: Decodable, Equatable {
        /// The transaction ULID text.
        let txn: String

        /// The updates of the change.
        let updates: [UpdateRow]
    }

    /// The response of one event of a subscription.
    struct EventResponse: Decodable {
        /// The `data` object of the event.
        struct Payload: Decodable {
            /// The change of the event.
            let changes: ChangeRow
        }

        /// The `data` object.
        let data: Payload
    }

    /// The response of a `history` query.
    struct HistoryResponse: Decodable {
        /// The `board` object.
        struct BoardPayload: Decodable {
            /// The changes, newest first.
            let history: [ChangeRow]
        }

        /// The `data` object.
        struct Payload: Decodable {
            /// The board.
            let board: BoardPayload
        }

        /// The `data` object.
        let data: Payload
    }

    /// The selection of each change: the transaction, and the type, the kind, and the id of each update.
    static let selection = "{ txn updates { type kind id } }"

    /// The filter that names the tombstones.
    static let deletedFilter = "#DELETED"

    /// The steps that delete the fixture task, write a later title to the tombstone, and add the column `qa`.
    static let tombstoneSteps: [Step] = [
        .mutation { task in TaskOperationTests.taskField(MutationName.deleteTask, of: task) },
        .laterTitleLine,
        .mutation { _ in ColumnActorTests.addQA },
    ]

    /// The cases of ``changesEqualHistory(feedCase:)``.
    static let cases = [
        FeedCase(
            testDescription: "No filter keeps the delete of a task, and drops a later update of the tombstone",
            filter: nil,
            steps: tombstoneSteps,
            expected: { task in
                [
                    [
                        updateText(.task, .deleted, .task(task)),
                        updateText(.actor, .created, ReplayTests.actor),
                        updateText(.board, .updated, .board),
                    ],
                    [updateText(.column, .created, ColumnActorTests.qaColumn)],
                ]
            }
        ),
        FeedCase(
            testDescription: "#DELETED keeps the delete of a task and each later update of the tombstone",
            filter: deletedFilter,
            steps: tombstoneSteps,
            expected: { task in
                [[updateText(.task, .deleted, .task(task))], [updateText(.task, .updated, .task(task))]]
            }
        ),
        FeedCase(
            testDescription: "No filter keeps the delete of a column and the delete of a tag",
            filter: nil,
            steps: [
                .mutation { _ in ColumnActorTests.addQA },
                .mutation { _ in TagMutationTests.addTag(named: TagMutationTests.bug) },
                .mutation { _ in CommentTests.nodeField(MutationName.deleteColumn, naming: ColumnActorTests.qaSlug) },
                .mutation { _ in CommentTests.nodeField(MutationName.deleteTag, naming: TagMutationTests.bug) },
            ],
            expected: { task in
                let bug = LocalRef.tag(slug: TagMutationTests.bug)
                // The fixture column `todo` is the last column. A column after it makes the fixture task open, and
                // the delete of that column makes the task done again. Each change updates the task and the board.
                let doneStateChange = [updateText(.board, .updated, .board), updateText(.task, .updated, .task(task))]
                return [
                    [
                        updateText(.column, .created, ColumnActorTests.qaColumn),
                        updateText(.actor, .created, ReplayTests.actor),
                    ] + doneStateChange,
                    [updateText(.tag, .created, bug)],
                    [updateText(.column, .deleted, ColumnActorTests.qaColumn)] + doneStateChange,
                    [updateText(.tag, .deleted, bug)],
                ]
            }
        ),
    ]

    // MARK: - Helpers

    /// Gives the text of one update, for example `TASK DELETED kanban://…`.
    ///
    /// - Parameters:
    ///   - type: The node type.
    ///   - kind: The kind of the update.
    ///   - ref: The local ref of the node in the fixture board.
    /// - Returns: The text.
    static func updateText(_ type: NodeType, _ kind: UpdateKind, _ ref: LocalRef) -> String {
        "\(ChangeBuilderTests.signature(type, kind)) \(ColumnActorTests.id(of: ref))"
    }

    /// Gives the text of each update of a change of a response, in the format of ``updateText(_:_:_:)``.
    ///
    /// - Parameter change: The change.
    /// - Returns: The text of each update, in the order of the change.
    static func updateTexts(of change: ChangeRow) -> [String] {
        change.updates.map { update in "\(update.type) \(update.kind) \(update.id)" }
    }

    /// Gives the arguments of a field, with their parentheses.
    ///
    /// - Parameter arguments: The arguments, each as `name: value`.
    /// - Returns: The text, or `""` when there are no arguments.
    static func argumentList(_ arguments: [String]) -> String {
        arguments.isEmpty ? "" : "(\(arguments.joined(separator: ", ")))"
    }

    /// Gives the `filter` argument of a filter.
    ///
    /// - Parameter filter: The filter, or `nil` for no filter.
    /// - Returns: The argument, or no argument for no filter.
    static func filterArguments(_ filter: String?) -> [String] {
        filter.map { text in [#"filter: "\#(text)""#] } ?? []
    }

    /// Runs one step of a case.
    ///
    /// - Parameters:
    ///   - step: The step.
    ///   - task: The ULID of the fixture task.
    ///   - graph: The engine.
    ///   - directory: The repo directory of the engine.
    ///   - recorder: The batch recorder of the engine.
    ///   - ids: The ULID source of the patch lines of the different process.
    static func run(
        _ step: Step,
        on task: ULID,
        in graph: KanbanGraph,
        atRepo directory: URL,
        recordedBy recorder: BatchRecorder,
        mintingFrom ids: inout FixedULIDSource
    ) async throws {
        switch step {
        case .mutation(let field):
            let response = try await CommentTests.run(field(task), on: graph)
            #expect(try KanbanGraphTests.object(of: response)["errors"] == nil, "\(response)")
        case .laterTitleLine:
            let log = EventLog(repositoryAt: directory)
            try BoardWatcherTests.writeLaterTitle(to: task, mintingFrom: &ids, in: log)
            let file = log.fileURL(for: .task(task))
            #expect(try await BoardWatcherTests.hasBatch(in: recorder.batches) { batch in
                BoardWatcherTests.batch(batch, holds: file)
            })
        }
    }

    /// Reads the newest changes of `history` with a filter.
    ///
    /// - Parameters:
    ///   - filter: The filter, or `nil` for no filter.
    ///   - count: The number of changes to read.
    ///   - graph: The engine.
    /// - Returns: The changes, oldest first.
    static func history(filteredBy filter: String?, count: Int, on graph: KanbanGraph) async throws -> [ChangeRow] {
        let arguments = argumentList(filterArguments(filter) + ["first: \(count)"])
        let response = try await KanbanGraphTests.execute("{ board { history\(arguments) \(selection) } }", on: graph)
        return try JSONDecoder().decode(HistoryResponse.self, from: Data(response.utf8)).data.board.history.reversed()
    }

    // MARK: - Tests

    @Test("Subscription.changes and history give the same changes, with the expected updates", arguments: cases)
    func changesEqualHistory(feedCase: FeedCase) async throws {
        let directory = try TemporaryDirectory()
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let recorder = BatchRecorder()
        let graph = try KanbanGraphTests.makeGraph(at: directory.url, observingBatchesWith: recorder)
        let document = SubscriptionTests.subscription(
            Self.argumentList(Self.filterArguments(feedCase.filter)),
            selecting: Self.selection
        )
        let stream = try await SubscriptionTests.subscribe(document, on: graph)
        var ids = GitGraphFixture.secondEngineIDs
        for step in feedCase.steps {
            try await Self.run(step, on: task, in: graph, atRepo: directory.url, recordedBy: recorder, mintingFrom: &ids)
        }
        let expected = feedCase.expected(task)
        let events = try await SubscriptionTests.events(expected.count, of: stream)
        let changes = try events.map { event in
            try JSONDecoder().decode(EventResponse.self, from: Data(event.utf8)).data.changes
        }
        #expect(changes.map(Self.updateTexts(of:)) == expected)
        #expect(try await Self.history(filteredBy: feedCase.filter, count: expected.count, on: graph) == changes)
        await graph.close()
    }
}
