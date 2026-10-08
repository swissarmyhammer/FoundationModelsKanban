import Foundation
import Synchronization
import Testing

@testable import FoundationModelsKanban

/// Tests the board locator: the scan of the places for git repos, the index of the copies, and the board refs
/// (plan.md §6.6, §12 items 13 and 26).
///
/// Each test makes real git repos in a ``GitSandbox``. The sandbox directory is the parent directory of the current
/// repo, so the scan looks in it first.
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

        /// Makes the repos.
        ///
        /// - Parameter sandbox: The sandbox of the test.
        /// - Throws: An error when a git command fails.
        init(in sandbox: GitSandbox) throws {
            current = try sandbox.makeRepo(named: currentCopyName, origin: appOrigin)
            worktree = try sandbox.addWorktree(named: worktreeName, to: current)
            firstCopy = try sandbox.makeRepo(named: firstCopyName, origin: libOrigin)
            secondCopy = try sandbox.makeRepo(named: secondCopyName, origin: libOrigin)
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
    static func scan(around root: URL, with locator: BoardLocator = .default) -> BoardIndex {
        locator.scan(around: root, readingKeysWith: BoardKey.read(fromRepoAt:))
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

    // MARK: - Scan

    @Test("A scan finds each git repo one level down in the parent directory, with the key of its origin")
    func scanFindsReposWithKeys() throws {
        let sandbox = try GitSandbox()
        let app = try sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        _ = try sandbox.makeRepo(named: Self.libName, origin: Self.libOrigin)
        try FileManager.default.createDirectory(
            at: sandbox.root.appending(path: "notes", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let index = Self.scan(around: app)
        #expect(Self.names(in: index) == [Self.appName, Self.libName])
        #expect(try index.copies.map(\.key) == [Self.key(of: Self.appOrigin), Self.key(of: Self.libOrigin)])
    }

    @Test("A copy is enabled only when it has .kanban/board.jsonl")
    func copyIsEnabledWithBoardLog() throws {
        let sandbox = try GitSandbox()
        let app = try sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        let lib = try sandbox.makeRepo(named: Self.libName, origin: Self.libOrigin)
        _ = try KanbanGraphTests.writeFixture(inRepoAt: lib)
        #expect(Self.scan(around: app).copies.map(\.isEnabled) == [false, true])
    }

    @Test("The scan order is the parent directory, then each search root in config order, with the names sorted")
    func scanOrderFollowsPlacesAndNames() throws {
        let sandbox = try GitSandbox()
        let app = try sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        _ = try sandbox.makeRepo(named: "b-lib", origin: Self.libOrigin)
        _ = try sandbox.makeRepo(named: "first-root/z-lib", origin: Self.libOrigin)
        _ = try sandbox.makeRepo(named: "second-root/a-lib", origin: Self.libOrigin)
        let roots = ["first-root", "second-root"].map { name in
            sandbox.root.appending(path: name, directoryHint: .isDirectory)
        }
        let index = Self.scan(around: app, with: BoardLocator(searchRoots: roots))
        #expect(index.places.map(\.path) == [sandbox.root.path] + roots.map(\.path))
        #expect(Self.names(in: index) == [Self.appName, "b-lib", "z-lib", "a-lib"])
    }

    @Test("A search root that is the parent directory is a place one time, and its repos are copies one time")
    func parentAsSearchRootIsScannedOneTime() throws {
        let sandbox = try GitSandbox()
        let app = try sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        let index = Self.scan(around: app, with: BoardLocator(searchRoots: [sandbox.root]))
        #expect(index.places.map(\.path) == [sandbox.root.path])
        #expect(Self.names(in: index) == [Self.appName])
    }

    @Test("A worktree is a copy with the key of its main clone")
    func worktreeIsCopyWithKeyOfMainClone() throws {
        let sandbox = try GitSandbox()
        let repos = try TwoCopies(in: sandbox)
        let index = Self.scan(around: repos.current)
        #expect(try Self.copy(at: repos.worktree, in: index).key == Self.key(of: Self.appOrigin))
    }

    @Test("A rescan reads the key only of a repo that the earlier scan did not find")
    func rescanReadsKeyOfNewRepoOnly() throws {
        let sandbox = try GitSandbox()
        let app = try sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        _ = try sandbox.makeRepo(named: Self.libName, origin: Self.libOrigin)
        let reader = CountingKeyReader()
        let first = BoardLocator.default.scan(around: app) { root throws(BoardKeyError) in
            try reader.key(ofRepoAt: root)
        }
        #expect(reader.readCount == Self.firstScanReads)
        let newRepo = try sandbox.makeRepo(named: "new-lib", origin: Self.newOrigin)
        let second = BoardLocator.default.scan(around: app, reusing: first) { root throws(BoardKeyError) in
            try reader.key(ofRepoAt: root)
        }
        #expect(reader.readCount == Self.firstScanReads + 1)
        #expect(try Self.copy(at: newRepo, in: second).key == Self.key(of: Self.newOrigin))
    }

    // MARK: - Board refs

    @Test("The current key resolves to the current directory, also when a different copy comes first")
    func currentKeyResolvesToCurrentDirectory() throws {
        let sandbox = try GitSandbox()
        let repos = try TwoCopies(in: sandbox)
        let index = Self.scan(around: repos.current)
        #expect(Self.names(in: index).first == Self.worktreeName)
        #expect(try Self.resolve(Self.key(of: Self.appOrigin).description, in: repos, index: index) == .current)
    }

    @Test("A related key resolves to the first copy in scan order")
    func relatedKeyResolvesToFirstCopy() throws {
        let sandbox = try GitSandbox()
        let repos = try TwoCopies(in: sandbox)
        let index = Self.scan(around: repos.current)
        let resolution = try Self.resolve(Self.key(of: Self.libOrigin).description, in: repos, index: index)
        #expect(resolution == .copy(try Self.copy(at: repos.firstCopy, in: index)))
    }

    @Test("A unique repo directory name resolves to its copy")
    func uniqueNameResolvesToCopy() throws {
        let sandbox = try GitSandbox()
        let repos = try TwoCopies(in: sandbox)
        let index = Self.scan(around: repos.current)
        let resolution = try Self.resolve(Self.secondCopyName, in: repos, index: index)
        #expect(resolution == .copy(try Self.copy(at: repos.secondCopy, in: index)))
    }

    @Test("A repo directory name of two copies resolves to nothing")
    func sharedNameResolvesToNothing() throws {
        let sandbox = try GitSandbox()
        let app = try sandbox.makeRepo(named: Self.appName, origin: Self.appOrigin)
        _ = try sandbox.makeRepo(named: Self.libName, origin: Self.libOrigin)
        let root = sandbox.root.appending(path: "src", directoryHint: .isDirectory)
        _ = try sandbox.makeRepo(named: "src/\(Self.libName)", origin: Self.libOrigin)
        let index = Self.scan(around: app, with: BoardLocator(searchRoots: [root]))
        let key = try Self.key(of: Self.appOrigin)
        #expect(index.resolution(of: Self.libName, currentRoot: app, currentKey: key) == nil)
    }

    @Test("A path resolves to its copy, and the path of the current repo resolves to the current board")
    func pathResolvesToCopy() throws {
        let sandbox = try GitSandbox()
        let repos = try TwoCopies(in: sandbox)
        let index = Self.scan(around: repos.current)
        let resolution = try Self.resolve(repos.secondCopy.path, in: repos, index: index)
        #expect(resolution == .copy(try Self.copy(at: repos.secondCopy, in: index)))
        #expect(try Self.resolve(repos.current.path, in: repos, index: index) == .current)
    }

    @Test("A board URI resolves by its key")
    func boardURIResolvesByKey() throws {
        let sandbox = try GitSandbox()
        let repos = try TwoCopies(in: sandbox)
        let index = Self.scan(around: repos.current)
        let uri = NodeURI(boardKey: try Self.key(of: Self.libOrigin).description, ref: .board).description
        let resolution = try Self.resolve(uri, in: repos, index: index)
        #expect(resolution == .copy(try Self.copy(at: repos.firstCopy, in: index)))
    }

    @Test("A ref that names no copy resolves to nothing")
    func unknownRefResolvesToNothing() throws {
        let sandbox = try GitSandbox()
        let repos = try TwoCopies(in: sandbox)
        let index = Self.scan(around: repos.current)
        #expect(try Self.resolve("github.com/example/missing", in: repos, index: index) == nil)
    }
}

// MARK: - Counting key reader

/// A key reader that reads the key from git and counts its reads.
final class CountingKeyReader: Sendable {
    /// The number of reads, behind a lock, because a scan can read from a different thread.
    private let reads = Mutex(0)

    /// The number of reads so far.
    var readCount: Int {
        reads.withLock { count in count }
    }

    /// Reads the key of a repo from git, and counts the read.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The key.
    /// - Throws: A ``BoardKeyError`` when git fails.
    func key(ofRepoAt root: URL) throws(BoardKeyError) -> BoardKey {
        reads.withLock { count in count += 1 }
        return try BoardKey.read(fromRepoAt: root)
    }
}
