import Foundation
import Synchronization
import Testing

/// Tests the time limit of a wait for an FSEvents event (``FolderEventWait``). The tests read streams that the test
/// feeds, so they need no FSEvents stream, and they give a short time limit.
@Suite("Folder event wait: the time limit of a wait for an FSEvents event")
struct FolderEventWaitTests {
    /// The short time limit of the tests.
    static let shortLimit = Duration.milliseconds(100)

    /// The number of short limits after which the test ends a stream that gives no value. Then a wait with no time
    /// limit also ends, and the test fails and does not wait forever.
    static let streamEndLimits = 20

    /// The change that a test names.
    static let change = "the batch of the title write"

    /// The path that a test names.
    static let path = "/private/tmp/board/.kanban/tasks"

    /// The folder at ``path``, for a wait that takes a URL.
    static let url = URL(filePath: path, directoryHint: .isDirectory)

    /// The first value that a stream gives.
    static let firstValue = 1

    /// The second value that a stream gives.
    static let secondValue = 2

    @Test("A wait that gets no value ends at the time limit, with a message that names the change and the path")
    func waitWithNoValueEndsAtLimit() async throws {
        let (values, sink) = AsyncStream<Int>.makeStream()
        let end = Task {
            try await Task.sleep(for: Self.shortLimit * Self.streamEndLimits)
            sink.finish()
        }
        defer { end.cancel() }
        let error = await #expect(throws: FolderEventTimeout.self) {
            try await FolderEventWait.value(waitingFor: Self.change, at: Self.path, within: Self.shortLimit) {
                await values.first { _ in true }
            }
        }
        #expect(error?.change == Self.change)
        #expect(error?.path == Self.path)
        #expect(error?.description.contains("The test waited for \(Self.change) at \(Self.path).") == true)
    }

    @Test("A value that comes before the time limit ends the wait, and a later wait gets the next value of the stream")
    func valueEndsWaitAndStreamStaysUsable() async throws {
        let (values, sink) = AsyncStream<Int>.makeStream()
        sink.yield(Self.firstValue)
        let first = try await FolderEventWait.value(waitingFor: Self.change, at: Self.path) {
            await values.first { _ in true }
        }
        sink.yield(Self.secondValue)
        let second = try await FolderEventWait.value(waitingFor: Self.change, at: Self.path) {
            await values.first { _ in true }
        }
        #expect([first, second] == [Self.firstValue, Self.secondValue])
    }

    @Test("A wait group that gives no result is a defect of the group, not a timeout, and the error names the wait")
    func groupWithNoResultIsDefect() async throws {
        let error = await #expect(throws: FolderEventWaitDefect.self) {
            try await withThrowingTaskGroup(of: Int.self) { group in
                try await FolderEventWait.firstResult(of: &group, waitingFor: Self.change, at: Self.path)
            }
        }
        #expect(error?.change == Self.change)
        #expect(error?.path == Self.path)
    }

    @Test("A wait for a change ends at the first change after which the condition is true")
    func changeWaitEndsWhenConditionIsTrue() async throws {
        let (changes, sink) = AsyncStream<Int>.makeStream()
        sink.yield(Self.firstValue)
        sink.yield(Self.secondValue)
        let checks = CheckCounter()
        let isShown = try await FolderEventWait.change(in: changes, waitingFor: Self.change, at: Self.url) {
            checks.countCheck() == Self.secondValue
        }
        #expect(isShown)
        #expect(checks.count == Self.secondValue)
    }

    @Test("A wait for a change gives false when the changes end before the condition is true")
    func changeWaitGivesFalseAtEndOfChanges() async throws {
        let (changes, sink) = AsyncStream<Int>.makeStream()
        sink.yield(Self.firstValue)
        sink.finish()
        let isShown = try await FolderEventWait.change(in: changes, waitingFor: Self.change, at: Self.url) { false }
        #expect(!isShown)
    }
}

/// Counts the checks of the condition of a wait.
private final class CheckCounter: Sendable {
    /// The number of checks, behind a lock, because the wait checks in a child task.
    private let checks = Mutex(0)

    /// The number of checks so far.
    var count: Int {
        checks.withLock { checks in checks }
    }

    /// Counts one check.
    ///
    /// - Returns: The number of checks, with this check.
    func countCheck() -> Int {
        checks.withLock { checks in
            checks += 1
            return checks
        }
    }
}
