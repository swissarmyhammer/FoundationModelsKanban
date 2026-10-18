import CoreServices
import Foundation
import Synchronization

@testable import FoundationModelsKanban

/// A fake FSEvents service whose streams give no events, also at their end. It is the same as a stream of a
/// fseventsd that is behind: the old stream holds an event that occurred before the start of the new stream, and it
/// does not give the event at its end. The fake records the folders of each start, so a test can count the streams
/// that a change of the set of folders makes. The fake makes no FSEvents stream, so a suite that uses only the fake
/// needs no slot of the ``WatcherBudget``.
///
/// Each start returns at once, unless the test gives a ``StartHold``. Then the first start waits until the test lets
/// it go, the same as a start that waits for a slow fseventsd.
final class QuietFolderEvents: FolderEventService {
    /// The last event id that the service gave, behind a lock.
    private let lastEventID = Mutex<FSEventStreamEventId>(0)

    /// The paths of the folders of each started stream, in the order of the starts, behind a lock.
    private let starts = Mutex<[[String]]>([])

    /// The hold of the first start, or `nil` when each start returns at once.
    private let firstStartHold: StartHold?

    /// Makes the service.
    ///
    /// - Parameter firstStartHold: The hold of the first start. The default gives no hold.
    init(holdingFirstStartWith firstStartHold: StartHold? = nil) {
        self.firstStartHold = firstStartHold
    }

    /// The paths of the folders of each started stream, in the order of the starts. A held start is in the list
    /// while it waits.
    var startedPaths: [[String]] {
        starts.withLock { starts in starts }
    }

    /// The number of started streams, a held start included.
    var startCount: Int {
        startedPaths.count
    }

    /// Gives the next event id of the fake.
    ///
    /// - Returns: The id.
    func currentEventID() -> FSEventStreamEventId {
        lastEventID.withLock { id in
            id += 1
            return id
        }
    }

    /// Records the paths of the folders, and gives a stream that gives no events. When the service has a hold, the
    /// first call waits until ``StartHold/release()``.
    ///
    /// - Parameters:
    ///   - paths: The paths of the folders. The fake records them.
    ///   - router: The router that gets each group of events. The fake gives it no events.
    ///   - queue: The queue of the events. The fake ignores it.
    /// - Returns: The stream.
    func startStream(
        watching paths: [String],
        routingTo router: EventRouter,
        on queue: DispatchQueue
    ) -> (any FolderEventStream)? {
        let isFirstStart = starts.withLock { starts in
            starts.append(paths)
            return starts.count == 1
        }
        if isFirstStart {
            firstStartHold?.wait()
        }
        return QuietStream()
    }
}

/// A hold on a stream start of a ``QuietFolderEvents``. The held start blocks its thread until the test lets it go,
/// the same as an FSEvents call that waits for a slow fseventsd.
final class StartHold: Sendable {
    /// Lets the held start go.
    private let releaseSignal = DispatchSemaphore(value: 0)

    /// Gives one element when the held start begins to wait.
    private let heldStarts: AsyncStream<Void>

    /// Gives the elements of ``heldStarts``.
    private let heldStartSink: AsyncStream<Void>.Continuation

    /// Makes a hold that holds no start yet.
    init() {
        (heldStarts, heldStartSink) = AsyncStream.makeStream()
    }

    /// Tells the test that the start waits, and blocks the thread of the start until ``release()``.
    func wait() {
        heldStartSink.yield()
        releaseSignal.wait()
    }

    /// Waits until the held start begins to wait.
    func waitForHeldStart() async {
        for await _ in heldStarts {
            return
        }
    }

    /// Lets the held start go.
    func release() {
        releaseSignal.signal()
    }
}

/// A stream of the fake service. It gives no events.
final class QuietStream: FolderEventStream {
    /// Does nothing: the stream gives no events.
    func end() {}
}
