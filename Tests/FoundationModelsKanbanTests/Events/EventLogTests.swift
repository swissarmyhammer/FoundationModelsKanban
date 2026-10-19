import Foundation
import Synchronization
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the log files of one board: the paths, the append, the read, the file signatures, and the write lock
/// (plan.md §5.2, §5.4 step 5, §5.6).
@Suite("Event log of one board")
struct EventLogTests {
    /// The time that the blocked lock test waits before it releases the first lock. The second lock must not get
    /// the lock in this time.
    static let holdDuration = Duration.milliseconds(200)

    /// The pause between two tries of a wait until a check is true.
    static let retryPause = Duration.milliseconds(retryPauseMilliseconds)

    /// The number of milliseconds in ``retryPause``.
    private static let retryPauseMilliseconds = 10

    /// The number of milliseconds in one second.
    private static let millisecondsPerSecond = 1000

    /// The pause between two tries of a wait until a check is true, for a wait on a thread of its own.
    private static let retryPauseInterval = TimeInterval(retryPauseMilliseconds) / TimeInterval(millisecondsPerSecond)

    /// The number of tasks for each processor that wait for the lock in the pool test. The Swift cooperative pool has
    /// about one thread for each processor, so this count of tasks is more than the pool can run when each wait blocks
    /// a thread.
    private static let waitingTasksPerProcessor = 2

    /// The record of the lock test when the first lock is released.
    static let releasedRecord = "first released"

    /// The record of the lock test when the second lock is held.
    static let acquiredRecord = "second acquired"

    /// The text of a `.gitignore` file that the caller wrote before the first append.
    static let callerIgnoreText = "custom\n"

    /// The text of a file in a node directory that is not a log, for example a file of the old Rust board.
    static let otherFileText = "title: old\n"

    /// The ref of the `todo` column.
    static let todoColumn = LocalRef.column(slug: "todo")

    /// The ref of the `claude-code` actor.
    static let actor = LocalRef.actor(slug: "claude-code")

    /// The ref of the `bug` tag.
    static let bugTag = LocalRef.tag(slug: "bug")

    /// A text with U+2028 (line separator), U+2029 (paragraph separator) and U+0085 (next line). `JSONEncoder` does
    /// not escape these characters, so they stay in the log line, but they do not end the line.
    static let unicodeBreakText = "one\u{2028}two\u{2029}three\u{0085}four"

    /// The line break of a line that a Windows editor wrote: a carriage return before the line feed.
    static let crlfLineBreak = "\r\n"

    /// Makes the event of a patch that sets the title of the test task.
    ///
    /// - Parameters:
    ///   - step: The step of the event. A larger step gives a later event id.
    ///   - title: The new title.
    /// - Returns: The event.
    static func titleEvent(atStep step: Int, setting title: String) throws -> Event {
        try Event(parsing: ReplayTests.line(atStep: step, patch: ReplayTests.titlePatch(setting: title)))
    }

    /// Makes the events of steps 1 and 2 of the test task: the first sets the title `first`, and the second sets the
    /// title `lastTitle`.
    ///
    /// - Parameter lastTitle: The title that the event of step 2 sets. The default is `last`.
    /// - Returns: The two events, in step order.
    static func firstAndLastTitleEvents(lastTitle: String = "last") throws -> [Event] {
        [try titleEvent(atStep: 1, setting: "first"), try titleEvent(atStep: 2, setting: lastTitle)]
    }

    /// Writes events to the log file of the test task as appended lines, and gives the log of the board.
    ///
    /// - Parameters:
    ///   - events: The events, in file order.
    ///   - directory: The temporary repo directory.
    /// - Returns: The event log of the board, and the ref of the test task.
    static func appendToTaskLog(
        _ events: [Event],
        in directory: TemporaryDirectory
    ) throws -> (log: EventLog, task: LocalRef) {
        let log = EventLog(repositoryAt: directory.url)
        let task = try ReplayTests.taskRef()
        try log.append(contentsOf: events, toLogOf: task)
        return (log, task)
    }

    /// Makes the event of a patch that sets the name of a node.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - step: The step of the event.
    /// - Returns: The event.
    static func nameEvent(of ref: LocalRef, atStep step: Int) throws -> Event {
        let patch = try PatchInput(node: ref, set: ["name": .json(.string("name \(step)"))])
        return try Event(parsing: ReplayTests.line(atStep: step, patch: patch))
    }

    /// Reads the text of a file.
    ///
    /// - Parameter url: The file.
    /// - Returns: The text of the file.
    static func text(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Writes a text as the full log file of one node, without an append. The directory of the file is made first.
    ///
    /// - Parameters:
    ///   - text: The full text of the file.
    ///   - ref: The local ref of the node.
    ///   - log: The event log of the board.
    /// - Returns: The file.
    @discardableResult
    static func writeLogFile(_ text: String, of ref: LocalRef, in log: EventLog) throws -> URL {
        let file = log.fileURL(for: ref)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Tells if a different file descriptor can get the lock of a board now. The check does not wait. It uses the
    /// open step and the lock try of the production lock.
    ///
    /// - Parameter log: The event log of the board.
    /// - Returns: `true` when the lock is free. `false` when a different lock holds it, or the lock file cannot be
    ///   opened.
    static func isLockFree(of log: EventLog) -> Bool {
        do {
            let descriptor = try log.openLockFile()
            defer { close(descriptor) }
            return EventLog.tryLock(on: descriptor) == 0
        } catch {
            return false
        }
    }

    /// Waits until the lock of a board is released. A child process that another test starts at the same time can
    /// hold a copy of the lock file for a short time, until its `exec` closes the copy. Thus the check tries again,
    /// so that this short time does not fail the test.
    ///
    /// - Parameter log: The event log of the board.
    /// - Throws: `CancellationError` when the test is cancelled during the wait.
    static func waitForLockRelease(of log: EventLog) async throws {
        try await waitUntil { isLockFree(of: log) }
    }

    /// Does a check again and again, with a short pause between two tries, until the check is true. The wait has no
    /// deadline. A test that waits for a different thread or process uses this wait.
    ///
    /// - Parameter condition: The check. It must not block. It can read an actor.
    /// - Throws: `CancellationError` when the test is cancelled during the wait.
    static func waitUntil(_ condition: () async -> Bool) async throws {
        while !(await condition()) {
            try await Task.sleep(for: retryPause)
        }
    }

    // MARK: - Paths

    @Test("Each node type has its log file in the directory of the plan")
    func pathsFollowLayout() throws {
        let log = EventLog(repositoryAt: URL(filePath: "/repo", directoryHint: .isDirectory))
        let task = try ReplayTests.taskRef()
        let comment = try ReplayTests.commentRef()
        #expect(log.directory.path == "/repo/.kanban")
        #expect(log.fileURL(for: .board).path == "/repo/.kanban/board.jsonl")
        #expect(log.fileURL(for: Self.todoColumn).path == "/repo/.kanban/columns/todo.jsonl")
        #expect(log.fileURL(for: Self.actor).path == "/repo/.kanban/actors/claude-code.jsonl")
        #expect(log.fileURL(for: Self.bugTag).path == "/repo/.kanban/tags/bug.jsonl")
        #expect(log.fileURL(for: task).path == "/repo/.kanban/tasks/\(ReplayTests.taskULID).jsonl")
        #expect(log.fileURL(for: comment).path == "/repo/.kanban/comments/\(ReplayTests.commentULID).jsonl")
        #expect(log.lockFileURL.path == "/repo/.kanban/.lock")
    }

    // MARK: - Append

    @Test("An append adds one line for each event and does not change the other lines")
    func appendAddsOneLinePerEvent() throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let task = try ReplayTests.taskRef()
        let first = try Self.titleEvent(atStep: 1, setting: "first")
        let later = [
            try Self.titleEvent(atStep: 2, setting: "second"),
            try Self.titleEvent(atStep: 3, setting: "third"),
        ]
        try log.append(contentsOf: [first], toLogOf: task)
        let before = try Self.text(of: log.fileURL(for: task))
        try log.append(contentsOf: later, toLogOf: task)
        let after = try Self.text(of: log.fileURL(for: task))
        let expectedLines = try ([first] + later).map { event in try event.encodedLine() }
        #expect(after.hasPrefix(before))
        #expect(after == expectedLines.map { line in line + "\n" }.joined())
    }

    @Test("An append to a file whose last line has no line break adds the line break first")
    func appendEndsLastLine() throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let task = try ReplayTests.taskRef()
        let first = try Self.titleEvent(atStep: 1, setting: "first")
        let second = try Self.titleEvent(atStep: 2, setting: "second")
        let file = try Self.writeLogFile(first.encodedLine(), of: task, in: log)
        try log.append(contentsOf: [second], toLogOf: task)
        #expect(try Self.text(of: file) == "\(try first.encodedLine())\n\(try second.encodedLine())\n")
    }

    @Test("The first append makes the git files of the board")
    func appendMakesGitFiles() throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        try log.append(contentsOf: [Self.nameEvent(of: .board, atStep: 1)], toLogOf: .board)
        let attributes = log.directory.appending(path: EventLog.gitattributesFileName)
        let ignore = log.directory.appending(path: EventLog.gitignoreFileName)
        #expect(try Self.text(of: attributes) == "*.jsonl merge=union\n")
        #expect(try Self.text(of: ignore) == ".lock\n")
    }

    @Test("An append does not change a git file that is already there")
    func appendKeepsGitFiles() throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let ignore = log.directory.appending(path: EventLog.gitignoreFileName)
        try FileManager.default.createDirectory(at: log.directory, withIntermediateDirectories: true)
        try Self.callerIgnoreText.write(to: ignore, atomically: true, encoding: .utf8)
        try log.append(contentsOf: [Self.nameEvent(of: .board, atStep: 1)], toLogOf: .board)
        #expect(try Self.text(of: ignore) == Self.callerIgnoreText)
    }

    @Test("An append refuses an event that changes a different node, and writes nothing")
    func appendRefusesOtherNode() throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let event = try Self.nameEvent(of: .board, atStep: 1)
        #expect(throws: EventLogError.nodeMismatch(log: Self.bugTag, event: .board)) {
            try log.append(contentsOf: [event], toLogOf: Self.bugTag)
        }
        #expect(!FileManager.default.fileExists(atPath: log.fileURL(for: Self.bugTag).path))
    }

    // MARK: - Read

    @Test("A read folds the events that an append wrote")
    func readFoldsAppendedEvents() throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let task = try ReplayTests.taskRef()
        let events = try Self.firstAndLastTitleEvents()
        try log.append(contentsOf: events, toLogOf: task)
        let read = try log.readLog(of: task)
        #expect(read.events == events)
        #expect((read.node?.state as? TaskNode)?.title == "last")
    }

    @Test("A read of a node with no file gives no events and no node")
    func readOfMissingFileIsEmpty() throws {
        let directory = try TemporaryDirectory()
        let read = try EventLog(repositoryAt: directory.url).readLog(of: Self.bugTag)
        #expect(read.events.isEmpty)
        #expect(read.node == nil)
    }

    @Test("A read keeps a line whose value holds U+2028, U+2029 and U+0085 as one event")
    func readKeepsUnicodeBreaksInLine() throws {
        let directory = try TemporaryDirectory()
        let events = try Self.firstAndLastTitleEvents(lastTitle: Self.unicodeBreakText)
        let (log, task) = try Self.appendToTaskLog(events, in: directory)
        let read = try log.readLog(of: task)
        #expect(read.events == events)
        #expect((read.node?.state as? TaskNode)?.title == Self.unicodeBreakText)
    }

    @Test("A read accepts lines that end with a carriage return and a line feed")
    func readAcceptsCRLFLines() throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let task = try ReplayTests.taskRef()
        let events = try Self.firstAndLastTitleEvents(lastTitle: Self.unicodeBreakText)
        let text = try events.map { event in try event.encodedLine() + Self.crlfLineBreak }.joined()
        try Self.writeLogFile(text, of: task, in: log)
        #expect(try log.readLog(of: task).events == events)
        #expect(try log.signature(of: task)?.lastEventID == events.last?.id)
    }

    // MARK: - Signatures

    @Test("A node with no file has no signature")
    func missingFileHasNoSignature() throws {
        let directory = try TemporaryDirectory()
        #expect(try EventLog(repositoryAt: directory.url).signature(of: Self.bugTag) == nil)
    }

    @Test("The signature holds the size and the modification time of the file, and the id of its last event")
    func signatureHoldsSizeTimeAndLastEvent() throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let task = try ReplayTests.taskRef()
        let events = try Self.firstAndLastTitleEvents()
        try log.append(contentsOf: events, toLogOf: task)
        let file = log.fileURL(for: task)
        let signature = try #require(try log.signature(of: task))
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect(signature.size == (try Data(contentsOf: file)).count)
        #expect(signature.modified == attributes[.modificationDate] as? Date)
        #expect(signature.lastEventID == events.last?.id)
    }

    @Test("The signature gives the id of a last line whose value holds U+2028, U+2029 and U+0085")
    func signatureReadsLastLineWithUnicodeBreaks() throws {
        let directory = try TemporaryDirectory()
        let events = try Self.firstAndLastTitleEvents(lastTitle: Self.unicodeBreakText)
        let (log, task) = try Self.appendToTaskLog(events, in: directory)
        #expect(try log.signature(of: task)?.lastEventID == events.last?.id)
    }

    @Test("The signature changes after an append and does not change after a read")
    func signatureChangesOnlyOnAppend() throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let task = try ReplayTests.taskRef()
        try log.append(contentsOf: [Self.titleEvent(atStep: 1, setting: "first")], toLogOf: task)
        let first = try log.signature(of: task)
        _ = try log.readLog(of: task)
        #expect(try log.signature(of: task) == first)
        try log.append(contentsOf: [Self.titleEvent(atStep: 2, setting: "second")], toLogOf: task)
        #expect(try log.signature(of: task) != first)
    }

    @Test("The list of node files holds each log of the board with its signature, and no other file")
    func nodeFilesListEachLog() throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let task = try ReplayTests.taskRef()
        let named: [LocalRef] = [.board, Self.todoColumn, Self.actor, Self.bugTag]
        for (step, ref) in named.enumerated() {
            try log.append(contentsOf: [Self.nameEvent(of: ref, atStep: step)], toLogOf: ref)
        }
        try log.append(contentsOf: [Self.titleEvent(atStep: named.count, setting: "task")], toLogOf: task)
        let otherFile = log.fileURL(for: Self.bugTag).deletingPathExtension().appendingPathExtension("yaml")
        try Self.otherFileText.write(to: otherFile, atomically: true, encoding: .utf8)
        let listed = try log.nodeFileSignatures()
        let expected = try Dictionary(
            uniqueKeysWithValues: (named + [task]).map { ref in (ref, try #require(try log.signature(of: ref))) }
        )
        #expect(listed == expected)
    }

    @Test("A board with no directory has no node files")
    func missingDirectoryHasNoNodeFiles() throws {
        let directory = try TemporaryDirectory()
        #expect(try EventLog(repositoryAt: directory.url).nodeFileSignatures().isEmpty)
    }

    // MARK: - Lock

    @Test("A different file descriptor cannot lock the board while the lock is held")
    func lockExcludesOtherDescriptor() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let lock = try await log.lock()
        #expect(!Self.isLockFree(of: log))
        lock.unlock()
        try await Self.waitForLockRelease(of: log)
    }

    @Test("A second lock of the same board waits until the first lock is released")
    func secondLockWaitsForFirst() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let records = Mutex<[String]>([])
        let first = try await log.lock()
        let waiter = Task {
            let second = try await log.lock()
            records.withLock { list in list.append(Self.acquiredRecord) }
            second.unlock()
        }
        try await Task.sleep(for: Self.holdDuration)
        records.withLock { list in list.append(Self.releasedRecord) }
        first.unlock()
        try await Self.waitUntil { records.withLock { list in list.contains(Self.acquiredRecord) } }
        try await waiter.value
        #expect(records.withLock { list in list } == [Self.releasedRecord, Self.acquiredRecord])
    }

    @Test(
        "Tasks that wait for the lock block no thread of the cooperative pool, so each task starts before the release"
    )
    func lockWaitsBlockNoPoolThread() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let descriptor = try Self.holdLockWithOwnDescriptor(of: log)
        let taskCount = Self.waitingTasksPerProcessor * ProcessInfo.processInfo.activeProcessorCount
        let progress = LockWaitProgress()
        Self.releaseOnOwnThread(descriptor, whenStarted: taskCount, recordingTo: progress)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<taskCount {
                group.addTask {
                    progress.recordStart()
                    let lock = try await log.lock()
                    lock.unlock()
                }
            }
            try await group.waitForAll()
        }
        #expect(progress.lateStartCount == 0)
    }

    /// Opens the lock file of a board with a file descriptor of the test, and gets its lock. The call uses the open
    /// step and the lock try of the production lock, but keeps the raw descriptor, so that a thread of the test can
    /// release the lock. The board has no other lock, so the call does not wait.
    ///
    /// - Parameter log: The event log of the board.
    /// - Returns: The file descriptor that holds the lock. Its close releases the lock.
    /// - Throws: An error when the directory cannot be made, or the file cannot be opened or locked.
    private static func holdLockWithOwnDescriptor(of log: EventLog) throws -> Int32 {
        try log.prepareDirectory()
        let descriptor = try log.openLockFile()
        let code = EventLog.tryLock(on: descriptor)
        if code != 0 {
            close(descriptor)
        }
        try #require(code == 0)
        return descriptor
    }

    /// Starts a thread of its own that releases a lock when a count of tasks started. The wait has no deadline. The
    /// thread is not a thread of the cooperative pool, so it releases the lock also when each pool thread is blocked.
    ///
    /// - Parameters:
    ///   - descriptor: The file descriptor that holds the lock. The thread closes it.
    ///   - taskCount: The count of tasks that must start before the release.
    ///   - progress: The record of the started tasks. The thread records the release in it.
    private static func releaseOnOwnThread(
        _ descriptor: Int32,
        whenStarted taskCount: Int,
        recordingTo progress: LockWaitProgress
    ) {
        Thread.detachNewThread {
            while progress.startCount < taskCount {
                Thread.sleep(forTimeInterval: retryPauseInterval)
            }
            progress.recordRelease()
            close(descriptor)
        }
    }

    @Test("The lock of many boards takes the boards in the sort order of the board key")
    func manyBoardsLockInKeyOrder() async throws {
        let directory = try TemporaryDirectory()
        let names = ["zeta", "alpha", "mid"]
        let logs = Dictionary(
            uniqueKeysWithValues: names.map { name in
                (BoardKey(rootCommit: name), EventLog(repositoryAt: directory.url.appending(path: name)))
            }
        )
        let ordered = EventLog.lockOrder(of: logs)
        #expect(ordered == names.sorted().map { name in EventLog(repositoryAt: directory.url.appending(path: name)) })
        try await Self.expectOneLockHolds(Array(logs), inOrder: ordered)
    }

    @Test("The lock of many boards holds two copies of one repo, which have the same key")
    func twoCopiesWithOneKeyLockBoth() async throws {
        let directory = try TemporaryDirectory()
        let key = BoardKey(rootCommit: "app")
        let logs = ["second", "first"].map { name in
            (key: key, value: EventLog(repositoryAt: directory.url.appending(path: name)))
        }
        let ordered = EventLog.lockOrder(of: logs)
        #expect(ordered == logs.map(\.value).reversed())
        try await Self.expectOneLockHolds(logs, inOrder: ordered)
    }

    /// Gets one lock of many boards, and checks that the lock holds each board until the release, and that the
    /// release frees each board.
    ///
    /// - Parameters:
    ///   - logs: The event log of each board, with its board key.
    ///   - ordered: The event logs, in lock order.
    /// - Throws: An error when a board cannot be locked, or the test is cancelled during the wait.
    static func expectOneLockHolds(
        _ logs: [(key: BoardKey, value: EventLog)],
        inOrder ordered: [EventLog]
    ) async throws {
        let lock = try await EventLog.lock(sortedByKey: logs)
        #expect(ordered.allSatisfy { log in !isLockFree(of: log) })
        lock.unlock()
        for log in ordered {
            try await waitForLockRelease(of: log)
        }
    }
}

// MARK: - Lock wait progress

/// The record of the pool test: the count of tasks that started, and the count of tasks that started after the
/// release of the lock. The tasks and the thread that releases the lock share one record.
///
/// The type is a class, because the tasks and the thread share one value. A mutex keeps its state safe.
///
/// The record does not use the shared ``TestGate``. It holds no call and waits for nothing: each start must read the
/// release flag and count itself in one lock, so that a start is late exactly when it comes after the release. Two
/// locks, one of a gate and one of the counts, cannot give that order.
private final class LockWaitProgress: Sendable {
    /// The state of the record.
    private struct State {
        /// The count of tasks that started.
        var startCount = 0

        /// The count of tasks that started after the release of the lock.
        var lateStartCount = 0

        /// `true` after the release of the lock.
        var isReleased = false
    }

    /// The state, under a mutex.
    private let state = Mutex(State())

    /// The count of tasks that started.
    var startCount: Int {
        state.withLock { current in current.startCount }
    }

    /// The count of tasks that started after the release of the lock.
    var lateStartCount: Int {
        state.withLock { current in current.lateStartCount }
    }

    /// Records the start of one task.
    func recordStart() {
        state.withLock { current in
            current.startCount += 1
            if current.isReleased {
                current.lateStartCount += 1
            }
        }
    }

    /// Records the release of the lock.
    func recordRelease() {
        state.withLock { current in current.isReleased = true }
    }
}

// MARK: - Temporary directory

/// An empty temporary directory for one test. The directory is removed when the value ends.
///
/// The type is a class, because its `deinit` removes the directory.
///
/// The directory is in the folder of the ``TestFolderGroup/temporaryDirectories`` group of the run folder of
/// ``TestFolderRoot``. A test that uses the directory as a repo root and reads a related board makes the engine scan
/// the parent directory (plan.md §6.6). Thus the parent holds only the directories of the tests, and the scan stays
/// small.
final class TemporaryDirectory {
    /// The directory.
    let url: URL

    /// Makes an empty temporary directory in the folder of the ``TestFolderGroup/temporaryDirectories`` group.
    ///
    /// - Throws: An error from `FileManager` when the directory cannot be made.
    convenience init() throws {
        try self.init(in: TestFolderRoot.folder(of: .temporaryDirectories))
    }

    /// Makes an empty temporary directory in a parent folder.
    ///
    /// - Parameter parent: The folder that holds the new directory.
    /// - Throws: An error from `FileManager` when the directory cannot be made.
    init(in parent: URL) throws {
        url = parent.appending(path: "EventLogTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
