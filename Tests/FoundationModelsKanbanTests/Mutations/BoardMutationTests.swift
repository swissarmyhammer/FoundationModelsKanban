import Foundation
import GraphQL
import Testing

@testable import FoundationModelsKanban

/// Tests the board mutations, the auto-init of a board, and the session actor (plan.md §4.2, §6).
///
/// These tests are the GraphQL form of the Rust auto-init and session actor dispatch tests. Each test uses a
/// temporary repo directory, the fake board key, the fixed clock, and the fixed ULID source of
/// ``KanbanGraphTests``.
@Suite("Board mutations, auto-init, and session actor")
struct BoardMutationTests {
    /// The name that a test gives to the board.
    static let boardName = "My Board"

    /// The body that a test gives to the board.
    static let boardBody = "A nice board"

    /// The `input` argument that gives ``boardName`` and ``boardBody``.
    static let boardInput = #"input: { name: "\#(boardName)", body: "\#(boardBody)" }"#

    /// The JSON of a board with ``boardName`` and ``boardBody`` in a response that selects `name body`.
    static let boardJSON = #"{"body":"\#(boardBody)","name":"\#(boardName)"}"#

    /// The body of the board before a test changes it.
    static let firstBody = "parse the filter\nport the evaluator\n"

    /// The body of the board after a test changes it.
    static let secondBody = "parse the filter\nport the parser\n"

    /// The name of the session actor of the named-actor test.
    static let namedActor = "Test Actor"

    /// The local refs of the four default columns.
    static let defaultColumns: Set<LocalRef> = [
        .column(slug: "todo"), .column(slug: "doing"), .column(slug: "review"), .column(slug: "done"),
    ]

    /// The JSON of the four default columns in a response that selects `columns { name order }`.
    static let defaultColumnsJSON = #"[{"name":"To Do","order":0},{"name":"Doing","order":1},"#
        + #"{"name":"Review","order":2},{"name":"Done","order":3}]"#

    /// The JSON of the session actor of ``KanbanGraphTests`` in a response that selects `actors { id name }`.
    static let sessionActorJSON = actorsJSON(of: KanbanGraphTests.sessionActor)

    /// The local refs of the nodes that the auto-init writes: the board, the four default columns, and the session
    /// actor of ``KanbanGraphTests``.
    static let initializedRefs = defaultColumns.union([.board, ReplayTests.actor])

    // MARK: - Helpers

    /// Gives the local refs of the node logs of a repo.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The local ref of each node that has a log file.
    static func storedRefs(inRepoAt root: URL) throws -> Set<LocalRef> {
        Set(try EventLog(repositoryAt: root).nodeFileSignatures().keys)
    }

    /// Gives the events of the log of a node.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - root: The root directory of the repo.
    /// - Returns: The events, in the order of their ids.
    static func events(of ref: LocalRef, inRepoAt root: URL) throws -> [Event] {
        try EventLog(repositoryAt: root).readLog(of: ref).events
    }

    /// Gives the JSON of one actor in a response that selects `actors { id name }`.
    ///
    /// - Parameter actor: The actor.
    /// - Returns: The JSON list that holds the actor.
    static func actorsJSON(of actor: SessionActor) -> String {
        let id = NodeURI(boardKey: KanbanGraphTests.boardKey.description, ref: actor.ref).description
        return #"[{"id":"\#(id)","name":"\#(actor.name)"}]"#
    }

    /// Runs one mutation on the empty repo of a temporary directory, with a session actor.
    ///
    /// - Parameters:
    ///   - mutation: The GraphQL document.
    ///   - actor: The session actor of the engine.
    ///   - directory: The temporary directory.
    /// - Returns: The root directory of the repo, and the response JSON text.
    static func execute(
        _ mutation: String,
        actingAs actor: SessionActor = KanbanGraphTests.sessionActor,
        onEmptyRepoIn directory: TemporaryDirectory
    ) async throws -> (root: URL, response: String) {
        let root = try KanbanGraphTests.makeEmptyRepo(in: directory)
        let graph = try KanbanGraphTests.makeGraph(at: root, actingAs: actor)
        return (root, try await KanbanGraphTests.execute(mutation, on: graph))
    }

    // MARK: - Auto-init

    @Test("The first mutation in an empty repo makes the board, the 4 default columns, and the session actor")
    func firstMutationInitializesBoard() async throws {
        let directory = try TemporaryDirectory()
        let mutation = #"mutation { updateBoard(input: { body: "Plan" }) "#
            + "{ name body columns { name order } actors { id name } } }"
        let (root, response) = try await Self.execute(mutation, onEmptyRepoIn: directory)
        let board = #"{"actors":\#(Self.sessionActorJSON),"body":"Plan","columns":\#(Self.defaultColumnsJSON),"#
            + #""name":"\#(KanbanGraphTests.emptyRepoName)"}"#
        #expect(response == #"{"data":{"updateBoard":\#(board)}}"#)
        #expect(try Self.storedRefs(inRepoAt: root) == Self.initializedRefs)
    }

    @Test("A new engine reads the board, the columns, and the actor that the auto-init wrote")
    func autoInitIsWrittenToTheLog() async throws {
        let directory = try TemporaryDirectory()
        let selection = "name columns { name order } actors { id name }"
        let (root, response) = try await Self.execute(
            "mutation { initBoard { \(selection) } }",
            onEmptyRepoIn: directory
        )
        let fresh = try KanbanGraphTests.makeGraph(at: root)
        let query = try await KanbanGraphTests.execute("{ board { \(selection) } }", on: fresh)
        #expect(query == response.replacingOccurrences(of: "initBoard", with: "board"))
    }

    @Test("initBoard with no input on an empty repo makes the board with the name of the repo directory")
    func initBoardWithNoInput() async throws {
        let directory = try TemporaryDirectory()
        let (root, response) = try await Self.execute(
            "mutation { initBoard { name columns { name order } } }",
            onEmptyRepoIn: directory
        )
        let board = #"{"columns":\#(Self.defaultColumnsJSON),"name":"\#(KanbanGraphTests.emptyRepoName)"}"#
        #expect(response == #"{"data":{"initBoard":\#(board)}}"#)
        #expect(try Self.storedRefs(inRepoAt: root) == Self.initializedRefs)
    }

    @Test("initBoard with a name and a body writes one board patch with the name and the body diff")
    func initBoardWithNameAndBody() async throws {
        let directory = try TemporaryDirectory()
        let (root, response) = try await Self.execute(
            "mutation { initBoard(\(Self.boardInput)) { name body } }",
            onEmptyRepoIn: directory
        )
        #expect(response == #"{"data":{"initBoard":\#(Self.boardJSON)}}"#)
        let expected = try PatchInput(
            node: .board,
            set: ["name": .json(.string(Self.boardName))],
            edit: PatchEdit(body: UnifiedDiff(from: "", to: Self.boardBody).text)
        )
        #expect(try Self.events(of: .board, inRepoAt: root).map(\.patch) == [expected])
    }

    @Test("initBoard on a board that exists writes only the given fields that differ, and adds no column")
    func initBoardOnExistingBoard() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let refsBefore = try Self.storedRefs(inRepoAt: directory.url)
        let boardEventsBefore = try Self.events(of: .board, inRepoAt: directory.url)
        let input = #"input: { name: "\#(KanbanGraphTests.boardName)", body: "\#(Self.boardBody)" }"#
        let mutation = "mutation { initBoard(\(input)) { name body columns { name } } }"
        let response = try await KanbanGraphTests.execute(mutation, on: KanbanGraphTests.makeGraph(at: directory.url))
        let columns = #"[{"name":"\#(KanbanGraphTests.todoName)"}]"#
        let board = #"{"body":"\#(Self.boardBody)","columns":\#(columns),"#
            + #""name":"\#(KanbanGraphTests.boardName)"}"#
        #expect(response == #"{"data":{"initBoard":\#(board)}}"#)
        let written = try Self.events(of: .board, inRepoAt: directory.url).dropFirst(boardEventsBefore.count)
        let diff = UnifiedDiff(from: "", to: Self.boardBody).text
        let expected = try PatchInput(node: .board, edit: PatchEdit(body: diff))
        #expect(written.map(\.patch) == [expected])
        #expect(try Self.storedRefs(inRepoAt: directory.url) == refsBefore.union([ReplayTests.actor]))
    }

    // MARK: - No-op and body

    @Test("A mutation that changes nothing writes no patch, and also no actor patch")
    func noOpMutationWritesNothing() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let log = EventLog(repositoryAt: directory.url)
        let before = try log.nodeFileSignatures()
        let mutation = "mutation { initBoard { name } "
            + #"updateBoard(input: { name: "\#(KanbanGraphTests.boardName)" }) { name } }"#
        let response = try await KanbanGraphTests.execute(mutation, on: KanbanGraphTests.makeGraph(at: directory.url))
        let name = #"{"name":"\#(KanbanGraphTests.boardName)"}"#
        #expect(response == #"{"data":{"initBoard":\#(name),"updateBoard":\#(name)}}"#)
        #expect(try log.nodeFileSignatures() == before)
    }

    @Test("updateBoard sets the name and the body of the board")
    func updateBoardSetsNameAndBody() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let mutation = "mutation { updateBoard(\(Self.boardInput)) { name body } }"
        let response = try await KanbanGraphTests.execute(mutation, on: KanbanGraphTests.makeGraph(at: directory.url))
        #expect(response == #"{"data":{"updateBoard":\#(Self.boardJSON)}}"#)
    }

    @Test("A body input writes an edit patch with the diff from the current body, and no set of the body")
    func bodyInputWritesDiffFromCurrentBody() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let mutation = "mutation($body: String) { updateBoard(input: { body: $body }) { body } }"
        for body in [Self.firstBody, Self.secondBody] {
            _ = try await graph.execute(query: mutation, variables: ["body": .string(body)], operationName: nil)
        }
        let last = try #require(try Self.events(of: .board, inRepoAt: directory.url).last)
        let expected = try PatchInput(
            node: .board,
            edit: PatchEdit(body: UnifiedDiff(from: Self.firstBody, to: Self.secondBody).text)
        )
        #expect(last.patch == expected)
    }

    @Test("updateBoard with a null body writes the diff to the empty text, and a missing name does not change")
    func nullBodyWritesDiffToEmptyText() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let mutation = #"mutation { first: updateBoard(input: { body: "\#(Self.boardBody)" }) { body } "#
            + "second: updateBoard(input: { body: null }) { name body } }"
        let response = try await KanbanGraphTests.execute(mutation, on: KanbanGraphTests.makeGraph(at: directory.url))
        let second = #"{"body":"","name":"\#(KanbanGraphTests.boardName)"}"#
        #expect(response == #"{"data":{"first":{"body":"\#(Self.boardBody)"},"second":\#(second)}}"#)
        let last = try #require(try Self.events(of: .board, inRepoAt: directory.url).last)
        let expected = try PatchInput(
            node: .board,
            edit: PatchEdit(body: UnifiedDiff(from: Self.boardBody, to: "").text)
        )
        #expect(last.patch == expected)
    }

    // MARK: - Session actor

    @Test("The session actor is the actor of KanbanGraph.init: each event names it, and the call makes it")
    func namedSessionActorIsMade() async throws {
        let directory = try TemporaryDirectory()
        let actor = try KanbanGraph.sessionActor(named: Self.namedActor)
        let (root, response) = try await Self.execute(
            "mutation { initBoard { actors { id name } } }",
            actingAs: actor,
            onEmptyRepoIn: directory
        )
        #expect(response == #"{"data":{"initBoard":{"actors":\#(Self.actorsJSON(of: actor))}}}"#)
        let events = try Self.storedRefs(inRepoAt: root).flatMap { ref in try Self.events(of: ref, inRepoAt: root) }
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { event in event.actor == .actor(slug: "test-actor") })
    }

    @Test("With no actor name, the session actor is the OS user, and the call makes it")
    func osUserSessionActorIsMade() async throws {
        let directory = try TemporaryDirectory()
        let actor = try KanbanGraph.sessionActor(named: nil)
        let (_, response) = try await Self.execute(
            "mutation { initBoard { actors { id name } } }",
            actingAs: actor,
            onEmptyRepoIn: directory
        )
        let userActor = try KanbanGraphTests.osUserActor()
        #expect(response == #"{"data":{"initBoard":{"actors":\#(Self.actorsJSON(of: userActor))}}}"#)
    }

    @Test("A later call that writes to the board writes no second actor patch")
    func sessionActorIsMadeOneTime() async throws {
        let directory = try TemporaryDirectory()
        let root = try KanbanGraphTests.makeEmptyRepo(in: directory)
        let graph = try KanbanGraphTests.makeGraph(at: root)
        let mutation = "mutation($name: String) { updateBoard(input: { name: $name }) { name } }"
        let names = [Self.boardName, KanbanGraphTests.boardName]
        for name in names {
            _ = try await graph.execute(query: mutation, variables: ["name": .string(name)], operationName: nil)
        }
        #expect(try Self.events(of: .board, inRepoAt: root).count == names.count)
        #expect(try Self.events(of: ReplayTests.actor, inRepoAt: root).count == 1)
    }

    // MARK: - Stored form

    @Test("No log line holds the key of its own board")
    func noLogLineHoldsBoardKey() async throws {
        let directory = try TemporaryDirectory()
        let mutation = "mutation { initBoard(\(Self.boardInput)) { id } }"
        let (root, _) = try await Self.execute(mutation, onEmptyRepoIn: directory)
        let log = EventLog(repositoryAt: root)
        let refs = try Self.storedRefs(inRepoAt: root)
        #expect(refs == Self.initializedRefs)
        for ref in refs {
            let text = try String(contentsOf: log.fileURL(for: ref), encoding: .utf8)
            #expect(!text.contains(KanbanGraphTests.boardKey.description))
            #expect(!text.contains(NodeURI.scheme))
        }
    }
}
