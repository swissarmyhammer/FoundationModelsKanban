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
@Suite("Scan cache: a board that is not found stays in memory", .watcherBudget, .timeLimit(.minutes(1)))
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
        try await recorder.waitForChange(.repo(moved.canonicalPath)) {
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
        let config = place.lib.appending(path: BoardKey.gitDirectoryName).appending(path: Self.gitConfigName)
        try Data(Self.newOrigin.utf8).write(to: config)
        try await recorder.waitForChange(.repo(place.lib.canonicalPath)) {
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
        try await recorder.waitForChange(.board(inRepo: place.lib.canonicalPath)) {
            try await CrossRepoReadTests.boardPaths(with: enabled, on: session).contains(place.lib.path)
        }
        let paths = try await CrossRepoReadTests.boardPaths(with: enabled, on: session)
        #expect(paths == [place.app.path, place.lib.path])
        await host.close()
    }

    // MARK: - Helpers

    /// Tells if a call finds the board of a board key.
    ///
    /// - Parameters:
    ///   - key: The board key.
    ///   - graph: The engine.
    /// - Returns: `true` when the call gives a board, and `false` when it gives no board.
    /// - Throws: An error when the call cannot run.
    static func hasBoard(of key: String, on graph: KanbanGraph) async throws -> Bool {
        let response = try await KanbanGraphTests.execute(#"{ board(id: "\#(key)") { path } }"#, on: graph)
        return try NameRewriteTests.data(of: response)["board"] as? [String: Any] != nil
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

// MARK: - Key reader

/// Gives the key of each repo of a ``ScanPlace`` by the name of its folder, with no git, and counts each read of a
/// key and of a worktree top. A repo with no origin in the table gives a git failure, the same as a repo whose key
/// git cannot read.
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

    /// The number of reads of a key or of a worktree top so far.
    var count: Int {
        calls.withLock { calls in calls }
    }

    /// Gives a repo a new `origin`, the same as `git remote set-url`.
    ///
    /// - Parameters:
    ///   - origin: The new `origin`.
    ///   - name: The name of the folder of the repo.
    func setOrigin(_ origin: String, ofRepoNamed name: String) {
        origins.withLock { origins in origins[name] = origin }
    }

    /// The reader as a ``BoardKeyReader``: it counts the read and gives the key of the `origin` of the folder.
    var keyReader: BoardKeyReader {
        { root throws(BoardKeyError) in
            self.calls.withLock { calls in calls += 1 }
            let name = root.lastPathComponent
            guard let origin = self.origins.withLock({ origins in origins[name] }) else {
                throw .gitFailed(arguments: [], status: Self.failureStatus, message: "no origin for \(name)")
            }
            return try BoardKey(remoteURL: origin)
        }
    }

    /// The reader as a ``WorktreeTopReader``: it counts the read, and each folder is the top folder of its worktree.
    var topReader: WorktreeTopReader {
        { directory in
            self.calls.withLock { calls in calls += 1 }
            return directory
        }
    }
}

// MARK: - Scan recorder

/// Records each scan of a host, and gives each change of a scan place that the file watcher of the host sees.
final class ScanRecorder: BoardScanObserver {
    /// The number of scans that started, behind a lock, because the scans run on different threads.
    private let starts = Mutex(0)

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

    /// Counts a scan.
    ///
    /// - Parameter places: The places of the scan.
    func scanDidStart(inPlaces places: [URL]) {
        starts.withLock { starts in starts += 1 }
    }

    /// Records a change of a scan place.
    ///
    /// - Parameter change: The change.
    func scanPlaceDidChange(_ change: ScanChange) {
        changeSink.yield(change)
    }

    /// Waits until the host saw a change, and the effect of the change shows. The file watcher can tell a change that
    /// came before the test action, for example the make of the repo folders, so the first change that is equal to
    /// `expected` is not always the change of the test action. After each change that is equal to `expected`, the
    /// wait asks the condition, and it ends when the condition is `true`. Call it one time for each recorder.
    ///
    /// - Parameters:
    ///   - expected: The change.
    ///   - isShown: Tells if the effect of the test action shows. The wait asks it after each equal change.
    /// - Throws: An error that `isShown` throws.
    func waitForChange(_ expected: ScanChange, until isShown: () async throws -> Bool) async throws {
        for await change in changes where change == expected {
            if try await isShown() {
                return
            }
        }
    }
}
