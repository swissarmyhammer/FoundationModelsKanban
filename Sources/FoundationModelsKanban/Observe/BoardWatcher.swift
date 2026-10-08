import CoreServices
import Foundation

/// Watches one directory, and each directory in it, with an FSEvents stream with file-level events (plan.md §5.6,
/// watcher).
///
/// FSEvents reports events in groups. The watcher gives the changed paths of each group as one batch in ``batches``.
/// When FSEvents tells that it dropped events, or that the receiver must scan the directories again, the batch also
/// holds the watched directory itself. The receiver then compares each file of the directory.
///
/// The watcher runs until ``stop()``, or until nothing holds the watcher. Then ``batches`` ends.
actor BoardWatcher {
    /// The time in seconds that FSEvents collects events before it gives a group. A short time keeps the live graph
    /// current; the events of one write still come in one group.
    private static let groupingLatency: CFTimeInterval = 0.05

    /// The flags of the stream: one event for each file, and the paths as a `CFArray` of `CFString` values.
    private static let streamFlags = FSEventStreamCreateFlags(
        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
    )

    /// The changed paths of each group of events, in the order of the groups. The stream ends when the watcher stops.
    nonisolated let batches: AsyncStream<[URL]>

    /// Gives each group of events to ``batches``.
    private let sink: BatchSink

    /// The FSEvents stream, or `nil` after ``stop()``.
    private var stream: FSEventStreamRef?

    /// Starts to watch a directory. Only the events after the start come in ``batches``.
    ///
    /// - Parameter directory: The directory. It must exist.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when FSEvents cannot make or start the stream.
    init(watching directory: URL) throws(BoardWatcherError) {
        let (batches, continuation) = AsyncStream<[URL]>.makeStream()
        let sink = BatchSink(watching: directory, feeding: continuation)
        stream = try Self.startStream(on: directory, feeding: sink)
        self.batches = batches
        self.sink = sink
    }

    /// Stops the watcher and ends ``batches``. A second call does nothing.
    func stop() {
        guard let stream else {
            return
        }
        self.stream = nil
        Self.end(stream, feeding: sink)
    }

    isolated deinit {
        guard let stream else {
            return
        }
        Self.end(stream, feeding: sink)
    }

    /// Makes and starts the FSEvents stream of a directory. The stream gives its events on its own serial queue.
    ///
    /// - Parameters:
    ///   - directory: The directory.
    ///   - sink: Gets each group of events. The stream retains it.
    /// - Returns: The started stream.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when FSEvents cannot make or start the stream.
    private static func startStream(
        on directory: URL,
        feeding sink: BatchSink
    ) throws(BoardWatcherError) -> FSEventStreamRef {
        var context = sink.makeContext()
        let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            BatchSink.receiveEvents,
            &context,
            [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            groupingLatency,
            streamFlags
        )
        guard let stream = created else {
            throw .streamNotStarted(path: directory.path)
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "FoundationModelsKanban.BoardWatcher"))
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            throw .streamNotStarted(path: directory.path)
        }
        return stream
    }

    /// Stops, invalidates, and releases a stream, and ends the batches of its sink.
    ///
    /// - Parameters:
    ///   - stream: The stream.
    ///   - sink: The sink of the stream.
    private static func end(_ stream: FSEventStreamRef, feeding sink: BatchSink) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        sink.finish()
    }
}

// MARK: - Sink

/// Changes each group of FSEvents events into one batch of changed paths.
///
/// The FSEvents stream holds the sink as the `info` pointer of its context, and retains it with the retain and
/// release callbacks of the context.
final class BatchSink: Sendable {
    /// The version of the `FSEventStreamContext` structure. FSEvents knows only version 0.
    private static let contextVersion: CFIndex = 0

    /// The event flags that tell that FSEvents dropped events, or that the receiver must scan the directories again.
    private static let rescanFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped
    )

    /// Gives the events of one group to the sink in the context of the stream.
    static let receiveEvents: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        receive(count: count, paths: paths, flags: flags, inContext: info)
    }

    /// Retains the sink while the stream holds it.
    private static let retainContext: CFAllocatorRetainCallBack = { info in
        retain(context: info)
    }

    /// Releases the sink when the stream does not hold it any more.
    private static let releaseContext: CFAllocatorReleaseCallBack = { info in
        release(context: info)
    }

    /// The watched directory.
    private let directory: URL

    /// The continuation of the batches of the watcher.
    private let continuation: AsyncStream<[URL]>.Continuation

    /// Makes the sink of a watcher.
    ///
    /// - Parameters:
    ///   - directory: The watched directory.
    ///   - continuation: The continuation of the batches of the watcher.
    init(watching directory: URL, feeding continuation: AsyncStream<[URL]>.Continuation) {
        self.directory = directory
        self.continuation = continuation
    }

    /// Makes the context of an FSEvents stream that gives its events to this sink.
    ///
    /// - Returns: The context. The stream retains the sink.
    func makeContext() -> FSEventStreamContext {
        FSEventStreamContext(
            version: Self.contextVersion,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: Self.retainContext,
            release: Self.releaseContext,
            copyDescription: nil
        )
    }

    /// Gives the paths of one group of events as one batch. When a flag tells that events are lost, the batch also
    /// holds the watched directory, so that the receiver compares each file of the directory.
    ///
    /// - Parameters:
    ///   - paths: The path of each event.
    ///   - flags: The flags of each event.
    func receive(paths: [String], flags: [FSEventStreamEventFlags]) {
        let changed = paths.map { path in URL(filePath: path) }
        let isLost = flags.contains { flag in flag & Self.rescanFlags != 0 }
        continuation.yield(isLost ? changed + [directory] : changed)
    }

    /// Ends the batches.
    func finish() {
        continuation.finish()
    }

    /// Gives one group of events of an FSEvents stream to the sink of the context of the stream.
    ///
    /// - Parameters:
    ///   - count: The number of events.
    ///   - paths: The paths of the events, as a `CFArray` of `CFString` values.
    ///   - flags: The flags of the events.
    ///   - info: The `info` pointer of the context: the sink.
    private static func receive(
        count: Int,
        paths: UnsafeMutableRawPointer,
        flags: UnsafePointer<FSEventStreamEventFlags>,
        inContext info: UnsafeMutableRawPointer?
    ) {
        guard let info else {
            return
        }
        let sink = Unmanaged<BatchSink>.fromOpaque(info).takeUnretainedValue()
        let names = (Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray) as? [String] ?? []
        sink.receive(paths: names, flags: Array(UnsafeBufferPointer(start: flags, count: count)))
    }

    /// Retains the sink of a context.
    ///
    /// - Parameter info: The `info` pointer of the context: the sink.
    /// - Returns: The same pointer.
    private static func retain(context info: UnsafeRawPointer?) -> UnsafeRawPointer? {
        guard let info else {
            return nil
        }
        _ = Unmanaged<BatchSink>.fromOpaque(info).retain()
        return info
    }

    /// Releases the sink of a context.
    ///
    /// - Parameter info: The `info` pointer of the context: the sink.
    private static func release(context info: UnsafeRawPointer?) {
        guard let info else {
            return
        }
        Unmanaged<BatchSink>.fromOpaque(info).release()
    }
}

/// An error of a ``BoardWatcher``.
enum BoardWatcherError: Error, Hashable, Sendable {
    /// FSEvents cannot make or start the stream of a directory.
    case streamNotStarted(path: String)
}
