import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the rule of the virtual tag names in the mutations (plan.md §6, §6.1): a mutation that makes a tag whose
/// slug is the name of a virtual tag gives `INVALID_TAG_NAME` and writes nothing. A `#marker` that names a virtual
/// tag makes no tag. The mutation fields come from ``ReservedSlugTests/Refusal``, with a virtual tag name in place
/// of the reserved name.
@Suite("Tag names that are the names of virtual tags")
struct VirtualTagNameTests {
    /// Each mutation field that makes a tag, with the name or the id that the field gives, and the virtual tag that the
    /// name names. The names are in different cases, because the rule ignores case.
    static let refusals: [(ReservedSlugTests.Refusal, String, VirtualTag)] = [
        (.addTagByName, "Deleted", .deleted),
        (.addTagByName, "blocked", .blocked),
        (.addTagByID, "DONE", .done),
        (.renameTag, "High", .high),
        (.addTaskTag, "done", .done),
        (.updateTaskTag, "Low", .low),
        (.tagTask, "medium", .medium),
    ]

    /// The name of the marker in a body: the name of ``VirtualTag/blocked``, in uppercase.
    static let markerName = VirtualTag.blocked.rawValue

    /// The body that a marker field writes.
    static let markedBody = ReservedSlugTests.Refusal.markedBody(naming: markerName)

    /// Each mutation field that writes a body with a marker, with the bodies of the tasks of the board after the
    /// field, in board order. The fixture task has no body.
    static let markerCases: [(ReservedSlugTests.Refusal, [String])] = [
        (.addTaskMarker, ["", markedBody]),
        (.updateTaskMarker, [markedBody]),
    ]

    /// A query of the tags of the board, and of the body and the tags of each task.
    static let tagsQuery = "{ board { tags { name } tasks { edges { node { body tags { name } } } } } }"

    @Test(
        "A mutation that makes a tag with the name of a virtual tag gives INVALID_TAG_NAME and writes nothing",
        arguments: refusals
    )
    func mutationRefusesVirtualTagName(refusal: ReservedSlugTests.Refusal, name: String, tag: VirtualTag) async throws {
        let directory = try TemporaryDirectory()
        let field = refusal.field(on: try AddUpdateTaskTests.fixtureTask(), naming: name, id: name)
        let error = try await ColumnActorTests.failure(
            of: AddUpdateTaskTests.mutation(of: field),
            after: refusal.setup,
            in: directory
        )
        #expect(error == .virtualTagName(tag: tag))
    }

    @Test("A body marker with the name of a virtual tag makes no tag", arguments: markerCases)
    func markerOfVirtualTagMakesNoTag(field: ReservedSlugTests.Refusal, bodies: [String]) async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let mutation = AddUpdateTaskTests.mutation(of: field.field(on: fixture.task, naming: Self.markerName))
        _ = try await KanbanGraphTests.execute(mutation, on: fixture.graph)
        let response = try await KanbanGraphTests.execute(Self.tagsQuery, on: fixture.graph)
        let edges = bodies.map { body in #"{"node":{"body":"\#(body)","tags":[]}}"# }.joined(separator: ",")
        #expect(response == #"{"data":{"board":{"tags":[],"tasks":{"edges":[\#(edges)]}}}}"#)
        #expect(try ColumnActorTests.patches(of: .tag(slug: Self.markerName.lowercased()), in: directory) == [])
    }
}
