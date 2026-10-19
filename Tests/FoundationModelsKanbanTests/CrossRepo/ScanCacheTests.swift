import Foundation
import Synchronization
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the scan cache of the host (divergence.md §16, Gap 1): a board ref that names no known board scans one time,
/// a read after that runs no git and no scan, and the file watcher of a scan place makes the next call scan again.
///
/// Each test makes its own scan place in a ``TemporaryDirectory``. Each repo of the place is a folder with an empty
/// `.git` directory, and a ``ScanKeyReader`` gives the keys, so no test runs git. No test uses the `.kanban/`
/// directory of this repo.
@Suite("Scan cache: a board that is not found stays in memory", .watcherBudget)
struct ScanCacheTests {
    /// The name of the current repo of each test.
    static let appName = "app"

    /// The name of the related repo of each test.
    static let libName = "lib"

    /// The name of a repo whose key read fails.
    static let brokenName = "broken"

    /// The name of a repo that a test moves into the place after the first scan.
    static let newName = "new-lib"

    /// The `origin` of the current repo.
    static let appOrigin = "https://github.com/example/app.git"

    /// The `origin` of the related repo.
    static let libOrigin = "https://github.com/example/lib.git"

    /// The `origin` of the repo that a test adds after the first scan, or that a test gives to the related repo.
    static let newOrigin = "https://github.com/example/new-lib.git"

    /// The key of a board that no repo of the place has.
    static let missingKey = "github.com/example/missing"

    /// The name of the git config file in the `.git` directory of a repo.
    static let gitConfigName = "config"

    /// A query of a board that no repo of the place has.
    static let missingQuery = #"{ board(id: "\#(missingKey)") { name } }"#

    /// A query of the next task of the current board.
    static let nextTaskQuery = "{ board { nextTask { title } } }"

    /// A query of the path of each copy of `Query.boards`.
    static let boardsQuery = "{ boards { path } }"

    // MARK: - Unknown key

    @Test("Two calls that reach the same unknown key run the scan one time")
    func unknownKeyScansOneTime() async throws {
        let place = try ScanPlace.make()
        let recorder = ScanRecorder()
        let host = Self.makeHost(reading: ScanKeyReader(), recordedBy: recorder)
        let session = try await host.session(workingDirectory: place.app, actor: KanbanHostTests.firstActor)
        _ = try await KanbanGraphTests.execute(Self.missingQuery, on: session)
        let response = try await KanbanGraphTests.execute(Self.missingQuery, on: session)
        let expected = KanbanError.boardNotFound(reference: Self.missingKey, searchRoots: [place.directory.url.path])
        try ErrorCoverageTests.expectFailure(of: "board", in: response, giving: expected, coded: "NOT_FOUND")
        #expect(recorder.scanCount == 1)
        await host.close()
    }

    @Test("Reads that reach an unknown key run no git and no scan after the first scan")
    func readsRunNoGit() async throws {
        let place = try ScanPlace.make()
        let reader = ScanKeyReader()
        let recorder = ScanRecorder()
        let host = Self.makeHost(reading: reader, recordedBy: recorder)
        let session = try await host.session(workingDirectory: place.app, actor: KanbanHostTests.firstActor)
        let target = NodeURI(boardKey: Self.missingKey, ref: .task(ULID())).description
        let task = try await CrossRepoFixture.addTask(dependingOn: target, on: session)
        let (gitCalls, scans) = (reader.count, recorder.scanCount)
        let reads = [
            Self.missingQuery,
            Self.nextTaskQuery,
            Self.boardsQuery,
            try CrossRepoReadTests.query(of: task, selecting: CrossRepoReadTests.readySelection),
        ]
        for read in reads {
            _ = try await KanbanGraphTests.execute(read, on: session)
        }
        #expect(reader.count == gitCalls)
        #expect(recorder.scanCount == scans)
        await host.close()
    }

    // MARK: - Parallel calls

    @Test("Two parallel calls that need the index run one scan, and read the key of each repo one time")
    func parallelCallsShareOneScan() async throws {
        let fixture = try HeldScanFixture.make()
        defer { fixture.hold.release() }
        let calls = try await fixture.startTwoCalls()
        fixture.hold.release()
        let firstIndex = try await calls.first.value
        let secondIndex = try await calls.second.value
        #expect(Self.copyPaths(of: secondIndex) == Self.copyPaths(of: firstIndex))
        #expect(Self.copyPaths(of: firstIndex) == fixture.foundPaths)
        #expect(fixture.recorder.scanCount == 1)
        for name in [Self.appName, Self.libName, Self.brokenName] {
            #expect(fixture.reader.keyReadCount(ofRepoNamed: name) == 1, "key reads of \(name)")
        }
        await fixture.host.close()
    }

    @Test("A cancel of a call that waits for a running scan ends its wait, and the scan goes on")
    func cancelledWaitEndsOnlyItsWait() async throws {
        let fixture = try HeldScanFixture.make()
        defer { fixture.hold.release() }
        let calls = try await fixture.startTwoCalls()
        calls.second.cancel()
        await #expect(throws: BoardKeyError.self) { try await calls.second.value }
        fixture.hold.release()
        let index = try await calls.first.value
        #expect(Self.copyPaths(of: index) == fixture.foundPaths)
        #expect(fixture.recorder.scanCount == 1)
        await fixture.host.close()
    }

    @Test("A call that waits for a running scan scans again when that scan gives no index")
    func waitingCallScansAgainAfterCancelledScan() async throws {
        let fixture = try HeldScanFixture.make()
        defer { fixture.hold.release() }
        let calls = try await fixture.startTwoCalls()
        calls.first.cancel()
        await #expect(throws: BoardKeyError.self) { try await calls.first.value }
        fixture.hold.release()
        let index = try await calls.second.value
        #expect(Self.copyPaths(of: index) == fixture.foundPaths)
        #expect(fixture.recorder.scanWaitCount == 1)
        #expect(fixture.recorder.scanCount == 2)
        await fixture.host.close()
    }

    // MARK: - Watcher

    @Test("A new repo folder in a scan place makes the next call find its key")
    func newRepoFolderIsFound() async throws {
        let place = try ScanPlace.make()
        let recorder = ScanRecorder()
        let host = Self.makeHost(reading: ScanKeyReader(), recordedBy: recorder)
        let session = try await host.session(workingDirectory: place.app, actor: KanbanHostTests.firstActor)
        let newKey = try CrossRepoFixture.keyText(of: Self.newOrigin)
        _ = try await KanbanGraphTests.execute(#"{ board(id: "\#(newKey)") { name } }"#, on: session)
        let staging = try TemporaryDirectory()
        let built = try ScanPlace.makeRepoFolder(named: Self.newName, in: staging.url)
        let moved = place.directory.url.appending(path: Self.newName, directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: built, to: moved)
        try await recorder.waitForChange(waitingFor: "a scan change after which the new repo is found", at: moved) {
            try await Self.hasBoard(of: newKey, on: session)
        }
        #expect(try await CrossRepoReadTests.board("path", of: newKey, on: session) == moved.path)
        await host.close()
    }

    @Test("A changed git remote in a scan place makes the next call read the key of that repo again")
    func changedRemoteIsReadAgain() async throws {
        let place = try ScanPlace.make()
        let reader = ScanKeyReader()
        let recorder = ScanRecorder()
        let host = Self.makeHost(reading: reader, recordedBy: recorder)
        let session = try await host.session(workingDirectory: place.app, actor: KanbanHostTests.firstActor)
        let newKey = try CrossRepoFixture.keyText(of: Self.newOrigin)
        _ = try await KanbanGraphTests.execute(#"{ board(id: "\#(newKey)") { name } }"#, on: session)
        reader.setOrigin(Self.newOrigin, ofRepoNamed: Self.libName)
        let config = try Self.writeOrigin(Self.newOrigin, intoConfigOfRepoAt: place.lib)
        try await recorder.waitForChange(waitingFor: "a scan change after which the new key is found", at: config) {
            try await Self.hasBoard(of: newKey, on: session)
        }
        #expect(try await CrossRepoReadTests.board("path", of: newKey, on: session) == place.lib.path)
        await host.close()
    }

    @Test("A new board log in a scan place makes Query.boards show the copy as enabled")
    func newBoardLogIsEnabled() async throws {
        let place = try ScanPlace.make()
        let recorder = ScanRecorder()
        let host = Self.makeHost(reading: ScanKeyReader(), recordedBy: recorder)
        let session = try await host.session(workingDirectory: place.app, actor: KanbanHostTests.firstActor)
        let enabled = "(enabled: true)"
        #expect(try await CrossRepoReadTests.boardPaths(with: enabled, on: session) == [place.app.path])
        _ = try KanbanGraphTests.writeFixture(inRepoAt: place.lib)
        let lib = place.lib
        let board = EventLog(repositoryAt: lib).directory
        try await recorder.waitForChange(waitingFor: "a scan change after which the new board is enabled", at: board) {
            try await CrossRepoReadTests.boardPaths(with: enabled, on: session).contains(lib.path)
        }
        let paths = try await CrossRepoReadTests.boardPaths(with: enabled, on: session)
        #expect(paths == [place.app.path, place.lib.path])
        await host.close()
    }

    // MARK: - Helpers

    /// Writes an `origin` into the git config file of a repo folder, so that the files of the repo change the same as
    /// at `git remote set-url`. The repo is a folder with a `.git` directory, so no git runs.
    ///
    /// - Parameters:
    ///   - origin: The `origin` that the test writes.
    ///   - repo: The repo folder.
    /// - Returns: The git config file.
    /// - Throws: An error from `Data` when the file cannot be written.
    @discardableResult
    static func writeOrigin(_ origin: String, intoConfigOfRepoAt repo: URL) throws -> URL {
        let config = repo.appending(path: BoardKey.gitDirectoryName).appending(path: gitConfigName)
        try Data(origin.utf8).write(to: config)
        return config
    }

    /// Tells if a call finds the board of a board key.
    ///
    /// - Parameters:
    ///   - key: The board key.
    ///   - graph: The engine.
    /// - Returns: `true` when the call gives a board, and `false` when it gives no board.
    /// - Throws: An error when the call cannot run.
    static func hasBoard(of key: String, on graph: KanbanGraph) async throws -> Bool {
        let response = try await KanbanGraphTests.execute(#"{ board(id: "\#(key)") { path } }"#, on: graph)
        return try KanbanGraphTests.data(of: response)["board"] as? [String: Any] != nil
    }

    /// Gives the canonical path of the repo directory of each copy of an index.
    ///
    /// - Parameter index: The index.
    /// - Returns: The paths.
    static func copyPaths(of index: BoardIndex) -> Set<String> {
        Set(index.copies.map(\.directory.canonicalPath))
    }

    /// Makes a host whose git reads come from a key reader, and whose scans a recorder records.
    ///
    /// - Parameters:
    ///   - reader: Gives the key and the worktree top of each repo, and counts each read.
    ///   - recorder: Records each scan and each change of a scan place.
    /// - Returns: The host.
    static func makeHost(reading reader: ScanKeyReader, recordedBy recorder: ScanRecorder) -> KanbanHost {
        HostFixture.makeHost(
            readingKeyWith: reader.keyReader,
            findingTopWith: reader.topReader,
            observingScansWith: recorder
        )
    }
}

// MARK: - Place

/// One scan place of a test: a temporary directory with the current repo, a related repo, and a repo whose key read
/// fails. Each repo is a folder with an empty `.git` directory. The current repo has a board.
struct ScanPlace {
    /// The temporary directory: the parent directory of the current repo, so the scan looks in it.
    let directory: TemporaryDirectory

    /// The current repo, ``ScanCacheTests/appName``.
    let app: URL

    /// The related repo, ``ScanCacheTests/libName``.
    let lib: URL

    /// Makes the place and its repos.
    ///
    /// - Returns: The place.
    /// - Throws: An error from `FileManager` when a folder or a log file cannot be made.
    static func make() throws -> ScanPlace {
        let directory = try TemporaryDirectory()
        let app = try makeRepoFolder(named: ScanCacheTests.appName, in: directory.url)
        _ = try KanbanGraphTests.writeFixture(inRepoAt: app)
        let lib = try makeRepoFolder(named: ScanCacheTests.libName, in: directory.url)
        _ = try makeRepoFolder(named: ScanCacheTests.brokenName, in: directory.url)
        return ScanPlace(directory: directory, app: app, lib: lib)
    }

    /// Makes a folder with an empty `.git` directory, so that the scan takes it as a repo.
    ///
    /// - Parameters:
    ///   - name: The name of the folder.
    ///   - parent: The folder that holds the new folder.
    /// - Returns: The new folder.
    /// - Throws: An error from `FileManager` when a folder cannot be made.
    static func makeRepoFolder(named name: String, in parent: URL) throws -> URL {
        let folder = try GitSandbox.makeFolder(named: name, in: parent)
        _ = try GitSandbox.makeFolder(named: BoardKey.gitDirectoryName, in: folder)
        return folder
    }
}

// MARK: - Held scan

/// A host and a ``ScanPlace`` whose scan holds at each key read of the related repo, so that a test can start a second
/// call while the scan of the first call runs.
struct HeldScanFixture {
    /// The type of a call that needs the current index.
    typealias IndexCall = Task<BoardIndex, any Error>

    /// The scan place.
    let place: ScanPlace

    /// The gate that each key read of the related repo waits at.
    let hold: TestGate

    /// Gives the keys, holds the key reads of the related repo, and counts each key read.
    let reader: ScanKeyReader

    /// Records each scan and each wait for a running scan.
    let recorder: ScanRecorder

    /// The host.
    let host: KanbanHost

    /// Makes the place, the reader, the recorder, and the host.
    ///
    /// - Returns: The fixture.
    /// - Throws: An error from `FileManager` when a folder or a log file cannot be made.
    static func make() throws -> HeldScanFixture {
        let place = try ScanPlace.make()
        let hold = TestGate()
        let reader = ScanKeyReader(holdingKeyReadsOfRepoNamed: ScanCacheTests.libName, at: hold)
        let recorder = ScanRecorder()
        let host = ScanCacheTests.makeHost(reading: reader, recordedBy: recorder)
        return HeldScanFixture(place: place, hold: hold, reader: reader, recorder: recorder, host: host)
    }

    /// The canonical path of each repo whose copy a complete scan of the place finds: the current repo and the
    /// related repo.
    var foundPaths: Set<String> {
        [place.app.canonicalPath, place.lib.canonicalPath]
    }

    /// Starts two calls that need the current index of the place. The first call starts the scan, and the scan holds
    /// at the key read of the related repo. The second call starts then. The method returns when the second call
    /// waits for the running scan, or when it started a second scan, so that a test can check both results.
    ///
    /// - Returns: The two calls.
    /// - Throws: `CancellationError` when the test is cancelled during a wait.
    func startTwoCalls() async throws -> (first: IndexCall, second: IndexCall) {
        let (host, app, recorder) = (host, place.app, recorder)
        let first = IndexCall { try await host.currentScanIndex(around: app) }
        await hold.waitForArrival()
        let second = IndexCall { try await host.currentScanIndex(around: app) }
        try await EventLogTests.waitUntil { recorder.scanWaitCount + recorder.scanCount > 1 }
        return (first, second)
    }
}

// MARK: - Key reader

/// Gives the key of each repo of a ``ScanPlace`` by the name of its folder, with no git, and counts each read of a
/// key and of a worktree top. A repo with no origin in the table gives a git failure, the same as a repo whose key
/// git cannot read.
///
/// The reader can hold the key reads of one repo at a ``TestGate``: each key read of that repo records its arrival,
/// and waits until the test releases the gate.
final class ScanKeyReader: Sendable {
    /// The exit status of the failed git read of a repo with no origin in the table.
    private static let failureStatus: Int32 = 128

    /// The `origin` of each repo, by the name of its folder, behind a lock, because the scan reads from different
    /// threads.
    private let origins = Mutex([
        ScanCacheTests.appName: ScanCacheTests.appOrigin,
        ScanCacheTests.libName: ScanCacheTests.libOrigin,
        ScanCacheTests.newName: ScanCacheTests.newOrigin,
    ])

    /// The number of reads, behind a lock.
    private let calls = Mutex(0)

    /// The number of key reads of each repo, by the name of its folder, behind a lock.
    private let keyReads = Mutex([String: Int]())

    /// The name of the folder of the repo whose key reads wait at ``hold``, or `nil` for no held read.
    private let heldName: String?

    /// The gate that each key read of the held repo waits at.
    private let hold: TestGate

    /// Makes a reader.
    ///
    /// - Parameters:
    ///   - heldName: The name of the folder of the repo whose key reads wait at the gate, or `nil` for no held read.
    ///   - hold: The gate that each key read of the held repo waits at.
    init(holdingKeyReadsOfRepoNamed heldName: String? = nil, at hold: TestGate = TestGate()) {
        self.heldName = heldName
        self.hold = hold
    }

    /// The number of reads of a key or of a worktree top so far.
    var count: Int {
        calls.withLock { calls in calls }
    }

    /// Gives the number of key reads of one repo so far.
    ///
    /// - Parameter name: The name of the folder of the repo.
    /// - Returns: The number of key reads.
    func keyReadCount(ofRepoNamed name: String) -> Int {
        keyReads.withLock { reads in reads[name, default: 0] }
    }

    /// Gives a repo a new `origin`, the same as `git remote set-url`.
    ///
    /// - Parameters:
    ///   - origin: The new `origin`.
    ///   - name: The name of the folder of the repo.
    func setOrigin(_ origin: String, ofRepoNamed name: String) {
        origins.withLock { origins in origins[name] = origin }
    }

    /// The reader as a ``BoardKeyReader``: it counts the read and gives the key of the `origin` of the folder. A key
    /// read of the held repo waits at the gate first.
    var keyReader: BoardKeyReader {
        { root throws(BoardKeyError) in
            self.calls.withLock { calls in calls += 1 }
            let name = root.lastPathComponent
            self.keyReads.withLock { reads in reads[name, default: 0] += 1 }
            if name == self.heldName {
                try await self.waitAtHold()
            }
            guard let origin = self.origins.withLock({ origins in origins[name] }) else {
                throw .gitFailed(arguments: [], status: Self.failureStatus, message: "no origin for \(name)")
            }
            return try BoardKey(remoteURL: origin)
        }
    }

    /// Records the arrival of a held key read, and waits until the test releases the gate.
    ///
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled before the release, the same
    ///   as a git command that a cancel stops.
    private func waitAtHold() async throws(BoardKeyError) {
        hold.recordArrival()
        do {
            try await hold.waitUntilReleased()
        } catch {
            throw .gitCancelled(arguments: [])
        }
    }

    /// The reader as a ``WorktreeTopReader``: it counts the read. Each folder with a `.git` entry is the top folder of
    /// its worktree, and a folder with no `.git` entry is not in a git repo, the same as `git rev-parse` in a folder
    /// whose parent folders hold no repo.
    var topReader: WorktreeTopReader {
        { directory throws(BoardKeyError) in
            self.calls.withLock { calls in calls += 1 }
            let gitEntry = directory.appending(path: BoardKey.gitDirectoryName)
            guard FileManager.default.fileExists(atPath: gitEntry.path) else {
                throw .notARepo(path: directory.path)
            }
            return directory
        }
    }
}

// MARK: - Scan recorder

/// Records each scan of a host, and gives each change that a file watcher of the host sees: of a scan place, or of a
/// folder that a path ref named.
final class ScanRecorder: BoardScanObserver {
    /// The number of scans that started, behind a lock, because the scans run on different threads.
    private let starts = Mutex(0)

    /// The number of calls that waited for a running scan, behind a lock.
    private let waits = Mutex(0)

    /// The changes that the host saw, in order.
    private let changes: AsyncStream<ScanChange>

    /// Gives the elements of ``changes``.
    private let changeSink: AsyncStream<ScanChange>.Continuation

    /// Makes a recorder.
    init() {
        (changes, changeSink) = AsyncStream.makeStream()
    }

    /// The number of scans that started.
    var scanCount: Int {
        starts.withLock { starts in starts }
    }

    /// The number of calls that waited for a running scan.
    var scanWaitCount: Int {
        waits.withLock { waits in waits }
    }

    /// Counts a scan.
    ///
    /// - Parameter places: The places of the scan.
    func scanDidStart(inPlaces places: [URL]) {
        starts.withLock { starts in starts += 1 }
    }

    /// Counts a call that waits for a running scan.
    ///
    /// - Parameter places: The places of the scan.
    func scanWaitDidStart(inPlaces places: [URL]) {
        waits.withLock { waits in waits += 1 }
    }

    /// Records a change of a scan place.
    ///
    /// - Parameter change: The change.
    func scanPlaceDidChange(_ change: ScanChange) {
        changeSink.yield(change)
    }

    /// Records a change that made the host forget what git told about a folder that a path ref named, in the same
    /// stream as a change of a scan place.
    ///
    /// - Parameter change: The change.
    func pathRefDidChange(_ change: ScanChange) {
        scanPlaceDidChange(change)
    }

    /// Waits until the host saw a change, and the effect of the test action shows. The file watcher can tell a change
    /// that came before the test action, for example the make of the repo folders. The host tells only the first
    /// change that makes the record of a path ref out of date, and that change can be of a different kind than the
    /// change of the test action, for example when a late change and the change of the test action come in one batch.
    /// Thus the wait does not compare the change (``FolderEventWait/change(in:waitingFor:at:until:)``). Call it one
    /// time for each recorder.
    ///
    /// - Parameters:
    ///   - change: The change that the test waits for. The failure message at the time limit names it.
    ///   - path: The file or folder that the test changed. The failure message at the time limit names it.
    ///   - isShown: Tells if the effect of the test action shows. The wait asks it after each change.
    /// - Throws: ``FolderEventTimeout`` when the effect does not show before the time limit, an error when the
    ///   changes end before the effect shows, or an error that `isShown` throws.
    func waitForChange(
        waitingFor change: String,
        at path: URL,
        until isShown: @escaping @Sendable () async throws -> Bool
    ) async throws {
        let isShownInTime = try await FolderEventWait.change(in: changes, waitingFor: change, at: path, until: isShown)
        try #require(isShownInTime, "The changes of the host ended before \(change) at \(path.path)")
    }
}
