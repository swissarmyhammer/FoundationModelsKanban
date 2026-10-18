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
            // The group has two child tasks, so the first `next()` always gives a result or an error.
            guard let first = try await group.next() else {
                throw FolderEventTimeout(change: change, path: path, limit: limit)
            }
            return first
        }
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
