import Foundation
import GraphQL
import Testing

@testable import FoundationModelsKanban

/// Tests the Rust fields that the schema has again (divergence.md Q19): the actor `avatar`, the board `model`, the
/// `totalActors` count of the board summary, the `taskCount` and the `readyCount` of each column, the `percent` of the
/// progress of a task, and the `color` and the `description` of each virtual tag.
///
/// Each test uses a temporary repo with the fixture logs of ``KanbanGraphTests``: the board, the column `todo`, and
/// one task in `todo`. The column `todo` is the only column, so it is the terminal column.
@Suite("Rust fields: avatar, model, counts, percent, and virtual tag metadata", .watcherBudget)
struct RustFieldTests {
    /// The slug of the actor that a test adds. The input gives no name, so the slug is also the name.
    static let actorSlug = "x"

    /// The local ref of the actor that a test adds.
    static let actor = LocalRef.actor(slug: actorSlug)

    /// The avatar that a test gives to the actor.
    static let robotAvatar = "https://example.com/robot.png"

    /// The avatar of the actor after the update test.
    static let catAvatar = "https://example.com/cat.png"

    /// The model that a test gives to the board.
    static let haiku = "haiku"

    /// The model of the board after the update test.
    static let opus = "opus"

    /// The mutation field that adds the actor ``actorSlug`` with ``robotAvatar`` and no name.
    static let addActorField = #"addActor(input: { id: "\#(actorSlug)", avatar: "\#(robotAvatar)" }) "#
        + "{ id name avatar }"

    /// The body of a task with one checked item and one open item.
    static let halfDoneBody = #"- [x] read the grammar\n- [ ] write the parser\n"#

    /// The percent of ``halfDoneBody``.
    static let halfPercent = 50.0

    /// The number of percent units in a whole.
    static let percentScale = 100.0

    /// The number of actors after the add test: the added actor and the session actor.
    static let actorsAfterAdd = 2

    /// The new fields of the output types, and of the input types, that must have a description, by type name.
    static let describedFields: [String: [String]] = [
        "Actor": ["avatar"],
        "Board": ["model", "virtualTags"],
        "Column": ["taskCount", "readyCount"],
        "BoardSummary": ["totalActors"],
        "Progress": ["percent"],
        "VirtualTag": ["name", "color", "description"],
        "AddActorInput": ["avatar"],
        "UpdateActorInput": ["avatar"],
        "BoardInput": ["model"],
    ]

    // MARK: - Helpers

    /// Gives the description of each field of an object type or an `input` type of the public schema.
    ///
    /// - Parameter name: The name of the type.
    /// - Returns: The description of each field, by the field name. A field with no description has `nil`.
    /// - Throws: An error when the schema cannot be made, or has no object type or `input` type with the name.
    static func fieldDescriptions(ofType name: String) throws -> [String: String?] {
        let type = try PublicSchema().schema.schema.typeMap[name]
        switch type {
        case let object as GraphQLObjectType:
            let pairs = try object.fields().map { name, field in (name, field.description) }
            return Dictionary(uniqueKeysWithValues: pairs)
        case let input as GraphQLInputObjectType:
            let pairs = try input.fields().map { name, field in (name, field.description) }
            return Dictionary(uniqueKeysWithValues: pairs)
        default:
            Issue.record("The public schema has no object or input type \(name)")
            return [:]
        }
    }

    // MARK: - Actor avatar

    @Test("addActor with an id and an avatar stores the avatar, and Actor.avatar reads it")
    func addActorStoresAvatar() async throws {
        let directory = try TemporaryDirectory()
        let response = try await ColumnActorTests.respond(
            to: "mutation { \(Self.addActorField) }",
            onFixtureIn: directory
        )
        let actor = #"{"avatar":"\#(Self.robotAvatar)","id":"\#(ColumnActorTests.id(of: Self.actor))","#
            + #""name":"\#(Self.actorSlug)"}"#
        #expect(response == #"{"data":{"addActor":\#(actor)}}"#)
        let set: [String: PatchValue] = [
            PropertyName.name: .json(.string(Self.actorSlug)),
            PropertyName.avatar: .json(.string(Self.robotAvatar)),
        ]
        #expect(try ColumnActorTests.patches(of: Self.actor, in: directory) == [PatchInput(node: Self.actor, set: set)])
    }

    @Test("A new engine reads the avatar that addActor wrote")
    func newEngineReadsAvatar() async throws {
        let directory = try TemporaryDirectory()
        _ = try await ColumnActorTests.respond(to: "mutation { \(Self.addActorField) }", onFixtureIn: directory)
        let fresh = try KanbanGraphTests.makeGraph(at: directory.url)
        let query = #"{ node(id: "\#(ColumnActorTests.id(of: Self.actor))") { ... on Actor { avatar } } }"#
        let response = try await KanbanGraphTests.execute(query, on: fresh)
        #expect(response == #"{"data":{"node":{"avatar":"\#(Self.robotAvatar)"}}}"#)
    }

    @Test("updateActor changes the avatar, and a null avatar writes an unset of the avatar")
    func updateActorChangesAndClearsAvatar() async throws {
        let directory = try TemporaryDirectory()
        let change = #"first: updateActor(input: { id: "\#(Self.actorSlug)", avatar: "\#(Self.catAvatar)" }) "#
            + "{ avatar }"
        let clear = #"second: updateActor(input: { id: "\#(Self.actorSlug)", avatar: null }) { avatar name }"#
        let mutation = "mutation { \(Self.addActorField) \(change) \(clear) }"
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        let changed = #""first":{"avatar":"\#(Self.catAvatar)"}"#
        let cleared = #""second":{"avatar":null,"name":"\#(Self.actorSlug)"}"#
        #expect(response.hasSuffix(#"\#(changed),\#(cleared)}}"#))
        let expected = try PatchInput(node: Self.actor, unset: [PropertyName.avatar])
        #expect(try ColumnActorTests.patches(of: Self.actor, in: directory).last == expected)
    }

    @Test("An actor that no patch gave an avatar has a null avatar")
    func actorWithNoAvatarHasNull() async throws {
        let directory = try TemporaryDirectory()
        let mutation = #"mutation { addActor(input: { name: "Bob" }) { avatar } }"#
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        #expect(response == #"{"data":{"addActor":{"avatar":null}}}"#)
    }

    @Test("addActor with no id and no name gives INVALID_SLUG", arguments: [
        "mutation { addActor { id } }",
        #"mutation { addActor(input: { avatar: "\#(robotAvatar)" }) { id } }"#,
    ])
    func addActorWithNoIDAndNoName(mutation: String) async throws {
        let directory = try TemporaryDirectory()
        let error = try await ColumnActorTests.failure(of: mutation, in: directory)
        #expect(error == .invalidSlug(name: ""))
    }

    @Test("addActor takes image as a name of the avatar, so an agent that writes image gets the avatar")
    func addActorTakesImageAlias() async throws {
        let directory = try TemporaryDirectory()
        let mutation = #"mutation { addActor(input: { id: "\#(Self.actorSlug)", image: "\#(Self.robotAvatar)" }) "#
            + "{ avatar } }"
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        #expect(response.contains(#"{"addActor":{"avatar":"\#(Self.robotAvatar)"}}"#))
    }

    // MARK: - Board model

    @Test("initBoard with a model stores the model, and Board.model reads it")
    func initBoardStoresModel() async throws {
        let directory = try TemporaryDirectory()
        let mutation = #"mutation { initBoard(input: { model: "\#(Self.haiku)" }) { model } }"#
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        #expect(response == #"{"data":{"initBoard":{"model":"\#(Self.haiku)"}}}"#)
        let expected = try PatchInput(node: .board, set: [PropertyName.model: .json(.string(Self.haiku))])
        #expect(try ColumnActorTests.patches(of: .board, in: directory).last == expected)
    }

    @Test("A new engine reads the model that updateBoard wrote")
    func newEngineReadsModel() async throws {
        let directory = try TemporaryDirectory()
        let mutation = #"mutation { updateBoard(input: { model: "\#(Self.opus)" }) { model } }"#
        _ = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        let fresh = try KanbanGraphTests.makeGraph(at: directory.url)
        let response = try await KanbanGraphTests.execute("{ board { model } }", on: fresh)
        #expect(response == #"{"data":{"board":{"model":"\#(Self.opus)"}}}"#)
    }

    @Test("A board that no patch gave a model has a null model, and a null model writes an unset of the model")
    func nullModelClearsModel() async throws {
        let directory = try TemporaryDirectory()
        let mutation = #"mutation { first: updateBoard { model } "#
            + #"second: updateBoard(input: { model: "\#(Self.haiku)" }) { model } "#
            + "third: updateBoard(input: { model: null }) { model } }"
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        let expected = #"{"first":{"model":null},"second":{"model":"\#(Self.haiku)"},"third":{"model":null}}"#
        #expect(response == #"{"data":\#(expected)}"#)
        let unset = try PatchInput(node: .board, unset: [PropertyName.model])
        #expect(try ColumnActorTests.patches(of: .board, in: directory).last == unset)
    }

    // MARK: - Counts and percent

    @Test("summary { totalActors } counts the live actors of the board")
    func summaryCountsActors() async throws {
        let directory = try TemporaryDirectory()
        let mutation = "mutation { \(Self.addActorField) } "
        let graph = try ColumnActorTests.makeFixtureGraph(in: directory).graph
        _ = try await KanbanGraphTests.execute(mutation, on: graph)
        let response = try await KanbanGraphTests.execute("{ board { summary { totalActors } } }", on: graph)
        #expect(response == #"{"data":{"board":{"summary":{"totalActors":\#(Self.actorsAfterAdd)}}}}"#)
    }

    @Test("Each column gives taskCount and readyCount of its live tasks")
    func columnGivesTaskAndReadyCounts() async throws {
        let directory = try TemporaryDirectory()
        let query = "{ board { columns { taskCount readyCount } } }"
        let response = try await ColumnActorTests.respond(to: query, onFixtureIn: directory)
        #expect(response == #"{"data":{"board":{"columns":[{"readyCount":1,"taskCount":1}]}}}"#)
    }

    @Test("Progress.percent is the fraction times 100")
    func progressGivesPercent() async throws {
        let directory = try TemporaryDirectory()
        let (graph, task) = try ColumnActorTests.makeFixtureGraph(in: directory)
        let update = AddUpdateTaskTests.updateTask(task, with: #"body: "\#(Self.halfDoneBody)""#)
        _ = try await KanbanGraphTests.execute(AddUpdateTaskTests.mutation(of: update), on: graph)
        let query = "{ board { tasks { nodes { progress { fraction percent } } } } }"
        let data = try KanbanGraphTests.data(of: try await KanbanGraphTests.execute(query, on: graph))
        let board = try #require(data["board"] as? [String: Any])
        let tasks = try #require(board["tasks"] as? [String: Any])
        let node = try #require((tasks["nodes"] as? [[String: Any]])?.first)
        let progress = try #require(node["progress"] as? [String: Any])
        let fraction = try #require(progress["fraction"] as? Double)
        #expect(progress["percent"] as? Double == Self.halfPercent)
        #expect(progress["percent"] as? Double == fraction * Self.percentScale)
    }

    // MARK: - Virtual tags

    @Test("Board.virtualTags gives the name, the color, and the description of each virtual tag")
    func boardGivesVirtualTagMetadata() async throws {
        let directory = try TemporaryDirectory()
        let query = "{ board { virtualTags { name color description } } }"
        let data = try KanbanGraphTests.data(of: try await ColumnActorTests.respond(to: query, onFixtureIn: directory))
        let board = try #require(data["board"] as? [String: Any])
        let tags = try #require(board["virtualTags"] as? [[String: String]])
        let expected = VirtualTag.allCases.map { tag in
            ["name": tag.rawValue, "color": tag.color, "description": tag.explanation]
        }
        #expect(tags == expected)
    }

    // MARK: - Change feed

    @Test("The history of the board gives a field change of the avatar and of the model", arguments: [
        (#"updateActor(input: { id: "\#(actorSlug)", avatar: "\#(catAvatar)" }) { id }"#, "avatar", catAvatar),
        (#"updateBoard(input: { model: "\#(haiku)" }) { id }"#, "model", haiku),
    ])
    func historyGivesFieldChange(field: String, name: String, value: String) async throws {
        let directory = try TemporaryDirectory()
        let graph = try ColumnActorTests.makeFixtureGraph(in: directory).graph
        _ = try await KanbanGraphTests.execute("mutation { \(Self.addActorField) }", on: graph)
        _ = try await KanbanGraphTests.execute("mutation { \(field) }", on: graph)
        let query = "{ board { history { updates { fields { name after } } } } }"
        let data = try KanbanGraphTests.data(of: try await KanbanGraphTests.execute(query, on: graph))
        let board = try #require(data["board"] as? [String: Any])
        let changes = try #require(board["history"] as? [[String: Any]])
        let updates = changes.compactMap { change in change["updates"] as? [[String: Any]] }.joined()
        let fields = updates.compactMap { update in update["fields"] as? [[String: Any]] }.joined()
        let isExpected: ([String: Any]) -> Bool = { change in
            change["name"] as? String == name && change["after"] as? String == value
        }
        #expect(fields.contains(where: isExpected))
    }

    // MARK: - Schema

    @Test("Each new field of the schema has a description", arguments: describedFields.keys.sorted())
    func newFieldsHaveDescriptions(type: String) throws {
        let descriptions = try Self.fieldDescriptions(ofType: type)
        for field in Self.describedFields[type] ?? [] {
            let description = try #require(descriptions[field], "\(type).\(field) is not in the schema")
            #expect(description?.isEmpty == false, "\(type).\(field) has no description")
        }
    }
}
