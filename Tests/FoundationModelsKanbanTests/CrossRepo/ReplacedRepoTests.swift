import Foundation
import Synchronization
import Testing

@testable import FoundationModelsKanban

/// Tests a session view after a new repo replaces the repo of a path board ref at the same path (divergence.md §16,
/// Gap 1): the next call with the path ref reads the board of the new repo, and the change feed of the view sends the
/// changes of the new board and no change of the old board.
///
/// Each test makes the current repo in a ``ScanPlace``, and the repo of the path ref in a second
/// ``TemporaryDirectory``, where the scan does not look. A ``ScanKeyReader`` gives the keys, so no test runs git. No
/// test uses the `.kanban/` directory of this repo.
@Suite("Cross-repo: a new repo at the path of a path board ref", .watcherBudget)
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

    // MARK: - The engine of the old repo

    @Test("After the replace, a write to the new board does not reach the engine of the old repo, and its watcher stops")
    func oldEngineDoesNotApplyNewBoard() async throws {
        let repo = try await PathRepo.make()
        _ = try await PathBoardKeyTests.addTask(inFolderAt: repo.folder, on: repo.session)
        let oldEngine = try await repo.host.relatedEngine(ofBoardAt: repo.folder, knownKey: nil)
        let oldEvents = await oldEngine.session.live.events.count
        _ = try await repo.replace()
        _ = try await PathBoardKeyTests.addTask(inFolderAt: repo.folder, on: repo.session)
        #expect(await oldEngine.activeWatch == nil)
        #expect(await oldEngine.session.live.events.count == oldEvents)
        await repo.host.close()
    }

    @Test("After a new repo replaces the repo of the working directory, a write goes to the board of the new repo")
    func writeOfCurrentBoardGoesToNewRepo() async throws {
        let repo = try await PathRepo.make()
        let session = try await repo.host.session(workingDirectory: repo.folder, actor: KanbanHostTests.secondActor)
        _ = try await CrossRepoFixture.addTask(with: "", on: session)
        let newKey = try repo.moveAndMakeNewRepo()
        let task = try await CrossRepoFixture.addTask(with: "", on: session)
        #expect(task.hasPrefix(Self.uriPrefix(ofBoard: newKey)))
        await repo.host.close()
    }

    @Test("A write whose repo is replaced during the call runs again on the board of the new repo")
    func writeDuringReplaceGoesToNewRepo() async throws {
        let repo = try await PathRepo.make()
        let replacer = ReplaceOnFirstCall(repo: repo)
        let view = try KanbanGraph(
            host: repo.host,
            owningHost: false,
            workingDirectory: repo.folder,
            actingAs: KanbanGraph.sessionActor(named: KanbanHostTests.secondActor),
            locatedBy: await repo.host.locator,
            reportingTo: replacer
        )
        try await view.prepareBoard()
        let task = try await CrossRepoFixture.addTask(with: "", on: view)
        let newKey = try #require(replacer.newKey)
        #expect(task.hasPrefix(Self.uriPrefix(ofBoard: newKey)))
        #expect(!FileManager.default.fileExists(atPath: EventLog(repositoryAt: repo.oldFolder).directory.path))
        await repo.host.close()
    }
}

/// Replaces the repo of a ``PathRepo`` at the start of the first call of a view: after the view took the serial gate
/// of the engine of the old repo, and before the call commits.
final class ReplaceOnFirstCall: KanbanCallObserver {
    /// The repo folder to replace.
    private let folder: URL

    /// The folder that gets the old repo.
    private let staging: URL

    /// Gives the keys of the repos.
    private let reader: ScanKeyReader

    /// The key of the new repo after the replace, or `nil` before it, behind a lock, because the calls run on
    /// different threads.
    private let replacedKey = Mutex<String?>(nil)

    /// Makes the observer.
    ///
    /// - Parameter repo: The repo to replace.
    init(repo: PathRepo) {
        folder = repo.folder
        staging = repo.staging.url
        reader = repo.reader
    }

    /// The key of the new repo after the replace, or `nil` before it.
    var newKey: String? {
        replacedKey.withLock { key in key }
    }

    /// Replaces the repo at the first call start. A later call start changes nothing.
    func callDidStart() async {
        let isFirst = replacedKey.withLock { key in key == nil }
        guard isFirst else {
            return
        }
        let key = try? PathRepo.moveAndMakeNewRepo(at: folder, movingOldRepoInto: staging, keyedBy: reader)
        replacedKey.withLock { replaced in replaced = key }
    }

    /// Does nothing: the observer acts only at a call start.
    func callDidFinish() {}
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

    /// The folder of the old repo in ``staging`` after a replace.
    var oldFolder: URL {
        staging.url.appending(path: folder.lastPathComponent)
    }

    /// Moves the repo of the path ref into ``staging``, makes a new repo with a different key at the same path, and
    /// waits until the host gives the new key for the folder.
    ///
    /// - Returns: The key of the new repo.
    /// - Throws: An error when a folder cannot change, or when the host does not see the change in time.
    func replace() async throws -> String {
        let newKey = try moveAndMakeNewRepo()
        try await recorder.waitForChange(.place(outside.url.canonicalPath)) {
            try await host.board(ofFolderAt: folder).copy?.key.description == newKey
        }
        return newKey
    }

    /// Moves the repo of the path ref into ``staging``, and makes a new repo with a different key at the same path,
    /// with no wait for the host.
    ///
    /// - Returns: The key of the new repo.
    /// - Throws: An error when a folder cannot change.
    func moveAndMakeNewRepo() throws -> String {
        try Self.moveAndMakeNewRepo(at: folder, movingOldRepoInto: staging.url, keyedBy: reader)
    }

    /// Moves a repo into a different folder, and makes a new repo with a different key at the same path, with no
    /// wait for the host.
    ///
    /// - Parameters:
    ///   - folder: The repo folder.
    ///   - staging: The folder that gets the old repo.
    ///   - reader: Gives the keys of the repos. It gets the origin of the new repo.
    /// - Returns: The key of the new repo.
    /// - Throws: An error when a folder cannot change.
    static func moveAndMakeNewRepo(
        at folder: URL,
        movingOldRepoInto staging: URL,
        keyedBy reader: ScanKeyReader
    ) throws -> String {
        try PathRefCacheTests.replaceRepo(at: folder, movingOldRepoInto: staging)
        reader.setOrigin(PathRefCacheTests.laterOrigin, ofRepoNamed: ScanCacheTests.newName)
        return try CrossRepoFixture.keyText(of: PathRefCacheTests.laterOrigin)
    }

    /// Gives each event of the board of the new repo as one change of the engine of the old repo, after
    /// ``replace()``. This is what the file watcher of the engine of the old repo sent when it read the files of the
    /// new repo: that engine kept the path of the folder, so its change has the same path as the board of the new
    /// repo, and it names the nodes of the new board. The host lets go of the engine of the old repo, so the change
    /// takes the identity of the old repo from its folder in ``staging``.
    ///
    /// - Returns: The change of the engine of the old repo, by the canonical path of the folder of the path ref.
    /// - Throws: An error when the old folder cannot be read, when the host has no engine for the new repo, or when
    ///   the new board has no event.
    func newBoardChangesOfOldEngine() async throws -> [String: BoardChanges] {
        let oldIdentity = try FolderIdentity(of: oldFolder)
        let newSession = try await host.relatedEngine(ofBoardAt: folder, knownKey: nil).session
        let change = LiveGraphChange(before: Graph(), after: newSession.live.graph, events: newSession.live.events)
        let changes = try #require(BoardChanges(of: newSession, changes: [change], madeBy: oldIdentity))
        return [folder.canonicalPath: changes]
    }
}
