import CoreServices
import Foundation
import Synchronization

@testable import FoundationModelsKanban

/// A fake FSEvents service. Its first stream start waits until the test lets it go, the same as a start that waits
/// for a slow fseventsd. Each later start returns at once. The streams give no events, so a suite that uses the fake
/// needs no slot of the ``WatcherBudget``.
final class HeldStartService: FolderEventService {
    /// Lets the held start go.
    private let release = DispatchSemaphore(value: 0)

    /// The last event id that the service gave, and the number of starts that began, behind a lock.
    private let state = Mutex(HeldStartState())

    /// Gives one element when the first start begins to wait.
    private let heldStarts: AsyncStream<Void>

    /// Gives the elements of ``heldStarts``.
    private let heldStartSink: AsyncStream<Void>.Continuation

    /// Makes the service.
    init() {
        (heldStarts, heldStartSink) = AsyncStream.makeStream()
    }

    /// The number of stream starts that began, the held start included.
    var startCount: Int {
        state.withLock { state in state.startCount }
    }

    /// Gives the next event id of the fake.
    ///
    /// - Returns: The id.
    func currentEventID() -> FSEventStreamEventId {
        state.withLock { state in state.nextEventID() }
    }

    /// Gives a stream that gives no events. The first call waits until ``releaseHeldStart()``.
    ///
    /// - Parameters:
    ///   - paths: The paths of the folders. The fake ignores them.
    ///   - router: The router that gets each group of events. The fake gives it no events.
    ///   - queue: The queue of the events. The fake ignores it.
    /// - Returns: The stream.
    func startStream(
        watching paths: [String],
        routingTo router: EventRouter,
        on queue: DispatchQueue
    ) -> (any FolderEventStream)? {
        if state.withLock({ state in state.takeHold() }) {
            heldStartSink.yield()
            release.wait()
        }
        return QuietStream()
    }

    /// Waits until the first start begins to wait.
    func waitForHeldStart() async {
        for await _ in heldStarts {
            return
        }
    }

    /// Lets the held start go.
    func releaseHeldStart() {
        release.signal()
    }
}

/// The state of a ``HeldStartService``.
struct HeldStartState {
    /// The last event id that the service gave.
    private var lastEventID: FSEventStreamEventId = 0

    /// The number of starts that began.
    private(set) var startCount = 0

    /// Gives the next event id.
    ///
    /// - Returns: The id.
    mutating func nextEventID() -> FSEventStreamEventId {
        lastEventID += 1
        return lastEventID
    }

    /// Records the begin of one start, and takes the hold of the first start.
    ///
    /// - Returns: `true` for the first start only.
    mutating func takeHold() -> Bool {
        startCount += 1
        return startCount == 1
    }
}

/// A stream of the fake service. It gives no events.
final class QuietStream: FolderEventStream {
    /// Does nothing: the stream gives no events.
    func end() {}
}
