import Foundation
import Synchronization

/// A gate of a test: a call that the test holds records its arrival at the gate, and then waits until the test
/// releases the gate.
///
/// The test waits for the arrival with ``waitForArrival()``, so it knows that the held call is at the gate. Then it
/// does its checks, and lets the call go with ``release()``. The release is permanent: each later wait at the gate
/// returns at once. A second release does nothing more, so a test can release the gate in a `defer` and also release
/// it earlier in its body.
///
/// A held async call waits with ``waitUntilReleased()``, and a cancel of its task ends that wait. A held synchronous
/// call, for example a fake FSEvents call on a thread of its own, waits with ``blockUntilReleased()``. That wait blocks
/// its thread and no cancel can end it, so the test must release the gate on each path.
///
/// Each wait has no time limit.
final class TestGate: Sendable {
    /// The arrivals and the release of the gate.
    private struct State {
        /// The number of calls that arrived at the gate.
        var arrivalCount = 0

        /// `true` after the first ``TestGate/release()``.
        var isReleased = false
    }

    /// The state, behind a lock, because the held calls and the test run on different threads.
    private let state = Mutex(State())

    /// Lets a blocked thread go. The first release signals it one time. Each thread that it lets go signals it again
    /// for the next blocked thread, so the release stays permanent.
    private let releaseSignal = DispatchSemaphore(value: 0)

    /// Makes a gate with no arrival and no release.
    init() {}

    /// The number of calls that arrived at the gate.
    var arrivalCount: Int {
        state.withLock { state in state.arrivalCount }
    }

    /// `true` after the first ``release()``.
    var isReleased: Bool {
        state.withLock { state in state.isReleased }
    }

    /// Records that a held call arrived at the gate.
    func recordArrival() {
        state.withLock { state in state.arrivalCount += 1 }
    }

    /// Waits until a call arrived at the gate. When a call arrived before, the wait returns at once, so the test can
    /// wait more than one time. A cancel of the task ends the wait.
    func waitForArrival() async {
        try? await EventLogTests.waitUntil { self.arrivalCount > 0 }
    }

    /// Releases the gate: each held call goes on, and each later wait returns at once. A second release does nothing.
    func release() {
        let isFirstRelease = state.withLock { state in
            defer { state.isReleased = true }
            return !state.isReleased
        }
        if isFirstRelease {
            releaseSignal.signal()
        }
    }

    /// Waits until the release of the gate. It does not record an arrival.
    ///
    /// - Throws: `CancellationError` when the task is cancelled before the release.
    func waitUntilReleased() async throws {
        try await EventLogTests.waitUntil { self.isReleased }
    }

    /// Blocks the thread until the release of the gate. It does not record an arrival. No cancel ends the wait. A block
    /// on a thread of the Swift cooperative pool holds that thread, so a different thread or task must release the
    /// gate.
    func blockUntilReleased() {
        releaseSignal.wait()
        releaseSignal.signal()
    }
}
