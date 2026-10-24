import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the filter agent with the real model (divergence.md §17, "Tests"): Qwen 3.8 writes a filter statement for the
/// English text of each example of the system prompt.
///
/// The test reads the examples from the prompt resource with `FilterAgentPrompt.load().examples`, so a new example is
/// tested with no code change. `@testable import` reaches the internal prompt type: `swift test` builds the debug
/// configuration, which turns on testability. The engine gets the model through
/// `KanbanHost.configure(locator:embedder:filterModel:)` (``IntegrationHost``).
///
/// For each example, the test adds the fixture board (``fixtureTasks``) to a new git repo. The board has each name of
/// the examples. Then the test sends the English text to `translateFilter`. The model can write a statement that is
/// equal to the statement of the example in a different form, so the test does not compare the text. The statement of
/// the model must:
///
/// - come back with no message;
/// - come back from a second `translateFilter` call as a filter of the board: `attempts: 0`, the same text, and no
///   message. Thus it parses and passes the name check;
/// - select the same tasks as the statement of the example on the fixture board.
///
/// The attachment of each example records the translation of the model, with its attempts.
///
/// The fixture board has no task with a conflict block: only a merge of two logs makes one, so `#CONFLICT` selects no
/// task there. The suite is serialized, because the model answers one call at a time.
@Suite("Filter agent: Qwen 3.8 writes a filter for each English example of the prompt", .serialized)
struct FilterAgentExampleTests {
    /// One task of the fixture board.
    struct FixtureTask {
        /// The title of the task. Each title is different, so its slug names one task.
        let title: String

        /// The slug of the column of the task.
        let column: String

        /// The tag slugs of the task. A tag that the board does not have is made.
        var tags: [String] = []

        /// The actor slugs of the assignees of the task.
        var assignees: [String] = []

        /// The title slugs of the tasks that this task depends on. Each one is a task earlier in ``fixtureTasks``.
        var dependsOn: [String] = []

        /// `true` when the task is deleted after the add.
        var isDeleted = false
    }

    /// The response of a `translateFilter` query.
    struct TranslationResponse: Decodable {
        /// The `data` object of the response.
        struct Payload: Decodable {
            /// The value of the `translateFilter` field.
            let translateFilter: FilterTranslation
        }

        /// The `data` object of the response.
        let data: Payload
    }

    /// The results of one example on the fixture board.
    struct ExampleRun {
        /// The translation of the English text.
        let translation: FilterTranslation

        /// The translation of the statement of the model, or `nil` when the model wrote no statement.
        let statementCheck: FilterTranslation?

        /// The response of the task list of the statement of the model, or `nil` when the model wrote no statement.
        let selection: String?

        /// The response of the task list of the statement of the example.
        let expectedSelection: String
    }

    /// The name of the repo directory.
    static let repoName = "filter-agent-repo"

    /// The name of the session actor of the engine.
    static let actorName = "Integration Filter Agent"

    /// The name of the test attachment that holds the translation of the English text, as JSON text.
    static let translationAttachmentName = "translate-filter.json"

    /// The most tasks of one task list. It is larger than the number of ``fixtureTasks``, so one page holds each
    /// selected task.
    static let pageSize = 50

    /// The slug of the first column, To Do.
    static let todo = "todo"

    /// The slug of the column Doing. The fixture gives it the name of the sample board, ``doingName``.
    static let doing = "doing"

    /// The name of the column ``doing`` on the sample board of the prompt examples.
    static let doingName = "In Progress"

    /// The slug of the column Review.
    static let review = "review"

    /// The slug of the terminal column, Done.
    static let done = "done"

    /// The slug of the actor Alice Smith.
    static let alice = "alice"

    /// The name of the actor ``alice``.
    static let aliceName = "Alice Smith"

    /// The slug of the actor Will. The actor has no name.
    static let will = "will"

    /// The tag of the bugs.
    static let bug = "bug"

    /// The tag of the features.
    static let feature = "feature"

    /// The tag of the documentation tasks.
    static let docs = "docs"

    /// The tag of the defects.
    static let defect = "defect"

    /// The calls that make the actors and the column names of the sample board, before the tasks. Each item is the
    /// name of the mutation field and the document. The first call makes the board with its default columns.
    static let boardDocuments = [
        (
            field: "addActor",
            document: #"mutation { addActor(input: { id: "\#(alice)", name: "\#(aliceName)" }) { id } }"#
        ),
        (
            field: "addActor",
            document: #"mutation { addActor(input: { id: "\#(will)" }) { id } }"#
        ),
        (
            field: "updateColumn",
            document: #"mutation { updateColumn(input: { id: "\#(doing)", name: "\#(doingName)" }) { id } }"#
        ),
    ]

    /// The tasks of the fixture board, in the order of the adds. Each column holds its tasks in this order.
    ///
    /// The board has open, done, blocked, and deleted tasks with each tag and each actor, so that a statement that
    /// differs from the statement of an example selects different tasks. Most open tasks are in `todo`, so that the
    /// last third of the open tasks in board order, `#LOW`, holds a task of `todo`.
    static let fixtureTasks = [
        FixtureTask(title: "Review the API docs", column: review, tags: [docs]),
        FixtureTask(title: "Review the search feature", column: review, tags: [feature], assignees: [alice]),
        FixtureTask(title: "Add the export feature", column: doing, tags: [feature], assignees: [will]),
        FixtureTask(title: "Fix the crash bug", column: done, tags: [bug], assignees: [alice]),
        FixtureTask(title: "Ship the dark mode feature", column: done, tags: [feature], assignees: [will]),
        FixtureTask(title: "Publish the install docs", column: done, tags: [docs]),
        FixtureTask(title: "Fix the login bug", column: todo, tags: [bug], assignees: [alice]),
        FixtureTask(
            title: "Fix the logout bug",
            column: todo,
            tags: [bug],
            assignees: [will],
            dependsOn: ["add-the-export-feature"]
        ),
        FixtureTask(title: "Fix the parser defect", column: todo, tags: [defect]),
        FixtureTask(
            title: "Plan the import feature",
            column: todo,
            tags: [feature],
            assignees: [alice],
            dependsOn: ["review-the-search-feature"]
        ),
        FixtureTask(title: "Write the setup docs", column: todo, tags: [docs], assignees: [will]),
        FixtureTask(title: "Fix the theme bug", column: todo, tags: [bug]),
        FixtureTask(title: "Tidy the test names", column: todo, assignees: [will]),
        FixtureTask(title: "Update the change log", column: todo, tags: [docs]),
        FixtureTask(title: "Sort the import list", column: todo, tags: [feature]),
        FixtureTask(title: "Remove the old defect", column: todo, tags: [defect], isDeleted: true),
        FixtureTask(title: "Remove the old bug", column: todo, tags: [bug], assignees: [alice], isDeleted: true),
    ]

    // MARK: - Helpers

    /// Gives a value as JSON text, with the keys of each object in sorted order. The JSON text of a string or of a list
    /// of strings is also a GraphQL literal of the value.
    ///
    /// - Parameter value: The value.
    /// - Returns: The JSON text.
    /// - Throws: The error of `JSONEncoder`.
    static func jsonText(of value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// Adds the actors, the column names, and the tasks of the fixture board.
    ///
    /// - Parameter graph: The session of the empty board.
    /// - Throws: An error when a call fails.
    static func addFixtureBoard(on graph: KanbanGraph) async throws {
        for (field, document) in boardDocuments {
            _ = try await CrossRepoDependencyTests.object(named: field, runningDocument: document, on: graph)
        }
        for task in fixtureTasks {
            try await add(task, on: graph)
        }
    }

    /// Adds one task of the fixture board, and deletes it when the fixture says so.
    ///
    /// - Parameters:
    ///   - task: The fixture task.
    ///   - graph: The session of the board.
    /// - Throws: An error when a call fails.
    static func add(_ task: FixtureTask, on graph: KanbanGraph) async throws {
        let input = [
            "title: \(try jsonText(of: task.title))",
            "column: \(try jsonText(of: task.column))",
            "tags: \(try jsonText(of: task.tags))",
            "assignees: \(try jsonText(of: task.assignees))",
            "dependsOn: \(try jsonText(of: task.dependsOn))",
        ].joined(separator: ", ")
        let addition = "mutation { addTask(input: { \(input) }) { id } }"
        let added = try await CrossRepoDependencyTests.object(named: "addTask", runningDocument: addition, on: graph)
        if task.isDeleted {
            let id = try #require(added["id"] as? String)
            let deletion = "mutation { deleteTask(input: { id: \(try jsonText(of: id)) }) { id } }"
            _ = try await CrossRepoDependencyTests.object(named: "deleteTask", runningDocument: deletion, on: graph)
        }
    }

    /// Sends a text to `translateFilter` on the current board.
    ///
    /// - Parameters:
    ///   - text: The text: English, or a filter statement.
    ///   - graph: The session of the board.
    /// - Returns: The translation.
    /// - Throws: An error when the call fails, or when the response has no translation.
    static func translation(of text: String, on graph: KanbanGraph) async throws -> FilterTranslation {
        let query = "{ translateFilter(text: \(try jsonText(of: text))) { attempts filter message } }"
        let response = try await graph.execute(query: query, variables: [:], operationName: nil)
        return try JSONDecoder().decode(TranslationResponse.self, from: Data(response.utf8)).data.translateFilter
    }

    /// Reads the titles of the tasks that a filter selects on the current board.
    ///
    /// - Parameters:
    ///   - filter: The filter statement.
    ///   - graph: The session of the board.
    /// - Returns: The full response of the task list.
    /// - Throws: An error when the call fails.
    static func selection(of filter: String, on graph: KanbanGraph) async throws -> String {
        let arguments = "filter: \(try jsonText(of: filter)), first: \(pageSize)"
        let query = "{ board { tasks(\(arguments)) { nodes { title } } } }"
        return try await graph.execute(query: query, variables: [:], operationName: nil)
    }

    /// Runs one example on a new fixture board: the translation of the English text, the check of the statement of
    /// the model, and the task lists of the two statements.
    ///
    /// - Parameter example: The example of the prompt.
    /// - Returns: The results of the example.
    /// - Throws: An error when a call fails.
    static func run(_ example: FilterAgentPrompt.Example) async throws -> ExampleRun {
        try await TemporaryGitRepo.withRepo(named: repoName) { root in
            let graph = try await IntegrationHost.session(workingDirectory: root, actor: Self.actorName)
            try await Self.addFixtureBoard(on: graph)
            let englishTranslation = try await Self.translation(of: example.english, on: graph)
            let exampleSelection = try await Self.selection(of: example.filter, on: graph)
            let statement = englishTranslation.filter
            let statementCheck: FilterTranslation? =
                if let statement { try await Self.translation(of: statement, on: graph) } else { nil }
            let statementSelection: String? =
                if let statement { try await Self.selection(of: statement, on: graph) } else { nil }
            await graph.close()
            return ExampleRun(
                translation: englishTranslation,
                statementCheck: statementCheck,
                selection: statementSelection,
                expectedSelection: exampleSelection
            )
        }
    }

    // MARK: - Tests

    @Test(
        "The statement of the model is a filter of the board that selects the tasks of the example",
        arguments: try FilterAgentPrompt.load().examples
    )
    func modelStatementSelectsTasksOfExample(_ example: FilterAgentPrompt.Example) async throws {
        try IntegrationHost.requireMetalDevice()
        let run = try await Self.run(example)

        // The record of the run: the statement of the model and its attempts.
        let record = try Self.jsonText(of: run.translation)
        Attachment.record(record, named: Self.translationAttachmentName)
        let comment: Comment = "\(example.english): \(record); the example statement is \(example.filter)"
        #expect(run.translation.message == nil, comment)
        let statement = try #require(run.translation.filter, comment)
        #expect(run.statementCheck == .unchanged(statement), comment)
        #expect(run.selection == run.expectedSelection, comment)
    }
}
