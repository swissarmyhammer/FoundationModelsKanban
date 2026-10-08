import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

extension Design {
    /// Tests that a schema change needs no upgrade step (plan.md §4.3, §5.3, §12 item 3): a patch holds only
    /// property values, so a log from a newer or an older version of the tool still replays.
    ///
    /// Each test writes the fixture logs of ``KanbanGraphTests`` and one more task log, and queries the task through
    /// a new engine. A whole response compare also proves that the response has no error.
    @Suite("Design: schema change with no upgrade step")
    struct SchemaChangeTests {
        /// The title of the task that a test writes after the fixture.
        static let title = KanbanGraphTests.laterTitle

        /// Writes a task log after the fixture logs, with one patch.
        ///
        /// - Parameters:
        ///   - values: The `set` part of the patch.
        ///   - directory: The temporary repo directory.
        /// - Returns: The ULID of the task.
        static func writeTask(setting values: [String: PatchValue], in directory: TemporaryDirectory) throws -> ULID {
            var ids = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).ids
            let task = ids.makeULID()
            let patch = try PatchInput(node: .task(task), set: values)
            try KanbanGraphTests.append(patch, mintingFrom: &ids, to: EventLog(repositoryAt: directory.url))
            return task
        }

        /// Queries one task through a new engine of a repo.
        ///
        /// - Parameters:
        ///   - task: The ULID of the task.
        ///   - selection: The selection of the task field.
        ///   - directory: The temporary repo directory.
        /// - Returns: The response JSON text.
        static func respond(
            toQueryOf task: ULID,
            selecting selection: String,
            in directory: TemporaryDirectory
        ) async throws -> String {
            let graph = try KanbanGraphTests.makeGraph(at: directory.url)
            return try await CommentTests.respond(toQueryOf: task, selecting: selection, on: graph)
        }

        @Test("A log line with a property that this version does not know replays, and its known properties apply")
        func unknownPropertyReplays() async throws {
            let directory = try TemporaryDirectory()
            let values = [CommitTests.pointsProperty: CommitTests.pointsValue, PropertyName.title: .string(Self.title)]
            let task = try Self.writeTask(setting: values, in: directory)
            let response = try await Self.respond(toQueryOf: task, selecting: "{ title }", in: directory)
            #expect(response == #"{"data":{"board":{"task":{"title":"\#(Self.title)"}}}}"#)
        }

        @Test("A property that no patch of an old node set gives its default value")
        func newPropertyOnOldNodeGivesDefault() async throws {
            let directory = try TemporaryDirectory()
            let task = try Self.writeTask(setting: [PropertyName.title: .string(Self.title)], in: directory)
            let selection = "{ assignees { id } body column { id } deleted dependsOn { id } ordinal "
                + "progress { completed total } tags { id } }"
            let response = try await Self.respond(toQueryOf: task, selecting: selection, in: directory)
            let column = ColumnActorTests.id(of: KanbanGraphTests.todoColumn)
            let fields = #"{"assignees":[],"body":"","column":{"id":"\#(column)"},"deleted":null,"dependsOn":[],"#
                + #""ordinal":"\#(Ordinal.first.value)","progress":{"completed":0,"total":0},"tags":[]}"#
            #expect(response == #"{"data":{"board":{"task":\#(fields)}}}"#)
        }
    }
}
