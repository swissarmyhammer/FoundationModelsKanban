import Foundation
import GraphQL
import Testing

@testable import FoundationModelsKanban

/// Tests the name rewrite of the keys in `variables` (divergence.md N1, Q8, K5): each key of an `input` object in a
/// variable gets the canonical name of the input type of the variable, at all depths, with the same matcher steps and
/// the same alias tables as the document text.
///
/// The rewrite tests run the rewriter of the public schema on a document and its variables, and read the variables
/// that it gives. The execution test runs a document on a fixture board in a temporary repo.
@Suite("Name rewrite of the keys in variables", .watcherBudget)
struct VariableRewriteTests {
    /// The value of each key in the variable tests. The rewrite changes keys, not values.
    private static let value: Map = "x"

    /// The name of the variable in the variable tests.
    private static let variable = "i"

    /// The title of the task that the execution test adds.
    private static let title = "Variable task"

    /// The name of the tag that the execution test adds.
    private static let tag = "bug"

    // MARK: - Helpers

    /// Runs the rewriter of a schema on a document and its variables.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - variables: The values of the variables of the document.
    ///   - schema: The schema whose names are canonical. The default is the public schema.
    /// - Returns: The rewritten document.
    /// - Throws: A `GraphQLError` when the document does not parse.
    private static func rewritten(
        from document: String,
        variables: [String: Map],
        in schema: GraphQLSchema? = nil
    ) throws -> RewrittenDocument {
        let schema = try schema ?? PublicSchema().schema.schema
        return try DocumentRewriter(for: schema).rewrittenDocument(from: document, variables: variables)
    }

    /// Gives the name of the input type of the `input` argument of a mutation of the public schema.
    ///
    /// - Parameter mutation: The mutation name, for example `addTask`.
    /// - Returns: The name of the input type, for example `AddTaskInput`.
    /// - Throws: An error when the mutation or its `input` argument is not in the schema.
    private static func inputTypeName(of mutation: String) throws -> String {
        let fields = try #require(try PublicSchema().schema.schema.mutationType?.fields())
        let input = try #require(fields[mutation]?.args["input"], "\(mutation)")
        return try #require(getNamedType(type: input.type)?.name)
    }

    /// Makes a mutation document whose one field takes its `input` from the variable ``variable``.
    ///
    /// - Parameter mutation: The mutation name.
    /// - Returns: The document, with the declared type of the variable from the schema.
    /// - Throws: An error when the mutation or its `input` argument is not in the schema.
    private static func variableDocument(of mutation: String) throws -> String {
        let type = try inputTypeName(of: mutation)
        return "mutation($\(variable): \(type)) { \(mutation)(input: $\(variable)) { __typename } }"
    }

    /// Makes a schema with a list of `input` objects in a list of `input` objects. The public schema has no list of
    /// `input` objects, so the nested list test uses this schema: the query field `add` takes `items: [ItemInput]`,
    /// and `ItemInput` has `title` and `steps: [StepInput]`, and `StepInput` has `body`.
    ///
    /// - Returns: The schema.
    /// - Throws: An error from GraphQL when a type is not valid.
    private static func nestedListSchema() throws -> GraphQLSchema {
        let text = InputObjectField(type: GraphQLString)
        let step = try GraphQLInputObjectType(name: "StepInput", fields: ["body": text])
        let steps = InputObjectField(type: GraphQLList(step))
        let item = try GraphQLInputObjectType(name: "ItemInput", fields: ["title": text, "steps": steps])
        let add = GraphQLField(type: GraphQLString, args: ["items": GraphQLArgument(type: GraphQLList(item))])
        return try GraphQLSchema(query: GraphQLObjectType(name: "Query", fields: ["add": add]))
    }

    // MARK: - Input fields

    @Test(
        "An input field name of tables 4.2 and 4.3 in a variable gets the canonical name of its input",
        arguments: AliasTableTests.inputRows
    )
    func variableKeyGetsCanonicalName(row: AliasRow) throws {
        let variables: [String: Map] = [Self.variable: [row.written: Self.value]]
        let rewritten = try Self.rewritten(from: Self.variableDocument(of: row.field), variables: variables)
        #expect(rewritten.variables == [Self.variable: [row.canonical: Self.value]])
        #expect(rewritten.ties.isEmpty)
    }

    @Test("A key in a variable that can name two fields gives AMBIGUOUS_NAME, and the key stays")
    func ambiguousVariableKeyGivesTie() throws {
        let variables: [String: Map] = [Self.variable: ["comment": Self.value]]
        let rewritten = try Self.rewritten(from: Self.variableDocument(of: "updateComment"), variables: variables)
        let tie = KanbanError.ambiguousName(name: "comment", matches: ["id", "body"])
        #expect(rewritten.ties.compactMap { error in error.originalError as? KanbanError } == [tie])
        #expect(rewritten.variables == variables)
    }

    @Test("The rewrite of a key in a variable is in the rewrites, with the path from the variable")
    func variableRewriteIsRecorded() throws {
        let variables: [String: Map] = [Self.variable: ["name": Self.value]]
        let rewritten = try Self.rewritten(from: Self.variableDocument(of: "addTask"), variables: variables)
        #expect(rewritten.rewrites == [NameRewrite(from: "name", to: "title", path: ["$\(Self.variable)", "name"])])
    }

    @Test("A variable that the operation does not declare stays as it is")
    func undeclaredVariableStays() throws {
        let variables: [String: Map] = [Self.variable: ["name": Self.value]]
        let document = #"mutation { addTask(input: { title: "t" }) { id } }"#
        let rewritten = try Self.rewritten(from: document, variables: variables)
        #expect(rewritten.variables == variables)
        #expect(rewritten.rewrites.isEmpty)
    }

    @Test("A key whose canonical name is also a key of the same object keeps the name that the caller wrote")
    func keyWithTakenCanonicalNameStays() throws {
        let variables: [String: Map] = [Self.variable: ["name": Self.value, "title": Self.value]]
        let rewritten = try Self.rewritten(from: Self.variableDocument(of: "addTask"), variables: variables)
        #expect(rewritten.variables == variables)
    }

    // MARK: - Nested lists

    @Test("The keys of a list of input objects in a list of input objects in a variable get their canonical names")
    func nestedListKeysGetCanonicalNames() throws {
        let document = "query($items: [ItemInput]) { add(items: $items) }"
        let variables: [String: Map] = ["items": [["Title": Self.value, "Steps": [["notes": Self.value]]]]]
        let rewritten = try Self.rewritten(from: document, variables: variables, in: Self.nestedListSchema())
        #expect(rewritten.variables == ["items": [["title": Self.value, "steps": [["body": Self.value]]]]])
    }

    @Test("A key that keeps the name that the caller wrote still gets the canonical keys in its nested value")
    func takenKeyRewritesItsNestedValue() throws {
        let document = "query($items: [ItemInput]) { add(items: $items) }"
        let item: Map = ["steps": [["body": Self.value]], "Steps": [["notes": Self.value]]]
        let rewritten = try Self.rewritten(from: document, variables: ["items": [item]], in: Self.nestedListSchema())
        let expected: Map = ["steps": [["body": Self.value]], "Steps": [["body": Self.value]]]
        #expect(rewritten.variables == ["items": [expected]])
    }

    // MARK: - Through execute

    @Test("addTask with an input variable with name, labels, and depends adds the task with its title and tags")
    func inputVariableAddsTheTask() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let variable = Self.variable
        let document = "mutation($\(variable): AddTaskInput!) { addTask(input: $\(variable)) { title tags { name } } }"
        let input: Map = ["name": .string(Self.title), "labels": [.string(Self.tag)], "depends": []]
        let response = try await KanbanGraphTests.execute(document, variables: [variable: input], on: fixture.graph)
        #expect(try KanbanGraphTests.object(of: response)["errors"] == nil, "\(response)")
        let task = try #require(try NameRewriteTests.data(of: response)["addTask"] as? [String: Any], "\(response)")
        #expect(task["title"] as? String == Self.title)
        #expect(task["tags"] as? [[String: String]] == [["name": Self.tag]])
        withExtendedLifetime(directory) {}
    }
}
