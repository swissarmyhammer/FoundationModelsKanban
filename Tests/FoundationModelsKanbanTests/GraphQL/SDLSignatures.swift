import GraphQL

@testable import FoundationModelsKanban

/// The field signatures of the public schema SDL, on one line each and with no descriptions.
///
/// The SDL prints the arguments of a field on many lines when an argument has a description. A test that checks the
/// arguments of a field reads this one-line form, so that the descriptions do not change what the test compares.
enum SDLSignatures {
    /// Gives the signature of each field of each object type and interface of the public schema SDL, for example
    /// `history(filter: String, since: ID, first: Int = 20): [Change!]`.
    ///
    /// - Returns: The signatures, in the order of the SDL.
    /// - Throws: An error when the schema cannot be made, or its SDL does not parse.
    static func ofPublicSchema() throws -> [String] {
        try parse(source: PublicSchema().sdl).definitions.flatMap(fields(of:)).map(signature(of:))
    }

    /// Gives the fields of a definition of the SDL.
    ///
    /// - Parameter definition: The definition.
    /// - Returns: The fields of an object type or an interface, or no field for another definition.
    private static func fields(of definition: any Definition) -> [FieldDefinition] {
        switch definition {
        case let object as ObjectTypeDefinition: object.fields
        case let interface as InterfaceTypeDefinition: interface.fields
        default: []
        }
    }

    /// Prints a field on one line, with no description.
    ///
    /// - Parameter field: The field of the SDL.
    /// - Returns: The name, the arguments in parentheses when the field has arguments, and the type.
    private static func signature(of field: FieldDefinition) -> String {
        let arguments = field.arguments.map { argument in
            let value = argument.defaultValue.map { value in " = \(text(of: value))" } ?? ""
            return "\(argument.name.value): \(text(of: argument.type))\(value)"
        }
        let list = arguments.isEmpty ? "" : "(\(arguments.joined(separator: ", ")))"
        return "\(field.name.value)\(list): \(text(of: field.type))"
    }

    /// Gives the GraphQL text of a node of the SDL, for example `[Task!]` for a type or `20` for a value.
    ///
    /// - Parameter node: The node.
    /// - Returns: The text, as the GraphQL printer writes it.
    private static func text(of node: any GraphQL.Node) -> String {
        // The GraphQL printer gives the text of an AST node; it writes nothing to standard out.
        // swiftlint:disable:next no_direct_standard_out_logs
        GraphQL.print(ast: node)
    }
}
