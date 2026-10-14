import Testing

/// Limits the number of tests that run at the same time and can hold a file watcher.
///
/// Each loaded board of a ``KanbanGraph`` holds one FSEvents stream, and the system gives a small number of streams
/// to all processes together. When too many tests hold a graph at the same time, `FSEventStreamStart` fails, and the
/// call of the test throws ``BoardWatcherError/streamNotStarted(path:)``. A test takes one slot of the budget for the
/// time that it runs. The graph of the test, and its streams, are gone before the slot is free.
actor WatcherBudget {
    /// The budget of the test run. Each test holds at most a few streams, so the whole budget stays far below the
    /// limit of the system.
    static let shared = WatcherBudget(slots: 16)

    /// The number of free slots.
    private var freeSlots: Int

    /// The tests that wait for a slot, in the order that they came.
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Makes a budget.
    ///
    /// - Parameter slots: The number of tests that can hold a slot at the same time.
    init(slots: Int) {
        freeSlots = slots
    }

    /// Runs an operation while it holds one slot. The slot is free again after the operation ends or throws.
    ///
    /// - Parameter operation: The operation.
    /// - Returns: The result of the operation.
    /// - Throws: The error of the operation.
    func withSlot<Result: Sendable>(_ operation: @Sendable () async throws -> Result) async throws -> Result {
        await acquire()
        do {
            let result = try await operation()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }

    /// Takes one slot, or waits until a slot is free.
    private func acquire() async {
        if freeSlots > 0 {
            freeSlots -= 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Gives one slot back, or gives it to the test that waits the longest.
    private func release() {
        if waiting.isEmpty {
            freeSlots += 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}

/// The trait that runs each test of a suite inside a slot of the ``WatcherBudget``.
struct WatcherBudgetTrait: SuiteTrait, TestTrait, TestScoping {
    /// The trait applies to each test of the suite, and of each suite in it. A recursive trait must be a `TestTrait`
    /// too, or the test runner stops when it makes the plan of the run.
    var isRecursive: Bool { true }

    /// Runs a test case inside one slot. The scope of a suite takes no slot, so a suite and its tests never take two
    /// slots.
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        guard testCase != nil else {
            return try await function()
        }
        try await WatcherBudget.shared.withSlot(function)
    }
}

extension Trait where Self == WatcherBudgetTrait {
    /// Runs each test of the suite inside a slot of the ``WatcherBudget``.
    static var watcherBudget: Self {
        WatcherBudgetTrait()
    }
}
