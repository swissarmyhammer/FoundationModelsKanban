import CoreServices
import Darwin
import Foundation
import OrderedCollections
import Synchronization

/// The one FSEvents stream of all the folders that the file watchers of one host watch (divergence.md §16).
///
/// The system gives a small number of FSEvents streams to all processes together. Thus a host does not start one
/// stream for each watched folder. Each ``BoardWatcher`` of the host adds its folder here, one stream watches all the
/// folders, and an ``EventRouter`` gives each group of events to each watcher whose folder holds a path of the group.
///
/// Each stream starts at "now" and reads no history of FSEvents. A volume can have no event log, and then a history
/// read gives no events, and a change during the history read is lost. FSEvents gives a folder each event that occurs
/// after the start of a stream that watches the folder.
///
/// Each change of the stream can lose an event, and each FSEvents call gives work to fseventsd. Thus the stream changes
/// only when a folder that it does not watch is added:
/// - A remove makes no new stream. The stream keeps the path of the removed folder, and the router gives no event of
///   that path, because no sink has it. When no folder is watched, the stream ends.
/// - An add of a folder that the stream watches makes no new stream: a folder in a watched folder, or a removed folder
///   whose path the stream keeps.
/// - The adds that wait while a stream starts share the next new stream (``add(_:)``).
///
/// When the stream changes, the new stream watches the folder of each sink, and starts first. Then the old stream gives
/// each event that FSEvents already sent to it, and stops. An event that both streams give has one id, and the router
/// gives it to the watchers one time only. A folder gets no event from before its add. When fseventsd is behind, the
/// old stream can stop before it gets an event that occurred before the start of the new stream, and the new stream
/// does not get that event. Thus after each change of the stream, each folder that the old stream watched gets one
/// batch with the folder itself, the same as a batch of lost events, and its receiver compares each file of the folder.
///
/// Each FSEvents call is a synchronous message to fseventsd, and fseventsd can be slow to answer. Thus the actor runs
/// on its own serial queue, not on the Swift cooperative pool: each change of the set of folders, and each FSEvents
/// call of the change, runs on that queue. An async caller waits for the change with no blocked thread of the pool,
/// so a slow fseventsd does not stop the other tasks of the process.
actor FolderStreams {
    /// The FSEvents calls.
    private let service: any FolderEventService

    /// The queue of each change of the set of folders: the executor of the actor.
    private let changes = DispatchSerialQueue(label: "FoundationModelsKanban.FolderStreams.changes")

    /// Gives each group of events to the sinks of the folders.
    private let router = EventRouter()

    /// The queue of the events of each stream. The old and the new stream use the same queue, so their groups come
    /// one at a time.
    private let queue = DispatchQueue(label: "FoundationModelsKanban.FolderStreams")

    /// The running stream and its folders.
    private var state = StreamState()

    /// Makes the streams of a host.
    ///
    /// - Parameter service: The FSEvents calls. A test gives a fake.
    init(service: any FolderEventService = SystemFolderEvents()) {
        self.service = service
    }

    /// The executor of the actor: the serial queue ``changes``, so that no FSEvents call runs on the cooperative pool.
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        changes.asUnownedSerialExecutor()
    }

    /// The number of FSEvents streams that run: 1 while a folder is watched, else 0. A test reads it to prove that a
    /// host holds one stream for all its folders, and that a remove makes no new stream.
    var streamCount: Int {
        state.stream == nil ? 0 : 1
    }

    /// The number of watched folders: one for each running ``BoardWatcher``. A test reads it to prove that the one
    /// stream serves each folder.
    nonisolated var folderCount: Int {
        router.sinkCount
    }

    /// Adds the folder of a sink to the stream. Only the events after the add go to the sink.
    ///
    /// The router keeps the sink before the add waits for the actor, as a sink that gets no event yet. Thus each add
    /// that waits while a slow stream start runs is in the router, and the next change of the stream watches the
    /// folders of all of them: the adds that come at the same time share one new stream, with no added delay. The
    /// later adds then find their folders watched, and make no stream.
    ///
    /// - Parameter sink: The sink. Its directory is the folder.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when FSEvents cannot make or start the stream of the new
    ///   set of folders. Then the old stream stays, and the sink gets no events.
    nonisolated func add(_ sink: BatchSink) async throws(BoardWatcherError) {
        router.insert(sink, at: Self.eventPath(of: sink.directory))
        do throws(BoardWatcherError) {
            try await watchEachFolder(adding: sink.directory)
        } catch {
            router.remove(sink)
            throw error
        }
    }

    /// Removes the folder of a sink. After the call returns, the sink gets no events. The call makes no new stream:
    /// the stream keeps the path of the folder until it changes for an add. When no folder is watched, the stream
    /// ends. A second call does nothing.
    ///
    /// - Parameter sink: The sink.
    func remove(_ sink: BatchSink) {
        router.remove(sink)
        endStreamWithNoFolder()
    }

    /// Removes the folder of a sink with no wait, for a caller that cannot wait, for example a `deinit`. After the call
    /// returns, the sink gets no events. When no folder is watched, the stream ends later, on the queue of the actor.
    ///
    /// - Parameter sink: The sink.
    nonisolated func removeWithoutWait(_ sink: BatchSink) {
        router.remove(sink)
        changes.async { [self] in
            assumeIsolated { streams in streams.endStreamWithNoFolder() }
        }
    }

    /// Gives the path of a folder as FSEvents gives it in each event: the path of the open folder from the file
    /// system, with each symbolic link resolved and the letter case of the disk. Thus `/var/…` gives `/private/var/…`,
    /// and a path with other letter case on a disk that ignores case gives the path on the disk. A folder that cannot
    /// be opened, for example a folder that was removed just now, gives its canonical path.
    ///
    /// - Parameter directory: The folder.
    /// - Returns: The path.
    static func eventPath(of directory: URL) -> String {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return directory.canonicalPath
        }
        defer { close(descriptor) }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else {
            return directory.canonicalPath
        }
        let bytes = buffer.prefix { byte in byte != 0 }.map { byte in UInt8(bitPattern: byte) }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Stream change

    /// Ends the stream when the router has no sink. Else the stream stays: a remove makes no new stream.
    private func endStreamWithNoFolder() {
        guard router.sinkCount == 0, let stream = state.stream else {
            return
        }
        stream.end()
        state = StreamState()
    }

    /// Makes the stream watch the folder of each sink of the router, after an add.
    ///
    /// First each sink that waits gets the id of the last event before this call: from then on it gets the later
    /// events. When the running stream watches each folder of the router, the call makes no new stream. Else a new
    /// stream of the folders of the router starts first, and then the old stream ends. The new stream does not watch
    /// the paths of removed folders. Each stream starts at "now" and reads no history of FSEvents. The new stream gives
    /// each event that FSEvents reads after its start. The end of the old stream gives each event that FSEvents already
    /// sent (``FolderEventStream/end()``). The router gives an event that both streams give one time only.
    ///
    /// When fseventsd is behind, it can hold an event that it read before the start of the new stream, and that it did
    /// not send to the old stream yet. The end of the old stream does not wait for that event, and the new stream does
    /// not get it, so the event is lost. Thus after the end of the old stream, each folder that the old stream watched
    /// gets one batch with the folder itself, the same as a batch of lost events
    /// (``EventRouter/reportLostEvents(inFoldersOf:)``). Its receiver then compares each file of the folder, and finds
    /// the change of the lost event: that change occurred before the start of the new stream. A folder that the old
    /// stream did not watch gets no such batch: no event of the old stream is an event of it.
    ///
    /// - Parameter directory: The added folder. The error names it.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when FSEvents cannot make or start the new stream. Then
    ///   the old stream stays.
    private func watchEachFolder(adding directory: URL) throws(BoardWatcherError) {
        router.startWaitingSinks(after: service.currentEventID())
        let paths = router.watchedPaths
        guard !state.watchesEach(of: paths) else {
            return
        }
        let next = try startStream(watching: paths, adding: directory)
        let old = state
        old.stream?.end()
        state = next
        router.reportLostEvents(inFoldersOf: old.paths)
    }

    /// Makes and starts an FSEvents stream of some folders, at "now". The stream gives its events on ``queue``.
    ///
    /// - Parameters:
    ///   - paths: The paths of the folders.
    ///   - directory: The added folder. The error names it.
    /// - Returns: The state of the started stream.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when FSEvents cannot make or start the stream.
    private func startStream(
        watching paths: [String],
        adding directory: URL
    ) throws(BoardWatcherError) -> StreamState {
        guard let stream = service.startStream(watching: paths, routingTo: router, on: queue) else {
            throw .streamNotStarted(path: directory.path)
        }
        return StreamState(stream: stream, paths: paths)
    }
}

/// The running FSEvents stream of a ``FolderStreams`` and the paths of its folders.
private struct StreamState {
    /// The running stream, or `nil` when no folder is watched.
    var stream: (any FolderEventStream)?

    /// The paths of the folders of ``stream``, sorted. After a remove, the paths keep the removed folder.
    var paths: [String] = []

    /// Tells if the stream watches each of some folders: each path is a folder of the stream, or a path in one.
    ///
    /// - Parameter candidates: The paths of the folders.
    /// - Returns: `true` when the stream watches each folder. `false` when no stream runs and a folder is given.
    func watchesEach(of candidates: [String]) -> Bool {
        candidates.allSatisfy { candidate in Route.oneOf(paths, holds: candidate) }
    }
}

// MARK: - Router

/// One event of an FSEvents stream: the path, the flags, and the id of the event.
struct FolderEvent: Sendable {
    /// The changed path.
    let path: String

    /// The flags of the event.
    let flags: FSEventStreamEventFlags

    /// The id of the event. Two streams that see one event give it the same id.
    let id: FSEventStreamEventId
}

/// Gives each group of events of the FSEvents stream of a host to the sink of each folder that holds a path of the
/// group.
///
/// Each sink gets one batch for each group: the paths of the group in its folder. When a flag tells that events of
/// its folder are lost, the batch also holds the folder itself, so that the receiver compares each file of the folder.
/// A sink whose folder has no path in the group and lost no events gets no batch.
///
/// The FSEvents stream holds the router as the `info` pointer of its context, and retains it with the retain and
/// release callbacks of the context.
final class EventRouter: Sendable {
    /// The version of the `FSEventStreamContext` structure. FSEvents knows only version 0.
    private static let contextVersion: CFIndex = 0

    /// The flag of the mark that a stream gave each event of its history: the mark is no change of a file.
    private static let historyDoneFlag = FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone)

    /// Gives the events of one group to the router in the context of the stream.
    static let receiveEvents: FSEventStreamCallback = { _, info, count, paths, flags, ids in
        receive(count: count, paths: paths, flags: flags, ids: ids, inContext: info)
    }

    /// Retains the router while a stream holds it.
    private static let retainContext: CFAllocatorRetainCallBack = { info in
        retain(context: info)
    }

    /// Releases the router when a stream does not hold it any more.
    private static let releaseContext: CFAllocatorReleaseCallBack = { info in
        release(context: info)
    }

    /// The sink of each folder, by the identity of the sink, and the ids of the recent events, behind a lock.
    private let table = Mutex(RouteTable())

    /// The number of sinks, the sinks that wait included.
    var sinkCount: Int {
        table.withLock { table in table.routes.count + table.waiting.count }
    }

    /// The path of each folder, sorted, with no repeat: the paths that the stream must watch. The folders of the
    /// sinks that wait are included.
    var watchedPaths: [String] {
        table.withLock { table in
            Set(table.routes.values.map(\.path) + table.waiting.values.map(\.path)).sorted()
        }
    }

    /// Adds the sink of a folder as a sink that waits: it gets no event until ``startWaitingSinks(after:)``.
    ///
    /// - Parameters:
    ///   - sink: The sink.
    ///   - path: The path of the folder, as FSEvents gives it (``FolderStreams/eventPath(of:)``).
    func insert(_ sink: BatchSink, at path: String) {
        let waiting = WaitingSink(sink: sink, path: path)
        table.withLock { table in table.waiting[ObjectIdentifier(sink)] = waiting }
    }

    /// Gives each sink that waits the events after an id, also when a stream gives an older event later.
    ///
    /// - Parameter since: The id of the last event before the start.
    func startWaitingSinks(after since: FSEventStreamEventId) {
        table.withLock { table in
            let started = table.waiting.mapValues { waiting in
                Route(sink: waiting.sink, path: waiting.path, since: since)
            }
            table.routes.merge(started) { _, route in route }
            table.waiting.removeAll()
        }
    }

    /// Removes the sink of a folder. After the call returns, the router gives the sink no batch.
    ///
    /// - Parameter sink: The sink.
    /// - Returns: `true` when the router had the sink.
    @discardableResult
    func remove(_ sink: BatchSink) -> Bool {
        let key = ObjectIdentifier(sink)
        return table.withLock { table in
            let route = table.routes.removeValue(forKey: key)
            let waiting = table.waiting.removeValue(forKey: key)
            return route != nil || waiting != nil
        }
    }

    /// Gives each sink whose folder an old stream watched one batch with its own folder, the same as a batch of lost
    /// events. The receiver of each batch then compares each file of the folder. ``FolderStreams`` calls it after the
    /// end of an old stream, because the old stream can lose an event when fseventsd is behind. A sink that waits, and
    /// a sink whose folder the old stream did not watch, get no batch.
    ///
    /// - Parameter oldPaths: The paths of the folders of the old stream.
    func reportLostEvents(inFoldersOf oldPaths: [String]) {
        let sinks = table.withLock { table in
            table.routes.values.filter { route in Route.oneOf(oldPaths, holds: route.path) }.map(\.sink)
        }
        for sink in sinks {
            sink.receive([], losingEvents: true)
        }
    }

    /// Gives one group of events to the sinks: to each sink, the paths in its folder, as one batch.
    ///
    /// FSEvents gives each event one id. Thus an id that the router gave before is the same event from a second
    /// stream, and the router drops it (``RecentEventIDs``). The mark that a stream gave each event of its history is
    /// no change of a file, so the router skips it.
    ///
    /// - Parameter group: The events of the group, in order.
    func route(_ group: [FolderEvent]) {
        let events = group.filter { event in event.flags & Self.historyDoneFlag == 0 }
        let deliveries = table.withLock { table in
            let fresh = table.recent.firstDeliveries(of: events)
            return table.routes.values.compactMap { route in route.delivery(of: fresh) }
        }
        for delivery in deliveries {
            delivery.sink.receive(delivery.paths, losingEvents: delivery.isLost)
        }
    }

    /// Makes the context of an FSEvents stream that gives its events to this router.
    ///
    /// - Returns: The context. The stream retains the router.
    func makeContext() -> FSEventStreamContext {
        FSEventStreamContext(
            version: Self.contextVersion,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: Self.retainContext,
            release: Self.releaseContext,
            copyDescription: nil
        )
    }

    /// Gives one group of events of an FSEvents stream to the router of the context of the stream.
    ///
    /// - Parameters:
    ///   - count: The number of events.
    ///   - paths: The paths of the events, as a `CFArray` of `CFString` values.
    ///   - flags: The flags of the events.
    ///   - ids: The ids of the events.
    ///   - info: The `info` pointer of the context: the router.
    private static func receive(
        count: Int,
        paths: UnsafeMutableRawPointer,
        flags: UnsafePointer<FSEventStreamEventFlags>,
        ids: UnsafePointer<FSEventStreamEventId>,
        inContext info: UnsafeMutableRawPointer?
    ) {
        guard let info else {
            return
        }
        let router = Unmanaged<EventRouter>.fromOpaque(info).takeUnretainedValue()
        let names = (Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray) as? [String] ?? []
        let events = (0..<min(count, names.count)).map { index in
            FolderEvent(path: names[index], flags: flags[index], id: ids[index])
        }
        router.route(events)
    }

    /// Retains the router of a context.
    ///
    /// - Parameter info: The `info` pointer of the context: the router.
    /// - Returns: The same pointer.
    private static func retain(context info: UnsafeRawPointer?) -> UnsafeRawPointer? {
        guard let info else {
            return nil
        }
        _ = Unmanaged<EventRouter>.fromOpaque(info).retain()
        return info
    }

    /// Releases the router of a context.
    ///
    /// - Parameter info: The `info` pointer of the context: the router.
    private static func release(context info: UnsafeRawPointer?) {
        guard let info else {
            return
        }
        Unmanaged<EventRouter>.fromOpaque(info).release()
    }
}

/// The sinks of an ``EventRouter`` and the ids of the events that it gave last.
private struct RouteTable {
    /// The sink of each folder that gets events, by the identity of the sink.
    var routes: [ObjectIdentifier: Route] = [:]

    /// The sink of each folder that waits for the change of the stream of its add, by the identity of the sink. It
    /// gets no event yet.
    var waiting: [ObjectIdentifier: WaitingSink] = [:]

    /// The ids of the events that the router gave last.
    var recent = RecentEventIDs()
}

/// The sink of one folder in an ``EventRouter`` that waits for the change of the stream of its add.
private struct WaitingSink {
    /// The sink.
    let sink: BatchSink

    /// The path of the folder, as FSEvents gives it.
    let path: String
}

/// The ids of the last events that an ``EventRouter`` gave, so that it gives an event one time only.
///
/// While the set of folders changes, an old and a new stream run, and both give the events that they both see. Each
/// event has one id, so a repeated id is the same event. The set keeps only the last ``capacity`` ids, so that its
/// size has a limit.
struct RecentEventIDs {
    /// The maximum number of ids that the set keeps. It is much larger than the number of events that two streams
    /// both give while the set of folders changes.
    static let capacity = 4096

    /// The ids, from the oldest to the newest.
    private var ids = OrderedSet<FSEventStreamEventId>()

    /// Keeps each event whose id the set does not have, and records its id. Above ``capacity``, the set forgets the
    /// oldest ids.
    ///
    /// - Parameter events: The events of one group.
    /// - Returns: The events to give.
    mutating func firstDeliveries(of events: [FolderEvent]) -> [FolderEvent] {
        let fresh = events.filter { event in ids.append(event.id).inserted }
        let excess = ids.count - Self.capacity
        if excess > 0 {
            ids.removeFirst(excess)
        }
        return fresh
    }
}

/// The sink of one folder in an ``EventRouter``.
private struct Route {
    /// The flags that tell that FSEvents dropped events. The events of each folder can be lost.
    private static let droppedFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
    )

    /// The flag that tells that the receiver must scan the folder of the event, and each folder in it, again.
    private static let rescanFlag = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)

    /// The sink.
    let sink: BatchSink

    /// The path of the folder, as FSEvents gives it.
    let path: String

    /// The id of the last event before the add of the sink: the sink gets only the later events.
    let since: FSEventStreamEventId

    /// Gives the batch of one group for the sink: the paths in the folder, and whether events of the folder are lost.
    /// An event from before the add of the sink is no event of the sink.
    ///
    /// - Parameter group: The events of the group.
    /// - Returns: The batch, or `nil` when no path is in the folder and no event of the folder is lost.
    func delivery(of group: [FolderEvent]) -> Delivery? {
        let events = group.filter { event in event.id > since }
        let paths = events.map(\.path).filter { eventPath in Self.folder(path, holds: eventPath) }
        let isLost = events.contains { event in losesEvents(event) }
        guard !paths.isEmpty || isLost else {
            return nil
        }
        return Delivery(sink: sink, paths: paths, isLost: isLost)
    }

    /// Tells if an event tells that events of the folder are lost: FSEvents dropped events, or the receiver must scan
    /// again a folder that holds the folder or is in it.
    ///
    /// - Parameter event: The event.
    /// - Returns: `true` when events of the folder are lost.
    private func losesEvents(_ event: FolderEvent) -> Bool {
        if event.flags & Self.droppedFlags != 0 {
            return true
        }
        guard event.flags & Self.rescanFlag != 0 else {
            return false
        }
        return Self.folder(path, holds: event.path) || Self.folder(event.path, holds: path)
    }

    /// Tells if a folder holds a path: the path is the folder, or a path in it.
    ///
    /// - Parameters:
    ///   - folder: The path of the folder.
    ///   - candidate: The path.
    /// - Returns: `true` when the folder holds the path.
    private static func folder(_ folder: String, holds candidate: String) -> Bool {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return candidate == folder || candidate.hasPrefix(prefix)
    }

    /// Tells if one of some folders holds a path: the path is one of the folders, or a path in one.
    ///
    /// - Parameters:
    ///   - folders: The paths of the folders.
    ///   - candidate: The path.
    /// - Returns: `true` when a folder holds the path.
    static func oneOf(_ folders: [String], holds candidate: String) -> Bool {
        folders.contains { folder in Self.folder(folder, holds: candidate) }
    }
}

/// The batch of one group of events for one sink.
private struct Delivery: Sendable {
    /// The sink.
    let sink: BatchSink

    /// The paths of the group in the folder of the sink, in order.
    let paths: [String]

    /// `true` when events of the folder are lost.
    let isLost: Bool
}
