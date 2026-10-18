import Foundation
import Testing

/// Tests the shared ``TestGate`` of the test target: the arrival signal, the release, and the two waits for the
/// release.
@Suite("Test gate: one gate that holds a call until the test releases it")
struct TestGateTests {
    @Test("A thread that blocks at the gate waits until the release")
    func blockedThreadWaitsForRelease() async throws {
        let gate = TestGate()
        let passed = TestGate()
        Thread.detachNewThread {
            gate.blockUntilReleased()
            passed.recordArrival()
        }
        try await Task.sleep(for: EventLogTests.retryPause)
        #expect(passed.arrivalCount == 0)
        gate.release()
        await passed.waitForArrival()
        #expect(passed.arrivalCount == 1)
    }

    @Test("After two releases, each thread that blocks at the gate goes at once")
    func repeatedReleaseLetsEachLaterBlockGo() async {
        let gate = TestGate()
        let passed = TestGate()
        gate.release()
        gate.release()
        Thread.detachNewThread {
            gate.blockUntilReleased()
            gate.blockUntilReleased()
            passed.recordArrival()
        }
        await passed.waitForArrival()
        #expect(gate.isReleased)
    }

    @Test("A wait for an arrival returns after an arrival that came first, also when the test waits two times")
    func waitForArrivalReturnsAfterEarlierArrival() async {
        let gate = TestGate()
        gate.recordArrival()
        await gate.waitForArrival()
        await gate.waitForArrival()
        #expect(gate.arrivalCount == 1)
    }

    @Test("A task that waits for the release goes on after the release")
    func asyncWaitEndsAtRelease() async throws {
        let gate = TestGate()
        let waiter = Task { try await gate.waitUntilReleased() }
        gate.release()
        try await waiter.value
        #expect(gate.isReleased)
    }

    @Test("A task that waits for the release throws CancellationError when the task is cancelled")
    func asyncWaitEndsAtCancel() async {
        let gate = TestGate()
        let waiter = Task { try await gate.waitUntilReleased() }
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(!gate.isReleased)
    }
}
