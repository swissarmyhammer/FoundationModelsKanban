import Testing

/// Tests the ``WatcherBudget`` that limits the number of tests that hold a file watcher.
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

    @Test("No more operations than the slots run at the same time, and each operation runs")
    func slotsLimitTheOperations() async throws {
        let budget = WatcherBudget(slots: 2)
        let meter = Meter()
        let operations = 12
        let finished = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<operations {
                group.addTask {
                    try await budget.withSlot {
                        await meter.begin()
                        for _ in 0..<20 {
                            await Task.yield()
                        }
                        await meter.end()
                        return index
                    }
                }
            }
            return try await group.reduce(into: Set<Int>()) { $0.insert($1) }
        }
        #expect(finished == Set(0..<operations))
        #expect(await meter.peak <= 2)
    }

    @Test("A slot is free again after an operation throws")
    func throwFreesTheSlot() async throws {
        let budget = WatcherBudget(slots: 1)
        await #expect(throws: OperationFailure.self) {
            try await budget.withSlot { () async throws -> Int in throw OperationFailure() }
        }
        let value = try await budget.withSlot { 7 }
        #expect(value == 7)
    }
}
