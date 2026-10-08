import Foundation
import FoundationModelsMultitool
import Testing

@testable import FoundationModelsKanban

/// Tests the `kanban` tool in code mode: a `runCode` script of Multitool calls the tool as `tools.kanban(...)`
/// (plan.md §9, §10 step 18).
///
/// Each test uses the empty repo of ``KanbanGraphTests``. The first mutation of the script makes the board with its
/// default columns.
@Suite("Code mode: the kanban tool in a Multitool runCode script")
struct CodeModeTests {
    /// The title of the task that the script adds.
    private static let taskTitle = KanbanGraphTests.taskTitle

    /// The slug of the default column that the script moves the task to.
    private static let doingSlug = CrossRepoWriteTests.doingSlug

    /// The name of the default column ``doingSlug``.
    private static let doingName = "Doing"

    /// The script of plan.md §9. It adds a task with `variables` as a JS object, and reads `nextTask`. It reads the
    /// `id` of `r.data.board.nextTask` directly in JS, as an object. It moves the task with `variables` as a JSON
    /// string. It returns the task that it read, and the two mutation responses whole. Thus a GraphQL error in a
    /// response shows in the result.
    private static let script = """
        const added = await tools.kanban({
          query: `mutation($title: String!) { addTask(input: { title: $title }) { id } }`,
          variables: { title: "\(taskTitle)" }
        });
        const r = await tools.kanban({ query: `{ board { nextTask { id shortId title } } }` });
        const t = r.data.board.nextTask;
        if (!t) return "no task is ready";
        const moved = await tools.kanban({
          query: `mutation($id: ID!) { moveTask(input: { id: $id, column: "\(doingSlug)" }) { id column { name } } }`,
          variables: JSON.stringify({ id: t.id })
        });
        return { added, next: t, moved };
        """

    // MARK: - Helpers

    /// Runs a script in a `runCode` tool whose one tool is the `kanban` tool over an engine.
    ///
    /// - Parameters:
    ///   - code: The JavaScript snippet.
    ///   - graph: The engine of the `kanban` tool.
    /// - Returns: The rendered result of `runCode`.
    private static func run(_ code: String, on graph: KanbanGraph) async throws -> String {
        let registry = try MultiTool.Builder()
            .addTool(KanbanTool(graph: graph))
            .buildRegistry()
        return try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
    }

    /// Reads one root field of the `data` of a GraphQL response that the script returned.
    ///
    /// - Parameters:
    ///   - field: The name of the root field, for example `addTask`.
    ///   - response: The response value, or `nil` when the result has no such key.
    /// - Returns: The object of the field, or `nil` when the response has no object for it.
    private static func dataField(_ field: String, of response: Any?) -> [String: Any]? {
        ((response as? [String: Any])?["data"] as? [String: Any])?[field] as? [String: Any]
    }

    // MARK: - Tests

    @Test("The script adds a task, reads nextTask as an object, and moves the task to doing")
    func scriptAddsReadsAndMoves() async throws {
        let directory = try TemporaryDirectory()
        let root = try KanbanGraphTests.makeEmptyRepo(in: directory)
        let output = try await Self.run(Self.script, on: KanbanGraphTests.makeGraph(at: root))
        let result = try KanbanGraphTests.object(of: output)
        let added = try #require(Self.dataField("addTask", of: result["added"])?["id"] as? String, "\(output)")
        let next = try #require(result["next"] as? [String: Any], "\(output)")
        let moved = try #require(Self.dataField("moveTask", of: result["moved"]), "\(output)")
        #expect(next["title"] as? String == Self.taskTitle)
        #expect(next["id"] as? String == added)
        #expect(moved["id"] as? String == added)
        #expect((moved["column"] as? [String: Any])?["name"] as? String == Self.doingName)
        let patch = try #require(try CrossRepoWriteTests.events(ofTask: added, inRepoAt: root).last?.patch)
        #expect(patch.set[PropertyName.column] == .ref(.local(.column(slug: Self.doingSlug))))
    }
}
