import Testing

@testable import FoundationModelsKanban

/// Limits the number of tests that run at the same time and can hold a file watcher.
///
/// Each host of a test, and each ``FolderStreams`` that a test makes, holds one FSEvents stream, and the system gives a
/// small number of streams to all processes together. When too many tests hold a stream at the same time,
/// `FSEventStreamStart` fails, and the call of the test throws ``BoardWatcherError/streamNotStarted(path:)``. A test
/// takes one slot of the budget for the time that it runs. The host of the test, and its stream, are gone before the
/// slot is free.
enum WatcherBudget {
    /// The number of tests that can hold a slot at the same time. Each test holds at most a few streams, so the whole
    /// budget stays far below the limit of the system.
    static let slotCount = 16

    /// The budget of the test run: a gate with ``slotCount`` slots.
    static let shared = SerialGate(slots: slotCount)
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
        try await WatcherBudget.shared.run(inSlot: function)
    }
}

extension Trait where Self == WatcherBudgetTrait {
    /// Runs each test of the suite inside a slot of the ``WatcherBudget``.
    static var watcherBudget: Self {
        WatcherBudgetTrait()
    }
}
