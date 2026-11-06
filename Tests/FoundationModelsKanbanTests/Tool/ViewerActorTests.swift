import Foundation
import FoundationModelsExtras
import Testing

@testable import FoundationModelsKanban

/// Tests the write actor of a call (divergence.md §26): a call of a client with a person writes as that person, each
/// other call writes as the session actor, `Query.viewer` gives the actor node of the caller, and `undoChange` and
/// `redoChange` with no `txn` take only a change of the caller.
///
/// Each test uses an empty temporary repo, the fixed clock, and the fixed ULID source of ``KanbanGraphTests``, so
/// that each response is deterministic.
@Suite("KanbanGraph: each change is written as the actor of the caller", .watcherBudget)
struct ViewerActorTests {
    /// The id of the person on the Mac.
    static let localID = "local/wballard"

    /// The iCloud user record id of the same person, after the person signs in.
    static let cloudID = "_1a2b3c"

    /// The name of the person.
    static let personName = "Will Ballard"

    /// The person with the local id.
    static let person = GraphQLActor(id: localID, name: personName)

    /// The same person with the iCloud id, and the local id as an alias.
    static let signedInPerson = GraphQLActor(id: cloudID, name: personName, aliases: [localID])

    /// The slug of the actor node of ``person``.
    static let personSlug = "local-wballard"

    /// The slug of the session actor of the test engine.
    static let agentSlug = "claude-code"

    // MARK: - Helpers

    /// Gives a viewer of a device of the user with a person.
    ///
    /// - Parameter person: The person.
    /// - Returns: The viewer.
    static func viewer(of person: GraphQLActor) -> GraphQLViewer {
        GraphQLViewer(clientId: "mac", trust: .userDevice, actor: person)
    }

    /// Makes an engine on a new empty repo.
    ///
    /// - Parameter directory: The temporary directory.
    /// - Returns: The engine and the root of the repo.
    static func makeGraph(in directory: TemporaryDirectory) throws -> (graph: KanbanGraph, root: URL) {
        let root = try KanbanGraphTests.makeEmptyRepo(in: directory)
        return (try KanbanGraphTests.makeGraph(at: root), root)
    }

    /// Runs one document as a viewer, or with no viewer.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - viewer: The viewer, or `nil` for a call of the agent.
    ///   - graph: The engine.
    /// - Returns: The response JSON text.
    static func execute(_ document: String, as viewer: GraphQLViewer?, on graph: KanbanGraph) async throws -> String {
        try await graph.execute(query: document, variables: [:], operationName: nil, viewer: viewer)
    }

    /// Adds a task as a viewer, and gives the transaction of the call.
    ///
    /// - Parameters:
    ///   - title: The title of the task.
    ///   - viewer: The viewer, or `nil` for a call of the agent.
    ///   - graph: The engine.
    /// - Returns: The ULID text of the transaction.
    @discardableResult
    static func addTask(titled title: String, as viewer: GraphQLViewer?, on graph: KanbanGraph) async throws -> String {
        let document = #"mutation { addTask(input: { title: "\#(title)" }) { id } }"#
        let response = try await execute(document, as: viewer, on: graph)
        let object = try KanbanGraphTests.object(of: response)
        let extensions = try #require(object["extensions"] as? [String: Any], "\(response)")
        return try #require(extensions["txn"] as? String, "\(response)")
    }

    /// Gives the `txn` and the actor id of each change of `Board.history`, newest first.
    ///
    /// - Parameter graph: The engine.
    /// - Returns: The pairs.
    static func history(on graph: KanbanGraph) async throws -> [(txn: String, actor: String)] {
        let response = try await execute("{ board { history { txn actor { id } } } }", as: nil, on: graph)
        let board = try KanbanGraphTests.object(named: "board", in: response)
        let changes = try #require(board["history"] as? [[String: Any]], "\(response)")
        return try changes.map { change in
            let actor = try #require(change["actor"] as? [String: Any])
            return (try #require(change["txn"] as? String), try #require(actor["id"] as? String))
        }
    }

    /// Gives the actor id of the change of one transaction in `Board.history`.
    ///
    /// - Parameters:
    ///   - txn: The ULID text of the transaction.
    ///   - graph: The engine.
    /// - Returns: The actor id.
    static func actorID(of txn: String, on graph: KanbanGraph) async throws -> String {
        try #require(try await history(on: graph).first { change in change.txn == txn }?.actor)
    }

    /// Gives the `viewer { actor { id name aliases } }` of a call.
    ///
    /// - Parameters:
    ///   - viewer: The viewer, or `nil` for a call of the agent.
    ///   - graph: The engine.
    /// - Returns: The actor object.
    static func viewerActor(as viewer: GraphQLViewer?, on graph: KanbanGraph) async throws -> [String: Any] {
        let response = try await execute("{ viewer { actor { id name aliases } } }", as: viewer, on: graph)
        let object = try KanbanGraphTests.object(named: "viewer", in: response)
        return try #require(object["actor"] as? [String: Any], "\(response)")
    }

    /// Runs `undoChange(input: {})` as a viewer, and gives the transaction that it reverses.
    ///
    /// - Parameters:
    ///   - viewer: The viewer, or `nil` for a call of the agent.
    ///   - graph: The engine.
    /// - Returns: The ULID text of the reversed transaction.
    static func undo(as viewer: GraphQLViewer?, on graph: KanbanGraph) async throws -> String {
        let response = try await execute("mutation { undoChange(input: {}) { undoes } }", as: viewer, on: graph)
        let change = try KanbanGraphTests.object(named: MutationName.undoChange, in: response)
        return try #require(change["undoes"] as? String, "\(response)")
    }

    /// Gives an actor of the board.
    ///
    /// - Parameters:
    ///   - slug: The slug of the actor.
    ///   - graph: The engine.
    /// - Returns: The actor object with `id`, `name`, and `aliases`.
    static func boardActor(_ slug: String, on graph: KanbanGraph) async throws -> [String: Any] {
        let document = #"{ board { actor(id: "\#(slug)") { id name aliases } } }"#
        let response = try await execute(document, as: nil, on: graph)
        let board = try KanbanGraphTests.object(named: "board", in: response)
        return try #require(board["actor"] as? [String: Any], "\(response)")
    }

    /// Gives the number of events in the log of one actor.
    ///
    /// - Parameters:
    ///   - slug: The slug of the actor.
    ///   - root: The root of the repo.
    /// - Returns: The number of lines in the log file of the actor, or 0 when it has no log file.
    static func eventCount(ofActor slug: String, inRepoAt root: URL) throws -> Int {
        let directory = EventLog(repositoryAt: root).directory
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        let files = (enumerator?.allObjects as? [URL] ?? []).filter { url in
            url.pathExtension == "jsonl" && url.deletingPathExtension().lastPathComponent == slug
                && url.deletingLastPathComponent().lastPathComponent.hasPrefix("actor")
        }
        let file = try #require(files.first, "No log file of the actor \(slug) in \(directory.path)")
        return try String(contentsOf: file, encoding: .utf8).split(separator: "\n").count
    }

    // MARK: - The write actor

    @Test("A call with a viewer person records that person, and a call with no viewer records the session actor")
    func writesAsViewerOrSessionActor() async throws {
        let directory = try TemporaryDirectory()
        let (graph, _) = try Self.makeGraph(in: directory)
        let personTxn = try await Self.addTask(titled: "By the person", as: Self.viewer(of: Self.person), on: graph)
        let agentTxn = try await Self.addTask(titled: "By the agent", as: nil, on: graph)
        let personActor = try await Self.actorID(of: personTxn, on: graph)
        let agentActor = try await Self.actorID(of: agentTxn, on: graph)
        await graph.close()
        #expect(personActor.hasSuffix("/actor/\(Self.personSlug)"))
        #expect(agentActor.hasSuffix("/actor/\(Self.agentSlug)"))
    }

    @Test("A viewer with no person writes as the session actor")
    func viewerWithNoPersonWritesAsSessionActor() async throws {
        let directory = try TemporaryDirectory()
        let (graph, _) = try Self.makeGraph(in: directory)
        let txn = try await Self.addTask(titled: "By the device", as: KanbanViewerFixture.userDevice, on: graph)
        let actor = try await Self.actorID(of: txn, on: graph)
        await graph.close()
        #expect(actor.hasSuffix("/actor/\(Self.agentSlug)"))
    }

    @Test("Two actors in one board give the correct actor on each change of Board.history")
    func historyShowsActorOfEachChange() async throws {
        let directory = try TemporaryDirectory()
        let (graph, _) = try Self.makeGraph(in: directory)
        let person = Self.viewer(of: Self.person)
        let first = try await Self.addTask(titled: "One", as: person, on: graph)
        let second = try await Self.addTask(titled: "Two", as: nil, on: graph)
        let third = try await Self.addTask(titled: "Three", as: person, on: graph)
        let history = try await Self.history(on: graph)
        await graph.close()
        #expect(history.map(\.txn) == [third, second, first])
        let slugs = history.map { change in change.actor.split(separator: "/").last.map(String.init) }
        #expect(slugs == [Self.personSlug, Self.agentSlug, Self.personSlug])
    }

    @Test("The first write of a person makes the actor node with the name and the ids of the person")
    func firstWriteMakesPersonNode() async throws {
        let directory = try TemporaryDirectory()
        let (graph, _) = try Self.makeGraph(in: directory)
        try await Self.addTask(titled: "One", as: Self.viewer(of: Self.person), on: graph)
        let actor = try await Self.boardActor(Self.personSlug, on: graph)
        await graph.close()
        #expect(actor["name"] as? String == Self.personName)
        #expect(actor["aliases"] as? [String] == [Self.localID])
    }

    @Test("A change of the name updates the actor node with one patch, and a write with no change writes no patch")
    func personNodePatchesOnlyChanges() async throws {
        let directory = try TemporaryDirectory()
        let (graph, root) = try Self.makeGraph(in: directory)
        try await Self.addTask(titled: "One", as: Self.viewer(of: Self.person), on: graph)
        try await Self.addTask(titled: "Two", as: Self.viewer(of: Self.person), on: graph)
        let unchanged = try Self.eventCount(ofActor: Self.personSlug, inRepoAt: root)
        let renamed = GraphQLActor(id: Self.localID, name: "Will B.")
        try await Self.addTask(titled: "Three", as: Self.viewer(of: renamed), on: graph)
        let afterRename = try Self.eventCount(ofActor: Self.personSlug, inRepoAt: root)
        let actor = try await Self.boardActor(Self.personSlug, on: graph)
        await graph.close()
        #expect(unchanged == 1)
        #expect(afterRename == 2)
        #expect(actor["name"] as? String == "Will B.")
    }

    // MARK: - Query.viewer

    @Test("viewer { actor } gives the person of the viewer, and the session actor with no viewer")
    func viewerFieldGivesWriteActor() async throws {
        let directory = try TemporaryDirectory()
        let (graph, _) = try Self.makeGraph(in: directory)
        let person = try await Self.viewerActor(as: Self.viewer(of: Self.signedInPerson), on: graph)
        let agent = try await Self.viewerActor(as: nil, on: graph)
        await graph.close()
        #expect((person["id"] as? String)?.hasSuffix("/actor/1a2b3c") == true)
        #expect(person["name"] as? String == Self.personName)
        #expect(person["aliases"] as? [String] == [Self.cloudID, Self.localID])
        #expect((agent["id"] as? String)?.hasSuffix("/actor/\(Self.agentSlug)") == true)
        #expect(agent["name"] as? String == KanbanGraphTests.actorName)
        #expect(agent["aliases"] as? [String] == [])
    }

    @Test("viewer { actor { id } } is the actor { id } of a change that the same caller wrote")
    func viewerIDMatchesChangeActor() async throws {
        let directory = try TemporaryDirectory()
        let (graph, _) = try Self.makeGraph(in: directory)
        let person = Self.viewer(of: Self.person)
        let personTxn = try await Self.addTask(titled: "One", as: person, on: graph)
        let agentTxn = try await Self.addTask(titled: "Two", as: nil, on: graph)
        let personViewer = try await Self.viewerActor(as: person, on: graph)["id"] as? String
        let agentViewer = try await Self.viewerActor(as: nil, on: graph)["id"] as? String
        let personChange = try await Self.actorID(of: personTxn, on: graph)
        let agentChange = try await Self.actorID(of: agentTxn, on: graph)
        await graph.close()
        #expect(personViewer == personChange)
        #expect(agentViewer == agentChange)
        #expect(personViewer != agentViewer)
    }

    // MARK: - Undo with no txn

    @Test("undoChange with no txn by the agent skips the newer change of the person")
    func agentUndoSkipsPersonChange() async throws {
        let directory = try TemporaryDirectory()
        let (graph, _) = try Self.makeGraph(in: directory)
        let agentTxn = try await Self.addTask(titled: "By the agent", as: nil, on: graph)
        try await Self.addTask(titled: "By the person", as: Self.viewer(of: Self.person), on: graph)
        let undone = try await Self.undo(as: nil, on: graph)
        await graph.close()
        #expect(undone == agentTxn)
    }

    @Test("undoChange with no txn by the person skips the newer change of the agent")
    func personUndoSkipsAgentChange() async throws {
        let directory = try TemporaryDirectory()
        let (graph, _) = try Self.makeGraph(in: directory)
        let person = Self.viewer(of: Self.person)
        let personTxn = try await Self.addTask(titled: "By the person", as: person, on: graph)
        try await Self.addTask(titled: "By the agent", as: nil, on: graph)
        let undone = try await Self.undo(as: person, on: graph)
        await graph.close()
        #expect(undone == personTxn)
    }

    // MARK: - Aliases

    @Test("A write under a new id with the old id as an alias goes to the actor node of the old id")
    func aliasWritesToExistingNode() async throws {
        let directory = try TemporaryDirectory()
        let (graph, _) = try Self.makeGraph(in: directory)
        let before = try await Self.addTask(titled: "Before", as: Self.viewer(of: Self.person), on: graph)
        let after = try await Self.addTask(titled: "After", as: Self.viewer(of: Self.signedInPerson), on: graph)
        let beforeActor = try await Self.actorID(of: before, on: graph)
        let afterActor = try await Self.actorID(of: after, on: graph)
        let actor = try await Self.boardActor(Self.personSlug, on: graph)
        let viewer = try await Self.viewerActor(as: Self.viewer(of: Self.signedInPerson), on: graph)
        await graph.close()
        #expect(afterActor == beforeActor)
        #expect(actor["aliases"] as? [String] == [Self.cloudID, Self.localID])
        #expect(viewer["id"] as? String == beforeActor)
    }

    @Test("undoChange with no txn under an alias id finds the change that the person wrote under the old id")
    func aliasUndoFindsOldChange() async throws {
        let directory = try TemporaryDirectory()
        let (graph, _) = try Self.makeGraph(in: directory)
        let personTxn = try await Self.addTask(titled: "By the person", as: Self.viewer(of: Self.person), on: graph)
        try await Self.addTask(titled: "By the agent", as: nil, on: graph)
        let undone = try await Self.undo(as: Self.viewer(of: Self.signedInPerson), on: graph)
        await graph.close()
        #expect(undone == personTxn)
    }

    @Test("A write under an old id that an actor node records as an alias goes to that node")
    func storedAliasFindsNode() async throws {
        let directory = try TemporaryDirectory()
        let (graph, _) = try Self.makeGraph(in: directory)
        let signedIn = try await Self.addTask(titled: "Signed in", as: Self.viewer(of: Self.signedInPerson), on: graph)
        let local = try await Self.addTask(titled: "Local", as: Self.viewer(of: Self.person), on: graph)
        let signedInActor = try await Self.actorID(of: signedIn, on: graph)
        let localActor = try await Self.actorID(of: local, on: graph)
        await graph.close()
        #expect(signedInActor.hasSuffix("/actor/1a2b3c"))
        #expect(localActor == signedInActor)
    }
}
