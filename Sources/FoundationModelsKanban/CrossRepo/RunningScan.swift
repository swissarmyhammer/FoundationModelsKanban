import Foundation
import Synchronization

/// One scan of a list of scan places that runs now, and the calls that wait for its index (divergence.md §16,
/// Gap 1).
///
/// The call that starts the scan runs it in its own task, so that a cancel of that call stops the scan. Each other
/// call that needs the index of the same places while the scan runs waits here with ``index()``. Thus it does not
/// start a second scan with its own reads of git. When the scan ends, ``finish(giving:)`` gives the index of the scan
/// to each waiting call, or `nil` when the scan gave no index.
///
/// A cancel of a waiting call ends only the wait of that call: its ``index()`` returns `nil` at once, and the scan
/// goes on for the other calls. The state is behind a lock, because the cancel handler of a wait runs on the thread of
/// the cancel.
final class RunningScan: Sendable {
    /// The waiting call of one ``index()``.
    private typealias Waiter = CheckedContinuation<BoardIndex?, Never>

    /// The phase of the scan.
    private enum Phase {
        /// The scan runs.
        case running

        /// The scan ended: with its index, or with `nil` when it gave no index.
        case finished(BoardIndex?)
    }

    /// The phase of the scan and its waiting calls.
    private struct State {
        /// The phase of the scan.
        var phase = Phase.running

        /// Each waiting call, by the number of its wait.
        var waiters: [Int: Waiter] = [:]

        /// The number of the next wait.
        var nextWait = 0
    }

    /// The state, behind a lock.
    private let state = Mutex(State())

    /// Waits until the scan ends.
    ///
    /// - Returns: The index of the scan. `nil` when the scan gave no index, or when the task of the call is cancelled
    ///   before the scan ends.
    func index() async -> BoardIndex? {
        let wait = state.withLock { state in
            defer { state.nextWait += 1 }
            return state.nextWait
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { waiter in
                register(waiter, as: wait)
            }
        } onCancel: {
            endWait(wait)
        }
    }

    /// Records the end of the scan, and gives its index to each waiting call. Each later ``index()`` returns the same
    /// index at once.
    ///
    /// - Parameter index: The index of the scan, or `nil` when the scan gave no index, for example after a cancel.
    func finish(giving index: BoardIndex?) {
        let waiters = state.withLock { state in
            state.phase = .finished(index)
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        for waiter in waiters {
            waiter.resume(returning: index)
        }
    }

    /// Keeps a waiting call until the scan ends. A scan that ended gives its index at once, and a cancelled task gets
    /// `nil` at once, because its cancel handler can run before the call is kept.
    ///
    /// - Parameters:
    ///   - waiter: The waiting call.
    ///   - wait: The number of the wait.
    private func register(_ waiter: Waiter, as wait: Int) {
        state.withLock { state in
            switch state.phase {
            case .finished(let index):
                waiter.resume(returning: index)
            case .running where Task.isCancelled:
                waiter.resume(returning: nil)
            case .running:
                state.waiters[wait] = waiter
            }
        }
    }

    /// Ends one wait with `nil`, because its task is cancelled. A wait that already ended does not change.
    ///
    /// - Parameter wait: The number of the wait.
    private func endWait(_ wait: Int) {
        let waiter = state.withLock { state in state.waiters.removeValue(forKey: wait) }
        waiter?.resume(returning: nil)
    }
}
