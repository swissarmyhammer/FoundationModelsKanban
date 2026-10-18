import CoreServices
import Foundation

/// The FSEvents calls of a ``FolderStreams`` (divergence.md §16).
///
/// Each call is a synchronous message to fseventsd, so each call can wait for fseventsd. ``FolderStreams`` makes the
/// calls only on its own serial queue, and never on a thread of the Swift cooperative pool. A test gives a fake
/// service whose start waits, to prove that the other tasks of the process still run.
protocol FolderEventService: Sendable {
    /// Gives the id of the last event that FSEvents gave to an event of the system.
    ///
    /// - Returns: The id.
    func currentEventID() -> FSEventStreamEventId

    /// Makes and starts a stream of some folders. The stream gives each group of its events to a router, on a queue.
    ///
    /// The stream starts at "now": it gives only the events after its start, and it reads no history of FSEvents. A
    /// volume can have no event log, and then a history read gives no events.
    ///
    /// - Parameters:
    ///   - paths: The paths of the folders.
    ///   - router: The router that gets each group of events.
    ///   - queue: The queue of the events.
    /// - Returns: The started stream, or `nil` when FSEvents cannot make or start the stream. FSEvents tells no reason.
    func startStream(
        watching paths: [String],
        routingTo router: EventRouter,
        on queue: DispatchQueue
    ) -> (any FolderEventStream)?
}

/// A stream that a ``FolderEventService`` started.
protocol FolderEventStream: AnyObject {
    /// Gives each event that occurred before the call, then stops the stream and releases it. The stream gives no
    /// event after the call returns. Call it one time, and not on the queue of the events of the stream.
    func end()
}

/// The FSEvents service of the system.
struct SystemFolderEvents: FolderEventService {
    /// The time in seconds that FSEvents collects events before it gives a group. A short time keeps the live graph
    /// current; the events of one write still come in one group.
    private static let groupingLatency: CFTimeInterval = 0.05

    /// The flags of the stream: one event for each file, and the paths as a `CFArray` of `CFString` values.
    private static let streamFlags = FSEventStreamCreateFlags(
        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
    )

    func currentEventID() -> FSEventStreamEventId {
        FSEventsGetCurrentEventId()
    }

    /// The start of each stream: "now", so that FSEvents reads no history.
    private static let sinceNow = FSEventStreamEventId(kFSEventStreamEventIdSinceNow)

    func startStream(
        watching paths: [String],
        routingTo router: EventRouter,
        on queue: DispatchQueue
    ) -> (any FolderEventStream)? {
        var context = router.makeContext()
        let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            EventRouter.receiveEvents,
            &context,
            paths as CFArray,
            Self.sinceNow,
            Self.groupingLatency,
            Self.streamFlags
        )
        guard let stream = created else {
            return nil
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        return SystemFolderEventStream(stream)
    }
}

/// An FSEvents stream of the system that runs.
private final class SystemFolderEventStream: FolderEventStream {
    /// The stream.
    private let stream: FSEventStreamRef

    /// Holds a started stream.
    ///
    /// - Parameter stream: The started stream.
    init(_ stream: FSEventStreamRef) {
        self.stream = stream
    }

    /// Gives each event that occurred before the call, then stops the stream and releases it.
    ///
    /// `FSEventStreamFlushSync` returns after the callback ran for each event that occurred before the call. The
    /// callbacks run on the queue of the events, and the router gives each batch with no wait for an actor. Thus the
    /// flush cannot wait for itself when the caller is not on that queue.
    func end() {
        FSEventStreamFlushSync(stream)
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
