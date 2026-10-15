import Foundation
import FoundationModelsExtras
import Synchronization
import Testing

@testable import FoundationModelsKanban

/// Tests the host of a process: one engine for each board, and one session view for each working directory
/// (divergence.md §16).
///
/// Each test makes its own host with the internal initializer, and closes it at the end, so that its file watchers
/// stop. The shared host of the process is not used, because a board of the shared host stays loaded until the
/// process ends.
@Suite("KanbanHost: one engine per board, and a session view per working directory", .watcherBudget)
struct KanbanHostTests {
    /// The name of the session actor of the first session of a test.
    static let firstActor = "Agent A"

    /// The name of the session actor of the second session of a test.
    static let secondActor = "Agent B"

    /// The name of the symbolic link to the current repo.
    static let linkName = "app-link"

    /// The time that the slow key reader of the load tests takes. The file load of a small board takes much less.
    static let keyReadDelay = Duration.milliseconds(300)

    /// The POSIX permissions of a log file that no user can read, so that the load of its board fails.
    static let unreadablePermissions = 0o000

    /// A query that counts the tasks of the board.
    static let countQuery = "{ board { tasks { totalCount } } }"

    /// Gives the response to ``countQuery``.
    ///
    /// - Parameter count: The number of tasks.
    /// - Returns: The response JSON text.
    static func countResponse(of count: Int) -> String {
        #"{"data":{"board":{"tasks":{"totalCount":\#(count)}}}}"#
    }

    // MARK: - One host

    @Test("The shared host is one object for the whole process")
    func sharedHostIsOneObject() {
        #expect(KanbanHost.shared === KanbanHost.shared)
    }

    // MARK: - One engine for each board

    @Test("Sessions on a repo, on a symlink to it, on a path with .., and on a related sibling share one engine each")
    func oneEngineForEachBoard() async throws {
        let repos = try await CrossRepoFixture.SideBySide.make()
        let link = repos.sandbox.root.appending(path: Self.linkName, directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repos.app)
        let dotted = repos.lib.appending(path: "..", directoryHint: .isDirectory)
            .appending(path: repos.app.lastPathComponent, directoryHint: .isDirectory)
        let host = HostFixture.makeGitHost()
        let lib = try await host.session(workingDirectory: repos.lib, actor: Self.firstActor)
        let target = try await CrossRepoFixture.addTask(with: "", on: lib)
        let sessions = [
            try await host.session(workingDirectory: repos.app, actor: Self.secondActor),
            try await host.session(workingDirectory: link, actor: Self.secondActor),
            try await host.session(workingDirectory: dotted, actor: Self.secondActor),
            try await host.session(workingDirectory: repos.app.resolvingSymlinksInPath(), actor: Self.secondActor),
        ]
        _ = try await CrossRepoFixture.addTask(dependingOn: target, on: sessions[1])
        #expect(await host.engineCount == 2)
        #expect(await host.runningWatcherCount == 2)
        await host.close()
    }

    @Test("Two sessions that start at the same time on one board load the board one time")
    func concurrentSessionsLoadOneTime() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let recorder = LoadRecorder()
        let host = HostFixture.makeHost(observingLoadsWith: recorder)
        let root = directory.url
        async let first = host.session(workingDirectory: root, actor: Self.firstActor)
        async let second = host.session(workingDirectory: root, actor: Self.secondActor)
        _ = try await [first, second]
        #expect(recorder.loadStarts == [root])
        #expect(await host.engineCount == 1)
        await host.close()
    }

    @Test("The board is loaded when host.session returns, before the first call")
    func sessionReturnsLoadedBoard() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let recorder = LoadRecorder()
        let host = HostFixture.makeHost(observingLoadsWith: recorder)
        _ = try await host.session(workingDirectory: directory.url, actor: Self.firstActor)
        #expect(recorder.loadFinishes == [directory.url])
        #expect(await host.runningWatcherCount == 1)
        await host.close()
    }

    @Test("A Rust board makes host.session fail with INCOMPATIBLE_BOARD")
    func rustBoardFailsSession() async throws {
        let directory = try TemporaryDirectory()
        try IncompatibleBoardTests.writeRustBoard(inRepoAt: directory.url)
        let host = HostFixture.makeHost()
        let expected = KanbanError.incompatibleBoard(directory: EventLog(repositoryAt: directory.url).directory.path)
        await #expect(throws: expected) {
            try await host.session(workingDirectory: directory.url, actor: Self.firstActor)
        }
        #expect(await host.engineCount == 0)
        #expect(await host.runningWatcherCount == 0)
        await host.close()
    }

    @Test("A load that fails after it started tells the load observer that it ended")
    func failedLoadTellsItsEnd() async throws {
        let directory = try TemporaryDirectory()
        try Self.writeUnreadableBoard(inRepoAt: directory.url)
        let recorder = LoadRecorder()
        let host = HostFixture.makeHost(observingLoadsWith: recorder)
        await #expect(throws: EventLogError.self) {
            try await host.session(workingDirectory: directory.url, actor: Self.firstActor)
        }
        #expect(recorder.loadStarts == [directory.url])
        #expect(recorder.loadFinishes == [directory.url])
        await host.close()
    }

    @Test("A session in a folder that is not in a git repo has no board, and each call gives NOT_A_REPO")
    func folderOutsideRepoHasNoBoard() async throws {
        let sandbox = try GitSandbox()
        let folder = try GitSandbox.makeFolder(named: RepoBoardTests.plainFolderName, in: sandbox.root)
        let host = HostFixture.makeGitHost()
        let session = try await host.session(workingDirectory: folder, actor: Self.firstActor)
        let expected = try KanbanError.notARepo(path: folder.path).responseJSON()
        #expect(try await KanbanGraphTests.execute(KanbanGraphTests.keyQuery, on: session) == expected)
        #expect(await host.engineCount == 0)
        await host.close()
    }

    // MARK: - Shared engine

    @Test("A write in one session shows in a read of a second session at once, with no wait for the file watcher")
    func writeShowsInOtherSessionAtOnce() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let host = HostFixture.makeHost()
        let first = try await host.session(workingDirectory: directory.url, actor: Self.firstActor)
        let second = try await host.session(workingDirectory: directory.url, actor: Self.secondActor)
        _ = try await CrossRepoFixture.addTask(with: "", on: first)
        #expect(try await KanbanGraphTests.execute(Self.countQuery, on: second) == Self.countResponse(of: 2))
        await host.close()
    }

    @Test("close() of one view keeps the board for a second view, and the board stays loaded after the last view")
    func closeOfViewKeepsBoard() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let host = HostFixture.makeHost()
        let first = try await host.session(workingDirectory: directory.url, actor: Self.firstActor)
        let second = try await host.session(workingDirectory: directory.url, actor: Self.secondActor)
        await first.close()
        #expect(try await KanbanGraphTests.execute(Self.countQuery, on: second) == Self.countResponse(of: 1))
        await second.close()
        #expect(await host.engineCount == 1)
        #expect(await host.runningWatcherCount == 1)
        await host.close()
    }

    @Test("A subscription that starts after close() of its view gets the change of a second session")
    func subscriptionAfterCloseGetsChanges() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let host = HostFixture.makeHost()
        let first = try await host.session(workingDirectory: directory.url, actor: Self.firstActor)
        let second = try await host.session(workingDirectory: directory.url, actor: Self.secondActor)
        await first.close()
        let document = SubscriptionTests.subscription(SubscriptionTests.taskArguments)
        let stream = try await SubscriptionTests.subscribe(document, on: first)
        _ = try await CrossRepoFixture.addTask(with: "", on: second)
        let events = try await SubscriptionTests.events(SubscriptionTests.oneEvent, of: stream)
        #expect(events.count == SubscriptionTests.oneEvent)
        await host.close()
    }

    @Test("A subscription after close() registers its view before it adds its subscriber, inside the gate")
    func subscriptionRegistersViewBeforeSubscriber() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let host = HostFixture.makeHost()
        let probe = RegistrationProbe()
        let view = try KanbanGraph(
            host: host,
            owningHost: false,
            workingDirectory: directory.url,
            actingAs: KanbanGraph.sessionActor(named: Self.firstActor),
            locatedBy: await host.locator,
            reportingTo: probe
        )
        try await view.prepareBoard()
        await view.close()
        probe.arm(host: host, view: view)
        let document = SubscriptionTests.subscription(SubscriptionTests.taskArguments)
        _ = try await SubscriptionTests.subscribe(document, on: view)
        #expect(probe.registrations == [true])
        await host.close()
    }

    @Test("A closed engine does not keep a moved watch: the watch stops, and the engine has no watcher")
    func closedEngineEndsMovedWatch() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let host = HostFixture.makeHost()
        let engine = try await host.engine(ofBoardAt: directory.url)
        await engine.close()
        let moved = BoardWatch(
            watcher: try BoardWatcher(watching: directory.url, in: host.folderStreams),
            directory: directory.url,
            consumer: Task {}
        )
        #expect(await !engine.adopt(moved))
        #expect(await !moved.watcher.isRunning)
        #expect(await engine.activeWatch == nil)
        await host.close()
    }

    @Test("A read after the load runs no git and reads no log file")
    func readUsesMemoryOnly() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let git = GitCallCounter()
        let workers = WorkerCounter()
        let host = HostFixture.makeHost(
            readingKeyWith: git.countingKeyReader,
            findingTopWith: git.countingTopReader,
            reportingWorkersTo: workers
        )
        let session = try await host.session(workingDirectory: directory.url, actor: Self.firstActor)
        let (gitCalls, fileReads) = (git.count, workers.count)
        _ = try await KanbanGraphTests.execute(KanbanGraphTests.boardQuery, on: session)
        _ = try await KanbanGraphTests.execute(#"{ board { nextTask { title } } }"#, on: session)
        #expect(git.count == gitCalls)
        #expect(workers.count == fileReads)
        await host.close()
    }

    @Test("undo with no argument in a second session does not reverse the work of a first session with its own actor")
    func undoStaysInItsSession() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let host = HostFixture.makeHost()
        let first = try await host.session(workingDirectory: directory.url, actor: Self.firstActor)
        let second = try await host.session(workingDirectory: directory.url, actor: Self.secondActor)
        _ = try await CrossRepoFixture.addTask(with: "", on: first)
        let response = try await CommentTests.run(CrossRepoUndoTests.undoField, on: second)
        try ErrorCoverageTests.expectFailure(
            of: MutationName.undo,
            in: response,
            giving: .nothingToUndo,
            coded: "NOTHING_TO_UNDO"
        )
        #expect(try await KanbanGraphTests.execute(Self.countQuery, on: second) == Self.countResponse(of: 2))
        await host.close()
    }

    // MARK: - Parallel load

    @Test("Two boards load at the same time, and the key read of each board overlaps its file load")
    func boardsLoadInParallel() async throws {
        let first = try TemporaryDirectory()
        let second = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: first.url)
        _ = try KanbanGraphTests.writeFixture(inRepoAt: second.url)
        let recorder = LoadRecorder()
        let host = HostFixture.makeHost(
            readingKeyWith: recorder.slowKeyReader(taking: Self.keyReadDelay),
            observingLoadsWith: recorder
        )
        let (firstRoot, secondRoot) = (first.url, second.url)
        async let firstSession = host.session(workingDirectory: firstRoot, actor: Self.firstActor)
        async let secondSession = host.session(workingDirectory: secondRoot, actor: Self.secondActor)
        _ = try await [firstSession, secondSession]
        let events = recorder.events
        let firstKeyEnd = try #require(events.firstIndex { event in event.kind == .keyReadDidFinish })
        #expect(events.prefix(firstKeyEnd).count { event in event.kind == .keyReadDidStart } == 2)
        for root in [firstRoot, secondRoot] {
            let loadStart = try #require(events.firstIndex(of: LoadEvent(kind: .loadDidStart, root: root)))
            let keyEnd = try #require(events.firstIndex(of: LoadEvent(kind: .keyReadDidFinish, root: root)))
            #expect(loadStart < keyEnd)
        }
        await host.close()
    }

    // MARK: - Worktrees

    @Test("Two worktrees of one repo are two engines with the same key")
    func worktreesAreTwoEngines() async throws {
        let sandbox = try GitSandbox()
        let (repo, _) = try await RepoBoardTests.makeRepoWithSubfolder(in: sandbox)
        let worktree = try await sandbox.addWorktree(named: RepoBoardTests.worktreeName, to: repo)
        let host = HostFixture.makeGitHost()
        let main = try await host.session(workingDirectory: repo, actor: Self.firstActor)
        let linked = try await host.session(workingDirectory: worktree, actor: Self.secondActor)
        let mainKey = try await KanbanGraphTests.execute(KanbanGraphTests.keyQuery, on: main)
        #expect(try await KanbanGraphTests.execute(KanbanGraphTests.keyQuery, on: linked) == mainKey)
        #expect(await host.engineCount == 2)
        await host.close()
    }

    @Test("A git merge of two worktree branches gives the union of both boards")
    func mergeOfWorktreesGivesUnion() async throws {
        let sandbox = try GitSandbox()
        let (repo, _) = try await RepoBoardTests.makeRepoWithSubfolder(in: sandbox)
        let worktree = try await sandbox.addWorktree(named: RepoBoardTests.worktreeName, to: repo)
        let host = HostFixture.makeGitHost(mintingFrom: SystemULIDSource())
        let main = try await host.session(workingDirectory: repo, actor: Self.firstActor)
        let linked = try await host.session(workingDirectory: worktree, actor: Self.secondActor)
        _ = try await CrossRepoFixture.addTask(with: "", on: main)
        _ = try await CrossRepoFixture.addTask(with: "", on: linked)
        await host.close()
        try await HostFixture.commitBoard(in: worktree, sandbox: sandbox)
        try await HostFixture.commitBoard(in: repo, sandbox: sandbox)
        try await sandbox.merge(RepoBoardTests.worktreeName, in: repo)
        let reader = HostFixture.makeGitHost()
        let merged = try await reader.session(workingDirectory: repo, actor: Self.firstActor)
        #expect(try await KanbanGraphTests.execute(Self.countQuery, on: merged) == Self.countResponse(of: 2))
        await reader.close()
    }

    // MARK: - One FSEvents stream

    @Test("A host with many boards, scan places, and boards that cannot load holds one FSEvents stream")
    func hostHoldsOneStream() async throws {
        let boards = try (0..<Self.streamTestBoardCount).map { _ in try TemporaryDirectory() }
        for board in boards {
            _ = try KanbanGraphTests.writeFixture(inRepoAt: board.url)
        }
        let place = try ScanPlace.make()
        let unreadable = try TemporaryDirectory()
        try Self.writeUnreadableBoard(inRepoAt: unreadable.url)
        let host = HostFixture.makeHost()
        for board in boards {
            _ = try await host.engine(ofBoardAt: board.url)
        }
        _ = try await host.currentScanIndex(around: place.app)
        await #expect(throws: EventLogError.self) {
            try await host.relatedEngine(ofBoardAt: unreadable.url, knownKey: nil)
        }
        let places = await host.locator.places(around: place.app)
        #expect(host.folderStreams.folderCount == boards.count + places.count + 1)
        #expect(host.folderStreams.streamCount == 1)
        await host.close()
        #expect(host.folderStreams.streamCount == 0)
    }

    @Test("A manual edit of a board while a second board loads reaches the first board")
    func editDuringSecondLoadArrives() async throws {
        let first = try TemporaryDirectory()
        let second = try TemporaryDirectory()
        var (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: first.url)
        _ = try KanbanGraphTests.writeFixture(inRepoAt: second.url)
        let recorder = BatchRecorder()
        let host = HostFixture.makeHost(observingBatchesWith: recorder)
        let session = try await host.session(workingDirectory: first.url, actor: Self.firstActor)
        try BoardWatcherTests.writeLaterTitle(to: task, mintingFrom: &ids, in: EventLog(repositoryAt: first.url))
        _ = try await host.engine(ofBoardAt: second.url)
        let expected = KanbanGraphTests.boardResponse(withTask: task, titled: KanbanGraphTests.laterTitle)
        let query = KanbanGraphTests.boardQuery
        #expect(try await BoardWatcherTests.query(query, reaches: expected, on: session, recordedBy: recorder))
        await host.close()
    }

    @Test("A manual edit of one board of a host goes to the engine of that board only")
    func editGoesToItsEngineOnly() async throws {
        let first = try TemporaryDirectory()
        let second = try TemporaryDirectory()
        var (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: first.url)
        let (secondTask, _) = try KanbanGraphTests.writeFixture(inRepoAt: second.url)
        let recorder = BatchRecorder()
        let host = HostFixture.makeHost(observingBatchesWith: recorder)
        let firstSession = try await host.session(workingDirectory: first.url, actor: Self.firstActor)
        let secondSession = try await host.session(workingDirectory: second.url, actor: Self.secondActor)
        let firstLog = EventLog(repositoryAt: first.url)
        try BoardWatcherTests.writeLaterTitle(to: task, mintingFrom: &ids, in: firstLog)
        let expected = KanbanGraphTests.boardResponse(withTask: task, titled: KanbanGraphTests.laterTitle)
        let query = KanbanGraphTests.boardQuery
        #expect(try await BoardWatcherTests.query(query, reaches: expected, on: firstSession, recordedBy: recorder))
        let unchanged = KanbanGraphTests.boardResponse(withTask: secondTask, titled: KanbanGraphTests.taskTitle)
        #expect(try await KanbanGraphTests.execute(query, on: secondSession) == unchanged)
        let boardPath = firstLog.directory.canonicalPath + "/"
        #expect(recorder.appliedBatches.joined().allSatisfy { file in file.canonicalPath.hasPrefix(boardPath) })
        await host.close()
    }

    // MARK: - Helpers

    /// The number of boards that the stream test loads.
    static let streamTestBoardCount = 3

    /// Writes the fixture board in a repo, and takes the read permission from the log file of its task, so that a
    /// load of the board fails.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Throws: An error when a file cannot be written or changed.
    static func writeUnreadableBoard(inRepoAt root: URL) throws {
        let (task, _) = try KanbanGraphTests.writeFixture(inRepoAt: root)
        let file = EventLog(repositoryAt: root).fileURL(for: .task(task))
        try FileManager.default.setAttributes([.posixPermissions: unreadablePermissions], ofItemAtPath: file.path)
    }
}

// MARK: - Fixture

/// Makes the hosts of the host tests.
enum HostFixture {
    /// The message of the commit of a board in a worktree.
    static let boardCommitMessage = "Board"

    /// Makes a host with the fake readers, the fixed clock, and the fixed ULID source of ``KanbanGraphTests``.
    ///
    /// - Parameters:
    ///   - keyReader: Gives the key of a board. The default is ``KanbanGraphTests/fakeKey(ofRepoAt:)``.
    ///   - topReader: Gives the top folder of the worktree of a folder. The default is
    ///     ``KanbanGraphTests/fakeTop(of:)``.
    ///   - ids: The source of the transaction ULIDs and the event ids. The default is
    ///     ``KanbanGraphTests/mutationIDs``.
    ///   - loadObserver: Gets a call when each board load starts and ends, or `nil` for no calls.
    ///   - workerObserver: Gets a call when each worker of a loader reads a file, or `nil` for no calls.
    ///   - embedder: The embedder of the search of each board, or `nil` for BM25 and trigram only.
    ///   - scanObserver: Gets a call when each scan starts and when a scan place changes, or `nil` for no calls.
    ///   - batchObserver: Gets a call when a file watcher applies a batch, or `nil` for no calls.
    /// - Returns: The host.
    static func makeHost(
        readingKeyWith keyReader: @escaping BoardKeyReader = KanbanGraphTests.fakeKey,
        findingTopWith topReader: @escaping WorktreeTopReader = KanbanGraphTests.fakeTop,
        mintingFrom ids: any ULIDSource = KanbanGraphTests.mutationIDs,
        observingLoadsWith loadObserver: (any BoardLoadObserver)? = nil,
        reportingWorkersTo workerObserver: (any LoaderWorkerObserver)? = nil,
        embeddingWith embedder: (any PooledEmbedding)? = nil,
        observingScansWith scanObserver: (any BoardScanObserver)? = nil,
        observingBatchesWith batchObserver: (any LiveGraphObserver)? = nil
    ) -> KanbanHost {
        KanbanHost(
            configuration: HostConfiguration(
                keyReader: keyReader,
                topReader: topReader,
                clock: { KanbanGraphTests.time },
                ids: ids,
                embedder: embedder,
                batchObserver: batchObserver,
                loadObserver: loadObserver,
                workerObserver: workerObserver,
                scanObserver: scanObserver
            )
        )
    }

    /// Makes a host that reads the worktree tops and the board keys from git.
    ///
    /// - Parameter ids: The source of the transaction ULIDs and the event ids. Two boards of one host each continue
    ///   their own copy of the source, so a test that merges two boards gives a source of random ids. The default is
    ///   ``KanbanGraphTests/mutationIDs``.
    /// - Returns: The host.
    static func makeGitHost(mintingFrom ids: any ULIDSource = KanbanGraphTests.mutationIDs) -> KanbanHost {
        makeHost(readingKeyWith: BoardKey.read(fromRepoAt:), findingTopWith: BoardKey.worktreeTop(of:), mintingFrom: ids)
    }

    /// Commits the `.kanban/` directory of a worktree to its branch.
    ///
    /// - Parameters:
    ///   - worktree: The top folder of the worktree.
    ///   - sandbox: The sandbox of the repo.
    /// - Throws: An error when a git command fails.
    static func commitBoard(in worktree: URL, sandbox: GitSandbox) async throws {
        try await GitSandbox.runGit(withArguments: ["add", EventLog.directoryName], in: worktree)
        try await sandbox.commit(message: boardCommitMessage, in: worktree)
    }
}

// MARK: - Load recorder

/// The kind of one event of a ``LoadRecorder``.
enum LoadEventKind: Equatable, Sendable {
    /// The key read of a board started.
    case keyReadDidStart

    /// The key read of a board ended.
    case keyReadDidFinish

    /// The file load of a board started.
    case loadDidStart

    /// The file load of a board ended.
    case loadDidFinish
}

/// One event of a ``LoadRecorder``: its kind and the root folder of its board.
struct LoadEvent: Equatable, Sendable {
    /// The kind of the event.
    let kind: LoadEventKind

    /// The root folder of the board.
    let root: URL
}

/// Records the start and the end of each board load and of each key read, in the order that they happen.
final class LoadRecorder: BoardLoadObserver {
    /// The recorded events, behind a lock, because the loads run on different threads.
    private let recorded = Mutex<[LoadEvent]>([])

    /// The time that each file load waits after its start is recorded: a slow load, so that a test can tell two
    /// loads in sequence from two loads at the same time.
    private let loadDelay: Duration

    /// Makes a recorder.
    ///
    /// - Parameter loadDelay: The time that each file load waits after its start is recorded. The default is no wait.
    init(waitingInEachLoad loadDelay: Duration = .zero) {
        self.loadDelay = loadDelay
    }

    /// The recorded events, in the order that they happened.
    var events: [LoadEvent] {
        recorded.withLock { events in events }
    }

    /// The root folder of each load that started, in order.
    var loadStarts: [URL] {
        roots(of: .loadDidStart)
    }

    /// The root folder of each load that ended, in order.
    var loadFinishes: [URL] {
        roots(of: .loadDidFinish)
    }

    /// Records the start of a file load, and then waits for the load delay of the recorder.
    ///
    /// - Parameter root: The root folder of the board.
    func boardLoadDidStart(at root: URL) async {
        record(LoadEvent(kind: .loadDidStart, root: root))
        try? await Task.sleep(for: loadDelay)
    }

    /// Records the end of a file load.
    ///
    /// - Parameter root: The root folder of the board.
    func boardLoadDidFinish(at root: URL) {
        record(LoadEvent(kind: .loadDidFinish, root: root))
    }

    /// Gives a key reader that records its start and its end, and waits between them.
    ///
    /// - Parameter delay: The time that each key read takes.
    /// - Returns: The key reader. It gives ``KanbanGraphTests/boardKey``.
    func slowKeyReader(taking delay: Duration) -> BoardKeyReader {
        { root in
            self.record(LoadEvent(kind: .keyReadDidStart, root: root))
            try? await Task.sleep(for: delay)
            self.record(LoadEvent(kind: .keyReadDidFinish, root: root))
            return KanbanGraphTests.boardKey
        }
    }

    /// Records one event.
    ///
    /// - Parameter event: The event.
    private func record(_ event: LoadEvent) {
        recorded.withLock { events in events.append(event) }
    }

    /// Gives the root folder of each event of one kind, in order.
    ///
    /// - Parameter kind: The kind of the events.
    /// - Returns: The root folders.
    private func roots(of kind: LoadEventKind) -> [URL] {
        events.filter { event in event.kind == kind }.map(\.root)
    }
}

// MARK: - Registration probe

/// Records, at the start of each call of a view, whether the host sends the changes of the boards to the view. The
/// call starts inside the serial gate, before a subscription adds its subscriber, so each answer tells whether the
/// view registered before its subscriber could miss a change.
final class RegistrationProbe: KanbanCallObserver {
    /// The host and the view to check, behind a lock, or `nil` until the test arms the probe.
    private let target = Mutex<(host: KanbanHost, view: KanbanGraph)?>(nil)

    /// The recorded answers, behind a lock, because the calls run on different threads.
    private let answers = Mutex<[Bool]>([])

    /// The answer of each call that started after the test armed the probe, in order: `true` when the host had the
    /// view registered.
    var registrations: [Bool] {
        answers.withLock { answers in answers }
    }

    /// Starts the checks: each later call start records whether the host has the view registered.
    ///
    /// - Parameters:
    ///   - host: The host of the view.
    ///   - view: The view.
    func arm(host: KanbanHost, view: KanbanGraph) {
        target.withLock { target in target = (host, view) }
    }

    /// Records whether the host has the view registered, after the test armed the probe.
    func callDidStart() async {
        guard let (host, view) = target.withLock({ target in target }) else {
            return
        }
        let isRegistered = await host.hasView(view)
        answers.withLock { answers in answers.append(isRegistered) }
    }

    /// Does nothing: the probe checks only the starts.
    func callDidFinish() {}
}

// MARK: - Counters

/// Counts each read of git: each key read and each read of a worktree top. The reads give the fake values of
/// ``KanbanGraphTests``.
final class GitCallCounter: Sendable {
    /// The number of reads, behind a lock.
    private let calls = Mutex(0)

    /// The number of reads.
    var count: Int {
        calls.withLock { calls in calls }
    }

    /// A key reader that counts each read.
    var countingKeyReader: BoardKeyReader {
        { root in
            self.calls.withLock { calls in calls += 1 }
            return KanbanGraphTests.fakeKey(ofRepoAt: root)
        }
    }

    /// A worktree top reader that counts each read.
    var countingTopReader: WorktreeTopReader {
        { directory in
            self.calls.withLock { calls in calls += 1 }
            return KanbanGraphTests.fakeTop(of: directory)
        }
    }
}

/// Counts each worker of a loader that reads a log file.
final class WorkerCounter: LoaderWorkerObserver {
    /// The number of workers that started, behind a lock, because the workers run on different threads.
    private let started = Mutex(0)

    /// The number of workers that started.
    var count: Int {
        started.withLock { started in started }
    }

    /// Counts a worker.
    func workerDidStart() {
        started.withLock { started in started += 1 }
    }

    /// Does nothing: the counter counts only the starts.
    func workerDidFinish() {}
}
