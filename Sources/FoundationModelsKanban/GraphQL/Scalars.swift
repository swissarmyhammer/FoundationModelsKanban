import FoundationModelsExtras
import Graphiti

/// The text of a GraphQL `ID` (plan.md §3.2).
///
/// In output, the text is always the full URI of a node, for example `kanban://<board-key>/task/01K6Z3…`. In input,
/// the text can also be a short form, and ``RefResolver`` reads it. The Codable form is the text, so the default
/// Graphiti scalar closures serialize and parse the value.
struct NodeID: Codable, Sendable, Hashable {
    /// The GraphQL name of the scalar: the built-in `ID` name.
    static let name = "ID"

    /// The text of the id.
    let text: String
}

extension NodeID {
    /// Decodes the id from its text.
    ///
    /// - Parameter decoder: The decoder that holds the text.
    /// - Throws: A `DecodingError` when the value is not text.
    init(from decoder: any Decoder) throws {
        try self.init(text: decoder.singleValueContainer().decode(String.self))
    }

    /// Encodes the id as its text.
    ///
    /// - Parameter encoder: The encoder that gets the text.
    /// - Throws: An error from the encoder.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}

extension SchemaBuilder {
    /// Adds the `ID` scalar, the `DateTime` and `JSON` scalars of the toolkit, and the `Priority` scalar, in this
    /// order.
    ///
    /// Graphiti maps no Swift type to the built-in `ID` scalar, so ``NodeID`` is a scalar with that name. The
    /// schema does not refer to the built-in scalar, so the two do not collide. ``PriorityValue`` keeps the text of
    /// each priority value, whatever its GraphQL kind.
    ///
    /// - Returns: This builder, for method chaining.
    @discardableResult
    func addKanbanScalars() -> Self {
        add {
            Scalar(NodeID.self, as: NodeID.name)
        }
        .addToolkitScalars()
        .add {
            Scalar(
                PriorityValue.self,
                as: PriorityValue.name,
                parseValue: PriorityValue.parseValue,
                parseLiteral: PriorityValue.parseLiteral
            )
        }
    }
}
