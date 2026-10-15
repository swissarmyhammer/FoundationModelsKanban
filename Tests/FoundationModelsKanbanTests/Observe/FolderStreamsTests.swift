import CoreServices
import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the one FSEvents stream of a host (divergence.md §16): the stream watches each folder of the host, and the
/// router gives each event only to the watchers whose folder holds the path of the event.
///
/// The router tests give events to the router directly, so they need no FSEvents stream. The stream tests watch
/// their own temporary folders, wait for the batch of their own write, and stop each watcher at the end.
@Suite("Folder streams: one FSEvents stream for the folders of a host", .watcherBudget, .timeLimit(.minutes(1)))
struct FolderStreamsTests {
    /// The id before each event of a router test: a sink that starts at it gets each event.
    static let beforeAllEvents: FSEventStreamEventId = 0

    /// The id of the first event that a router test gives.
    static let firstEventID: FSEventStreamEventId = 1

    /// The id of the second event that a router test gives.
    static let secondEventID: FSEventStreamEventId = 2

    /// The id of the third event that a router test gives.
    static let thirdEventID: FSEventStreamEventId = 3

    /// The name of the file that a stream test writes into a watched folder.
    static let markerName = "marker.txt"

    // MARK: - Router

    @Test("The router gives an event only to the sink whose folder holds the path of the event")
    func eventGoesToItsFolderOnly() async throws {
        let (first, second) = (RouterSink(named: "first"), RouterSink(named: "second"))
        let router = EventRouter()
        first.add(to: router)
        second.add(to: router)
        let file = first.folder.appending(path: Self.markerName)
        router.route([FolderEvent(path: file.path, flags: Self.noFlags, id: Self.firstEventID)])
        #expect(await first.finishedBatches() == [[file]])
        #expect(await second.finishedBatches().isEmpty)
    }

    @Test("The router gives an event that two streams both give one time only while the streams change")
    func repeatedEventGoesOnce() async throws {
        let target = RouterSink(named: "target")
        let router = EventRouter()
        target.add(to: router)
        let file = target.folder.appending(path: Self.markerName)
        let event = FolderEvent(path: file.path, flags: Self.noFlags, id: Self.firstEventID)
        router.beginOverlap()
        router.route([event])
        router.route([event])
        router.endOverlap()
        #expect(await target.finishedBatches() == [[file]])
    }

    @Test("The router gives an event again when no two streams run, because FSEvents gives each event one time")
    func eventAfterOverlapGoesAgain() async throws {
        let target = RouterSink(named: "target")
        let router = EventRouter()
        target.add(to: router)
        let file = target.folder.appending(path: Self.markerName)
        router.beginOverlap()
        router.route([FolderEvent(path: file.path, flags: Self.noFlags, id: Self.firstEventID)])
        router.endOverlap()
        router.route([FolderEvent(path: file.path, flags: Self.noFlags, id: Self.secondEventID)])
        #expect(await target.finishedBatches() == [[file], [file]])
    }

    @Test("A flag for events that FSEvents dropped gives each folder a batch with its own directory")
    func droppedEventsGoToEachFolder() async throws {
        let (first, second) = (RouterSink(named: "first"), RouterSink(named: "second"))
        let router = EventRouter()
        first.add(to: router)
        second.add(to: router)
        let flags = FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
        router.route([FolderEvent(path: "/", flags: flags, id: Self.firstEventID)])
        #expect(await first.finishedBatches() == [[first.folder]])
        #expect(await second.finishedBatches() == [[second.folder]])
    }

    @Test("A flag to scan a parent folder again gives the folder in it a batch with its own directory")
    func parentRescanGoesToFolderInIt() async throws {
        let target = RouterSink(named: "target")
        let router = EventRouter()
        target.add(to: router)
        let parent = target.folder.deletingLastPathComponent().path
        let flags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        router.route([FolderEvent(path: parent, flags: flags, id: Self.firstEventID)])
        #expect(await target.finishedBatches() == [[target.folder]])
    }

    @Test("The router gives no batch for the mark that a new stream gave each event of its history")
    func historyMarkGivesNoBatch() async throws {
        let target = RouterSink(named: "target")
        let router = EventRouter()
        target.add(to: router)
        router.route([FolderEvent(path: target.folder.path, flags: Self.historyFlags, id: Self.firstEventID)])
        #expect(await target.finishedBatches().isEmpty)
    }

    @Test("The mark that a new stream gave its history ends the drop of repeated events")
    func historyMarkEndsOverlap() async throws {
        let target = RouterSink(named: "target")
        let router = EventRouter()
        target.add(to: router)
        let file = target.folder.appending(path: Self.markerName)
        let event = FolderEvent(path: file.path, flags: Self.noFlags, id: Self.firstEventID)
        router.beginOverlap()
        router.route([event])
        router.route([FolderEvent(path: target.folder.path, flags: Self.historyFlags, id: Self.secondEventID)])
        router.route([event])
        #expect(await target.finishedBatches() == [[file], [file]])
    }

    @Test("A folder gets no event from before its add, also when a new stream gives the event from its history")
    func folderGetsNoEventFromBeforeItsAdd() async throws {
        let target = RouterSink(named: "target")
        let router = EventRouter()
        target.add(to: router, after: Self.secondEventID)
        let file = target.folder.appending(path: Self.markerName)
        router.route([FolderEvent(path: file.path, flags: Self.noFlags, id: Self.firstEventID)])
        router.route([FolderEvent(path: file.path, flags: Self.noFlags, id: Self.thirdEventID)])
        #expect(await target.finishedBatches() == [[file]])
    }

    @Test("The router keeps the id of the last event that it got, so that a new stream starts after it")
    func routerKeepsLastEventID() {
        let target = RouterSink(named: "target")
        let router = EventRouter()
        target.add(to: router)
        let file = target.folder.appending(path: Self.markerName).path
        router.route([FolderEvent(path: file, flags: Self.noFlags, id: Self.secondEventID)])
        router.route([FolderEvent(path: file, flags: Self.noFlags, id: Self.firstEventID)])
        #expect(router.lastEventID == Self.secondEventID)
    }

    // MARK: - Stream

    @Test("Two folders of one FolderStreams each get only the events of their own folder")
    func eachFolderGetsItsOwnEvents() async throws {
        let first = try TemporaryDirectory()
        let second = try TemporaryDirectory()
        let streams = FolderStreams()
        let firstWatcher = try BoardWatcher(watching: first.url, in: streams)
        let secondWatcher = try BoardWatcher(watching: second.url, in: streams)
        let firstFile = try Self.writeMarker(in: first.url)
        let secondFile = try Self.writeMarker(in: second.url)
        let (firstFolder, secondFolder) = (first.url, second.url)
        let isFirstFound = try await BoardWatcherTests.hasBatch(in: firstWatcher.batches) { batch in
            #expect(!Self.batch(batch, reaches: secondFolder))
            return BoardWatcherTests.batch(batch, holds: firstFile)
        }
        let isSecondFound = try await BoardWatcherTests.hasBatch(in: secondWatcher.batches) { batch in
            #expect(!Self.batch(batch, reaches: firstFolder))
            return BoardWatcherTests.batch(batch, holds: secondFile)
        }
        #expect(isFirstFound)
        #expect(isSecondFound)
        await firstWatcher.stop()
        await secondWatcher.stop()
    }

    @Test("Two watched folders use one FSEvents stream, and no stream runs after the watchers stop")
    func twoFoldersUseOneStream() async throws {
        let first = try TemporaryDirectory()
        let second = try TemporaryDirectory()
        let streams = FolderStreams()
        let firstWatcher = try BoardWatcher(watching: first.url, in: streams)
        let secondWatcher = try BoardWatcher(watching: second.url, in: streams)
        #expect(streams.folderCount == 2)
        #expect(streams.streamCount == 1)
        await firstWatcher.stop()
        #expect(streams.folderCount == 1)
        #expect(streams.streamCount == 1)
        await secondWatcher.stop()
        #expect(streams.folderCount == 0)
        #expect(streams.streamCount == 0)
    }

    @Test("A write just before a second folder is added still reaches the watcher of the first folder")
    func writeBeforeAddArrives() async throws {
        let first = try TemporaryDirectory()
        let second = try TemporaryDirectory()
        let streams = FolderStreams()
        let firstWatcher = try BoardWatcher(watching: first.url, in: streams)
        let file = try Self.writeMarker(in: first.url)
        let secondWatcher = try BoardWatcher(watching: second.url, in: streams)
        #expect(try await BoardWatcherTests.hasBatch(in: firstWatcher.batches) { batch in
            BoardWatcherTests.batch(batch, holds: file)
        })
        await firstWatcher.stop()
        await secondWatcher.stop()
    }

    @Test("A folder named with other letter case gets the events of the folder")
    func otherLetterCaseGetsEvents() async throws {
        let directory = try TemporaryDirectory()
        let name = directory.url.lastPathComponent
        let renamed = directory.url.deletingLastPathComponent().appending(
            path: name.lowercased(),
            directoryHint: .isDirectory
        )
        try #require(renamed.lastPathComponent != name)
        let watcher = try BoardWatcher(watching: renamed, in: FolderStreams())
        let file = try Self.writeMarker(in: directory.url)
        #expect(try await BoardWatcherTests.hasBatch(in: watcher.batches) { batch in
            BoardWatcherTests.batch(batch, holds: file)
        })
        await watcher.stop()
    }

    // MARK: - Helpers

    /// The flags of a plain event of one file.
    static let noFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagNone)

    /// The flags of the mark that a new stream gave each event of its history.
    static let historyFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone)

    /// Writes the marker file into a folder.
    ///
    /// - Parameter folder: The folder.
    /// - Returns: The marker file.
    /// - Throws: An error when the file cannot be written.
    static func writeMarker(in folder: URL) throws -> URL {
        let file = folder.appending(path: markerName)
        try Data(markerName.utf8).write(to: file)
        return file
    }

    /// Tells if a batch holds a path in a folder. The compare resolves symbolic links, because FSEvents gives
    /// `/private/var/…` for a file in `/var/…`.
    ///
    /// - Parameters:
    ///   - batch: The changed paths.
    ///   - folder: The folder.
    /// - Returns: `true` when a path of the batch is in the folder.
    static func batch(_ batch: [URL], reaches folder: URL) -> Bool {
        let prefix = folder.resolvingSymlinksInPath().path + "/"
        return batch.contains { changed in changed.resolvingSymlinksInPath().path.hasPrefix(prefix) }
    }
}

// MARK: - Router sink

/// A sink of a router test and its batches. The folder is a path that the router only compares; the test makes no
/// folder on the disk.
private struct RouterSink {
    /// The folder of the sink.
    let folder: URL

    /// The sink.
    let sink: BatchSink

    /// The batches of the sink.
    private let batches: AsyncStream<[URL]>

    /// Makes a sink for a folder with a name.
    ///
    /// - Parameter name: The name of the folder, in the temporary directory of the user.
    init(named name: String) {
        folder = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        let (batches, continuation) = AsyncStream<[URL]>.makeStream()
        sink = BatchSink(watching: folder, feeding: continuation)
        self.batches = batches
    }

    /// Adds the sink to a router.
    ///
    /// - Parameters:
    ///   - router: The router.
    ///   - since: The id of the last event before the add. The default gives the sink each event of the test.
    func add(to router: EventRouter, after since: FSEventStreamEventId = FolderStreamsTests.beforeAllEvents) {
        router.insert(sink, at: folder.path, after: since)
    }

    /// Ends the batches of the sink, and gives each batch that the router gave it.
    ///
    /// - Returns: The batches, in order.
    func finishedBatches() async -> [[URL]] {
        sink.finish()
        return await batches.reduce(into: []) { batches, batch in batches.append(batch) }
    }
}
