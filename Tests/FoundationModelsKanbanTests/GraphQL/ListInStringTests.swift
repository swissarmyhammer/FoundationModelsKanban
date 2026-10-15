import Foundation
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

/// A list field of `AddTaskInput`, for the tests of a JSON array that the caller sends as one string.
enum ListInStringField: String, CaseIterable, Sendable {
    /// `tags`: tag names.
    case tags

    /// `assignees`: actor refs.
    case assignees

    /// `dependsOn`: task refs.
    case dependsOn

    /// The type of the items of the field, for the declaration of a list variable.
    var itemType: String {
        switch self {
        case .tags: "String"
        case .assignees, .dependsOn: "ID"
        }
    }

    /// The field of each item of the result that the test reads.
    var resultKey: String {
        switch self {
        case .tags, .assignees: "name"
        case .dependsOn: "id"
        }
    }

    /// The selection of the field on the added task.
    var selection: String {
        "{ \(rawValue) { \(resultKey) } }"
    }

    /// Makes the nodes that the items name, and gives the items and the values that the result must give.
    ///
    /// - Parameters:
    ///   - graph: The engine of the fixture board.
    ///   - task: The ULID of the fixture task.
    /// - Returns: The items of the list, and the sorted values of ``resultKey`` that the added task must give.
    /// - Throws: An error when a setup call fails.
    func prepare(on graph: KanbanGraph, task: ULID) async throws -> (items: [String], expected: [String]) {
        switch self {
        case .tags:
            return (ListInStringTests.tagNames, ListInStringTests.tagNames)
        case .assignees:
            let addActors = AddUpdateTaskTests.mutation(of: AddUpdateTaskTests.addActors)
            _ = try await KanbanGraphTests.execute(addActors, on: graph)
            let actors = [AddUpdateTaskTests.alice, AddUpdateTaskTests.bob]
            return (actors, actors)
        case .dependsOn:
            let added = AddUpdateTaskTests.mutation(of: #"addTask(input: { title: "dep" }) { id }"#)
            let other = try AddUpdateTaskTests.firstTask(in: try await KanbanGraphTests.execute(added, on: graph))
            let ids = [task, other].map { ulid in ColumnActorTests.id(of: .task(ulid)) }
            return ([task, other].map(AddUpdateTaskTests.sigilRef(of:)), ids.sorted())
        }
    }
}

/// The place where the caller writes the JSON array of a list field.
enum ListInStringForm: String, CaseIterable, Sendable {
    /// A string literal in the text of the document.
    case documentText

    /// A string value of a key of the `input` variable.
    case inputVariable

    /// A string value of a variable whose declared type is a list.
    case listVariable
}

/// Tests that a JSON array of strings that the caller sends as one string for a list field gives the items of the
/// array, as Rust does (divergence.md Q13, N6). Each test runs on the fixture board of ``KanbanGraphTests`` in a
/// temporary repo.
@Suite("A JSON array sent as a string for a list field", .watcherBudget)
struct ListInStringTests {
    /// The tag names of the JSON array of the tag tests.
    static let tagNames = ["bug", "ui"]

    /// The tag that the untag test keeps.
    private static let keptTag = "chore"

    // MARK: - Helpers

    /// Runs a test body on the fixture board in a new temporary repo. The repo stays until the body ends.
    ///
    /// - Parameter body: The test body. It gets the engine and the ULID of the fixture task.
    /// - Throws: An error when the fixture cannot be made, or the error of the body.
    private static func withFixture(_ body: (KanbanGraph, ULID) async throws -> Void) async throws {
        let directory = try TemporaryDirectory()
        let made = try ColumnActorTests.makeFixtureGraph(in: directory)
        try await body(made.graph, made.task)
        withExtendedLifetime(directory) {}
    }

    /// Gives the JSON array text of some strings, for example `["bug","ui"]`.
    ///
    /// - Parameter items: The strings.
    /// - Returns: The JSON text.
    /// - Throws: An error when the strings cannot be encoded.
    private static func jsonArray(of items: [String]) throws -> String {
        String(decoding: try JSONEncoder().encode(items), as: UTF8.self)
    }

    /// Gives a GraphQL string literal of a text, with each quote and backslash escaped.
    ///
    /// - Parameter text: The text.
    /// - Returns: The literal, for example `"[\"bug\"]"`.
    /// - Throws: An error when the text cannot be encoded.
    private static func stringLiteral(of text: String) throws -> String {
        String(decoding: try JSONEncoder().encode(text), as: UTF8.self)
    }

    /// Gives the sorted values of one key of the items of a list field of a mutation result.
    ///
    /// - Parameters:
    ///   - response: The response JSON text.
    ///   - mutation: The name of the mutation field in `data`.
    ///   - field: The list field of the result.
    ///   - key: The key of each item.
    /// - Returns: The sorted values.
    /// - Throws: An error when the response has no such list.
    private static func values(
        in response: String,
        of mutation: String,
        field: String,
        key: String
    ) throws -> [String] {
        let result = try #require(try NameRewriteTests.data(of: response)[mutation] as? [String: Any], "\(response)")
        let items = try #require(result[field] as? [[String: Any]], "\(response)")
        return items.compactMap { item in item[key] as? String }.sorted()
    }

    /// Runs an `addTask` whose list field holds one string, in one form.
    ///
    /// - Parameters:
    ///   - text: The string of the list field.
    ///   - field: The list field.
    ///   - form: The place where the call writes the string.
    ///   - graph: The engine.
    /// - Returns: The response JSON text.
    /// - Throws: An error when the call cannot run.
    private static func addTask(
        withString text: String,
        in field: ListInStringField,
        as form: ListInStringForm,
        on graph: KanbanGraph
    ) async throws -> String {
        let name = field.rawValue
        switch form {
        case .documentText:
            let input = #"title: "x", \#(name): \#(try stringLiteral(of: text))"#
            return try await KanbanGraphTests.execute(
                "mutation { addTask(input: { \(input) }) \(field.selection) }",
                on: graph
            )
        case .inputVariable:
            let document = "mutation ($input: AddTaskInput!) { addTask(input: $input) \(field.selection) }"
            let input: Map = ["title": "x", name: .string(text)]
            return try await KanbanGraphTests.execute(document, variables: ["input": input], on: graph)
        case .listVariable:
            let add = #"addTask(input: { title: "x", \#(name): $list }) \#(field.selection)"#
            let document = "mutation ($list: [\(field.itemType)!]) { \(add) }"
            return try await KanbanGraphTests.execute(document, variables: ["list": .string(text)], on: graph)
        }
    }

    /// Runs a `tagTask` or an `untagTask` on the fixture task whose `tags` holds one string, in one form.
    ///
    /// - Parameters:
    ///   - mutation: `tagTask` or `untagTask`.
    ///   - text: The string of `tags`.
    ///   - form: The place where the call writes the string.
    ///   - task: The ULID of the fixture task.
    ///   - graph: The engine.
    /// - Returns: The response JSON text.
    /// - Throws: An error when the call cannot run.
    private static func run(
        _ mutation: String,
        withTags text: String,
        as form: ListInStringForm,
        onTask task: ULID,
        on graph: KanbanGraph
    ) async throws -> String {
        let id = AddUpdateTaskTests.sigilRef(of: task)
        let selection = "{ tags { name } }"
        switch form {
        case .documentText:
            let input = #"id: "\#(id)", tags: \#(try stringLiteral(of: text))"#
            let document = "mutation { \(mutation)(input: { \(input) }) \(selection) }"
            return try await KanbanGraphTests.execute(document, on: graph)
        case .inputVariable:
            let document = "mutation ($input: TagTaskInput!) { \(mutation)(input: $input) \(selection) }"
            let input: Map = ["id": .string(id), "tags": .string(text)]
            return try await KanbanGraphTests.execute(document, variables: ["input": input], on: graph)
        case .listVariable:
            let field = #"\#(mutation)(input: { id: "\#(id)", tags: $list }) \#(selection)"#
            let document = "mutation ($list: [String!]!) { \(field) }"
            return try await KanbanGraphTests.execute(document, variables: ["list": .string(text)], on: graph)
        }
    }

    // MARK: - addTask

    @Test(
        "addTask with a JSON array in a string for a list field gives the items of the array",
        arguments: ListInStringField.allCases,
        ListInStringForm.allCases
    )
    func addTaskSplitsJSONArray(field: ListInStringField, form: ListInStringForm) async throws {
        try await Self.withFixture { graph, task in
            let (items, expected) = try await field.prepare(on: graph, task: task)
            let text = try Self.jsonArray(of: items)
            let response = try await Self.addTask(withString: text, in: field, as: form, on: graph)
            #expect(try KanbanGraphTests.object(of: response)["errors"] == nil, "\(response)")
            let values = try Self.values(in: response, of: "addTask", field: field.rawValue, key: field.resultKey)
            #expect(values == expected, "\(response)")
        }
    }

    @Test("addTask with one tag name in a string for tags gives that one tag", arguments: ListInStringForm.allCases)
    func addTaskKeepsOneTagName(form: ListInStringForm) async throws {
        try await Self.withFixture { graph, _ in
            let response = try await Self.addTask(withString: "bug", in: .tags, as: form, on: graph)
            #expect(try Self.values(in: response, of: "addTask", field: "tags", key: "name") == ["bug"], "\(response)")
        }
    }

    @Test(
        "addTask with a string that is not a JSON array of strings for tags gives one tag with that name",
        arguments: ["[bug", "[1,2]"]
    )
    func addTaskKeepsTextThatIsNotJSONArray(text: String) async throws {
        try await Self.withFixture { graph, _ in
            let response = try await Self.addTask(withString: text, in: .tags, as: .documentText, on: graph)
            #expect(try Self.values(in: response, of: "addTask", field: "tags", key: "name") == [text], "\(response)")
        }
    }

    // MARK: - tagTask and untagTask

    @Test("tagTask with a JSON array in a string for tags adds each tag", arguments: ListInStringForm.allCases)
    func tagTaskSplitsJSONArray(form: ListInStringForm) async throws {
        try await Self.withFixture { graph, task in
            let tags = try Self.jsonArray(of: Self.tagNames)
            let response = try await Self.run("tagTask", withTags: tags, as: form, onTask: task, on: graph)
            let values = try Self.values(in: response, of: "tagTask", field: "tags", key: "name")
            #expect(values == Self.tagNames, "\(response)")
        }
    }

    @Test("untagTask with a JSON array in a string for tags removes each tag", arguments: ListInStringForm.allCases)
    func untagTaskSplitsJSONArray(form: ListInStringForm) async throws {
        try await Self.withFixture { graph, task in
            let all = try Self.jsonArray(of: Self.tagNames + [Self.keptTag])
            let setup = #"tagTask(input: { id: "\#(AddUpdateTaskTests.sigilRef(of: task))", tags: \#(all) }) { id }"#
            _ = try await KanbanGraphTests.execute(AddUpdateTaskTests.mutation(of: setup), on: graph)
            let tags = try Self.jsonArray(of: Self.tagNames)
            let response = try await Self.run("untagTask", withTags: tags, as: form, onTask: task, on: graph)
            let values = try Self.values(in: response, of: "untagTask", field: "tags", key: "name")
            #expect(values == [Self.keptTag], "\(response)")
        }
    }
}
