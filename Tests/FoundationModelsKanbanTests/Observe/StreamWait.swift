import Foundation

/// The time-limited wait of the suites that wait for a value of an async stream: a batch of a file watcher, or an
/// event of a subscription (plan.md §5.6, §6.7).
///
/// FSEvents gives a batch some milliseconds after a write, so a test waits for a definite signal. The time limit only
/// stops a test that would wait forever. The wait cancels the task that reads the stream when the time limit ends, and
/// a read of an `AsyncStream` or an `AsyncThrowingStream` ends at a cancel. Thus, no wait blocks past its limit.
enum StreamWait {
    /// The number of seconds of ``timeLimit``.
    private static let timeLimitSeconds = 10

    /// The longest time that a test waits for a value.
    private static let timeLimit = Duration.seconds(timeLimitSeconds)

    /// Runs an operation that reads a stream, and stops it when the time limit ends first.
    ///
    /// - Parameter operation: Reads the stream, and gives the value that the test waits for.
    /// - Returns: The value of the operation, or `nil` when the time limit ends first.
    /// - Throws: The error of the operation.
    static func value<Value: Sendable>(
        of operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value? {
        try await withThrowingTaskGroup(of: Value?.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeLimit)
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
