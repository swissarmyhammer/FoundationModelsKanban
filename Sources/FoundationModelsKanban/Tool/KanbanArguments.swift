import Foundation
import FoundationModels
import GraphQL
import OrderedCollections

/// The arguments of one call of the `kanban` tool: one GraphQL document, the values of its variables, and the
/// operation to run (plan.md §7.1, §12 item 8).
///
/// The decode is forgiving about `variables`. A code-mode script sends a plain object. A model, for example Qwen 3.8
/// (`mlx-community/Qwen3.8-27B-mxfp4`), sends a string that holds a JSON object, sometimes in a code fence. Each of
/// these forms gives the same variables. `null`, an empty object, an empty string, and no key give no variables. Any
/// other value does not make the decode throw: it sets ``variablesError``, and the tool then returns the error
/// `INVALID_VARIABLES`. The decode throws only when the `query` is missing.
///
/// The model test in `IntegrationTests/` uses Qwen 3.8, and Qwen 3.8 sent the string form with the value in 3 of 3
/// runs. The on-device `SystemLanguageModel` sent `"variables": {}` in 3 of 3 runs, because guided generation picked
/// the object choice with no properties (plan.md §7.1).
public struct KanbanArguments: ConvertibleFromGeneratedContent {
    /// The error of a call whose arguments have no `query` text.
    struct MissingQueryError: LocalizedError {
        /// The message of the error: what is wrong, and how to correct the call.
        var errorDescription: String? {
            "The arguments have no query. Send the GraphQL document as text in query."
        }
    }

    /// The result of the decode of the `variables` value.
    private enum DecodedVariables {
        /// The value gives these variables.
        case values([String: Map])

        /// The value is not a JSON object. The text tells what the call sent, for example `a number`.
        case invalid(received: String)
    }

    /// The keys of the arguments object.
    private enum Key {
        /// The key of the GraphQL document.
        static let query = "query"

        /// The key of the values of the variables.
        static let variables = "variables"

        /// The key of the name of the operation to run.
        static let operationName = "operationName"
    }

    /// The text that starts and ends a Markdown code fence.
    private static let fence = "```"

    /// The GraphQL document.
    let query: String

    /// The values of the variables of the document. The map is empty when the call sent no variables, or when the
    /// value was not a JSON object.
    let variables: [String: Map]

    /// What the call sent as `variables` when it is not a JSON object, for example `a number`, or `nil` when the
    /// variables decoded.
    let variablesError: String?

    /// The operation of the document to run, or `nil` when the document has one operation.
    let operationName: String?

    /// The schema of the arguments that the model and Multitool see.
    ///
    /// `variables` is `anyOf` a string and an object with no properties, so its encoded JSON Schema has no `type`.
    /// Multitool checks the `type` of each top-level argument before it calls the tool, and it does not check an
    /// argument with no `type`. Thus, a script can send a plain object. The guide of the string choice asks the model
    /// for one JSON object in text, because the model can make only an empty object from the object choice.
    static let generationSchema: GenerationSchema = {
        let text = DynamicGenerationSchema(type: String.self)
        let object = DynamicGenerationSchema(name: "VariablesObject", properties: [])
        let variables = DynamicGenerationSchema(
            name: "Variables",
            description: "the variables as one JSON object in text",
            anyOf: [text, object]
        )
        let root = DynamicGenerationSchema(
            name: "KanbanArguments",
            description: "One GraphQL request to the kanban task graph.",
            properties: [
                DynamicGenerationSchema.Property(
                    name: Key.query,
                    description: "One GraphQL document: a query or a mutation.",
                    schema: text
                ),
                DynamicGenerationSchema.Property(
                    name: Key.variables,
                    description: "The values of the variables of the document.",
                    schema: variables,
                    isOptional: true
                ),
                DynamicGenerationSchema.Property(
                    name: Key.operationName,
                    description: "The operation of the document to run, when the document has more than one.",
                    schema: text,
                    isOptional: true
                ),
            ]
        )
        do {
            return try GenerationSchema(root: root, dependencies: [])
        } catch {
            preconditionFailure("The schema of the kanban tool arguments is not valid: \(error)")
        }
    }()

    /// Decodes the arguments of one call.
    ///
    /// - Parameter content: The arguments object that the model or the script sent.
    /// - Throws: ``MissingQueryError`` when the content is not an object with a `query` string. A `variables` value
    ///   that is not a JSON object does not throw: it sets ``variablesError``.
    public init(_ content: GeneratedContent) throws {
        guard case .structure(let properties, _) = content.kind,
            case .string(let document)? = properties[Key.query]?.kind
        else {
            throw MissingQueryError()
        }
        query = document
        if case .string(let name)? = properties[Key.operationName]?.kind {
            operationName = name
        } else {
            operationName = nil
        }
        switch Self.decodedVariables(from: properties[Key.variables]) {
        case .values(let values):
            variables = values
            variablesError = nil
        case .invalid(let received):
            variables = [:]
            variablesError = received
        }
    }

    /// Decodes a `variables` value: an object converts directly, and a string is read as JSON text one time.
    ///
    /// - Parameters:
    ///   - content: The value, or `nil` when the arguments have no `variables` key.
    ///   - readsText: `true` to read a string as JSON text. The text of a string is not read again.
    /// - Returns: The variables, or what the call sent when it is not a JSON object.
    private static func decodedVariables(from content: GeneratedContent?, readsText: Bool = true) -> DecodedVariables {
        switch content?.kind {
        case nil, .null?:
            .values([:])
        case .structure(let properties, _)?:
            .values(properties.mapValues(map(of:)))
        case .string(let text)?:
            readsText ? decodedVariables(fromText: text) : .invalid(received: "a string")
        case .bool?:
            .invalid(received: "a boolean")
        case .number?:
            .invalid(received: "a number")
        case .array?:
            .invalid(received: "a list")
        @unknown default:
            .invalid(received: "a value of an unknown kind")
        }
    }

    /// Decodes the JSON text of a `variables` string. The text can have white space and a code fence around it.
    ///
    /// - Parameter text: The text of the string.
    /// - Returns: The variables: none for empty text or JSON `null`. Otherwise what the text holds when it is not a
    ///   JSON object.
    private static func decodedVariables(fromText text: String) -> DecodedVariables {
        let json = unfenced(text)
        guard !json.isEmpty else {
            return .values([:])
        }
        guard let content = try? GeneratedContent(json: json) else {
            return .invalid(received: "text that is not JSON")
        }
        let decoded = decodedVariables(from: content, readsText: false)
        guard case .invalid(let received) = decoded else {
            return decoded
        }
        return .invalid(received: "text that holds \(received)")
    }

    /// Removes the white space and a Markdown code fence around a text. The language tag of the fence, for example
    /// `json`, goes too.
    ///
    /// - Parameter text: The text.
    /// - Returns: The text inside the fence, with no white space around it.
    private static func unfenced(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(fence) else {
            return trimmed
        }
        let body = trimmed.dropFirst(fence.count).drop(while: \.isLetter)
        let inside = body.hasSuffix(fence) ? body.dropLast(fence.count) : body
        return inside.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Converts a JSON value to a GraphQL `Map`, with its JSON type kept. GraphQL input coercion then converts the
    /// value to the type of its variable, for example a JSON number to `Int`.
    ///
    /// - Parameter content: The JSON value.
    /// - Returns: The `Map`. The keys of an object are in sorted order.
    private static func map(of content: GeneratedContent) -> Map {
        switch content.kind {
        case .null:
            .null
        case .bool(let value):
            .bool(value)
        case .number(let value):
            Map(value)
        case .string(let value):
            .string(value)
        case .array(let elements):
            .array(elements.map(map(of:)))
        case .structure(let properties, _):
            .dictionary(OrderedDictionary(uniqueKeysWithValues: properties.sorted { $0.key < $1.key }.map { member in
                (member.key, map(of: member.value))
            }))
        @unknown default:
            .string(content.jsonString)
        }
    }
}
