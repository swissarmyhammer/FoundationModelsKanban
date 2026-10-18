import Foundation

/// The time limit of each wait of a test for an FSEvents event: a batch of a file watcher, a change of a scan place or
/// of a path ref, or an event of the change feed that a watcher batch sends.
///
/// FSEvents can give an event late, and on some runs it gives no event at all (fseventsd keeps no history on the volume
/// of the tests). With no time limit, such a test waits forever, and the full `swift test` run never ends. With this
/// limit, the test fails with a message that names the path and the change that it waited for, and the run continues.
///
/// Only a wait for an FSEvents event gets this limit. A wait for a lock, for the search, or for a load has no time
/// limit, because no system service can lose the signal of such a wait.
enum FolderEventWait {
    /// The number of seconds of ``timeLimit``.
    ///
    /// The value is 60 seconds. On the development machine, FSEvents gave the event of a write 0.2 to 15 seconds after
    /// the write, while a background index build made about 1200 file events each second (task ^4p9q125). A probe that
    /// waited 15 seconds got 4 of 5 events. 60 seconds is four times the longest delay that was measured, so a late
    /// event still passes the test. A lost event stops only its own test, after 60 seconds.
    static let timeLimitSeconds = 60

    /// The longest time that a test waits for one FSEvents event.
    static let timeLimit = Duration.seconds(timeLimitSeconds)

    /// Runs a wait for an FSEvents event, and stops it when the time limit ends first.
    ///
    /// The wait runs in a child task. When the time limit ends first, the child task is cancelled, and a read of an
    /// `AsyncStream` or an `AsyncThrowingStream` ends at a cancel. When the wait ends first, no read of its stream is
    /// open, so the stream stays usable for a later wait.
    ///
    /// - Parameters:
    ///   - change: The change that the test waits for, for example "the batch of the title write".
    ///   - path: The path of the file or folder of the change.
    ///   - limit: The time limit. The default is ``timeLimit``. Only the tests of this type give a shorter limit.
    ///   - wait: Reads the stream, and gives the value that the test waits for.
    /// - Returns: The value of the wait.
    /// - Throws: ``FolderEventTimeout`` when the time limit ends first, or the error of the wait.
    static func value<Value: Sendable>(
        waitingFor change: String,
        at path: String,
        within limit: Duration = timeLimit,
        of wait: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                try await wait()
            }
            group.addTask {
                try await Task.sleep(for: limit)
                throw FolderEventTimeout(change: change, path: path, limit: limit)
            }
            defer { group.cancelAll() }
            return try await firstResult(of: &group, waitingFor: change, at: path)
        }
    }

    /// Gives the first result of the task group of a wait: the value of the wait, or the error of the wait or of the
    /// time limit.
    ///
    /// The group of ``value(waitingFor:at:within:of:)`` has two child tasks, so it always gives a first result. A
    /// group that gives no result is a defect of the wait, not a late FSEvents event, so the error is
    /// ``FolderEventWaitDefect`` and not ``FolderEventTimeout``.
    ///
    /// - Parameters:
    ///   - group: The task group of the wait.
    ///   - change: The change that the test waits for. The failure message names it.
    ///   - path: The path of the file or folder of the change. The failure message names it.
    /// - Returns: The first result.
    /// - Throws: The first error of the group, or ``FolderEventWaitDefect`` when the group gives no result.
    static func firstResult<Value: Sendable>(
        of group: inout ThrowingTaskGroup<Value, any Error>,
        waitingFor change: String,
        at path: String
    ) async throws -> Value {
        guard let first = try await group.next() else {
            throw FolderEventWaitDefect(change: change, path: path)
        }
        return first
    }

    /// Waits until a stream of changes gives a change after which the effect of the test action shows. After each
    /// change, the wait asks the condition, and it ends when the condition is `true`. The wait has the time limit
    /// ``timeLimit``. Each recorder of the tests that gives a stream of changes calls this wait.
    ///
    /// - Parameters:
    ///   - changes: The changes that the host saw, in order.
    ///   - change: The change that the test waits for. The failure message at the time limit names it.
    ///   - path: The file or folder that the test changed. The failure message at the time limit names it.
    ///   - isShown: Tells if the effect of the test action shows. The wait asks it after each change.
    /// - Returns: `true` when the effect shows, and `false` when the changes end first.
    /// - Throws: ``FolderEventTimeout`` when the effect does not show before the time limit, or an error that
    ///   `isShown` throws.
    static func change<Changes: AsyncSequence & Sendable>(
        in changes: Changes,
        waitingFor change: String,
        at path: URL,
        until isShown: @escaping @Sendable () async throws -> Bool
    ) async throws -> Bool {
        try await value(waitingFor: change, at: path.path) {
            try await changes.contains { _ in try await isShown() }
        }
    }
}

/// The error of a wait whose task group gave no result. The group of a wait has two child tasks, so this is a defect of
/// the wait, not a late FSEvents event.
struct FolderEventWaitDefect: Error, CustomStringConvertible {
    /// The change that the test waited for.
    let change: String

    /// The path of the file or folder of the change.
    let path: String

    /// The message of the test failure.
    var description: String {
        "The wait group gave no result. The test waited for \(change) at \(path)."
    }
}

/// The error of a wait for an FSEvents event that did not end before its time limit.
struct FolderEventTimeout: Error, CustomStringConvertible {
    /// The change that the test waited for.
    let change: String

    /// The path of the file or folder of the change.
    let path: String

    /// The time limit of the wait.
    let limit: Duration

    /// The message of the test failure.
    var description: String {
        "The FSEvents event did not come before the time limit (\(limit)). The test waited for \(change) at \(path)."
    }
}
