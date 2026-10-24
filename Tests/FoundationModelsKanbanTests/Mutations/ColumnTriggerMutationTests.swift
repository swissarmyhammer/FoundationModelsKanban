import Foundation
import GraphQL
import Testing

@testable import FoundationModelsKanban

/// Tests `Column.trigger` and `Column.next`, and the `trigger` and `next` fields of `addColumn` and `updateColumn`
/// (divergence.md §22, TestudoApp KANBAN-2).
///
/// Each test uses the fixture logs of ``KanbanGraphTests``: the board, the column `todo` with no body, and one task.
@Suite("Column trigger and next", .watcherBudget)
struct ColumnTriggerMutationTests {
    /// The selection of a column field: its body and its trigger fields.
    private static let columnSelection = "{ body trigger next }"

    /// The skill of the trigger that a test writes.
    private static let skill = ColumnTriggerTests.skill

    /// The text of the body of `todo` that a test writes before a trigger write.
    private static let text = ColumnTriggerTests.text

    /// The body of `todo` after a write of the trigger ``skill`` on the body ``text``.
    private static let triggerBody = "---\ntrigger: \(skill)\n---\n" + text

    /// A frontmatter with the trigger ``skill`` and `next: false`, and no text after it.
    private static let noNextBody = "---\ntrigger: \(skill)\nnext: false\n---\n"

    /// The `input` field that sets the trigger ``skill``.
    private static let triggerInput = #"trigger: "\#(skill)""#

    /// The selection of each event of the `changes` test: the changed fields and the node now.
    private static let changeSelection = "{ txn ops updates { id kind fields { name before after } "
        + "node { ... on Column \(columnSelection) } } }"

    // MARK: - Helpers

    /// Makes an `updateColumn` field that changes `todo` and selects ``columnSelection``.
    ///
    /// - Parameter input: The other fields of the `input` object.
    /// - Returns: The field.
    private static func updateTodo(with input: String) -> String {
        CommentTests.nodeField(
            MutationName.updateColumn,
            naming: TaskOperationTests.todoSlug,
            with: input,
            selecting: columnSelection
        )
    }

    /// Makes a new engine of the fixture repo, and writes a body to `todo`.
    ///
    /// - Parameters:
    ///   - body: The body of `todo`.
    ///   - directory: The temporary repo directory.
    /// - Returns: The engine.
    private static func todo(withBody body: String, in directory: TemporaryDirectory) async throws -> KanbanGraph {
        let graph = try ColumnActorTests.makeFixtureGraph(in: directory).graph
        _ = try await writeBody(body, on: graph)
        return graph
    }

    /// Writes a body to `todo` with the variable `$body`, and gives the response with no `extensions.txn`.
    ///
    /// - Parameters:
    ///   - body: The new body.
    ///   - graph: The engine.
    /// - Returns: The response JSON text.
    private static func writeBody(_ body: String, on graph: KanbanGraph) async throws -> String {
        let document = AddUpdateTaskTests.bodyMutation(of: updateTodo(with: "body: $body"))
        let response = try await KanbanGraphTests.execute(document, variables: ["body": .string(body)], on: graph)
        return KanbanGraphTests.withoutTransaction(response)
    }

    /// Gives the JSON object that ``columnSelection`` gives.
    ///
    /// - Parameters:
    ///   - body: The body of the column.
    ///   - trigger: The skill of the trigger, or `nil` for no trigger.
    ///   - next: The `next` value.
    /// - Returns: The JSON object text, with sorted keys.
    private static func columnJSON(body: String, trigger: String?, next: Bool) -> String {
        let triggerJSON = trigger.map { skill in #""\#(skill)""# } ?? "null"
        return #"{"body":"\#(TaskOperationTests.jsonText(of: body))","next":\#(next),"trigger":\#(triggerJSON)}"#
    }

    /// Gives the response of a document with one `updateColumn` field that selects ``columnSelection``.
    ///
    /// - Parameters:
    ///   - body: The body of the column.
    ///   - trigger: The skill of the trigger, or `nil` for no trigger.
    ///   - next: The `next` value.
    ///   - extensions: The `extensions` object of the response, or `nil` for none.
    /// - Returns: The response JSON text.
    private static func updatedResponse(
        body: String,
        trigger: String?,
        next: Bool,
        extensions: String? = nil
    ) -> String {
        let column = columnJSON(body: body, trigger: trigger, next: next)
        let tail = extensions.map { object in #","extensions":\#(object)"# } ?? ""
        return #"{"data":{"\#(MutationName.updateColumn)":\#(column)}\#(tail)}"#
    }

    // MARK: - Read

    @Test("Column.trigger and Column.next of a column with no frontmatter are null and true")
    func columnWithNoFrontmatterHasNoTrigger() async throws {
        let response = try await ColumnActorTests.respond(
            to: #"{ board { column(id: "\#(TaskOperationTests.todoSlug)") { trigger next } } }"#,
            onFixtureIn: try TemporaryDirectory()
        )
        #expect(response == #"{"data":{"board":{"column":{"next":true,"trigger":null}}}}"#)
    }

    @Test("A body write gives the trigger and the next value of the frontmatter of the new body")
    func bodyWriteGivesTriggerOfNewBody() async throws {
        let directory = try TemporaryDirectory()
        let graph = try ColumnActorTests.makeFixtureGraph(in: directory).graph
        let body = Self.noNextBody + Self.text
        let response = try await Self.writeBody(body, on: graph)
        #expect(response == Self.updatedResponse(body: body, trigger: Self.skill, next: false))
    }

    @Test("A body write with bad YAML writes the body, and gives no trigger, next true, and a warning")
    func badYAMLBodyGivesDefaultsAndWarning() async throws {
        let directory = try TemporaryDirectory()
        let graph = try ColumnActorTests.makeFixtureGraph(in: directory).graph
        let body = ColumnTriggerTests.badYAMLBody
        let response = try await Self.writeBody(body, on: graph)
        let warning = try #require(ColumnTrigger(body: body).warning(ofColumn: TaskOperationTests.todoSlug))
        let warnings = #"{"warnings":[{"code":"\#(ColumnTrigger.warningCode)","message":"\#(warning.message)"}]}"#
        #expect(response == Self.updatedResponse(body: body, trigger: nil, next: true, extensions: warnings))
    }

    // MARK: - Write

    @Test("updateColumn with a trigger writes it into the frontmatter of the body, and keeps the text")
    func updateColumnTriggerWritesFrontmatter() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.todo(withBody: Self.text, in: directory)
        let response = try await KanbanGraphTests.runWithoutTransaction(
            Self.updateTodo(with: Self.triggerInput),
            on: graph
        )
        #expect(response == Self.updatedResponse(body: Self.triggerBody, trigger: Self.skill, next: true))
    }

    @Test("updateColumn with a null trigger removes the key, and keeps the other keys and the text")
    func nullTriggerRemovesKey() async throws {
        let directory = try TemporaryDirectory()
        let owner = "owner: qa\n"
        let body = "---\ntrigger: \(Self.skill)\n\(owner)---\n" + Self.text
        let graph = try await Self.todo(withBody: body, in: directory)
        let response = try await KanbanGraphTests.runWithoutTransaction(
            Self.updateTodo(with: "trigger: null"),
            on: graph
        )
        #expect(response == Self.updatedResponse(body: "---\n\(owner)---\n" + Self.text, trigger: nil, next: true))
    }

    @Test("addColumn with a trigger and next false writes both keys into the frontmatter of the new body")
    func addColumnWritesTriggerAndNext() async throws {
        let directory = try TemporaryDirectory()
        let field = #"addColumn(input: { name: "\#(ColumnActorTests.qaSlug)", \#(Self.triggerInput), "#
            + "next: false }) \(Self.columnSelection)"
        let graph = try ColumnActorTests.makeFixtureGraph(in: directory).graph
        let response = try await KanbanGraphTests.runWithoutTransaction(field, on: graph)
        let column = Self.columnJSON(body: Self.noNextBody, trigger: Self.skill, next: false)
        #expect(response == TaskOperationTests.dataResponse(of: #""addColumn":\#(column)"#))
    }

    @Test("skill names trigger and autoAdvance names next in the input of updateColumn")
    func aliasesNameTriggerAndNext() async throws {
        let directory = try TemporaryDirectory()
        let graph = try ColumnActorTests.makeFixtureGraph(in: directory).graph
        let response = try await KanbanGraphTests.runWithoutTransaction(
            Self.updateTodo(with: #"skill: "\#(Self.skill)", autoAdvance: false"#),
            on: graph
        )
        let path = #""\#(MutationName.updateColumn)","input""#
        let rewrites = [
            #"{"from":"skill","path":[\#(path),"skill"],"to":"trigger"}"#,
            #"{"from":"autoAdvance","path":[\#(path),"autoAdvance"],"to":"next"}"#,
        ]
        let extensions = #"{"rewrites":[\#(rewrites.joined(separator: ","))]}"#
        #expect(
            response == Self.updatedResponse(
                body: Self.noNextBody,
                trigger: Self.skill,
                next: false,
                extensions: extensions
            )
        )
    }

    // MARK: - Change feed and undo

    @Test("The changes event of a trigger write gives the new body and the new trigger")
    func changesEventGivesNewBodyAndTrigger() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.todo(withBody: Self.text, in: directory)
        let stream = try await SubscriptionTests.subscribe(
            SubscriptionTests.subscription(#"(filter: "~column")"#, selecting: Self.changeSelection),
            on: graph
        )
        let response = try await CommentTests.run(Self.updateTodo(with: Self.triggerInput), on: graph)
        let fields = #"[{"after":null,"before":null,"name":"body"},"#
            + #"{"after":"\#(Self.skill)","before":null,"name":"trigger"}]"#
        let node = Self.columnJSON(body: Self.triggerBody, trigger: Self.skill, next: true)
        let update = #"{"fields":\#(fields),"id":"\#(ColumnActorTests.id(of: KanbanGraphTests.todoColumn))","#
            + #""kind":"\#(UpdateKind.updated.rawValue)","node":\#(node)}"#
        let expected = SubscriptionTests.event(
            txn: try ResponseTransactionTests.transaction(of: response),
            operation: MutationName.updateColumn,
            updates: [update]
        )
        let events = try await SubscriptionTests.events(
            SubscriptionTests.oneEvent,
            of: stream,
            afterChangeAt: directory.url
        )
        #expect(events == [expected])
        await graph.close()
    }

    @Test("One undoChange of a trigger write gives back the body and the trigger before the write")
    func undoOfTriggerWriteRestoresBody() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.todo(withBody: Self.text, in: directory)
        let document = AddUpdateTaskTests.mutation(of: Self.updateTodo(with: Self.triggerInput))
        let call = try await ResponseTransactionTests.run(document, on: graph, in: directory)
        let txn = try ResponseTransactionTests.transaction(of: call.response)
        let undo = UndoTests.reverseField(MutationName.undoChange, with: #"txn: "\#(txn)""#)
        _ = try await CommentTests.run(undo, on: graph)
        let column = try await KanbanGraphTests.execute(
            #"{ board { column(id: "\#(TaskOperationTests.todoSlug)") \#(Self.columnSelection) } }"#,
            on: graph
        )
        let json = Self.columnJSON(body: Self.text, trigger: nil, next: true)
        #expect(column == #"{"data":{"board":{"column":\#(json)}}}"#)
    }
}
