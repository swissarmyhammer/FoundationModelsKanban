import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the rule of the virtual tag names (plan.md §6, §6.1): no mutation makes a tag whose slug is the name of a
/// virtual tag, because the filter `#<slug>` matches only the virtual tag. A log that already has such a tag still
/// loads, and the filter atom of the name still matches only the virtual tag.
@Suite("Tag slugs that are the names of virtual tags")
struct VirtualTagSlugTests {
    /// The slug of the real tag in the old log, and of the column of the done task: the name of ``VirtualTag/done``.
    static let doneSlug = VirtualTag.done.rawValue.lowercased()

    /// The order of the `done` column in the old log: after the fixture column `todo`, so that `done` is the terminal
    /// column.
    static let doneColumnOrder = 1

    /// The title of the task in the `done` column of the old log.
    static let doneTaskTitle = "Ship the parser"

    // MARK: - Check

    @Test("A tag slug that is the name of a virtual tag gives INVALID_TAG_NAME", arguments: VirtualTag.allCases)
    func tagSlugOfVirtualTagIsRefused(tag: VirtualTag) {
        #expect(throws: KanbanError.virtualTagName(tag: tag)) {
            try LocalRef.tag(slug: tag.rawValue.lowercased()).checkSlugIsNotReserved()
        }
    }

    @Test("A column or an actor can have the slug of a virtual tag name", arguments: [PatchNodeType.column, .actor])
    func columnOrActorSlugOfVirtualTagIsAccepted(type: PatchNodeType) throws {
        let ref = type == .column ? LocalRef.column(slug: Self.doneSlug) : .actor(slug: Self.doneSlug)
        try ref.checkSlugIsNotReserved()
    }

    // MARK: - Old logs

    @Test("A log with a real tag done loads, lists the tag, and #done matches only the tasks of the done column")
    func oldLogWithRealDoneTagLoads() async throws {
        let directory = try TemporaryDirectory()
        try Self.writeOldLog(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let response = try await KanbanGraphTests.execute(
            ##"{ board { tags { name } tasks(filter: "#\##(Self.doneSlug)") { edges { node { title } } } } }"##,
            on: graph
        )
        let tasks = #"{"edges":[{"node":{"title":"\#(Self.doneTaskTitle)"}}]}"#
        #expect(response == #"{"data":{"board":{"tags":[{"name":"\#(Self.doneSlug)"}],"tasks":\#(tasks)}}}"#)
    }

    // MARK: - Helpers

    /// Writes the fixture logs, and then the logs that no mutation can write now: a column `done` after `todo`, a
    /// real tag `done`, a tag edge from the fixture task in `todo` to that tag, and one task in the `done` column.
    ///
    /// - Parameter root: The root directory of the repo.
    private static func writeOldLog(inRepoAt root: URL) throws {
        let fixture = try KanbanGraphTests.writeFixture(inRepoAt: root)
        var ids = fixture.ids
        let log = EventLog(repositoryAt: root)
        let doneColumn = LocalRef.column(slug: Self.doneSlug)
        let doneTag = LocalRef.tag(slug: Self.doneSlug)
        let name: [String: PatchValue] = [PropertyName.name: .string(Self.doneSlug)]
        let order: [String: PatchValue] = [PropertyName.order: .integer(Self.doneColumnOrder)]
        let doneTask: [String: PatchValue] = [
            PropertyName.title: .string(Self.doneTaskTitle),
            PropertyName.column: .ref(.local(doneColumn)),
        ]
        let patches = try [
            PatchInput(node: doneColumn, set: name.merging(order) { first, _ in first }),
            PatchInput(node: doneTag, set: name),
            PatchInput(node: .task(fixture.task), add: [PropertyName.tags: [.local(doneTag)]]),
            PatchInput(node: .task(ids.makeULID()), set: doneTask),
        ]
        for patch in patches {
            try KanbanGraphTests.append(patch, mintingFrom: &ids, to: log)
        }
    }
}
