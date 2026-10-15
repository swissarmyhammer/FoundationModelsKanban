import GraphQL
import Testing

@testable import FoundationModelsKanban

/// Tests the descriptions of the public schema (divergence.md R17): introspection is the way the agent learns the
/// schema (plan.md §12 item 10), so the fields that are not clear from their names must tell what they do.
@Suite("Descriptions of the public schema", .watcherBudget)
struct SchemaDescriptionTests {
    /// The start of the full URI of a node. A dependency on a task of a different board must use this form.
    static let uriScheme = "kanban://"

    /// The sigils of the filter atoms that each `filter` description names (plan.md §6.3).
    static let filterSigils = ["#", "@", "^", "%", "~"]

    /// The `Task` fields that must have a description.
    static let describedTaskFields = ["dependsOn", "blockedBy", "unresolvedDependsOn", "ready", "virtualTags"]

    /// The name of the removed virtual tag of the reverse dependency (divergence.md Q1). No description can name it.
    static let removedVirtualTag = "BLOCKING"

    /// The introspection query that reads the descriptions of the fields of `Task` and of `AddTaskInput`.
    static let introspectionQuery = """
        { task: __type(name: "Task") { fields { name description } } \
        input: __type(name: "AddTaskInput") { inputFields { name description } } }
        """

    // MARK: - Helpers

    /// Runs the introspection query on a fixture board, and reads the description of each field.
    ///
    /// - Returns: The description of each `Task` field and of each `AddTaskInput` field, by the field name. A field
    ///   with no description is not in its map.
    /// - Throws: An error when the response is not the expected JSON.
    static func introspectedDescriptions() async throws -> (task: [String: String], input: [String: String]) {
        let response = try await PublicSchema().respond(
            to: introspectionQuery,
            context: GraphQLEngineTests.makeContext()
        )
        let data = try #require(try KanbanGraphTests.object(of: response)["data"] as? [String: Any])
        let task = try #require(data["task"] as? [String: Any])
        let input = try #require(data["input"] as? [String: Any])
        return (
            try descriptions(of: try #require(task["fields"] as? [[String: Any]])),
            try descriptions(of: try #require(input["inputFields"] as? [[String: Any]]))
        )
    }

    /// Reads the description of each field of an introspection result.
    ///
    /// - Parameter fields: The `fields` or `inputFields` list of a `__type` result.
    /// - Returns: The description of each field, by the field name. A field with no description is not in the map.
    /// - Throws: An error when a field has no name.
    static func descriptions(of fields: [[String: Any]]) throws -> [String: String] {
        var described: [String: String] = [:]
        for field in fields {
            let name = try #require(field["name"] as? String)
            described[name] = field["description"] as? String
        }
        return described
    }

    /// Gives each named type of the public schema.
    ///
    /// - Returns: The types, without the introspection types.
    /// - Throws: An error from Graphiti when the schema cannot be made.
    static func schemaTypes() throws -> [any GraphQLNamedType] {
        try PublicSchema().schema.schema.typeMap.values.filter { type in !type.name.hasPrefix("__") }
    }

    /// Gives each argument and each `input` field of the public schema with a name, with its place.
    ///
    /// - Parameter name: The name of the argument or of the `input` field, for example `filter`.
    /// - Returns: The place (`Type.field(name:)` or `Input.name`) and the description of each one.
    /// - Throws: An error when the schema cannot be made, or a type gives no fields.
    static func inputValues(named name: String) throws -> [(place: String, description: String?)] {
        try schemaTypes().flatMap { type throws -> [(place: String, description: String?)] in
            switch type {
            case let object as GraphQLObjectType:
                try object.fields().compactMap { fieldName, field in
                    field.args[name].map { argument in
                        ("\(object.name).\(fieldName)(\(name):)", argument.description)
                    }
                }
            case let input as GraphQLInputObjectType:
                try input.fields()[name].map { field in [("\(input.name).\(name)", field.description)] } ?? []
            default:
                []
            }
        }
    }

    /// Gives each description of the object types and the `input` types of the public schema: of the types, the
    /// fields, the arguments, and the `input` fields.
    ///
    /// - Returns: The descriptions.
    /// - Throws: An error when the schema cannot be made, or a type gives no fields.
    static func allDescriptions() throws -> [String] {
        try schemaTypes().flatMap { type throws -> [String?] in
            switch type {
            case let object as GraphQLObjectType:
                try [object.description]
                    + object.fields().values.flatMap { field in
                        [field.description] + field.args.values.map(\.description)
                    }
            case let input as GraphQLInputObjectType:
                try [input.description] + input.fields().values.map(\.description)
            default:
                []
            }
        }
        .compactMap { description in description }
    }

    // MARK: - Tests

    @Test("Introspection of Task.dependsOn names the full kanban:// URI of a task on a different board")
    func taskDependsOnNamesTheURI() async throws {
        let description = try #require(try await Self.introspectedDescriptions().task["dependsOn"])
        #expect(description.contains(Self.uriScheme))
    }

    @Test("Introspection of AddTaskInput.dependsOn names the full kanban:// URI of a task on a different board")
    func addTaskDependsOnNamesTheURI() async throws {
        let description = try #require(try await Self.introspectedDescriptions().input["dependsOn"])
        #expect(description.contains(Self.uriScheme))
    }

    @Test("UpdateTaskInput.dependsOn names the full kanban:// URI of a task on a different board")
    func updateTaskDependsOnNamesTheURI() throws {
        let schema = try PublicSchema().schema.schema
        let type = try #require(schema.getType(name: "UpdateTaskInput") as? GraphQLInputObjectType)
        let description = try #require(try type.fields()["dependsOn"]?.description)
        #expect(description.contains(Self.uriScheme))
    }

    @Test("Each derived dependency field of Task has a description")
    func derivedTaskFieldsHaveDescriptions() async throws {
        let described = try await Self.introspectedDescriptions().task
        let missing = Self.describedTaskFields.filter { name in described[name]?.isEmpty ?? true }
        #expect(missing == [])
    }

    @Test("Board.nextTask has a description that names the READY virtual tag")
    func nextTaskHasDescription() throws {
        let schema = try PublicSchema().schema.schema
        let board = try #require(schema.getType(name: GraphQLTypeName.board) as? GraphQLObjectType)
        let description = try #require(try board.fields()["nextTask"]?.description)
        #expect(description.contains(VirtualTag.ready.rawValue))
    }

    @Test("Each filter argument has a description that names each sigil of the filter atoms")
    func filterArgumentsNameTheSigils() throws {
        let filters = try Self.inputValues(named: "filter")
        #expect(filters.count > 1)
        let missing = filters.filter { filter in
            let description = filter.description ?? ""
            return !Self.filterSigils.allSatisfy { sigil in description.contains(sigil) }
        }
        #expect(missing.map(\.place) == [])
    }

    @Test("Each board argument and each board input field has a description that names the board URI")
    func boardArgumentsHaveDescriptions() throws {
        let boards = try Self.inputValues(named: "board")
        #expect(boards.count > 1)
        let missing = boards.filter { board in !(board.description ?? "").contains(Self.uriScheme) }
        #expect(missing.map(\.place) == [])
    }

    @Test("The id argument of Query.board has a description that names the board URI")
    func boardQueryIDHasDescription() throws {
        let query = try #require(PublicSchema().schema.schema.queryType)
        let board = try #require(try query.fields()["board"])
        let argument = try #require(board.args["id"])
        #expect((argument.description ?? "").contains(Self.uriScheme))
    }

    @Test("No description names the removed BLOCKING virtual tag")
    func noDescriptionNamesTheRemovedVirtualTag() throws {
        let descriptions = try Self.allDescriptions()
        #expect(!descriptions.isEmpty)
        #expect(descriptions.filter { description in description.contains(Self.removedVirtualTag) } == [])
    }

    @Test("The schema SDL shows the description of Task.dependsOn")
    func sdlShowsTheDescriptions() async throws {
        let description = try #require(try await Self.introspectedDescriptions().task["dependsOn"])
        #expect(KanbanGraph.schemaSDL.contains(description))
    }
}
