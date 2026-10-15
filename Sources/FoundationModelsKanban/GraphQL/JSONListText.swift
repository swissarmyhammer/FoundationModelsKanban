import Foundation
import GraphQL

/// A JSON array of strings that the caller sends as one string for a list field (divergence.md Q13, N6).
///
/// Rust accepts `"[\"a\",\"b\"]"` for `tags`, `depends_on`, and `assignees`, so an agent sends a list in this form.
/// The name rewrite gives the items of the array to each list position: an argument or an `input` field whose type is
/// a list, and a variable whose declared type is a list. A string that is not a JSON array of strings stays one
/// string, and GraphQL input coercion makes it a list of one item.
enum JSONListText {
    /// Gives the items of a text that is a JSON array of strings.
    ///
    /// - Parameter text: The text, for example `["bug","ui"]`.
    /// - Returns: The items, or `nil` when the text is not a JSON array of strings.
    static func items(of text: String) -> [String]? {
        try? JSONDecoder().decode([String].self, from: Data(text.utf8))
    }

    /// Gives a value of a variable with the items of the array when the value is a string that is a JSON array of
    /// strings.
    ///
    /// - Parameter value: The value of a list position.
    /// - Returns: The array of the items, or `value` when it is not such a string.
    static func splitting(_ value: Map) -> Map {
        guard case .string(let text) = value, let items = items(of: text) else {
            return value
        }
        return .array(items.map(Map.string))
    }

    /// Gives the GraphQL list literal of a string literal that is a JSON array of strings.
    ///
    /// JSON string syntax is GraphQL string syntax, and commas in a GraphQL list are optional separators, so the JSON
    /// text of the items is a GraphQL list literal.
    ///
    /// - Parameter value: A value of a list position in the document.
    /// - Returns: The list literal, or `nil` when the value is not a string literal that is a JSON array of strings.
    static func listLiteral(of value: any GraphQL.Value) -> String? {
        guard let string = value as? StringValue, let items = items(of: string.value),
              let encoded = try? JSONEncoder().encode(items)
        else {
            return nil
        }
        return String(decoding: encoded, as: UTF8.self)
    }

    /// Tells if an input type of the schema is a list type, also under a non-null type.
    ///
    /// - Parameter type: The input type, or `nil` when the type is not known.
    /// - Returns: `true` for a list type.
    static func isList(_ type: (any GraphQLInputType)?) -> Bool {
        switch type {
        case let nonNull as GraphQLNonNull:
            nonNull.ofType is GraphQLList
        case is GraphQLList:
            true
        default:
            false
        }
    }

    /// Tells if a type of the syntax tree is a list type, also under a non-null type.
    ///
    /// - Parameter type: The type as the document declares it.
    /// - Returns: `true` for a list type, for example `[String!]` or `[ID!]!`.
    static func isList(_ type: any GraphQL.`Type`) -> Bool {
        switch type {
        case let nonNull as NonNullType:
            nonNull.type is ListType
        case is ListType:
            true
        default:
            false
        }
    }
}
