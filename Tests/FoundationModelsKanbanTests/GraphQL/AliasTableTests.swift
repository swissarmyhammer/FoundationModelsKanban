import Foundation
import GraphQL
import Testing

@testable import FoundationModelsKanban

/// One row of the alias tests: the field that holds a name, the name that the agent writes, and the canonical name
/// (divergence.md tables 4.2 and 4.3).
struct AliasRow: Sendable, CustomTestStringConvertible {
    /// The field that holds the name: a mutation for an input field, or a field of `Board` or `Query` for an
    /// argument.
    let field: String

    /// The name that the agent writes.
    let written: String

    /// The name that the rewrite must give.
    let canonical: String

    /// The text of the row in the test report.
    var testDescription: String {
        "\(field): \(written) → \(canonical)"
    }

    /// Makes one row for each field and each written name.
    ///
    /// - Parameters:
    ///   - fields: The fields that hold the names.
    ///   - names: The names that the agent writes.
    ///   - canonical: The name that the rewrite must give for each of them.
    /// - Returns: The rows, field by field.
    static func rows(on fields: [String], mapping names: [String], to canonical: String) -> [Self] {
        fields.flatMap { field in names.map { name in Self(field: field, written: name, canonical: canonical) } }
    }
}

/// Tests the alias tables of the name rewrite (divergence.md N2, Q9, Q14, E5, tables 4.2 and 4.3): an alias applies
/// only at the positions of its table, so that a name with one clear meaning in a position gets the canonical name
/// there, and a name with two meanings gives `AMBIGUOUS_NAME`.
///
/// Each test runs the rewriter of the public schema on a document and reads the text that it gives.
@Suite("Alias tables of the name rewrite", .watcherBudget)
struct AliasTableTests {
    /// The task mutations whose `input` names the task in the field `id`.
    private static let taskOperations = [
        "updateTask", "moveTask", "completeTask", "assignTask", "unassignTask", "tagTask", "untagTask", "deleteTask",
        "undeleteTask",
    ]

    /// The mutations whose `input` has a `body` field and no field that `comment` can also name.
    private static let bodyInputs = [
        "initBoard", "updateBoard", "addColumn", "updateColumn", "addActor", "updateActor", "addTask", "updateTask",
        "addComment", "addTag", "updateTag",
    ]

    /// The names of the agent for the `body` field of an input, except `comment`.
    private static let bodyNames = ["notes", "details", "message", "text", "description"]

    /// The names of the agent for the page size of a list.
    private static let pageSizeNames = ["top_k", "topK", "limit", "page_size", "count", "size"]

    /// The rows of the input fields of the mutations.
    static let inputRows: [AliasRow] = [
        AliasRow.rows(on: ["assignTask", "unassignTask"], mapping: ["assignee", "actorId", "actor_id", "user", "who"],
                      to: "actor"),
        AliasRow.rows(on: ["moveTask"], mapping: ["before_id", "beforeId", "beforeTask"], to: "before"),
        AliasRow.rows(on: ["moveTask"], mapping: ["after_id", "afterId", "afterTask"], to: "after"),
        AliasRow.rows(on: taskOperations, mapping: ["task", "ref", "uri", "key", "taskId", "task_id"], to: "id"),
        AliasRow.rows(
            on: ["addTask", "moveTask", "updateTask"],
            mapping: ["state", "status", "lane", "col", "columnId", "column_id", "to", "toColumn"],
            to: "column"
        ),
        AliasRow.rows(on: ["updateColumn", "deleteColumn", "undeleteColumn"],
                      mapping: ["column", "columnId", "column_id", "ref", "uri", "key"], to: "id"),
        AliasRow.rows(on: ["updateActor", "deleteActor", "undeleteActor"],
                      mapping: ["actor", "actorId", "actor_id", "ref", "uri", "key"], to: "id"),
        AliasRow.rows(on: ["updateTag", "deleteTag", "undeleteTag"],
                      mapping: ["tag", "tagId", "tag_id", "ref", "uri", "key"], to: "id"),
        AliasRow.rows(on: ["updateComment", "deleteComment", "undeleteComment"],
                      mapping: ["commentId", "comment_id", "ref", "uri", "key"], to: "id"),
        AliasRow.rows(on: ["deleteComment", "undeleteComment"], mapping: ["comment"], to: "id"),
        AliasRow.rows(on: ["addComment", "updateComment", "deleteComment", "undeleteComment"],
                      mapping: ["task_id", "taskId"], to: "task"),
        AliasRow.rows(on: ["addComment"], mapping: ["author", "user"], to: "actor"),
        AliasRow.rows(on: ["addTask", "updateTask"], mapping: ["name", "subject", "summary"], to: "title"),
        AliasRow.rows(on: bodyInputs, mapping: bodyNames + ["comment"], to: "body"),
        AliasRow.rows(on: ["updateComment"], mapping: bodyNames, to: "body"),
        AliasRow.rows(on: ["addTask", "updateTask"], mapping: ["assignTo", "owner", "owners"], to: "assignees"),
        AliasRow.rows(
            on: ["addTask", "updateTask"],
            mapping: ["dependencies", "dependency", "depends", "deps", "blockers", "prerequisites", "blockedBy"],
            to: "dependsOn"
        ),
        AliasRow.rows(on: ["addTask", "updateTask", "tagTask", "untagTask"], mapping: ["labels", "label"], to: "tags"),
        AliasRow.rows(on: ["renameTag"], mapping: ["tag", "old", "oldName"], to: "from"),
        AliasRow.rows(on: ["renameTag"], mapping: ["name", "new", "newName"], to: "to"),
        AliasRow.rows(on: ["undo", "redo"], mapping: ["transaction", "txnId", "txn_id", "id"], to: "txn"),
    ].flatMap { rows in rows }

    /// The rows of the arguments of the fields of `Board`.
    static let boardArgumentRows: [AliasRow] = [
        AliasRow.rows(on: ["tasks", "searchTasks", "history"], mapping: pageSizeNames, to: "first"),
        AliasRow.rows(on: ["tasks"], mapping: ["cursor"], to: "after"),
        AliasRow.rows(on: ["task"], mapping: ["task", "ref", "uri", "key", "taskId", "task_id"], to: "id"),
    ].flatMap { rows in rows }

    /// The rows of the arguments of the root query fields.
    static let rootArgumentRows: [AliasRow] = [
        AliasRow.rows(on: ["board"], mapping: ["path", "board", "key", "repo"], to: "id"),
        AliasRow.rows(
            on: ["node"],
            mapping: ["task", "column", "actor", "tag", "comment", "ref", "uri", "key", "nodeId", "node_id"],
            to: "id"
        ),
    ].flatMap { rows in rows }

    // MARK: - Helpers

    /// Runs the rewriter of the public schema on a document.
    ///
    /// - Parameter document: The GraphQL document.
    /// - Returns: The rewritten document.
    /// - Throws: A `GraphQLError` when the document does not parse.
    private static func rewritten(from document: String) throws -> RewrittenDocument {
        try DocumentRewriter(for: PublicSchema().schema.schema).rewrittenDocument(from: document)
    }

    /// Makes a mutation document with one field whose `input` has one field.
    ///
    /// - Parameters:
    ///   - mutation: The mutation name.
    ///   - name: The name of the input field.
    /// - Returns: The document.
    private static func inputDocument(of mutation: String, naming name: String) -> String {
        #"mutation { \#(mutation)(input: { \#(name): "x" }) { __typename } }"#
    }

    /// Makes a query document with one argument of a field of `Board`.
    ///
    /// - Parameters:
    ///   - field: The field of `Board`.
    ///   - name: The name of the argument.
    /// - Returns: The document.
    private static func boardArgumentDocument(of field: String, naming name: String) -> String {
        #"{ board { \#(field)(\#(name): "x") { __typename } } }"#
    }

    /// Makes a query document with one argument of a root query field.
    ///
    /// - Parameters:
    ///   - field: The root query field.
    ///   - name: The name of the argument.
    /// - Returns: The document.
    private static func rootArgumentDocument(of field: String, naming name: String) -> String {
        #"{ \#(field)(\#(name): "x") { __typename } }"#
    }

    // MARK: - Input fields

    @Test("An input field name of tables 4.2 and 4.3 gets the canonical name of its input", arguments: inputRows)
    func inputFieldGetsCanonicalName(row: AliasRow) throws {
        let rewritten = try Self.rewritten(from: Self.inputDocument(of: row.field, naming: row.written))
        #expect(rewritten.text == Self.inputDocument(of: row.field, naming: row.canonical))
        #expect(rewritten.ties.isEmpty)
    }

    @Test("task_id is not an alias of id on an input that is not a task input")
    func taskIDIsNotGlobalAliasOfID() throws {
        let document = #"mutation { updateColumn(input: { id: "qa", task_id: "x" }) { id } }"#
        let rewritten = try Self.rewritten(from: document)
        #expect(rewritten.text == document)
        #expect(rewritten.rewrites.isEmpty)
    }

    @Test("comment on updateComment can name the comment or the body, and gives AMBIGUOUS_NAME")
    func commentOnUpdateCommentIsAmbiguous() throws {
        let rewritten = try Self.rewritten(from: Self.inputDocument(of: "updateComment", naming: "comment"))
        let tie = KanbanError.ambiguousName(name: "comment", matches: ["id", "body"])
        #expect(rewritten.ties.compactMap { error in error.originalError as? KanbanError } == [tie])
    }

    // MARK: - Arguments

    @Test("An argument name of a Board field gets the canonical name of its field", arguments: boardArgumentRows)
    func boardArgumentGetsCanonicalName(row: AliasRow) throws {
        let rewritten = try Self.rewritten(from: Self.boardArgumentDocument(of: row.field, naming: row.written))
        #expect(rewritten.text == Self.boardArgumentDocument(of: row.field, naming: row.canonical))
    }

    @Test("An argument name of a root query field gets the canonical name of its field", arguments: rootArgumentRows)
    func rootArgumentGetsCanonicalName(row: AliasRow) throws {
        let rewritten = try Self.rewritten(from: Self.rootArgumentDocument(of: row.field, naming: row.written))
        #expect(rewritten.text == Self.rootArgumentDocument(of: row.field, naming: row.canonical))
    }

    // MARK: - Mutation names

    @Test(
        "removeAssignee and addAssignee give unassignTask and assignTask",
        arguments: [("removeAssignee", "unassignTask"), ("remove_assignee", "unassignTask"),
                    ("addAssignee", "assignTask")]
    )
    func assigneeMutationGetsCanonicalName(written: String, canonical: String) throws {
        let rewritten = try Self.rewritten(from: "mutation { \(written)(input: { id: \"a\", actor: \"b\" }) { id } }")
        #expect(rewritten.text == "mutation { \(written): \(canonical)(input: { id: \"a\", actor: \"b\" }) { id } }")
    }

    // MARK: - Selection fields

    @Test(
        "A selection field name of table 4.3 gets the canonical name of its type",
        arguments: [("created_at", "created"), ("createdAt", "created"), ("updated_at", "updated"),
                    ("updatedAt", "updated"), ("status", "column"), ("state", "column")]
    )
    func taskSelectionGetsCanonicalName(written: String, canonical: String) throws {
        let rewritten = try Self.rewritten(from: #"{ board { task(id: "^aaaaaaa") { \#(written) } } }"#)
        #expect(rewritten.text == #"{ board { task(id: "^aaaaaaa") { \#(written): \#(canonical) } } }"#)
    }

    @Test("count and total on a task list give totalCount", arguments: ["count", "total"])
    func taskListCountGetsTotalCount(written: String) throws {
        let rewritten = try Self.rewritten(from: "{ board { tasks { \(written) } } }")
        #expect(rewritten.text == "{ board { tasks { \(written): totalCount } } }")
    }

    @Test("total on the board summary stays total")
    func summaryTotalStaysTotal() throws {
        let document = "{ board { summary { total } } }"
        #expect(try Self.rewritten(from: document).text == document)
    }
}
