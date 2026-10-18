import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests that a scan index compares the files of a change with the files that the scan read (divergence.md §16,
/// Gap 1).
///
/// FSEvents gives an event id when fseventsd reads the change from the kernel, not when the change occurs. Thus the
/// file watcher of a scan place can give a change that occurred before the scan, after the scan ended. The scan read
/// the files after that change, so such a change must not make the index stale. Each test makes a real scan place
/// in a ``TemporaryDirectory`` and gives the change to the ``ScanCache`` directly, so no test needs a file watcher.
@Suite("Scan cache: a change of files that the scan already read keeps the index")
struct ScanMarksTests {
    /// The `origin` that a test writes into the git config of the related repo.
    static let changedOrigin = "https://github.com/example/changed.git"

    /// The name of a repo folder that a test makes after the scan.
    static let laterName = "later"

    @Test("A change of a repo whose files did not change after the scan keeps the index current")
    func unchangedRepoKeepsIndex() async throws {
        let place = try ScanPlace.make()
        var cache = try await Self.cache(afterScanOf: place)
        cache.apply(.repo(place.lib.canonicalPath), inPlace: Self.placePath(of: place))
        #expect(cache.currentIndex(ofPlaces: Self.placesKey(of: place)) != nil)
    }

    @Test("A change of the git config of a repo after the scan makes the index stale")
    func changedConfigExpiresIndex() async throws {
        let place = try ScanPlace.make()
        var cache = try await Self.cache(afterScanOf: place)
        let config = place.lib.appending(path: BoardKey.gitDirectoryName).appending(path: ScanCacheTests.gitConfigName)
        try Data(Self.changedOrigin.utf8).write(to: config)
        cache.apply(.repo(place.lib.canonicalPath), inPlace: Self.placePath(of: place))
        #expect(cache.currentIndex(ofPlaces: Self.placesKey(of: place)) == nil)
    }

    @Test("A change of the place whose repos did not change after the scan keeps the index current")
    func unchangedPlaceKeepsIndex() async throws {
        let place = try ScanPlace.make()
        var cache = try await Self.cache(afterScanOf: place)
        cache.apply(.place(Self.placePath(of: place)), inPlace: Self.placePath(of: place))
        #expect(cache.currentIndex(ofPlaces: Self.placesKey(of: place)) != nil)
    }

    @Test("A change of the place after a write of the git config of one repo forgets only the key of that repo")
    func placeChangeForgetsOnlyChangedRepo() async throws {
        let place = try ScanPlace.make()
        var cache = try await Self.cache(afterScanOf: place)
        let config = place.lib.appending(path: BoardKey.gitDirectoryName).appending(path: ScanCacheTests.gitConfigName)
        try Data(Self.changedOrigin.utf8).write(to: config)
        cache.apply(.place(Self.placePath(of: place)), inPlace: Self.placePath(of: place))
        #expect(cache.currentIndex(ofPlaces: Self.placesKey(of: place)) == nil)
        #expect(try Self.copyPaths(of: cache, for: place) == [place.app.canonicalPath])
    }

    @Test("A change of the place after a new board log in one repo makes the index stale and forgets no key")
    func placeChangeAfterBoardLogKeepsKeys() async throws {
        let place = try ScanPlace.make()
        var cache = try await Self.cache(afterScanOf: place)
        _ = try KanbanGraphTests.writeFixture(inRepoAt: place.lib)
        cache.apply(.place(Self.placePath(of: place)), inPlace: Self.placePath(of: place))
        #expect(cache.currentIndex(ofPlaces: Self.placesKey(of: place)) == nil)
        #expect(try Self.copyPaths(of: cache, for: place) == [place.app.canonicalPath, place.lib.canonicalPath])
    }

    @Test("A new repo folder in the place after the scan makes the index stale")
    func newRepoExpiresIndex() async throws {
        let place = try ScanPlace.make()
        var cache = try await Self.cache(afterScanOf: place)
        let later = try ScanPlace.makeRepoFolder(named: Self.laterName, in: place.directory.url)
        cache.apply(.repo(later.canonicalPath), inPlace: Self.placePath(of: place))
        #expect(cache.currentIndex(ofPlaces: Self.placesKey(of: place)) == nil)
    }

    @Test("A change during a scan of files that the scan read keeps the result of the scan current")
    func earlierChangeDuringScanKeepsResult() async throws {
        let place = try ScanPlace.make()
        let key = Self.placesKey(of: place)
        var cache = ScanCache()
        _ = cache.beginScan(ofPlaces: key)
        cache.apply(.repo(place.lib.canonicalPath), inPlace: Self.placePath(of: place))
        let index = try await Self.scan(of: place)
        _ = cache.finishScan(index, ofPlaces: key, isWatched: true)
        #expect(cache.currentIndex(ofPlaces: key) != nil)
    }

    // MARK: - Helpers

    /// Scans a place with a key reader that runs no git.
    ///
    /// - Parameter place: The place.
    /// - Returns: The index of the scan.
    /// - Throws: An error of the scan.
    static func scan(of place: ScanPlace) async throws -> BoardIndex {
        try await BoardLocator.default.scan(around: place.app, readingKeysWith: ScanKeyReader().keyReader)
    }

    /// Makes a cache that holds the index of one watched scan of a place.
    ///
    /// - Parameter place: The place.
    /// - Returns: The cache. Its index is current.
    /// - Throws: An error of the scan.
    static func cache(afterScanOf place: ScanPlace) async throws -> ScanCache {
        let key = placesKey(of: place)
        var cache = ScanCache()
        _ = cache.beginScan(ofPlaces: key)
        _ = cache.finishScan(try await scan(of: place), ofPlaces: key, isWatched: true)
        try #require(cache.currentIndex(ofPlaces: key) != nil)
        return cache
    }

    /// Gives the canonical path of the directory of each copy of the index of a place, sorted.
    ///
    /// - Parameters:
    ///   - cache: The cache.
    ///   - place: The place.
    /// - Returns: The paths.
    /// - Throws: An error when the cache has no index of the place.
    static func copyPaths(of cache: ScanCache, for place: ScanPlace) throws -> [String] {
        let index = try #require(cache.index(ofPlaces: placesKey(of: place)))
        return index.copies.map(\.directory.canonicalPath).sorted()
    }

    /// Gives the canonical path of a place.
    ///
    /// - Parameter place: The place.
    /// - Returns: The path.
    static func placePath(of place: ScanPlace) -> String {
        place.directory.url.canonicalPath
    }

    /// Gives the key of the list of scan places of a place in the cache: the place alone.
    ///
    /// - Parameter place: The place.
    /// - Returns: The key.
    static func placesKey(of place: ScanPlace) -> [String] {
        [placePath(of: place)]
    }
}
