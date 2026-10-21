import GraphQL
import Testing

@testable import FoundationModelsKanban

/// Tests the `input` argument of each public mutation against EXTRAS-9 rule 7: `input` is required also when its type
/// has no required field, so a call that sets no field gives `input: {}`.
///
/// The schema tests read the public schema that ``KanbanGraph/schemaSDL`` prints. The call tests run a document on the
/// fixture board in a temporary directory.
@Suite("Required input of the mutations", .watcherBudget)
struct MutationInputSchemaTests {
    /// The name of the one argument of each public mutation.
    private static let inputArgument = "input"

    /// The mutations whose `input` type has no required field, sorted by name.
    static let mutationsWithNoRequiredField = [
        MutationName.addActor, MutationName.addTag, MutationName.collectBoards, MutationName.initBoard,
        MutationName.redoChange, MutationName.repairLinks, MutationName.undoChange, MutationName.updateBoard,
    ]

    // MARK: - Helpers

    /// Tells if a type of an argument or of an `input` field is required: the type is non-null and has no default.
    ///
    /// - Parameters:
    ///   - type: The type of the argument or of the field.
    ///   - defaultValue: The default value, or `nil` when there is none.
    /// - Returns: `true` when a caller must give the value.
    private static func isRequired(_ type: any GraphQLInputType, defaultValue: Map?) -> Bool {
        type is GraphQLNonNull && defaultValue == nil
    }

    /// Gives the `input` argument of each public mutation whose `input` type has no required field.
    ///
    /// - Returns: The name of each of these mutations, with its `input` argument.
    /// - Throws: An error when the schema cannot be made, or a type gives no fields.
    private static func inputArgumentsWithNoRequiredField() throws -> [(mutation: String, input: GraphQLArgument)] {
        let mutation = try #require(PublicSchema().schema.schema.mutationType)
        return try mutation.fields()
            .compactMap { name, field in field.args[inputArgument].map { input in (name, input) } }
            .filter { _, input in try hasNoRequiredField(input) }
    }

    /// Tells if the `input` type of an argument has no required field.
    ///
    /// - Parameter argument: The `input` argument of a mutation.
    /// - Returns: `true` when each field of the `input` type is optional.
    /// - Throws: An error when the argument type is not an `input` object type, or the type gives no fields.
    private static func hasNoRequiredField(_ argument: GraphQLArgument) throws -> Bool {
        let type = try #require(getNamedType(type: argument.type) as? GraphQLInputObjectType)
        return try type.fields().values.allSatisfy { field in !isRequired(field.type, defaultValue: field.defaultValue) }
    }

    // MARK: - Tests

    @Test("Each mutation whose input has no required field still takes a required input")
    func inputWithNoRequiredFieldIsRequired() throws {
        let arguments = try Self.inputArgumentsWithNoRequiredField()
        #expect(arguments.map(\.mutation).sorted() == Self.mutationsWithNoRequiredField)
        let optionalInputs = arguments.filter { _, input in !Self.isRequired(input.type, defaultValue: input.defaultValue) }
        #expect(optionalInputs.map(\.mutation) == [])
    }

    @Test("The schema SDL shows the input of addTag as required")
    func addTagInputIsRequiredInSDL() throws {
        #expect(try SDLSignatures.ofPublicSchema().contains("addTag(input: AddTagInput!): Tag"))
    }

    @Test(
        "A call with no input argument fails validation, also when the input type has no required field",
        arguments: mutationsWithNoRequiredField
    )
    func callWithNoInputFailsValidation(mutation: String) async throws {
        try await ErrorCoverageTests.expectRequestFailure(
            of: "mutation { \(mutation) { __typename } }",
            coded: "GRAPHQL_VALIDATION_FAILED"
        )
    }
}
