import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the version of a node and the `ifVersion` field of `updateTask` (divergence.md §18).
///
/// The version of a node is the id of the last event of the node, so each write gives a new version. `updateTask` with
/// an `ifVersion` that is not the current version of the task gives `STALE_WRITE`, and writes nothing. Each test uses
/// the fixture logs of ``KanbanGraphTests``: the board, the column `todo`, and one task in `todo`. The test of all node
/// types also adds a comment, the actor of the comment, and a tag.
@Suite("Node version and ifVersion", .watcherBudget)
struct StaleWriteTests {
    /// The title that the first write of a test gives to the fixture task.
    private static let firstTitle = "Port the lexer"

    /// The title that the second write of a test gives to the fixture task.
    private static let secondTitle = "Port the printer"

    /// The selection of an `updateTask` field that reads the title and the version.
    private static let titleAndVersion = "{ title version }"

    /// The text that a test puts around a version to show that the comparison ignores the spaces at the two ends.
    private static let padding = "  "

    /// The code of the error of a stale write.
    private static let staleWriteCode = "STALE_WRITE"

    /// The name of the actor that a test makes as the author of a comment.
    private static let authorName = "Bob Smith"

    /// The name of the tag that a test adds.
    private static let tagName = "bug"

    /// The start of the response key of each `node` field of a query that reads more than one node.
    private static let nodeFieldPrefix = "node"

    // MARK: - Version

    @Test("Task.version is the id of the last event of the task, and a write gives a new version")
    func versionIsLastEventID() async throws {
        let directory = try TemporaryDirectory()
        let task = try AddUpdateTaskTests.fixtureTask()
        let before = try Self.fixtureVersion()
        let update = AddUpdateTaskTests.updateTask(
            task,
            with: #"title: "\#(Self.firstTitle)""#,
            selecting: Self.titleAndVersion
        )
        let response = try await ColumnActorTests.respond(
            to: AddUpdateTaskTests.mutation(of: update),
            onFixtureIn: directory
        )
        let after = try Self.lastEventID(of: .task(task), in: directory)
        #expect(after != before)
        #expect(try Self.version(in: response, ofField: MutationName.updateTask) == after.ulidString)
    }

    @Test("Each node type gives the id of its last event as its version")
    func eachNodeHasVersion() async throws {
        let directory = try TemporaryDirectory()
        let (graph, task) = try ColumnActorTests.makeFixtureGraph(in: directory)
        let setup = AddUpdateTaskTests.mutation(
            of: CommentTests.addComment(
                to: AddUpdateTaskTests.sigilRef(of: task),
                with: #"actor: "\#(Self.authorName)""#
            ),
            TagMutationTests.addTag(named: Self.tagName)
        )
        let setupResponse = try await KanbanGraphTests.execute(setup, on: graph)
        #expect(try CrossRepoWriteTests.hasNoErrors(setupResponse), "\(setupResponse)")
        let refs = try BoardMutationTests.storedRefs(inRepoAt: directory.url).sorted { left, right in
            left.description < right.description
        }
        #expect(Set(refs.map(\.nodeType)) == Set(PatchNodeType.allCases))
        let fields = refs.enumerated().map { index, ref in
            #"\#(Self.nodeField(at: index)): node(id: "\#(ColumnActorTests.id(of: ref))") { version }"#
        }
        let response = try await KanbanGraphTests.execute("{ \(fields.joined(separator: " ")) }", on: graph)
        for (index, ref) in refs.enumerated() {
            let version = try Self.version(in: response, ofField: Self.nodeField(at: index))
            #expect(version == (try Self.lastEventID(of: ref, in: directory).ulidString), "\(ref)")
        }
    }

    // MARK: - ifVersion

    @Test(
        "updateTask with the current version in ifVersion writes; the case and the spaces at the ends do not matter",
        arguments: [false, true]
    )
    func currentVersionWrites(isLoose: Bool) async throws {
        let directory = try TemporaryDirectory()
        let task = try AddUpdateTaskTests.fixtureTask()
        let current = try Self.fixtureVersion().ulidString
        let given = isLoose ? Self.padding + current.lowercased() + Self.padding : current
        let update = AddUpdateTaskTests.updateTask(
            task,
            with: #"title: "\#(Self.firstTitle)", ifVersion: "\#(given)""#,
            selecting: "{ title }"
        )
        let response = try await ColumnActorTests.respond(
            to: AddUpdateTaskTests.mutation(of: update),
            onFixtureIn: directory
        )
        #expect(
            KanbanGraphTests.withoutTransaction(response)
                == #"{"data":{"updateTask":{"title":"\#(Self.firstTitle)"}}}"#
        )
    }

    @Test("updateTask with an old version in ifVersion gives STALE_WRITE with the current version and writes nothing")
    func oldVersionIsRefused() async throws {
        let directory = try TemporaryDirectory()
        let task = try AddUpdateTaskTests.fixtureTask()
        let old = try Self.fixtureVersion().ulidString
        let setup = Self.titleUpdate(of: task, to: Self.firstTitle)
        // The log of the task does not change after the setup, so the call adds no event and no undo entry: the undo
        // log reads only the events.
        let error = try await ColumnActorTests.failure(after: setup, in: directory) { setupResponse in
            let current = try Self.version(in: setupResponse, ofField: MutationName.updateTask)
            #expect(current != old)
            return Self.titleUpdate(of: task, to: Self.secondTitle, input: #"ifVersion: "\#(old)""#)
        }
        let current = try Self.lastEventID(of: .task(task), in: directory).ulidString
        let reference = AddUpdateTaskTests.sigilRef(of: task)
        #expect(error == .staleWrite(task: reference, givenVersion: old, currentVersion: current))
    }

    @Test(
        "updateTask with an old version in an alias of ifVersion gives STALE_WRITE through execute and writes nothing",
        arguments: ["expectedVersion", "version", "etag"]
    )
    func aliasOfOldVersionIsRefused(field: String) async throws {
        let directory = try TemporaryDirectory()
        let task = try AddUpdateTaskTests.fixtureTask()
        let old = try Self.fixtureVersion().ulidString
        let response = try await ColumnActorTests.respondWritingNothing(
            to: Self.titleUpdate(of: task, to: Self.secondTitle, input: #"\#(field): "\#(old)""#),
            after: Self.titleUpdate(of: task, to: Self.firstTitle),
            in: directory
        )
        let errors = try NameRewriteTests.errors(of: response)
        #expect(errors.map(ErrorCoverageTests.code(of:)) == [Self.staleWriteCode])
    }

    @Test("updateTask with no ifVersion writes after a different write changed the task")
    func noVersionWrites() async throws {
        let directory = try TemporaryDirectory()
        let task = try AddUpdateTaskTests.fixtureTask()
        let mutation = AddUpdateTaskTests.mutation(
            of: "first: " + AddUpdateTaskTests.updateTask(task, with: #"title: "\#(Self.firstTitle)""#),
            "second: "
                + AddUpdateTaskTests.updateTask(task, with: #"title: "\#(Self.secondTitle)""#, selecting: "{ title }")
        )
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        let first = AddUpdateTaskTests.idJSON(of: .task(task))
        #expect(
            KanbanGraphTests.withoutTransaction(response)
                == #"{"data":{"first":\#(first),"second":{"title":"\#(Self.secondTitle)"}}}"#
        )
    }

    // MARK: - Helpers

    /// Makes a mutation document with one `updateTask` field that changes the title, and reads the title and the
    /// version.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task.
    ///   - title: The new title.
    ///   - input: The other fields of the `input` object, or `nil` for none.
    /// - Returns: The document.
    private static func titleUpdate(of task: ULID, to title: String, input: String? = nil) -> String {
        let fields = [#"title: "\#(title)""#, input].compactMap(\.self).joined(separator: ", ")
        return AddUpdateTaskTests.mutation(
            of: AddUpdateTaskTests.updateTask(task, with: fields, selecting: titleAndVersion)
        )
    }

    /// Gives the version of the fixture task before a test changes it: the id of the last event of the task in the
    /// fixture logs. The fixture mints its ids from a fixed source, so each copy of the fixture has the same ids.
    ///
    /// - Returns: The event id.
    private static func fixtureVersion() throws -> ULID {
        let directory = try TemporaryDirectory()
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        return try lastEventID(of: .task(task), in: directory)
    }

    /// Gives the id of the last event of a node in the log of the repo.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - directory: The temporary repo directory.
    /// - Returns: The event id.
    private static func lastEventID(of ref: LocalRef, in directory: TemporaryDirectory) throws -> ULID {
        try #require(BoardMutationTests.events(of: ref, inRepoAt: directory.url).last).id
    }

    /// Gives the response key of one `node` field of a query that reads more than one node.
    ///
    /// - Parameter index: The place of the field in the query.
    /// - Returns: The response key.
    private static func nodeField(at index: Int) -> String {
        "\(nodeFieldPrefix)\(index)"
    }

    /// Gives the `version` of the object of one field of the `data` object of a response.
    ///
    /// - Parameters:
    ///   - response: The response JSON text.
    ///   - field: The response key of the field, for example `updateTask`.
    /// - Returns: The version text.
    private static func version(in response: String, ofField field: String) throws -> String {
        try #require(KanbanGraphTests.object(named: field, in: response)["version"] as? String)
    }
}
