import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the stored local form `tag/<slug>` in the tag list of a task mutation (divergence.md R18a). A tag text that
/// starts with `tag/` names the tag with the slug after the `/`, and makes the tag when the board has no such tag. A
/// tag text with a `/` that does not start with `tag/` stays a tag name. The mutation fields come from
/// ``ReservedSlugTests/Refusal``. Each test uses the fixture logs of ``KanbanGraphTests`` in a temporary repo.
@Suite("The stored local form tag/<slug> in the tag list of a task", .watcherBudget)
struct StoredTagRefTests {
    /// The slug of the tag that the stored local form names.
    static let slug = "bug"

    /// The stored local form of the tag ``slug``, as the log stores it: `tag/bug`.
    static let storedForm = LocalRef.tag(slug: slug).description

    /// A tag name with a `/` that does not start with `tag/`.
    static let slashedName = "area/backend"

    /// The slug of ``slashedName``.
    static let slashedSlug = "area-backend"

    /// Each task mutation field that takes a tag list: `addTask`, `updateTask`, and `tagTask`.
    static let tagListFields: [ReservedSlugTests.Refusal] = [.addTaskTag, .updateTaskTag, .tagTask]

    /// Each tag text in the stored local form, with the tag name that the text gives. The type segment ignores case,
    /// and white space at the two ends of the text and of the slug does not change the tag.
    static let storedForms: [(text: String, name: String)] = [
        (storedForm, slug),
        ("Tag/Bug", "Bug"),
        (" tag/ bug ", slug),
    ]

    // MARK: - Helpers

    /// Makes a query of the tags of the board, and of the tags of each task that has a tag.
    ///
    /// - Parameter slug: The slug of the tag that the task filter selects.
    /// - Returns: The query.
    static func tagsQuery(selecting slug: String) -> String {
        ##"{ board { tags { name } tasks(filter: "#\##(slug)") { edges { node { tags { name } } } } } }"##
    }

    /// Gives the response of ``tagsQuery(selecting:)`` when the board has one tag.
    ///
    /// - Parameters:
    ///   - name: The name of the tag of the board.
    ///   - isOnTask: `true` when one task has the tag.
    /// - Returns: The response JSON text.
    static func tagsResponse(named name: String, isOnTask: Bool = true) -> String {
        let tags = #"[{"name":"\#(name)"}]"#
        let edges = isOnTask ? #"{"node":{"tags":\#(tags)}}"# : ""
        return #"{"data":{"board":{"tags":\#(tags),"tasks":{"edges":[\#(edges)]}}}}"#
    }

    /// Runs mutation fields on the fixture repo, and then runs a query of the tags of the board.
    ///
    /// - Parameters:
    ///   - fields: Makes the mutation fields from the ULID of the fixture task.
    ///   - slug: The slug of the tag that the task filter of the query selects.
    ///   - directory: The temporary repo directory.
    /// - Returns: The response JSON text of the query.
    static func boardTags(
        after fields: (ULID) -> [String],
        selecting slug: String,
        in directory: TemporaryDirectory
    ) async throws -> String {
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let mutation = "mutation { \(fields(fixture.task).joined(separator: " ")) }"
        _ = try await KanbanGraphTests.execute(mutation, on: fixture.graph)
        return try await KanbanGraphTests.execute(tagsQuery(selecting: slug), on: fixture.graph)
    }

    // MARK: - Tests

    @Test(
        "A tag text in the stored local form tag/<slug> gives the task the tag with that slug",
        arguments: tagListFields,
        storedForms
    )
    func storedFormNamesTag(field: ReservedSlugTests.Refusal, form: (text: String, name: String)) async throws {
        let directory = try TemporaryDirectory()
        let response = try await Self.boardTags(
            after: { task in [field.field(on: task, naming: form.text)] },
            selecting: Self.slug,
            in: directory
        )
        #expect(response == Self.tagsResponse(named: form.name))
        let tagPatch = try PatchInput(node: .tag(slug: Self.slug), set: [PropertyName.name: .string(form.name)])
        #expect(try ColumnActorTests.patches(of: .tag(slug: Self.slug), in: directory) == [tagPatch])
    }

    @Test("A tag name with a / that does not start with tag/ stays a tag name", arguments: tagListFields)
    func slashedNameStaysTagName(field: ReservedSlugTests.Refusal) async throws {
        let response = try await Self.boardTags(
            after: { task in [field.field(on: task, naming: Self.slashedName)] },
            selecting: Self.slashedSlug,
            in: try TemporaryDirectory()
        )
        #expect(response == Self.tagsResponse(named: Self.slashedName))
    }

    @Test("untagTask with the stored local form tag/<slug> removes the tag with that slug")
    func untagTaskWithStoredForm() async throws {
        let response = try await Self.boardTags(
            after: { task in
                [
                    "a: " + ReservedSlugTests.Refusal.tagTask.field(on: task, naming: Self.slug),
                    "b: " + TaskOperationTests.taskField(
                        "untagTask",
                        of: task,
                        with: TaskOperationTests.tagsInput(Self.storedForm)
                    ),
                ]
            },
            selecting: Self.slug,
            in: try TemporaryDirectory()
        )
        #expect(response == Self.tagsResponse(named: Self.slug, isOnTask: false))
    }

    @Test("The stored local form tag/ with no slug gives INVALID_TAG_NAME with the text as written")
    func storedFormWithNoSlugIsRefused() async throws {
        let text = LocalRef.tag(slug: "").description
        let field = ReservedSlugTests.Refusal.tagTask.field(on: try AddUpdateTaskTests.fixtureTask(), naming: text)
        let error = try await CommentTests.failure(of: field, in: try TemporaryDirectory())
        #expect(error == .invalidTagName(name: text))
    }
}
