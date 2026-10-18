import CoreServices
import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the one FSEvents stream of a host (divergence.md §16): the stream watches each folder of the host, and the
/// router gives each event only to the watchers whose folder holds the path of the event.
///
/// The router tests give events to the router directly, so they need no FSEvents stream. The stream tests watch
/// their own temporary folders, wait for the batch of their own write, and stop each watcher at the end.
@Suite("Folder streams: one FSEvents stream for the folders of a host", .watcherBudget)
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

    /// The number of adds that wait while the first stream starts, in the test of the adds that share one stream.
    static let waitingAddCount = 3

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
        router.route([event])
        router.route([event])
        #expect(await target.finishedBatches() == [[file]])
    }

    @Test("The router forgets the oldest event id above its capacity, so the event of that id goes again")
    func oldestEventIDIsForgotten() async throws {
        let target = RouterSink(named: "target")
        let router = EventRouter()
        target.add(to: router)
        let file = target.folder.appending(path: Self.markerName)
        let ids = (0...RecentEventIDs.capacity).map { offset in Self.firstEventID + FSEventStreamEventId(offset) }
        for id in ids {
            router.route([FolderEvent(path: file.path, flags: Self.noFlags, id: id)])
        }
        router.route([FolderEvent(path: file.path, flags: Self.noFlags, id: Self.firstEventID)])
        let batches = await target.finishedBatches()
        #expect(batches.count == ids.count + 1)
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

    @Test("The router gives an event one time, also when a second stream gives it after the stream change ended")
    func repeatedEventAfterMarkGoesOnce() async throws {
        let target = RouterSink(named: "target")
        let router = EventRouter()
        target.add(to: router)
        let file = target.folder.appending(path: Self.markerName)
        let event = FolderEvent(path: file.path, flags: Self.noFlags, id: Self.firstEventID)
        router.route([event])
        router.route([FolderEvent(path: target.folder.path, flags: Self.historyFlags, id: Self.secondEventID)])
        router.route([event])
        #expect(await target.finishedBatches() == [[file]])
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

    // MARK: - Stream change

    @Test("After the add of a second folder, the folder that the old stream watched gets a batch with its directory")
    func addReportsLostEventsToEachOtherFolder() async throws {
        let streams = FolderStreams(service: QuietFolderEvents())
        let (first, second) = (RouterSink(named: "first"), RouterSink(named: "second"))
        try await first.add(to: streams)
        try await second.add(to: streams)
        #expect(await first.finishedBatches() == [[first.folder]])
        #expect(await second.finishedBatches().isEmpty)
    }

    @Test("The remove of a folder makes no new stream, and the folder that stays gets no compare batch")
    func removeMakesNoNewStream() async throws {
        let service = QuietFolderEvents()
        let streams = FolderStreams(service: service)
        let (first, second) = (RouterSink(named: "first"), RouterSink(named: "second"))
        try await first.add(to: streams)
        try await second.add(to: streams)
        await second.remove(from: streams)
        #expect(service.startCount == 2)
        #expect(await streams.streamCount == 1)
        #expect(streams.folderCount == 1)
        #expect(await first.finishedBatches() == [[first.folder]])
    }

    @Test("The add of a folder in a watched folder makes no new stream")
    func addInWatchedFolderMakesNoNewStream() async throws {
        let service = QuietFolderEvents()
        let streams = FolderStreams(service: service)
        let (parent, child) = (RouterSink(named: "parent"), RouterSink(named: "parent/child"))
        try await parent.add(to: streams)
        try await child.add(to: streams)
        #expect(service.startCount == 1)
        #expect(streams.folderCount == 2)
        #expect(await parent.finishedBatches().isEmpty)
    }

    @Test("The add of a removed folder makes no new stream, because the stream still watches its path")
    func addOfRemovedFolderMakesNoNewStream() async throws {
        let service = QuietFolderEvents()
        let streams = FolderStreams(service: service)
        let (first, second) = (RouterSink(named: "first"), RouterSink(named: "second"))
        try await first.add(to: streams)
        try await second.add(to: streams)
        await second.remove(from: streams)
        try await second.add(to: streams)
        #expect(service.startCount == 2)
        #expect(streams.folderCount == 2)
    }

    @Test("A new stream watches only the folders that stay, and each folder of the old stream gets a compare batch")
    func switchAfterRemoveLosesNoChange() async throws {
        let service = QuietFolderEvents()
        let streams = FolderStreams(service: service)
        let (first, second) = (RouterSink(named: "first"), RouterSink(named: "second"))
        let third = RouterSink(named: "third")
        try await first.add(to: streams)
        try await second.add(to: streams)
        await second.remove(from: streams)
        try await third.add(to: streams)
        let expected = [first.folder, third.folder].map(FolderStreams.eventPath(of:)).sorted()
        #expect(service.startedPaths.last == expected)
        #expect(await first.finishedBatches() == [[first.folder], [first.folder]])
        #expect(await third.finishedBatches().isEmpty)
    }

    @Test("The adds that wait while a stream starts share one new stream")
    func waitingAddsShareOneStream() async throws {
        let hold = StartHold()
        let service = QuietFolderEvents(holdingFirstStartWith: hold)
        let streams = FolderStreams(service: service)
        let held = RouterSink(named: "held")
        let waiting = (0..<Self.waitingAddCount).map { index in RouterSink(named: "waiting-\(index)") }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await held.add(to: streams) }
            await hold.waitForHeldStart()
            for sink in waiting {
                group.addTask { try await sink.add(to: streams) }
            }
            try await EventLogTests.waitUntil { streams.folderCount == waiting.count + 1 }
            hold.release()
            try await group.waitForAll()
        }
        #expect(service.startCount == 2)
        #expect(streams.folderCount == waiting.count + 1)
    }

    // MARK: - Stream

    @Test("Two folders of one FolderStreams each get only the events of their own folder")
    func eachFolderGetsItsOwnEvents() async throws {
        let first = try TemporaryDirectory()
        let second = try TemporaryDirectory()
        let streams = FolderStreams()
        let firstWatcher = try await BoardWatcher(watching: first.url, in: streams)
        let secondWatcher = try await BoardWatcher(watching: second.url, in: streams)
        let firstFile = try Self.writeMarker(in: first.url)
        let secondFile = try Self.writeMarker(in: second.url)
        #expect(try await Self.hasBatch(in: firstWatcher.batches, holding: firstFile, outside: second.url))
        #expect(try await Self.hasBatch(in: secondWatcher.batches, holding: secondFile, outside: first.url))
        await firstWatcher.stop()
        await secondWatcher.stop()
    }

    @Test("Two watched folders use one FSEvents stream, and no stream runs after the watchers stop")
    func twoFoldersUseOneStream() async throws {
        let first = try TemporaryDirectory()
        let second = try TemporaryDirectory()
        let streams = FolderStreams()
        let firstWatcher = try await BoardWatcher(watching: first.url, in: streams)
        let secondWatcher = try await BoardWatcher(watching: second.url, in: streams)
        #expect(streams.folderCount == 2)
        #expect(await streams.streamCount == 1)
        await firstWatcher.stop()
        #expect(streams.folderCount == 1)
        #expect(await streams.streamCount == 1)
        await secondWatcher.stop()
        #expect(streams.folderCount == 0)
        #expect(await streams.streamCount == 0)
    }

    @Test("A write before the add of a second folder reaches the first watcher as its event or as a compare batch")
    func writeBeforeAddArrives() async throws {
        let first = try TemporaryDirectory()
        let second = try TemporaryDirectory()
        let streams = FolderStreams()
        let firstWatcher = try await BoardWatcher(watching: first.url, in: streams)
        let file = try Self.writeMarker(in: first.url)
        let secondWatcher = try await BoardWatcher(watching: second.url, in: streams)
        let change = "a batch that holds the marker file, or the folder itself so that the receiver compares each file"
        let (batches, folder) = (firstWatcher.batches, first.url)
        let isReached = try await BoardWatcherTests.hasBatch(in: batches, waitingFor: change, at: file) { batch in
            BoardWatcherTests.batch(batch, holds: file) || BoardWatcherTests.batch(batch, holds: folder)
        }
        #expect(isReached)
        await firstWatcher.stop()
        await secondWatcher.stop()
    }

    @Test("A write just after a second folder is added reaches the watcher of the second folder")
    func writeAfterAddArrives() async throws {
        let first = try TemporaryDirectory()
        let second = try TemporaryDirectory()
        let streams = FolderStreams()
        let firstWatcher = try await BoardWatcher(watching: first.url, in: streams)
        let secondWatcher = try await BoardWatcher(watching: second.url, in: streams)
        let file = try Self.writeMarker(in: second.url)
        #expect(try await BoardWatcherTests.hasBatch(in: secondWatcher.batches, holding: file))
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
        let watcher = try await BoardWatcher(watching: renamed, in: FolderStreams())
        let file = try Self.writeMarker(in: directory.url)
        #expect(try await BoardWatcherTests.hasBatch(in: watcher.batches, holding: file))
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

    /// Waits for the first batch that holds a file. The wait expects that each batch before it has no path in a
    /// different folder. The wait has the time limit of ``FolderEventWait``.
    ///
    /// - Parameters:
    ///   - batches: The batches of the watcher of the folder of the file.
    ///   - file: The file that the test changed.
    ///   - other: The folder of a different watcher. No batch must reach it.
    /// - Returns: `true` when a batch holds the file, `false` when the batches end first.
    /// - Throws: ``FolderEventTimeout`` when no batch holds the file before the time limit.
    static func hasBatch(in batches: AsyncStream<[URL]>, holding file: URL, outside other: URL) async throws -> Bool {
        let change = "a batch that holds the marker file and no path of the other folder"
        return try await BoardWatcherTests.hasBatch(in: batches, waitingFor: change, at: file) { batch in
            #expect(!Self.batch(batch, reaches: other))
            return BoardWatcherTests.batch(batch, holds: file)
        }
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
        router.insert(sink, at: folder.path)
        router.startWaitingSinks(after: since)
    }

    /// Adds the sink to the streams of a host.
    ///
    /// - Parameter streams: The streams.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the service cannot start the new stream.
    func add(to streams: FolderStreams) async throws {
        try await streams.add(sink)
    }

    /// Removes the sink from the streams of a host.
    ///
    /// - Parameter streams: The streams.
    func remove(from streams: FolderStreams) async {
        await streams.remove(sink)
    }

    /// Ends the batches of the sink, and gives each batch that the router gave it.
    ///
    /// - Returns: The batches, in order.
    func finishedBatches() async -> [[URL]] {
        sink.finish()
        return await batches.reduce(into: []) { batches, batch in batches.append(batch) }
    }
}
