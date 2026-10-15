import CoreServices
import Darwin
import Foundation
import Synchronization

/// The one FSEvents stream of all the folders that the file watchers of one host watch (divergence.md §16).
///
/// The system gives a small number of FSEvents streams to all processes together. Thus a host does not start one
/// stream for each watched folder. Each ``BoardWatcher`` of the host adds its folder here, one stream watches all the
/// folders, and an ``EventRouter`` gives each group of events to each watcher whose folder holds a path of the group.
///
/// When the set of folders changes, the stream of the new set starts first, and then the old stream stops. The new
/// stream starts at the last event that the router got, so FSEvents gives it each later event from its history, also
/// an event that the old stream did not give yet. Thus no event is lost. Until the new stream gave its history, an
/// event that both streams give goes to the watchers one time only. A folder gets no event from before its add.
final class FolderStreams: Sendable {
    /// The time in seconds that FSEvents collects events before it gives a group. A short time keeps the live graph
    /// current; the events of one write still come in one group.
    private static let groupingLatency: CFTimeInterval = 0.05

    /// The flags of the stream: one event for each file, and the paths as a `CFArray` of `CFString` values.
    private static let streamFlags = FSEventStreamCreateFlags(
        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
    )

    /// Gives each group of events to the sinks of the folders.
    private let router = EventRouter()

    /// The queue of the events of each stream. The old and the new stream use the same queue, so their groups come
    /// one at a time.
    private let queue = DispatchQueue(label: "FoundationModelsKanban.FolderStreams")

    /// The running stream and its folders, behind a lock. The lock also lets one change of the set of folders run at
    /// a time.
    private let state = Mutex(StreamState())

    /// The number of FSEvents streams that run: 1 while a folder is watched, else 0. A test reads it to prove that a
    /// host holds one stream for all its folders.
    var streamCount: Int {
        state.withLock { state in state.stream == nil ? 0 : 1 }
    }

    /// The number of watched folders: one for each running ``BoardWatcher``. A test reads it to prove that the one
    /// stream serves each folder.
    var folderCount: Int {
        router.sinkCount
    }

    /// Adds the folder of a sink to the stream. Only the events after the add go to the sink.
    ///
    /// - Parameter sink: The sink. Its directory is the folder.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when FSEvents cannot make or start the stream of the new
    ///   set of folders. Then the old stream stays, and the sink gets no events.
    func add(_ sink: BatchSink) throws(BoardWatcherError) {
        try state.withLock { state throws(BoardWatcherError) in
            let addedAfter = FSEventsGetCurrentEventId()
            router.insert(sink, at: Self.eventPath(of: sink.directory), after: addedAfter)
            do throws(BoardWatcherError) {
                try replaceStream(in: &state, changing: sink.directory, addedAfter: addedAfter)
            } catch {
                router.remove(sink)
                throw error
            }
        }
    }

    /// Removes the folder of a sink from the stream. After the call returns, the sink gets no events. A second call
    /// does nothing.
    ///
    /// When FSEvents cannot start the stream of the smaller set of folders, the old stream stays, and the host
    /// records the failure with swift-log. The old stream watches more folders than needed; no folder loses events.
    ///
    /// - Parameter sink: The sink.
    func remove(_ sink: BatchSink) {
        state.withLock { state in
            guard router.remove(sink) else {
                return
            }
            do {
                try replaceStream(in: &state, changing: sink.directory)
            } catch {
                Log.kanban.warning(
                    "The FSEvents stream of the smaller set of folders cannot start, so the old stream stays",
                    metadata: ["path": "\(sink.directory.path)", "error": "\(error)"]
                )
            }
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

    /// Replaces the running stream with a stream of the current set of folders, when the set changed. The caller holds
    /// the lock of ``state``.
    ///
    /// The first stream starts at the current event of the system. Each later stream starts at the last event that
    /// the router got, or at the start of the old stream, and FSEvents gives it the events after that from its
    /// history. Thus an event that FSEvents did not give the old stream yet, when the old stream stops, comes from the
    /// new stream. The new stream starts before the old stream stops. Until the new stream gave its history, the
    /// router drops an event that it gave before. No call here waits for FSEvents to give events, so the change does
    /// not hold a thread.
    ///
    /// The new stream also starts no later than the add of a new folder. Thus an event of the new folder after its
    /// add comes from the new stream, also when the old stream gave a later event of another folder before the start.
    ///
    /// - Parameters:
    ///   - state: The running stream and its folders.
    ///   - directory: The folder that was added or removed. The error names it.
    ///   - addedAfter: For an add, the id of the last event before the add of the folder; for a remove, `nil`.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when FSEvents cannot make or start the new stream. Then
    ///   the old stream stays.
    private func replaceStream(
        in state: inout StreamState,
        changing directory: URL,
        addedAfter: FSEventStreamEventId? = nil
    ) throws(BoardWatcherError) {
        let paths = router.watchedPaths
        guard paths != state.paths else {
            return
        }
        guard let old = state.stream else {
            state = try startStream(watching: paths, since: FSEventsGetCurrentEventId(), adding: directory)
            return
        }
        let next =
            paths.isEmpty
            ? StreamState()
            : try startOverlappingStream(after: state, notAfter: addedAfter, watching: paths, directory)
        Self.end(old)
        state = next
    }

    /// Starts the stream that replaces a running stream, at the last event that the router got, or at the start of
    /// the running stream. The router drops each event that it gave before, until the new stream gave its history.
    ///
    /// - Parameters:
    ///   - running: The running stream.
    ///   - latest: The latest event to start at, or `nil` for no limit.
    ///   - paths: The paths of the folders of the new stream.
    ///   - directory: The folder that was added or removed. The error names it.
    /// - Returns: The state of the new stream.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when FSEvents cannot make or start the new stream. Then
    ///   the router drops no event.
    private func startOverlappingStream(
        after running: StreamState,
        notAfter latest: FSEventStreamEventId?,
        watching paths: [String],
        _ directory: URL
    ) throws(BoardWatcherError) -> StreamState {
        router.beginOverlap()
        do throws(BoardWatcherError) {
            let since = min(max(router.lastEventID, running.since), latest ?? .max)
            return try startStream(watching: paths, since: since, adding: directory)
        } catch {
            router.endOverlap()
            throw error
        }
    }

    /// Makes and starts an FSEvents stream of some folders. The stream gives its events on ``queue``.
    ///
    /// - Parameters:
    ///   - paths: The paths of the folders.
    ///   - since: The id of the last event before the stream: FSEvents gives each later event of the folders, also an
    ///     event from before the start of the stream.
    ///   - directory: The folder that was added or removed. The error names it.
    /// - Returns: The state of the started stream.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when FSEvents cannot make or start the stream.
    private func startStream(
        watching paths: [String],
        since: FSEventStreamEventId,
        adding directory: URL
    ) throws(BoardWatcherError) -> StreamState {
        var context = router.makeContext()
        let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            EventRouter.receiveEvents,
            &context,
            paths as CFArray,
            since,
            Self.groupingLatency,
            Self.streamFlags
        )
        guard let stream = created else {
            throw .streamNotStarted(path: directory.path)
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            throw .streamNotStarted(path: directory.path)
        }
        return StreamState(stream: stream, paths: paths, since: since)
    }

    /// Stops, invalidates, and releases a stream.
    ///
    /// - Parameter stream: The stream.
    private static func end(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

/// The running FSEvents stream of a ``FolderStreams``, the paths of its folders, and the event that it started at.
private struct StreamState {
    /// The running stream, or `nil` when no folder is watched.
    var stream: FSEventStreamRef?

    /// The paths of the folders of ``stream``, sorted.
    var paths: [String] = []

    /// The id of the last event before ``stream``: the stream gives only the later events.
    var since: FSEventStreamEventId = 0
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

    /// The sink of each folder, by the identity of the sink, and the ids of the events while two streams run, behind
    /// a lock.
    private let table = Mutex(RouteTable())

    /// The number of sinks.
    var sinkCount: Int {
        table.withLock { table in table.routes.count }
    }

    /// The path of each folder, sorted, with no repeat: the paths that the stream watches.
    var watchedPaths: [String] {
        table.withLock { table in Set(table.routes.values.map(\.path)).sorted() }
    }

    /// The id of the last event that the router got, or 0 before the first event. A new stream starts at it.
    var lastEventID: FSEventStreamEventId {
        table.withLock { table in table.lastEventID }
    }

    /// Adds the sink of a folder. The sink gets only the events after the add, also when a new stream gives an older
    /// event from its history.
    ///
    /// - Parameters:
    ///   - sink: The sink.
    ///   - path: The path of the folder, as FSEvents gives it (``FolderStreams/eventPath(of:)``).
    ///   - since: The id of the last event before the add.
    func insert(_ sink: BatchSink, at path: String, after since: FSEventStreamEventId) {
        let route = Route(sink: sink, path: path, since: since)
        table.withLock { table in table.routes[ObjectIdentifier(sink)] = route }
    }

    /// Removes the sink of a folder. After the call returns, the router gives the sink no batch.
    ///
    /// - Parameter sink: The sink.
    /// - Returns: `true` when the router had the sink.
    @discardableResult
    func remove(_ sink: BatchSink) -> Bool {
        table.withLock { table in table.routes.removeValue(forKey: ObjectIdentifier(sink)) != nil }
    }

    /// Starts to drop each event whose id the router gave before: two streams run, and both give the events that
    /// they both see.
    func beginOverlap() {
        table.withLock { table in table.overlap = .overlapping(delivered: []) }
    }

    /// Stops to drop repeated events: one stream runs again.
    func endOverlap() {
        table.withLock { table in table.overlap = .single }
    }

    /// Gives one group of events to the sinks: to each sink, the paths in its folder, as one batch.
    ///
    /// The mark that a new stream gave each event of its history is no change of a file, so the router skips it. After
    /// the mark, the old stream is gone and the new stream gives only new events, so the router stops to drop
    /// repeated events.
    ///
    /// - Parameter group: The events of the group, in order.
    func route(_ group: [FolderEvent]) {
        let events = group.filter { event in event.flags & Self.historyDoneFlag == 0 }
        let isHistoryDone = events.count < group.count
        let deliveries = table.withLock { table in
            table.lastEventID = events.map(\.id).reduce(table.lastEventID, max)
            let fresh = table.overlap.firstDeliveries(of: events)
            if isHistoryDone {
                table.overlap = .single
            }
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

/// The sinks of an ``EventRouter`` and its state of the stream change.
private struct RouteTable {
    /// The sink of each folder, by the identity of the sink.
    var routes: [ObjectIdentifier: Route] = [:]

    /// Whether two streams run, and the ids of the events that the router gave while they run.
    var overlap = StreamOverlap.single

    /// The id of the last event that the router got, or 0 before the first event.
    var lastEventID: FSEventStreamEventId = 0
}

/// Whether one stream runs, or an old and a new stream run while the set of folders changes.
private enum StreamOverlap {
    /// One stream runs. FSEvents gives each event one time.
    case single

    /// Two streams run. The router gave the events with these ids, and drops them when the other stream gives them.
    case overlapping(delivered: Set<FSEventStreamEventId>)

    /// Keeps the events that the router did not give yet, and records their ids while two streams run.
    ///
    /// - Parameter events: The events of one group.
    /// - Returns: The events to give.
    mutating func firstDeliveries(of events: [FolderEvent]) -> [FolderEvent] {
        guard case .overlapping(var delivered) = self else {
            return events
        }
        let fresh = events.filter { event in delivered.insert(event.id).inserted }
        self = .overlapping(delivered: delivered)
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
