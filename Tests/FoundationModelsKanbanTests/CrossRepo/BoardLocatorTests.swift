import Foundation
import Synchronization
import Testing

@testable import FoundationModelsKanban

/// Tests the board locator: the scan of the places for git repos and for folders with a board, the index of the
/// copies, and the board refs (plan.md §6.6, §12 items 13 and 26).
///
/// Each test makes real git repos or plain folders in a ``GitSandbox``. The sandbox directory is the parent directory
/// of the current repo, so the scan looks in it first.
@Suite("Cross-repo: board locator")
struct BoardLocatorTests {
    /// The `origin` of the current repo of the tests.
    static let appOrigin = "https://github.com/example/app.git"

    /// The `origin` of the related repo of the tests.
    static let libOrigin = "https://github.com/example/lib.git"

    /// The `origin` of a repo that a test makes after the first scan.
    static let newOrigin = "https://github.com/example/new-lib.git"

    /// The name of the current repo of a test with one copy of each repo.
    static let appName = "app"

    /// The name of the related repo of a test with one copy of each repo.
    static let libName = "lib"

    /// The name of the first copy of the current repo in scan order: a worktree of ``currentCopyName``.
    static let worktreeName = "a-app"

    /// The name of the current repo of a test with two copies of each repo.
    static let currentCopyName = "b-app"

    /// The name of the first copy of the related repo in scan order.
    static let firstCopyName = "c-lib"

    /// The name of the second copy of the related repo in scan order.
    static let secondCopyName = "d-lib"

    /// The number of key reads of the first scan of the rescan test: the current repo and the related repo.
    static let firstScanReads = 2

    /// The key of ``appOrigin`` with its host in mixed case.
    static let mixedCaseAppKey = "GitHub.com/example/app"

    /// The key of ``libOrigin`` with its host in mixed case.
    static let mixedCaseLibKey = "GitHub.com/example/lib"

    /// The name of the folder of a board outside the places of the scan.
    static let outsideName = "other"

    /// The path of ``outsideName`` from the sandbox root. The folder is two levels down, so the scan does not find it.
    static let outsidePath = "outside/\(outsideName)"

    /// The name of a folder that no test makes.
    static let missingName = "missing"

    /// The name of a file that a test makes in the sandbox root.
    static let fileName = "notes.txt"

    // MARK: - Fixture

    /// The repos of a sandbox with two copies of the current repo and two copies of the related repo.
    struct TwoCopies {
        /// The current repo, ``currentCopyName``.
        let current: URL

        /// The worktree of the current repo, ``worktreeName``. It comes first in scan order.
        let worktree: URL

        /// The first copy of the related repo, ``firstCopyName``.
        let firstCopy: URL

        /// The second copy of the related repo, ``secondCopyName``.
        let secondCopy: URL

        /// Runs git to make the repos in a sandbox.
        ///
        /// - Parameter sandbox: The sandbox of the test.
        /// - Returns: The repos.
        /// - Throws: An error when a git command fails.
        static func make(in sandbox: GitSandbox) async throws -> TwoCopies {
            let current = try await sandbox.makeRepo(named: currentCopyName, origin: appOrigin)
            return TwoCopies(
                current: current,
                worktree: try await sandbox.addWorktree(named: worktreeName, to: current),
                firstCopy: try await sandbox.makeRepo(named: firstCopyName, origin: libOrigin),
                secondCopy: try await sandbox.makeRepo(named: secondCopyName, origin: libOrigin)
            )
        }
    }

    /// Gives the key of a remote URL.
    ///
    /// - Parameter origin: The remote URL.
    /// - Returns: The key.
    /// - Throws: An error when the URL is not a valid remote.
    static func key(of origin: String) throws -> BoardKey {
        try BoardKey(remoteURL: origin)
    }

    /// Scans the places around a current repo, with the keys from git.
    ///
    /// - Parameters:
    ///   - root: The root directory of the current repo.
    ///   - locator: The locator. The default looks only in the parent directory.
    /// - Returns: The index.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the test is cancelled during the scan.
    static func scan(
        around root: URL,
        with locator: BoardLocator = .default
    ) async throws(BoardKeyError) -> BoardIndex {
        try await locator.scan(around: root, readingKeysWith: BoardKey.read(fromRepoAt:))
    }

    /// Gives the names of the directories of the copies of an index, in scan order.
    ///
    /// - Parameter index: The index.
    /// - Returns: The names.
    static func names(in index: BoardIndex) -> [String] {
        index.copies.map(\.directory.lastPathComponent)
    }

    /// Gives the copy of an index in a directory.
    ///
    /// - Parameters:
    ///   - directory: The root directory of the copy.
    ///   - index: The index.
    /// - Returns: The copy.
    /// - Throws: An error when the index has no copy in the directory.
    static func copy(at directory: URL, in index: BoardIndex) throws -> BoardCopy {
        try #require(index.copies.first { copy in copy.directory.path == directory.path })
    }

    /// Resolves a board ref in the index of a sandbox with two copies of each repo.
    ///
    /// - Parameters:
    ///   - reference: The board ref.
    ///   - repos: The repos of the sandbox.
    ///   - index: The index of the scan around the current repo.
    /// - Returns: The resolution.
    /// - Throws: An error when the key of the current repo is not valid.
    static func resolve(_ reference: String, in repos: TwoCopies, index: BoardIndex) throws -> BoardResolution? {
        index.resolution(of: reference, currentRoot: repos.current, currentKey: try key(of: appOrigin))
    }

    /// Resolves a board ref in the index of a new sandbox with two copies of each repo, and gives the board of one copy
    /// for the comparison.
    ///
    /// - Parameters:
    ///   - reference: The board ref.
    ///   - name: The directory name of the copy that the ref must name.
    /// - Returns: The resolution of the ref, and the board of the copy with the name.
    /// - Throws: An error when a git command fails, or when the index has no copy with the name.
    static func resolveInTwoCopies(
        _ reference: String,
        expectingCopyNamed name: String
    ) async throws -> (actual: BoardResolution?, expected: BoardResolution) {
        let sandbox = try GitSandbox()
        let repos = try await TwoCopies.make(in: sandbox)
        let index = try await scan(around: repos.current)
        let directory = sandbox.root.appending(path: name, directoryHint: .isDirectory)
        let expected = BoardResolution(of: try copy(at: directory, in: index), currentRoot: repos.current)
        return (try resolve(reference, in: repos, index: index), expected)
    }

    /// Resolves a path ref to the board of any folder, with the keys from git.
    ///
    /// - Parameters:
    ///   - reference: The board ref.
    ///   - root: The root directory of the current repo.
    /// - Returns: The resolution, or `nil` when the ref is not a path to a folder.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the test is cancelled during the key read.
    static func resolveFolder(_ reference: String, around root: URL) async throws(BoardKeyError) -> BoardResolution? {
        try await BoardLocator.resolution(
            ofFolderAt: reference,
            currentRoot: root,
            readingKeysWith: BoardKey.read(fromRepoAt:)
        )
    }

    // MARK: - Scan

    @Test("A scan finds each git repo one level down in the parent directory, with the key of its origin")
    func scanFindsReposWithKeys() async throws {
        let sandbox = try GitSandbox()
        let app = try await sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        _ = try await sandbox.makeRepo(named: Self.libName, origin: Self.libOrigin)
        try FileManager.default.createDirectory(
            at: sandbox.root.appending(path: "notes", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let index = try await Self.scan(around: app)
        #expect(Self.names(in: index) == [Self.appName, Self.libName])
        #expect(try index.copies.map(\.key) == [Self.key(of: Self.appOrigin), Self.key(of: Self.libOrigin)])
    }

    @Test("A copy is enabled only when it has .kanban/board.jsonl")
    func copyIsEnabledWithBoardLog() async throws {
        let sandbox = try GitSandbox()
        let app = try await sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        let lib = try await sandbox.makeRepo(named: Self.libName, origin: Self.libOrigin)
        _ = try KanbanGraphTests.writeFixture(inRepoAt: lib)
        #expect(try await Self.scan(around: app).copies.map(\.isEnabled) == [false, true])
    }

    @Test("A scan finds a folder with .kanban/board.jsonl and no .git, with the key local/<folder-name>")
    func scanFindsBoardInFolderWithNoGit() async throws {
        let sandbox = try GitSandbox()
        let app = try await sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        let lib = try GitSandbox.makeFolder(named: Self.libName, in: sandbox.root)
        _ = try KanbanGraphTests.writeFixture(inRepoAt: lib)
        let index = try await Self.scan(around: app)
        let expected = BoardCopy(directory: lib, key: BoardKey(localDirectoryName: Self.libName), isEnabled: true)
        #expect(try Self.copy(at: lib, in: index) == expected)
    }

    @Test("A folder with no .git and no .kanban/board.jsonl is not a copy")
    func folderWithNoGitAndNoBoardIsNotCopy() async throws {
        let sandbox = try GitSandbox()
        let app = try await sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        _ = try GitSandbox.makeFolder(named: Self.libName, in: sandbox.root)
        #expect(Self.names(in: try await Self.scan(around: app)) == [Self.appName])
    }

    @Test("The scan order is the parent directory, then each search root in config order, with the names sorted")
    func scanOrderFollowsPlacesAndNames() async throws {
        let sandbox = try GitSandbox()
        let app = try await sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        _ = try await sandbox.makeRepo(named: "b-lib", origin: Self.libOrigin)
        _ = try await sandbox.makeRepo(named: "first-root/z-lib", origin: Self.libOrigin)
        _ = try await sandbox.makeRepo(named: "second-root/a-lib", origin: Self.libOrigin)
        let roots = ["first-root", "second-root"].map { name in
            sandbox.root.appending(path: name, directoryHint: .isDirectory)
        }
        let index = try await Self.scan(around: app, with: BoardLocator(searchRoots: roots))
        #expect(index.places.map(\.path) == [sandbox.root.path] + roots.map(\.path))
        #expect(Self.names(in: index) == [Self.appName, "b-lib", "z-lib", "a-lib"])
    }

    @Test("A search root that is the parent directory is a place one time, and its repos are copies one time")
    func parentAsSearchRootIsScannedOneTime() async throws {
        let sandbox = try GitSandbox()
        let app = try await sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        let index = try await Self.scan(around: app, with: BoardLocator(searchRoots: [sandbox.root]))
        #expect(index.places.map(\.path) == [sandbox.root.path])
        #expect(Self.names(in: index) == [Self.appName])
    }

    @Test("A worktree is a copy with the key of its main clone")
    func worktreeIsCopyWithKeyOfMainClone() async throws {
        let sandbox = try GitSandbox()
        let repos = try await TwoCopies.make(in: sandbox)
        let index = try await Self.scan(around: repos.current)
        #expect(try Self.copy(at: repos.worktree, in: index).key == Self.key(of: Self.appOrigin))
    }

    @Test("A rescan reads the key only of a repo that the earlier scan did not find")
    func rescanReadsKeyOfNewRepoOnly() async throws {
        let sandbox = try GitSandbox()
        let app = try await sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        _ = try await sandbox.makeRepo(named: Self.libName, origin: Self.libOrigin)
        let reader = CountingKeyReader()
        let readKey: BoardKeyReader = reader.keyReader
        let first = try await BoardLocator.default.scan(around: app, readingKeysWith: readKey)
        #expect(reader.readCount == Self.firstScanReads)
        let newRepo = try await sandbox.makeRepo(named: "new-lib", origin: Self.newOrigin)
        let second = try await BoardLocator.default.scan(around: app, reusing: first, readingKeysWith: readKey)
        #expect(reader.readCount == Self.firstScanReads + 1)
        #expect(try Self.copy(at: newRepo, in: second).key == Self.key(of: Self.newOrigin))
    }

    // MARK: - Board refs

    @Test("The current key resolves to the current directory, also when a different copy comes first")
    func currentKeyResolvesToCurrentDirectory() async throws {
        let sandbox = try GitSandbox()
        let repos = try await TwoCopies.make(in: sandbox)
        let index = try await Self.scan(around: repos.current)
        #expect(Self.names(in: index).first == Self.worktreeName)
        #expect(try Self.resolve(Self.key(of: Self.appOrigin).description, in: repos, index: index) == .current)
    }

    @Test("A related key resolves to the first copy in scan order")
    func relatedKeyResolvesToFirstCopy() async throws {
        let sandbox = try GitSandbox()
        let repos = try await TwoCopies.make(in: sandbox)
        let index = try await Self.scan(around: repos.current)
        let resolution = try Self.resolve(Self.key(of: Self.libOrigin).description, in: repos, index: index)
        #expect(resolution == .copy(try Self.copy(at: repos.firstCopy, in: index)))
    }

    @Test(
        "A bare key whose host is in mixed case resolves to the board of the key with the host in lowercase",
        arguments: [(mixedCaseAppKey, currentCopyName), (mixedCaseLibKey, firstCopyName)]
    )
    func mixedCaseHostKeyResolves(reference: String, expectedCopyName: String) async throws {
        let resolved = try await Self.resolveInTwoCopies(reference, expectingCopyNamed: expectedCopyName)
        #expect(resolved.actual == resolved.expected)
    }

    @Test("A unique repo directory name resolves to its copy")
    func uniqueNameResolvesToCopy() async throws {
        let sandbox = try GitSandbox()
        let repos = try await TwoCopies.make(in: sandbox)
        let index = try await Self.scan(around: repos.current)
        let resolution = try Self.resolve(Self.secondCopyName, in: repos, index: index)
        #expect(resolution == .copy(try Self.copy(at: repos.secondCopy, in: index)))
    }

    @Test("A repo directory name of two copies resolves to nothing")
    func sharedNameResolvesToNothing() async throws {
        let sandbox = try GitSandbox()
        let app = try await sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        _ = try await sandbox.makeRepo(named: Self.libName, origin: Self.libOrigin)
        let root = sandbox.root.appending(path: "src", directoryHint: .isDirectory)
        _ = try await sandbox.makeRepo(named: "src/\(Self.libName)", origin: Self.libOrigin)
        let index = try await Self.scan(around: app, with: BoardLocator(searchRoots: [root]))
        let key = try Self.key(of: Self.appOrigin)
        #expect(index.resolution(of: Self.libName, currentRoot: app, currentKey: key) == nil)
    }

    @Test("A path resolves to its copy, and the path of the current repo resolves to the current board")
    func pathResolvesToCopy() async throws {
        let sandbox = try GitSandbox()
        let repos = try await TwoCopies.make(in: sandbox)
        let index = try await Self.scan(around: repos.current)
        let resolution = try Self.resolve(repos.secondCopy.path, in: repos, index: index)
        #expect(resolution == .copy(try Self.copy(at: repos.secondCopy, in: index)))
        #expect(try Self.resolve(repos.current.path, in: repos, index: index) == .current)
    }

    @Test(
        "A path that starts with ./ or ../ resolves from the current root",
        arguments: [("../\(secondCopyName)", secondCopyName), ("./", currentCopyName)]
    )
    func relativePathResolvesFromRoot(reference: String, expectedCopyName: String) async throws {
        let resolved = try await Self.resolveInTwoCopies(reference, expectingCopyNamed: expectedCopyName)
        #expect(resolved.actual == resolved.expected)
    }

    @Test(
        "A path to a folder that the scan does not find resolves to a copy with the key of the folder",
        arguments: CrossRepoFixture.FolderKind.allCases
    )
    func pathOutsidePlacesResolvesToFolder(kind: CrossRepoFixture.FolderKind) async throws {
        let sandbox = try GitSandbox()
        let app = try await sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        let other = try await kind.makeFolder(named: Self.outsidePath, origin: Self.libOrigin, in: sandbox)
        #expect(Self.names(in: try await Self.scan(around: app)) == [Self.appName])
        let key = try kind.key(ofFolderNamed: Self.outsideName, origin: Self.libOrigin)
        let expected = BoardResolution.copy(BoardCopy(directory: other, key: key, isEnabled: false))
        #expect(try await Self.resolveFolder(other.path, around: app) == expected)
    }

    @Test("A path from the current root to a folder that the scan does not find resolves to that folder")
    func relativePathOutsidePlacesResolvesToFolder() async throws {
        let sandbox = try GitSandbox()
        let app = try await sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        let other = try GitSandbox.makeFolder(named: Self.outsidePath, in: sandbox.root)
        let key = BoardKey(localDirectoryName: Self.outsideName)
        let expected = BoardResolution.copy(BoardCopy(directory: other, key: key, isEnabled: false))
        #expect(try await Self.resolveFolder("../\(Self.outsidePath)", around: app) == expected)
    }

    @Test("The path of the current repo resolves to the current board with no scan")
    func folderPathOfCurrentRepoResolvesToCurrent() async throws {
        let sandbox = try GitSandbox()
        let app = try await sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        #expect(try await Self.resolveFolder(app.path, around: app) == .current)
    }

    @Test("A path to a folder that does not exist resolves to nothing")
    func missingFolderPathResolvesToNothing() async throws {
        let sandbox = try GitSandbox()
        let app = try await sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        let missing = sandbox.root.appending(path: Self.missingName, directoryHint: .isDirectory)
        #expect(try await Self.resolveFolder(missing.path, around: app) == nil)
    }

    @Test("A path to a file resolves to nothing")
    func filePathResolvesToNothing() async throws {
        let sandbox = try GitSandbox()
        let app = try await sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        let file = sandbox.root.appending(path: Self.fileName, directoryHint: .notDirectory)
        try Data().write(to: file)
        #expect(try await Self.resolveFolder(file.path, around: app) == nil)
    }

    @Test("A ref that is not a path does not resolve to a folder, also when a folder has the name")
    func nameIsNotFolderPath() async throws {
        let sandbox = try GitSandbox()
        let app = try await sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        _ = try GitSandbox.makeFolder(named: Self.libName, in: app)
        #expect(try await Self.resolveFolder(Self.libName, around: app) == nil)
    }

    @Test("A board URI resolves by its key")
    func boardURIResolvesByKey() async throws {
        let sandbox = try GitSandbox()
        let repos = try await TwoCopies.make(in: sandbox)
        let index = try await Self.scan(around: repos.current)
        let uri = NodeURI(boardKey: try Self.key(of: Self.libOrigin).description, ref: .board).description
        let resolution = try Self.resolve(uri, in: repos, index: index)
        #expect(resolution == .copy(try Self.copy(at: repos.firstCopy, in: index)))
    }

    @Test("A ref that names no copy resolves to nothing")
    func unknownRefResolvesToNothing() async throws {
        let sandbox = try GitSandbox()
        let repos = try await TwoCopies.make(in: sandbox)
        let index = try await Self.scan(around: repos.current)
        #expect(try Self.resolve("github.com/example/missing", in: repos, index: index) == nil)
    }
}

// MARK: - Counting key reader

/// A key reader that reads the key from git and counts its reads.
///
/// The reader can block the first read of one repo until the task of the read is cancelled. The blocked read then
/// throws ``BoardKeyError/gitCancelled(arguments:)``, the same as a git command that a cancel stops.
final class CountingKeyReader: Sendable {
    /// The number of seconds in ``blockLimit``.
    private static let blockLimitSeconds = 60

    /// The longest time that the blocked read waits for the cancel. After this time, the read reads from git.
    private static let blockLimit = Duration.seconds(blockLimitSeconds)

    /// The number of reads of each repo, by the canonical path of the repo, behind a lock, because a scan can read
    /// from a different thread.
    private let reads = Mutex([String: Int]())

    /// The canonical path of the repo whose first read blocks, or `nil` for no blocked read.
    private let blockedPath: String?

    /// Gets one element when the blocked read starts to wait for the cancel.
    private let blockedReads: AsyncStream<Void>

    /// Gives the element of ``blockedReads``.
    private let blockedReadStarts: AsyncStream<Void>.Continuation

    /// Makes a reader.
    ///
    /// - Parameter blocked: The root directory of the repo whose first read blocks until the task is cancelled, or
    ///   `nil` for no blocked read.
    init(blockingFirstReadOf blocked: URL? = nil) {
        blockedPath = blocked?.canonicalPath
        (blockedReads, blockedReadStarts) = AsyncStream.makeStream()
    }

    /// The reader as a ``BoardKeyReader`` for a scan or a graph: each call gives ``key(ofRepoAt:)``.
    var keyReader: BoardKeyReader {
        { root throws(BoardKeyError) in try await self.key(ofRepoAt: root) }
    }

    /// The number of reads so far.
    var readCount: Int {
        reads.withLock { counts in counts.values.reduce(0, +) }
    }

    /// Gives the number of reads of one repo so far.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The number of reads.
    func readCount(ofRepoAt root: URL) -> Int {
        reads.withLock { counts in counts[root.canonicalPath, default: 0] }
    }

    /// Waits until the blocked read starts to wait for the cancel.
    func waitForBlockedRead() async {
        var starts = blockedReads.makeAsyncIterator()
        await starts.next()
    }

    /// Reads the key of a repo from git, and counts the read. The first read of the blocked repo waits for the cancel
    /// of the task first.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The key.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the blocked read. A
    ///   ``BoardKeyError`` when git fails.
    func key(ofRepoAt root: URL) async throws(BoardKeyError) -> BoardKey {
        let path = root.canonicalPath
        let isFirstRead = reads.withLock { counts in
            counts[path, default: 0] += 1
            return counts[path] == 1
        }
        if isFirstRead, path == blockedPath {
            try await waitForCancel()
        }
        return try await BoardKey.read(fromRepoAt: root)
    }

    /// Waits for the cancel of the task, but not longer than ``blockLimit``.
    ///
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the wait.
    private func waitForCancel() async throws(BoardKeyError) {
        blockedReadStarts.yield()
        do {
            try await Task.sleep(for: Self.blockLimit)
        } catch {
            throw .gitCancelled(arguments: [])
        }
    }
}
