import Foundation
import Synchronization
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the write side of a call (plan.md §5.4 steps 4 to 6): the working copy, the `patch` mutation, the locks, the
/// signature check, and the run again.
///
/// Each test writes the board fixture of the loader tests to a temporary repo, loads its live graph, and drives the
/// commit with a test mutation: a call that applies patches to the working copy. A test simulates a write by a
/// different process with a direct append to a log file between the load and the commit.
@Suite("Commit path: working copy, locks, and signature check")
struct CommitTests {
    /// The step of the time and of the ids of the calls of a test. It is after each step of the fixture and after
    /// each step of the writes of a different process.
    static let callStep = 10_000

    /// The title that a call writes.
    static let callTitle = "written by the call"

    /// The second title that a call writes, after ``callTitle``, in one field.
    static let laterCallTitle = "written later by the call"

    /// The name of the first mutation field of a test call.
    static let firstOperation = "firstMutation"

    /// The name of the second mutation field of a test call.
    static let secondOperation = "secondMutation"

    /// The error of a mutation field that breaks a graph rule.
    static let ruleFailure = KanbanError.dependencyCycle(path: ["^aaaaaaa", "^aaaaaaa"])

    /// The name of a property that the fixture tasks do not have.
    static let pointsProperty = "points"

    /// The value that a test sets on ``pointsProperty``.
    static let pointsValue = PatchValue.json(3)

    /// The time of each change of a test call.
    static let callTime = ReplayTests.time(atStep: callStep)

    /// The number of runs of a call that finds one changed file before its commit: the first run, and the run again.
    static let runsAfterOneChange = 2

    // MARK: - Fixture

    /// Writes the board fixture of the loader tests, and gives the refs of its tasks.
    ///
    /// - Parameter directory: The temporary repo directory.
    /// - Returns: The event log of the board, and the refs of its tasks.
    static func writeBoard(in directory: TemporaryDirectory) throws -> (log: EventLog, tasks: [LocalRef]) {
        let log = EventLog(repositoryAt: directory.url)
        return (log, try LiveGraphApplyTests.writeBoard(to: log))
    }

    /// Loads the live graph of a board, and makes the commit session of the board.
    ///
    /// - Parameters:
    ///   - log: The event log of the board.
    ///   - ids: The ULID source of the calls. The default gives ids after each event of the fixture.
    ///   - writer: The writer of the appends of the commit. The default writes the log files.
    /// - Returns: The commit session. Its task search has no embedder.
    static func makeSession(
        of log: EventLog,
        mintingFrom ids: any ULIDSource = FixedULIDSource(at: ReplayTests.date(atStep: callStep)),
        writingWith writer: any EventLogWriter = FileEventLogWriter()
    ) async throws -> CommitSession {
        CommitSession(
            of: try await LiveGraphApplyTests.load(log),
            inBoard: KanbanGraphTests.boardKey,
            actingAs: KanbanGraphTests.sessionActor,
            mintingFrom: ids,
            timedBy: { callTime },
            searchingWith: TaskSearch(embeddingWith: nil),
            writingWith: writer
        )
    }

    /// Makes the context of one call. All test code that makes a ``KanbanContext`` uses this function.
    ///
    /// - Parameters:
    ///   - store: The store of the call, for example the store of the working copy of a commit session.
    ///   - clock: The fixed clock of the call. The default clock gives ``callTime``.
    ///   - search: The task search of the call. The default search has no embedder and no task.
    /// - Returns: The context.
    static func callContext(
        of store: BoardStore,
        timedBy clock: @escaping @Sendable () -> DateTime = { CommitTests.callTime },
        searchingWith search: TaskSearch = TaskSearch(embeddingWith: nil)
    ) -> KanbanContext {
        KanbanContext(store: store, clock: clock, search: search, feed: ChangeFeed())
    }

    /// Runs one mutation field that applies one patch to the working copy.
    ///
    /// - Parameters:
    ///   - patch: The patch.
    ///   - operation: The name of the mutation field.
    ///   - store: The store of the working copy of the call.
    static func apply(_ patch: PatchInput, as operation: String, to store: BoardStore) async throws {
        try await store.runField(as: operation) { work throws(EventError) in
            try work.apply(patch, at: callTime)
        }
    }

    /// Runs one mutation field that sets the title of a task in the working copy.
    ///
    /// - Parameters:
    ///   - title: The new title.
    ///   - task: The local ref of the task.
    ///   - operation: The name of the mutation field.
    ///   - store: The store of the working copy of the call.
    static func setTitle(
        _ title: String,
        of task: LocalRef,
        as operation: String,
        in store: BoardStore
    ) async throws {
        try await apply(ReplayTests.titlePatch(setting: title, of: task), as: operation, to: store)
    }

    /// Gives the two title patches of a task, in call order: the patch of ``callTitle``, then the patch of
    /// ``laterCallTitle``.
    ///
    /// - Parameter task: The local ref of the task.
    /// - Returns: The patches.
    static func callTitlePatches(of task: LocalRef) throws -> [PatchInput] {
        try [callTitle, laterCallTitle].map { title in try ReplayTests.titlePatch(setting: title, of: task) }
    }

    /// Adds one run to the run count of a call.
    ///
    /// - Parameter runs: The run count of the call.
    /// - Returns: The number of the run that starts: 1 for the first run.
    @discardableResult
    static func countRun(in runs: borrowing Mutex<Int>) -> Int {
        runs.withLock { count in
            count += 1
            return count
        }
    }

    /// Writes the title of a task as a different process: a direct append to the log file of the task.
    ///
    /// - Parameters:
    ///   - task: The local ref of the task.
    ///   - run: The number of the run of the call. Each run writes a different event.
    ///   - log: The event log of the board.
    static func writeAsOtherProcess(to task: LocalRef, inRun run: Int, of log: EventLog) throws {
        try LiveGraphApplyTests.writeTitle(to: task, atStep: LiveGraphApplyTests.laterStep + run, in: log)
    }

    /// Gives one field of a task in the live graph of a session.
    ///
    /// - Parameters:
    ///   - keyPath: The key path of the field in the task, for example `\.title` or `\.fields.body`.
    ///   - task: The local ref of the task.
    ///   - session: The commit session.
    /// - Returns: The value of the field.
    static func field<Value>(
        _ keyPath: KeyPath<TaskNode, Value>,
        of task: LocalRef,
        in session: CommitSession
    ) throws -> Value {
        try LiveGraphApplyTests.task(task, in: session.live.graph)[keyPath: keyPath]
    }

    /// Gives the title of a task in the live graph of a session.
    ///
    /// - Parameters:
    ///   - task: The local ref of the task.
    ///   - session: The commit session.
    /// - Returns: The title.
    static func title(of task: LocalRef, in session: CommitSession) throws -> String {
        try field(\.title, of: task, in: session)
    }

    /// Gives the events of the log file of a node that a call of a session wrote: the events with the actor of the
    /// session and the time of the calls.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - log: The event log of the board.
    /// - Returns: The events, in the order of their ids.
    static func callEvents(of ref: LocalRef, in log: EventLog) throws -> [Event] {
        try log.readLog(of: ref).events.filter { event in event.at == callTime }
    }

    // MARK: - Fields

    @Test("A failed mutation field writes none of its patches, and the other fields of the call are written")
    func failedFieldWritesNothing() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try Self.writeBoard(in: directory)
        var session = try await Self.makeSession(of: log)
        try await session.run { store in
            try await Self.setTitle(Self.callTitle, of: tasks[0], as: Self.firstOperation, in: store)
            await #expect(throws: Self.ruleFailure) {
                try await store.runField(as: Self.secondOperation) { work in
                    try work.apply(ReplayTests.titlePatch(setting: Self.callTitle, of: tasks[1]), at: Self.callTime)
                    throw Self.ruleFailure
                }
            }
        }
        #expect(try Self.title(of: tasks[0], in: session) == Self.callTitle)
        #expect(try Self.title(of: tasks[1], in: session) == tasks[1].description)
        #expect(try Self.callEvents(of: tasks[0], in: log).count == 1)
        #expect(try Self.callEvents(of: tasks[1], in: log).isEmpty)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(session.live, of: log)
    }

    @Test("A failed mutation field leaves the working copy as it was before the field")
    func failedFieldKeepsWorkingCopy() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try Self.writeBoard(in: directory)
        var session = try await Self.makeSession(of: log)
        try await session.run { store in
            let before = await store.view.graph
            _ = try? await store.runField(as: Self.firstOperation) { work in
                try work.apply(ReplayTests.titlePatch(setting: Self.callTitle, of: tasks[0]), at: Self.callTime)
                throw Self.ruleFailure
            }
            let work = await store.work
            #expect(work.graph == before)
            #expect(work.kept.isEmpty)
            #expect(work.operations.isEmpty)
        }
        #expect(try Self.title(of: tasks[0], in: session) == tasks[0].description)
    }

    @Test("Each patch of a call has the txn, the ops, and the actor of the full call, and no boards")
    func patchesHaveEnvelopeOfCall() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try Self.writeBoard(in: directory)
        var session = try await Self.makeSession(of: log)
        let written = [tasks[0], tasks[1]]
        try await session.run { store in
            try await Self.setTitle(Self.callTitle, of: written[0], as: Self.firstOperation, in: store)
            try await Self.setTitle(Self.callTitle, of: written[1], as: Self.secondOperation, in: store)
        }
        let events = try written.flatMap { task in try Self.callEvents(of: task, in: log) }
        #expect(events.count == written.count)
        #expect(Set(events.map(\.txn)).count == 1)
        for event in events {
            #expect(event.ops == [Self.firstOperation, Self.secondOperation])
            #expect(event.actor == ReplayTests.actor)
            #expect(event.boards == nil)
        }
    }

    @Test("The event ids of one call increase, also when the ULID source gives a smaller id")
    func eventIDsIncrease() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try Self.writeBoard(in: directory)
        let patches = try Self.callTitlePatches(of: tasks[0])
        // One id for the txn and one id for each patch. Each id is one step earlier than the id before it.
        let fallingIDs = (0...patches.count).map { offset in
            ULID(timestamp: ReplayTests.date(atStep: Self.callStep - offset))
        }
        var session = try await Self.makeSession(of: log, mintingFrom: ScriptedULIDSource(candidates: fallingIDs))
        try await session.run { store in
            try await store.runField(as: Self.firstOperation) { work throws(EventError) in
                for patch in patches {
                    try work.apply(patch, at: Self.callTime)
                }
            }
        }
        let events = try Self.callEvents(of: tasks[0], in: log)
        let idsInCallOrder = try patches.map { patch in
            try #require(events.first { event in event.patch == patch }).id
        }
        #expect(zip(idsInCallOrder, idsInCallOrder.dropFirst()).allSatisfy { earlier, later in earlier < later })
        #expect(events.map(\.patch) == patches)
        #expect(try Self.title(of: tasks[0], in: session) == Self.laterCallTitle)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(session.live, of: log)
    }

    // MARK: - Changes only

    @Test("A patch keeps only the parts that change the node")
    func patchKeepsOnlyChanges() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try Self.writeBoard(in: directory)
        var session = try await Self.makeSession(of: log)
        let patch = try PatchInput(
            node: tasks[0],
            set: ["title": .json(.string(tasks[0].description)), Self.pointsProperty: Self.pointsValue],
            unset: ["color"],
            add: ["tags": [.local(ReplayTests.bugTag), .local(ReplayTests.uiTag)]],
            remove: ["tags": [.local(LocalRef.tag(slug: "absent"))]],
            delete: false
        )
        try await session.run { store in try await Self.apply(patch, as: Self.firstOperation, to: store) }
        let expected = try PatchInput(
            node: tasks[0],
            set: [Self.pointsProperty: Self.pointsValue],
            add: ["tags": [.local(ReplayTests.uiTag)]]
        )
        #expect(try Self.callEvents(of: tasks[0], in: log).map(\.patch) == [expected])
        try await LiveGraphApplyTests.expectEqualToFreshLoad(session.live, of: log)
    }

    @Test("An add and a remove of the same member in one patch keep the result of the fold")
    func addAndRemoveOfOneMemberKeepFoldResult() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try Self.writeBoard(in: directory)
        var session = try await Self.makeSession(of: log)
        let patch = try PatchInput(
            node: tasks[0],
            add: ["tags": [.local(ReplayTests.uiTag)]],
            remove: ["tags": [.local(ReplayTests.uiTag), .local(ReplayTests.bugTag)]]
        )
        try await session.run { store in try await Self.apply(patch, as: Self.firstOperation, to: store) }
        let expected = try PatchInput(node: tasks[0], remove: ["tags": [.local(ReplayTests.bugTag)]])
        #expect(try Self.callEvents(of: tasks[0], in: log).map(\.patch) == [expected])
        try await LiveGraphApplyTests.expectEqualToFreshLoad(session.live, of: log)
    }

    @Test("A call that changes nothing writes nothing and takes no lock")
    func noChangeWritesNothing() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try Self.writeBoard(in: directory)
        let before = try log.nodeFileSignatures()
        var session = try await Self.makeSession(of: log)
        try await session.run { store in
            try await Self.setTitle(tasks[0].description, of: tasks[0], as: Self.firstOperation, in: store)
        }
        #expect(try log.nodeFileSignatures() == before)
        #expect(!FileManager.default.fileExists(atPath: log.lockFileURL.path))
    }

    // MARK: - Signature check

    @Test("A file that changes before the commit makes the call run again, and both writes are kept")
    func changedFileRunsCallAgain() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try Self.writeBoard(in: directory)
        var session = try await Self.makeSession(of: log)
        let runs = Mutex(0)
        try await session.run { store in
            let run = Self.countRun(in: runs)
            try await Self.setTitle(Self.callTitle, of: tasks[0], as: Self.firstOperation, in: store)
            if run == 1 {
                try Self.writeAsOtherProcess(to: tasks[1], inRun: run, of: log)
            }
        }
        #expect(runs.withLock { count in count } == Self.runsAfterOneChange)
        #expect(try Self.title(of: tasks[0], in: session) == Self.callTitle)
        #expect(try Self.title(of: tasks[1], in: session) == LiveGraphApplyTests.changedTitle)
        #expect(try Self.callEvents(of: tasks[0], in: log).count == 1)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(session.live, of: log)
    }

    @Test("A file that changes before each of 5 commits gives BOARD_BUSY, writes nothing, and keeps the live graph")
    func changedFileInEachRunGivesBoardBusy() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try Self.writeBoard(in: directory)
        var session = try await Self.makeSession(of: log)
        let runs = Mutex(0)
        do {
            try await session.run { store in
                let run = Self.countRun(in: runs)
                try await Self.setTitle(Self.callTitle, of: tasks[0], as: Self.firstOperation, in: store)
                try Self.writeAsOtherProcess(to: tasks[1], inRun: run, of: log)
            }
            Issue.record("The call did not give BOARD_BUSY")
        } catch let error as KanbanError {
            #expect(error == .boardBusy(attempts: CommitSession.maximumRuns))
        }
        #expect(runs.withLock { count in count } == CommitSession.maximumRuns)
        #expect(try Self.title(of: tasks[0], in: session) == tasks[0].description)
        #expect(try Self.callEvents(of: tasks[0], in: log).isEmpty)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(session.live, of: log)
    }

    @Test("A committed call records the new signatures of the files that it wrote, also of a new file")
    func commitRecordsSignatures() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try Self.writeBoard(in: directory)
        var session = try await Self.makeSession(of: log)
        let newTask = LocalRef.task(ULID(timestamp: ReplayTests.date(atStep: Self.callStep)))
        let before = session.live.signatures
        try await session.run { store in
            try await Self.setTitle(Self.callTitle, of: tasks[0], as: Self.firstOperation, in: store)
            try await Self.setTitle(Self.callTitle, of: newTask, as: Self.secondOperation, in: store)
        }
        let onDisk = try log.nodeFileSignatures()
        let recorded = session.live.signatures
        for ref in [tasks[0], newTask] {
            let signature = try #require(onDisk[ref])
            #expect(recorded[ref] == signature)
            #expect(before[ref] != signature)
        }
        #expect(recorded == onDisk)
    }

    @Test("A call after a committed call commits in its first run, because the commit recorded the signatures")
    func callAfterCommitRunsOneTime() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try Self.writeBoard(in: directory)
        var session = try await Self.makeSession(of: log)
        try await session.run { store in
            try await Self.setTitle(Self.callTitle, of: tasks[0], as: Self.firstOperation, in: store)
        }
        let runs = Mutex(0)
        try await session.run { store in
            Self.countRun(in: runs)
            try await Self.setTitle(Self.laterCallTitle, of: tasks[0], as: Self.firstOperation, in: store)
        }
        #expect(runs.withLock { count in count } == 1)
        #expect(try Self.callEvents(of: tasks[0], in: log).map(\.patch) == Self.callTitlePatches(of: tasks[0]))
        try await LiveGraphApplyTests.expectEqualToFreshLoad(session.live, of: log)
    }

    // MARK: - Patch mutation

    @Test("The internal patch mutation applies one PatchInput to the working graph, and the commit writes it")
    func patchMutationAppliesToWorkingGraph() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try Self.writeBoard(in: directory)
        var session = try await Self.makeSession(of: log)
        let patch = try ReplayTests.titlePatch(setting: Self.callTitle, of: tasks[0])
        try await session.run { store in
            let response = try await PatchSchema().respond(
                to: Event.patchQuery,
                variables: ["p": patch.map],
                context: Self.callContext(of: store)
            )
            #expect(!response.contains("errors"))
            #expect(try LiveGraphApplyTests.task(tasks[0], in: await store.view.graph).title == Self.callTitle)
        }
        let events = try Self.callEvents(of: tasks[0], in: log)
        #expect(events.map(\.patch) == [patch])
        #expect(events.map(\.ops) == [[]])
        try await LiveGraphApplyTests.expectEqualToFreshLoad(session.live, of: log)
    }

    // MARK: - Engine

    @Test("A mutation through the engine is written to the log, and a new engine reads it")
    func engineMutationIsWritten() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let mutation = #"mutation { updateBoard(input: { name: "Port" }) { name } }"#
        let response = try await KanbanGraphTests.execute(mutation, on: KanbanGraphTests.makeGraph(at: directory.url))
        #expect(response == #"{"data":{"updateBoard":{"name":"Port"}}}"#)
        let fresh = try KanbanGraphTests.makeGraph(at: directory.url)
        let query = try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: fresh)
        #expect(query == #"{"data":{"board":{"name":"Port"}}}"#)
        let boardEvents = try EventLog(repositoryAt: directory.url).readLog(of: .board).events
        #expect(boardEvents.last?.ops == ["updateBoard"])
        #expect(boardEvents.last?.actor == ReplayTests.actor)
    }
}
