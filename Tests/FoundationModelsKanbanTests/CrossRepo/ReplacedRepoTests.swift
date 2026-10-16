import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests a session view after a new repo replaces the repo of a path board ref at the same path (divergence.md §16,
/// Gap 1): the next call with the path ref reads the board of the new repo, and the change feed of the view sends the
/// changes of the new board and no change of the old board.
///
/// Each test makes the current repo in a ``ScanPlace``, and the repo of the path ref in a second
/// ``TemporaryDirectory``, where the scan does not look. A ``ScanKeyReader`` gives the keys, so no test runs git. No
/// test uses the `.kanban/` directory of this repo.
@Suite("Cross-repo: a new repo at the path of a path board ref", .watcherBudget, .timeLimit(.minutes(1)))
struct ReplacedRepoTests {
    /// The selection of the id of the task of each update of a change.
    static let updateSelection = "{ updates { node { ... on Task { id } } } }"

    /// Gives the query of the key and the tasks of the board that a path ref names.
    ///
    /// - Parameter folder: The folder that the path ref names.
    /// - Returns: The query.
    static func boardQuery(ofBoardAt folder: URL) -> String {
        #"{ board(id: "\#(folder.path)") { key tasks { edges { node { id } } } } }"#
    }

    /// Gives the subscription to the task changes of the board that a path ref names.
    ///
    /// - Parameter folder: The folder that the path ref names.
    /// - Returns: The subscription document.
    static func taskChanges(ofBoardAt folder: URL) -> String {
        SubscriptionTests.subscription(#"(board: "\#(folder.path)", filter: "~task")"#, selecting: updateSelection)
    }

    /// Gives the response of one change event with the update of one task.
    ///
    /// - Parameter task: The full URI of the task.
    /// - Returns: The response JSON text.
    static func event(updating task: String) -> String {
        #"{"data":{"changes":{"updates":[{"node":{"id":"\#(task)"}}]}}}"#
    }

    /// Gives the start of the full URI of each node of a board.
    ///
    /// - Parameter key: The key of the board.
    /// - Returns: The start of the URI, with the `/` after the key.
    static func uriPrefix(ofBoard key: String) -> String {
        "\(NodeURI.scheme)\(key)/"
    }

    @Test("After a new repo replaces the repo of a path ref, the view gives the key and the tasks of the new repo")
    func viewReadsNewRepo() async throws {
        let repo = try await PathRepo.make()
        _ = try await PathBoardKeyTests.addTask(inFolderAt: repo.folder, on: repo.session)
        let newKey = try await repo.replace()
        let response = try await KanbanGraphTests.execute(Self.boardQuery(ofBoardAt: repo.folder), on: repo.session)
        #expect(response == #"{"data":{"board":{"key":"\#(newKey)","tasks":{"edges":[]}}}}"#)
        await repo.host.close()
    }

    @Test("A subscriber of a path ref from before the replace gets the changes of the new repo")
    func subscriberGetsChangesOfNewRepo() async throws {
        let repo = try await PathRepo.make()
        let stream = try await SubscriptionTests.subscribe(Self.taskChanges(ofBoardAt: repo.folder), on: repo.session)
        let newKey = try await repo.replace()
        let task = try await PathBoardKeyTests.addTask(inFolderAt: repo.folder, on: repo.session)
        let events = try await SubscriptionTests.events(SubscriptionTests.oneEvent, of: stream)
        #expect(task.hasPrefix(Self.uriPrefix(ofBoard: newKey)))
        #expect(events == [Self.event(updating: task)])
        await repo.host.close()
    }

    @Test("After the replace, a change that the engine of the old repo sends for the same path goes to no subscriber")
    func changeOfOldEngineIsNotSent() async throws {
        let repo = try await PathRepo.make()
        let stream = try await SubscriptionTests.subscribe(Self.taskChanges(ofBoardAt: repo.folder), on: repo.session)
        _ = try await repo.replace()
        let first = try await PathBoardKeyTests.addTask(inFolderAt: repo.folder, on: repo.session)
        await repo.host.publish(try await repo.newBoardChangesOfOldEngine())
        let second = try await PathBoardKeyTests.addTask(inFolderAt: repo.folder, on: repo.session)
        let events = try await SubscriptionTests.events(SubscriptionTests.twoEvents, of: stream)
        #expect(events == [Self.event(updating: first), Self.event(updating: second)])
        await repo.host.close()
    }
}

/// The repo of a path board ref of one test, outside the scan place of the current repo, and the session view of the
/// current repo.
struct PathRepo {
    /// The scan place of the current repo.
    let place: ScanPlace

    /// The temporary directory that holds the repo of the path ref.
    let outside: TemporaryDirectory

    /// The temporary directory that gets the old repo when the test replaces it.
    let staging: TemporaryDirectory

    /// The repo folder that the path ref names.
    let folder: URL

    /// Gives the keys of the repos and counts each read.
    let reader: ScanKeyReader

    /// Records each change that a file watcher of the host sees.
    let recorder: ScanRecorder

    /// The host of the session view.
    let host: KanbanHost

    /// The session view of the current repo.
    let session: KanbanGraph

    /// Makes the repos, the host, and the session view.
    ///
    /// - Returns: The repo of the path ref.
    /// - Throws: An error when a folder, the host, or the view cannot be made.
    static func make() async throws -> PathRepo {
        let place = try ScanPlace.make()
        let outside = try TemporaryDirectory()
        let folder = try ScanPlace.makeRepoFolder(named: ScanCacheTests.newName, in: outside.url)
        let reader = ScanKeyReader()
        let recorder = ScanRecorder()
        let host = ScanCacheTests.makeHost(reading: reader, recordedBy: recorder)
        let session = try await host.session(workingDirectory: place.app, actor: KanbanHostTests.firstActor)
        return PathRepo(
            place: place,
            outside: outside,
            staging: try TemporaryDirectory(),
            folder: folder,
            reader: reader,
            recorder: recorder,
            host: host,
            session: session
        )
    }

    /// Moves the repo of the path ref into ``staging``, makes a new repo with a different key at the same path, and
    /// waits until the host gives the new key for the folder.
    ///
    /// - Returns: The key of the new repo.
    /// - Throws: An error when a folder cannot change, or when the host does not see the change in time.
    func replace() async throws -> String {
        try PathRefCacheTests.replaceRepo(at: folder, movingOldRepoInto: staging.url)
        reader.setOrigin(PathRefCacheTests.laterOrigin, ofRepoNamed: ScanCacheTests.newName)
        let newKey = try CrossRepoFixture.keyText(of: PathRefCacheTests.laterOrigin)
        try await recorder.waitForChange(.place(outside.url.canonicalPath)) {
            try await host.board(ofFolderAt: folder).copy?.key.description == newKey
        }
        return newKey
    }

    /// Gives each event of the board of the new repo as one change of the engine of the old repo, after
    /// ``replace()``. This is what the file watcher of the engine of the old repo sends when it reads the files of the
    /// new repo: that engine keeps the path of the folder, so its change has the same path as the board of the new
    /// repo, and it names the nodes of the new board.
    ///
    /// - Returns: The change of the engine of the old repo, by the canonical path of the root directory of that
    ///   engine.
    /// - Throws: An error when the host has no engine for a repo, or when the new board has no event.
    func newBoardChangesOfOldEngine() async throws -> [String: BoardChanges] {
        let oldFolder = staging.url.appending(path: folder.lastPathComponent)
        let oldEngine = try await host.relatedEngine(ofBoardAt: oldFolder, knownKey: nil)
        let newSession = try await host.relatedEngine(ofBoardAt: folder, knownKey: nil).session
        let change = LiveGraphChange(before: Graph(), after: newSession.live.graph, events: newSession.live.events)
        let changes = try #require(BoardChanges(of: newSession, changes: [change], madeBy: oldEngine.identity))
        return [oldEngine.root.canonicalPath: changes]
    }
}
