import Foundation
import Synchronization
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests that the event ids increase from one call to the next (divergence.md S3, §16 M6).
///
/// Each call starts after the largest event id of the log of its board. Thus a later call gives larger ids than an
/// earlier call, also when the two calls run in the same millisecond or the clock moves back, and an undo has larger
/// ids than its target. The ids of events that the watcher loads, for example after a union merge, also count.
///
/// Each test writes the fixture logs of ``KanbanGraphTests`` to a temporary repo, and runs its calls in a commit
/// session of the board with a ULID source that gives smaller ids than the log already holds.
@Suite("Event ids increase from one call to the next", .watcherBudget)
struct EventIDOrderTests {
    /// The title that the first call of a test writes.
    static let firstTitle = "written by the first call"

    /// The title that the second call of a test writes.
    static let secondTitle = "written by the second call"

    /// The number of time steps that the clock moves back between the two calls of the clock test.
    static let clockBackSteps = 5

    /// A ULID source whose ULIDs all have the time of a call, and where each ULID is smaller than the ULID before
    /// it. Two random ids in one millisecond can come in this order.
    static let descendingIDs = FixedULIDSource(
        at: ReplayTests.date(atStep: CommitTests.callStep),
        generator: .descending
    )

    /// The events that one call wrote, and the largest event id of the log before the call.
    struct CallEvents {
        /// The largest event id of the log before the call.
        let largestBefore: ULID

        /// The events that the call wrote, in the order of their ids.
        let events: [Event]
    }

    // MARK: - Helpers

    /// Writes the fixture logs to a repo, and loads a commit session of the board.
    ///
    /// - Parameters:
    ///   - ids: The ULID source of the calls of the session.
    ///   - directory: The temporary repo directory.
    /// - Returns: The session, and the ULID of the fixture task.
    static func session(
        mintingFrom ids: any ULIDSource,
        inRepoAt directory: TemporaryDirectory
    ) async throws -> (session: CommitSession, task: ULID) {
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        let log = EventLog(repositoryAt: directory.url)
        return (try await CommitTests.makeSession(of: log, mintingFrom: ids), task)
    }

    /// Runs one mutation field in its own call, and gives the events that the call wrote.
    ///
    /// - Parameters:
    ///   - field: The mutation field.
    ///   - session: The commit session.
    /// - Returns: The events of the call, and the largest event id of the log before the call.
    static func run(_ field: String, in session: inout CommitSession) async throws -> CallEvents {
        let known = Set(session.live.events.map(\.id))
        let largest = try #require(known.max())
        try await HistoryTests.run(eachOf: [field], in: &session)
        return CallEvents(largestBefore: largest, events: newEvents(of: session, notIn: known))
    }

    /// Gives the events of the live graph of a session whose ids are not in a set.
    ///
    /// - Parameters:
    ///   - session: The commit session.
    ///   - known: The ids of the events before the change.
    /// - Returns: The new events, in the order of their ids.
    static func newEvents(of session: CommitSession, notIn known: Set<ULID>) -> [Event] {
        session.live.events.filter { event in !known.contains(event.id) }
    }

    /// Expects that a list of events is not empty, and that the id and the transaction of each event are larger
    /// than an id.
    ///
    /// - Parameters:
    ///   - events: The events.
    ///   - largest: The id that each id must be larger than.
    static func expect(_ events: [Event], after largest: ULID) {
        #expect(!events.isEmpty)
        for event in events {
            #expect(event.id > largest, "event \(event.id) is not after \(largest)")
            #expect(event.txn > largest, "transaction \(event.txn) is not after \(largest)")
        }
    }

    // MARK: - Tests

    @Test("Two calls in the same millisecond give ids in call order, also when the source gives smaller ids")
    func sameMillisecondKeepsCallOrder() async throws {
        let directory = try TemporaryDirectory()
        var (session, task) = try await Self.session(mintingFrom: Self.descendingIDs, inRepoAt: directory)
        let first = try await Self.run(UndoTests.titleField(Self.firstTitle, of: task), in: &session)
        let second = try await Self.run(UndoTests.titleField(Self.secondTitle, of: task), in: &session)
        Self.expect(first.events, after: first.largestBefore)
        Self.expect(second.events, after: try #require(first.events.map(\.id).max()))
        Self.expect(second.events, after: second.largestBefore)
        #expect(try CommitTests.title(of: .task(task), in: session) == Self.secondTitle)
    }

    @Test("When the clock moves back, the next call gives ids after the largest id of the log")
    func clockBackStillFollowsLog() async throws {
        let directory = try TemporaryDirectory()
        let clock = TestClock(at: ReplayTests.date(atStep: CommitTests.callStep))
        var (session, task) = try await Self.session(mintingFrom: ClockULIDSource(clock: clock), inRepoAt: directory)
        let first = try await Self.run(UndoTests.titleField(Self.firstTitle, of: task), in: &session)
        clock.move(to: ReplayTests.date(atStep: CommitTests.callStep - Self.clockBackSteps))
        let second = try await Self.run(UndoTests.titleField(Self.secondTitle, of: task), in: &session)
        Self.expect(first.events, after: first.largestBefore)
        Self.expect(second.events, after: second.largestBefore)
        #expect(try CommitTests.title(of: .task(task), in: session) == Self.secondTitle)
    }

    @Test("An undo has ids after the ids of its target, also when the source gives smaller ids")
    func undoFollowsTarget() async throws {
        let directory = try TemporaryDirectory()
        var (session, task) = try await Self.session(mintingFrom: Self.descendingIDs, inRepoAt: directory)
        let target = try await Self.run(UndoTests.titleField(Self.firstTitle, of: task), in: &session)
        let txn = try #require(target.events.first?.txn)
        let undoField = UndoTests.reverseField(MutationName.undoChange, with: UndoTests.txnInput(txn))
        let undo = try await Self.run(undoField, in: &session)
        Self.expect(undo.events, after: try #require(target.events.map(\.id).max()))
        Self.expect(undo.events, after: undo.largestBefore)
        #expect(undo.events.allSatisfy { event in event.undoes == txn })
        #expect(try CommitTests.title(of: .task(task), in: session) == KanbanGraphTests.taskTitle)
    }

    @Test("A field on a related board gives ids after the largest id of that board, also when it is larger")
    func relatedBoardFieldFollowsItsLog() throws {
        let callDate = ReplayTests.date(atStep: CommitTests.callStep)
        let relatedLargest = ULID(timestamp: ReplayTests.date(atStep: Design.MergeTests.otherBranchStep))
        let stamp = EventStamp(actingAs: ReplayTests.actor, mintingFrom: FixedULIDSource(at: callDate), after: nil)
        var current = WorkingCopy(graph: Graph(), events: [], stamp: stamp, after: nil)
        var related = WorkingCopy(graph: Graph(), events: [], stamp: stamp, after: relatedLargest)
        let patch = try ReplayTests.titlePatch(setting: Self.firstTitle, of: .task(ULID(timestamp: callDate)))
        let field: (inout WorkingCopy) throws(EventError) -> Void = { work throws(EventError) in
            try work.apply(patch, at: CommitTests.callTime)
        }
        try current.runField(as: CommitTests.firstOperation, on: &related, reading: .unavailable, field)
        #expect(!related.kept.isEmpty)
        #expect(related.kept.allSatisfy { event in event.id > relatedLargest })
    }

    @Test("After the watcher applies a union merge of two board copies, a new call gives ids after each merged id")
    func watcherMergeCountsAsLargest() async throws {
        let directory = try TemporaryDirectory()
        let (session, task) = try await Self.session(
            mintingFrom: FixedULIDSource(at: ReplayTests.date(atStep: CommitTests.callStep)),
            inRepoAt: directory
        )
        var main = Design.MergeTests.Branch(directory: directory, session: session)
        var other = try await Design.MergeTests.branch(copying: main, mintingAtStep: Design.MergeTests.otherBranchStep)
        _ = try await Self.run(UndoTests.titleField(Self.firstTitle, of: task), in: &main.session)
        _ = try await Self.run(UndoTests.titleField(Self.secondTitle, of: task), in: &other.session)
        let changed = try Design.MergeTests.unionMerge(other.log, into: main.log)
        let applied = try await main.session.apply(watchedPaths: changed.map(main.log.fileURL(for:)))
        #expect(!applied.isEmpty)
        let merged = Set(main.session.live.events.map(\.id))
        #expect(merged.isSuperset(of: other.session.live.events.map(\.id)))
        let runs = Mutex(0)
        try await main.session.run { store in
            CommitTests.countRun(in: runs)
            try await CommitTests.setTitle(Self.firstTitle, of: .task(task), as: CommitTests.firstOperation, in: store)
        }
        #expect(runs.withLock { count in count } == 1)
        Self.expect(Self.newEvents(of: main.session, notIn: merged), after: try #require(merged.max()))
    }
}

/// A clock for tests that the test sets, also back in time.
final class TestClock: Sendable {
    /// The time that the clock gives now.
    private let time: Mutex<Date>

    /// Makes a clock that gives one time until the test moves it.
    ///
    /// - Parameter time: The first time of the clock.
    init(at time: Date) {
        self.time = Mutex(time)
    }

    /// The time that the clock gives now.
    var now: Date {
        time.withLock { current in current }
    }

    /// Sets the time of the clock, also to a time before the current time.
    ///
    /// - Parameter newTime: The new time.
    func move(to newTime: Date) {
        time.withLock { current in current = newTime }
    }
}

/// A ULID source for tests that reads the time of a ``TestClock``, with random bits: the system source with a clock
/// that the test can move back.
struct ClockULIDSource: ULIDSource {
    /// The clock that gives the time of each ULID.
    let clock: TestClock

    /// Makes a ULID with the current time of the clock and random bits.
    ///
    /// - Returns: A new ULID.
    func makeULID() -> ULID {
        ULID(timestamp: clock.now)
    }
}
