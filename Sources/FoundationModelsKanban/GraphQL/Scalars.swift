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
    /// Decodes the id from its text, or from an integer, as the GraphQL `ID` input rule gives (divergence.md §30).
    /// Thus `item: 2` and `item: "2"` give the same id.
    ///
    /// - Parameter decoder: The decoder that holds the text or the integer.
    /// - Throws: A `DecodingError` when the value is not text and not an integer.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let text = try? container.decode(String.self) else {
            try self.init(text: String(container.decode(Int.self)))
            return
        }
        self.init(text: text)
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
            .description(SchemaDescription.priority)
        }
    }
}
