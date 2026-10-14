import Testing

@testable import FoundationModelsKanban

/// Tests the ``SerialGate`` with more than one slot, as the ``WatcherBudget`` uses it to limit the number of tests
/// that hold a file watcher.
@Suite("Watcher budget")
struct WatcherBudgetTests {
    /// Counts the operations that run at the same time, and the most that ran at the same time.
    private actor Meter {
        /// The number of operations that run now.
        private var running = 0

        /// The most operations that ran at the same time.
        private(set) var peak = 0

        /// Records the start of an operation.
        func begin() {
            running += 1
            peak = max(peak, running)
        }

        /// Records the end of an operation.
        func end() {
            running -= 1
        }
    }

    /// An error that an operation throws.
    private struct OperationFailure: Error {}

    /// The number of slots of the gate in the limit test.
    static let limitSlots = 2

    /// The number of operations in the limit test. This is much more than ``limitSlots``.
    static let limitOperations = 12

    /// The number of times that each operation of the limit test yields, so that the operations overlap.
    static let yieldsPerOperation = 20

    /// The value that the operation after a thrown error gives.
    static let valueAfterError = 7

    @Test("No more operations than the slots run at the same time, and each operation runs")
    func slotsLimitTheOperations() async {
        let budget = SerialGate(slots: Self.limitSlots)
        let meter = Meter()
        let finished = await withTaskGroup(of: Int.self) { group in
            for index in 0..<Self.limitOperations {
                group.addTask {
                    await budget.run {
                        await meter.begin()
                        for _ in 0..<Self.yieldsPerOperation {
                            await Task.yield()
                        }
                        await meter.end()
                        return index
                    }
                }
            }
            return await group.reduce(into: Set<Int>()) { $0.insert($1) }
        }
        #expect(finished == Set(0..<Self.limitOperations))
        #expect(await meter.peak <= Self.limitSlots)
    }

    @Test("A slot is free again after an operation throws")
    func throwFreesTheSlot() async {
        let budget = SerialGate(slots: 1)
        await #expect(throws: OperationFailure.self) {
            try await budget.run { () async throws -> Int in throw OperationFailure() }
        }
        let value = await budget.run { Self.valueAfterError }
        #expect(value == Self.valueAfterError)
    }
}
