import Foundation
import FoundationModels
import GraphQL
import Testing

@testable import FoundationModelsKanban

/// Tests the forgiving decode of the tool arguments and the declared schema of `variables` (plan.md §7.1, §12 item 8).
@Suite("KanbanArguments: forgiving variables and the variables schema")
struct KanbanArgumentsTests {
    /// The document of each test.
    static let query = KanbanGraphTests.nameQuery

    /// The variables as JSON text, with each JSON type one time.
    static let variablesJSON = """
        {"id": "^ajv8v4t", "first": 2, "ratio": 0.5, "done": true, "none": null, "tags": ["bug", 3], \
        "input": {"title": "Port the parser"}}
        """

    /// The variables that ``variablesJSON`` gives, with the JSON types kept.
    static let expectedVariables: [String: Map] = [
        "id": "^ajv8v4t",
        "first": 2,
        "ratio": 0.5,
        "done": true,
        "none": .null,
        "tags": ["bug", 3],
        "input": ["title": "Port the parser"],
    ]

    /// The text forms of ``variablesJSON``: plain, with white space around it, and in a code fence with and without a
    /// language tag.
    static let textForms = [
        variablesJSON,
        "\n  \(variablesJSON)\n\t",
        "```json\n\(variablesJSON)\n```",
        "  ```\n\(variablesJSON)\n```\n",
    ]

    /// The `variables` JSON values that mean no variables. `nil` leaves out the key.
    static let noVariableForms: [String?] = [nil, "null", #""""#, #""  ""#]

    /// Each `variables` JSON value that is not a JSON object, with the description of what the call sent.
    static let invalidForms = [
        ("3", "a number"),
        ("true", "a boolean"),
        ("[1, 2]", "a list"),
        (#""[1, 2]""#, "text that holds a list"),
        (#""not json""#, "text that is not JSON"),
    ]

    /// The name of the operation of the operation-name test.
    static let operationName = "Names"

    /// The `operationName` values that hold no name: empty, spaces, and other white space.
    static let blankOperationNames = ["", "  ", "\n\t"]

    /// Each `operationName` that the call sends, with the name that the decode gives. `nil` leaves out the key. A
    /// blank name gives `nil`, the same as no key.
    static let operationNameForms: [(sent: String?, decoded: String?)] =
        [(operationName, operationName), (nil, nil)] + blankOperationNames.map { blank in (blank, nil) }

    // MARK: - Helpers

    /// Gives a string as JSON text: in quotes, with each special character escaped.
    ///
    /// - Parameter text: The string.
    /// - Returns: The JSON string literal.
    static func jsonLiteral(of text: String) throws -> String {
        String(decoding: try JSONEncoder().encode(text), as: UTF8.self)
    }

    /// Gives the JSON text of the tool arguments.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - variables: The JSON value of `variables`, or `nil` to leave out the key.
    ///   - operationName: The text of `operationName`, or `nil` to leave out the key.
    /// - Returns: The arguments as JSON text.
    static func argumentsJSON(
        query document: String,
        variables: String?,
        operationName: String? = nil
    ) throws -> String {
        let variablesMember = variables.map { #", "variables": \#($0)"# } ?? ""
        let operationMember = try operationName.map { name in #", "operationName": \#(try jsonLiteral(of: name))"# }
        return #"{"query": \#(try jsonLiteral(of: document))\#(variablesMember)\#(operationMember ?? "")}"#
    }

    /// Decodes the tool arguments of ``query`` with a `variables` JSON value.
    ///
    /// - Parameter variables: The JSON value of `variables`, or `nil` to leave out the key.
    /// - Returns: The decoded arguments.
    static func arguments(withVariables variables: String?) throws -> KanbanArguments {
        try KanbanArguments(GeneratedContent(json: argumentsJSON(query: query, variables: variables)))
    }

    // MARK: - Variables

    @Test("An object converts directly, and the JSON types are kept")
    func objectKeepsJSONTypes() throws {
        let arguments = try Self.arguments(withVariables: Self.variablesJSON)
        #expect(arguments.query == Self.query)
        #expect(arguments.variables == Self.expectedVariables)
        #expect(arguments.variablesError == nil)
    }

    @Test("A string that holds a JSON object gives the same variables as the object", arguments: textForms)
    func textGivesSameVariables(text: String) throws {
        let arguments = try Self.arguments(withVariables: Self.jsonLiteral(of: text))
        #expect(arguments.variables == Self.expectedVariables)
        #expect(arguments.variablesError == nil)
    }

    @Test("null, an empty string, and no key give no variables and no error", arguments: noVariableForms)
    func noVariables(variables: String?) throws {
        let arguments = try Self.arguments(withVariables: variables)
        #expect(arguments.variables.isEmpty)
        #expect(arguments.variablesError == nil)
    }

    @Test("A value that is not a JSON object sets variablesError, and init does not throw", arguments: invalidForms)
    func invalidVariables(variables: String, received: String) throws {
        let arguments = try Self.arguments(withVariables: variables)
        #expect(arguments.variables.isEmpty)
        #expect(arguments.variablesError == received)
    }

    // MARK: - Query and operation name

    @Test("init throws when the query is missing, and the message tells the caller to send the query")
    func missingQueryThrows() throws {
        let content = try GeneratedContent(json: #"{"variables": {}}"#)
        let error = try #require(throws: KanbanArguments.MissingQueryError.self) {
            try KanbanArguments(content)
        }
        #expect(error.localizedDescription.contains("query"))
    }

    @Test(
        "The operation name is read; no key, an empty name, and a blank name give nil",
        arguments: operationNameForms
    )
    func operationName(sent: String?, decoded: String?) throws {
        let document = "query \(Self.operationName) \(Self.query)"
        let json = try Self.argumentsJSON(query: document, variables: nil, operationName: sent)
        #expect(try KanbanArguments(GeneratedContent(json: json)).operationName == decoded)
    }

    // MARK: - Schema

    @Test("The encoded schema declares variables with anyOf and no type, and requires only the query")
    func variablesSchemaHasAnyOfAndNoType() throws {
        let schema = try KanbanErrorTests.jsonObject(of: KanbanArguments.generationSchema)
        let properties = try #require(schema["properties"] as? [String: Any])
        let property = try #require(properties["variables"] as? [String: Any])
        let reference = try #require(property["$ref"] as? String)
        let definition = try Self.definition(at: reference, in: schema)
        let choices = try #require(definition["anyOf"] as? [[String: Any]])
        #expect(property["type"] == nil)
        #expect(definition["type"] == nil)
        #expect(choices.compactMap { $0["type"] as? String } == ["string"])
        let objectChoices = try choices.compactMap { $0["$ref"] as? String }.map { choice in
            try Self.definition(at: choice, in: schema)
        }
        #expect(objectChoices.map { $0["type"] as? String } == ["object"])
        #expect(objectChoices.map { ($0["properties"] as? [String: Any])?.isEmpty } == [true])
        #expect(schema["required"] as? [String] == ["query"])
    }

    /// Gives the definition that a `$ref` of an encoded schema names, for example `#/$defs/Variables`.
    ///
    /// - Parameters:
    ///   - reference: The value of the `$ref`.
    ///   - schema: The encoded schema, which holds the definitions in `$defs`.
    /// - Returns: The JSON object of the definition.
    static func definition(at reference: String, in schema: [String: Any]) throws -> [String: Any] {
        let definitions = try #require(schema["$defs"] as? [String: Any])
        let name = try #require(reference.split(separator: "/").last.map(String.init))
        return try #require(definitions[name] as? [String: Any])
    }
}
