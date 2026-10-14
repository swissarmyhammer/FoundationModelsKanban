import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the parts of the scan cache that need no file watcher (divergence.md §16, Gap 1): which changed path of a
/// scan place is a ``ScanChange``, what a change does to a ``BoardIndex``, and when a ``ScanCache`` gives its index
/// with no new scan.
@Suite("Scan cache: changes of a scan place")
struct ScanChangeTests {
    /// The canonical path of the scan place of the tests.
    static let placePath = "/work/src"

    /// The real path of the scan place, as FSEvents gives it.
    static let placeRealPath = "/private/work/src"

    /// The scan place of the tests.
    static let place = WatchedPlace(path: placePath, realPath: placeRealPath)

    /// The canonical path of the related repo of the tests.
    static let libPath = "\(placePath)/lib"

    /// The canonical path of a worktree of the related repo.
    static let worktreePath = "\(placePath)/lib-feature"

    /// The canonical path of the current repo of the tests.
    static let appPath = "\(placePath)/app"

    /// The canonical path of a repo whose key read failed.
    static let brokenPath = "\(placePath)/broken"

    /// The canonical path of a repo in a different place.
    static let otherPath = "/elsewhere/tool"

    /// The places key of the cache tests: the one place of the tests.
    static let placesKey = [placePath]

    /// Gives a copy of a repo of the tests.
    ///
    /// - Parameters:
    ///   - path: The canonical path of the repo.
    ///   - origin: The `origin` of the repo.
    /// - Returns: The copy.
    /// - Throws: An error when the origin is not a valid remote.
    static func copy(at path: String, origin: String) throws -> BoardCopy {
        BoardCopy(
            directory: URL(filePath: path, directoryHint: .isDirectory),
            key: try BoardKey(remoteURL: origin),
            isEnabled: false
        )
    }

    /// The index of the tests: the current repo, the related repo and its worktree, a repo in a different place, and
    /// a repo whose key read failed.
    ///
    /// - Returns: The index.
    /// - Throws: An error when an origin is not a valid remote.
    static func index() throws -> BoardIndex {
        BoardIndex(
            places: [URL(filePath: placePath, directoryHint: .isDirectory)],
            copies: [
                try copy(at: appPath, origin: ScanCacheTests.appOrigin),
                try copy(at: libPath, origin: ScanCacheTests.libOrigin),
                try copy(at: worktreePath, origin: ScanCacheTests.libOrigin),
                try copy(at: otherPath, origin: ScanCacheTests.newOrigin),
            ],
            unreadable: [brokenPath]
        )
    }

    /// Gives the canonical path of each copy of an index.
    ///
    /// - Parameter index: The index.
    /// - Returns: The paths, in index order.
    static func paths(in index: BoardIndex) -> [String] {
        index.copies.map(\.directory.path)
    }

    // MARK: - Classification

    @Test(
        "A changed path in a scan place gives the change of its repo",
        arguments: [
            ("", ScanChange.place(placePath)),
            ("/lib", .repo(libPath)),
            ("/lib/.git", .repo(libPath)),
            ("/lib/.git/config", .repo(libPath)),
            ("/lib/.kanban", .board(inRepo: libPath)),
            ("/lib/.kanban/board.jsonl", .board(inRepo: libPath)),
            ("/lib/.git/refs/heads/main", .commits(inRepo: libPath)),
            ("/lib/.git/packed-refs", .commits(inRepo: libPath)),
        ]
    )
    func changedPathGivesChange(relativePath: String, expected: ScanChange) {
        #expect(Self.place.change(at: Self.placeRealPath + relativePath) == expected)
    }

    @Test(
        "A changed path that does not change a repo, its key, or its board log gives no change",
        arguments: [
            "/lib/README.md",
            "/lib/Sources/main.swift",
            "/lib/.git/index",
            "/lib/.git/objects/ab/cdef",
            "/lib/.kanban/tasks/01ABC.jsonl",
            "/lib-other/.git/config/extra",
        ]
    )
    func otherPathGivesNoChange(relativePath: String) {
        #expect(Self.place.change(at: Self.placeRealPath + relativePath) == nil)
    }

    @Test("A changed path outside the place gives no change")
    func pathOutsidePlaceGivesNoChange() {
        #expect(Self.place.change(at: "/private/work/srcfoo/lib/.git/config") == nil)
        #expect(Self.place.change(at: "/private/work") == nil)
    }

    @Test("A changed path under the canonical path of the place gives the same change as under its real path")
    func canonicalPathGivesChange() {
        #expect(Self.place.change(at: "\(Self.libPath)/.git/config") == .repo(Self.libPath))
    }

    @Test("A watched place has the canonical path and the real path of its folder")
    func watchedPlaceOfFolder() throws {
        let directory = try TemporaryDirectory()
        let place = WatchedPlace(watching: directory.url)
        #expect(place.path == directory.url.canonicalPath)
        #expect(place.realPath.hasSuffix(directory.url.lastPathComponent))
        #expect(place.change(at: "\(place.realPath)/lib") == .repo("\(place.path)/lib"))
    }

    // MARK: - Index

    @Test("A changed repo makes the index forget that repo and each copy with its key")
    func changedRepoForgetsCopiesWithItsKey() throws {
        let index = try Self.index()
        let forgotten = index.forgetting(.repo(Self.libPath))
        #expect(index.isExpired(by: .repo(Self.libPath)))
        #expect(Self.paths(in: forgotten) == [Self.appPath, Self.otherPath])
    }

    @Test("A changed repo whose key read failed makes the index read its key again")
    func changedBrokenRepoIsReadAgain() throws {
        let index = try Self.index()
        let forgotten = index.forgetting(.repo(Self.brokenPath))
        #expect(forgotten.unreadable.isEmpty)
        #expect(Self.paths(in: forgotten) == Self.paths(in: index))
    }

    @Test("New commits expire the index only for a repo whose key read failed")
    func commitsExpireOnlyUnreadableRepo() throws {
        let index = try Self.index()
        #expect(!index.isExpired(by: .commits(inRepo: Self.libPath)))
        #expect(index.isExpired(by: .commits(inRepo: Self.brokenPath)))
        #expect(index.forgetting(.commits(inRepo: Self.brokenPath)).unreadable.isEmpty)
    }

    @Test("A changed board log expires the index and forgets no key")
    func boardLogExpiresAndKeepsKeys() throws {
        let index = try Self.index()
        #expect(index.isExpired(by: .board(inRepo: Self.libPath)))
        #expect(Self.paths(in: index.forgetting(.board(inRepo: Self.libPath))) == Self.paths(in: index))
    }

    @Test("A change of the place itself forgets each repo of the place, and keeps the repos of other places")
    func placeChangeForgetsReposOfPlace() throws {
        let forgotten = try Self.index().forgetting(.place(Self.placePath))
        #expect(Self.paths(in: forgotten) == [Self.otherPath])
        #expect(forgotten.unreadable.isEmpty)
    }

    // MARK: - Cache

    @Test("A cache gives no current index before a scan, and the index of a watched scan after it")
    func cacheIsCurrentAfterWatchedScan() throws {
        var cache = ScanCache()
        #expect(cache.currentIndex(ofPlaces: Self.placesKey) == nil)
        _ = cache.beginScan(ofPlaces: Self.placesKey)
        let index = try Self.index()
        _ = cache.finishScan(index, ofPlaces: Self.placesKey, isWatched: true)
        #expect(cache.currentIndex(ofPlaces: Self.placesKey).map(Self.paths(in:)) == Self.paths(in: index))
    }

    @Test("A scan whose places have no running watcher is not current")
    func unwatchedScanIsNotCurrent() throws {
        var cache = ScanCache()
        _ = cache.beginScan(ofPlaces: Self.placesKey)
        _ = cache.finishScan(try Self.index(), ofPlaces: Self.placesKey, isWatched: false)
        #expect(cache.currentIndex(ofPlaces: Self.placesKey) == nil)
        #expect(cache.index(ofPlaces: Self.placesKey) != nil)
    }

    @Test("A change after a scan makes the index stale, forgets its repo, and the next scan reuses the rest")
    func changeAfterScanMakesIndexStale() throws {
        var cache = ScanCache()
        _ = cache.beginScan(ofPlaces: Self.placesKey)
        _ = cache.finishScan(try Self.index(), ofPlaces: Self.placesKey, isWatched: true)
        cache.apply(.repo(Self.libPath), inPlace: Self.placePath)
        #expect(cache.currentIndex(ofPlaces: Self.placesKey) == nil)
        let earlier = cache.beginScan(ofPlaces: Self.placesKey)
        #expect(earlier.map(Self.paths(in:)) == [Self.appPath, Self.otherPath])
    }

    @Test("A change that does not expire the index keeps it current")
    func changeThatDoesNotExpireKeepsIndex() throws {
        var cache = ScanCache()
        _ = cache.beginScan(ofPlaces: Self.placesKey)
        _ = cache.finishScan(try Self.index(), ofPlaces: Self.placesKey, isWatched: true)
        cache.apply(.commits(inRepo: Self.libPath), inPlace: Self.placePath)
        #expect(cache.currentIndex(ofPlaces: Self.placesKey) != nil)
    }

    @Test("A change in a different place does not change the index")
    func changeInOtherPlaceKeepsIndex() throws {
        var cache = ScanCache()
        _ = cache.beginScan(ofPlaces: Self.placesKey)
        _ = cache.finishScan(try Self.index(), ofPlaces: Self.placesKey, isWatched: true)
        cache.apply(.repo(Self.otherPath), inPlace: "/elsewhere")
        #expect(cache.currentIndex(ofPlaces: Self.placesKey) != nil)
    }

    @Test("A change during a scan makes the result of the scan stale, and the result forgets the repo of the change")
    func changeDuringScanMakesResultStale() throws {
        var cache = ScanCache()
        _ = cache.beginScan(ofPlaces: Self.placesKey)
        cache.apply(.repo(Self.libPath), inPlace: Self.placePath)
        let stored = cache.finishScan(try Self.index(), ofPlaces: Self.placesKey, isWatched: true)
        #expect(cache.currentIndex(ofPlaces: Self.placesKey) == nil)
        #expect(Self.paths(in: stored) == [Self.appPath, Self.otherPath])
    }

    @Test("A scan that stops keeps the earlier index of the places")
    func abandonedScanKeepsEarlierIndex() throws {
        var cache = ScanCache()
        _ = cache.beginScan(ofPlaces: Self.placesKey)
        let index = try Self.index()
        _ = cache.finishScan(index, ofPlaces: Self.placesKey, isWatched: true)
        _ = cache.beginScan(ofPlaces: Self.placesKey)
        cache.abandonScan(ofPlaces: Self.placesKey)
        #expect(cache.currentIndex(ofPlaces: Self.placesKey).map(Self.paths(in:)) == Self.paths(in: index))
    }
}
