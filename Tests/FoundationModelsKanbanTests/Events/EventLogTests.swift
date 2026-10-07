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
    /// title `last`.
    ///
    /// - Returns: The two events, in step order.
    static func firstAndLastTitleEvents() throws -> [Event] {
        [try titleEvent(atStep: 1, setting: "first"), try titleEvent(atStep: 2, setting: "last")]
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

    /// Tells if a different file descriptor can get the lock of a board now. The check does not wait.
    ///
    /// - Parameter log: The event log of the board.
    /// - Returns: `true` when the lock is free.
    static func isLockFree(of log: EventLog) -> Bool {
        let descriptor = open(log.lockFileURL.path, O_RDWR | O_CREAT, EventLog.lockFileMode)
        defer { close(descriptor) }
        return flock(descriptor, LOCK_EX | LOCK_NB) == 0
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
        let file = log.fileURL(for: task)
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try first.encodedLine().write(to: file, atomically: true, encoding: .utf8)
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
    func lockExcludesOtherDescriptor() throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let lock = try log.lock()
        #expect(!Self.isLockFree(of: log))
        lock.unlock()
        #expect(Self.isLockFree(of: log))
    }

    @Test("A second lock of the same board waits until the first lock is released")
    func secondLockWaitsForFirst() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let records = Mutex<[String]>([])
        let first = try log.lock()
        let waiter = Task.detached {
            let second = try log.lock()
            records.withLock { list in list.append(Self.acquiredRecord) }
            second.unlock()
        }
        try await Task.sleep(for: Self.holdDuration)
        records.withLock { list in list.append(Self.releasedRecord) }
        first.unlock()
        try await waiter.value
        #expect(records.withLock { list in list } == [Self.releasedRecord, Self.acquiredRecord])
    }

    @Test("The lock of many boards takes the boards in the sort order of the board key")
    func manyBoardsLockInKeyOrder() throws {
        let directory = try TemporaryDirectory()
        let names = ["zeta", "alpha", "mid"]
        let logs = Dictionary(
            uniqueKeysWithValues: names.map { name in
                (BoardKey(localDirectoryName: name), EventLog(repositoryAt: directory.url.appending(path: name)))
            }
        )
        let ordered = EventLog.lockOrder(of: logs)
        #expect(ordered == names.sorted().map { name in EventLog(repositoryAt: directory.url.appending(path: name)) })
        let lock = try EventLog.lock(sortedByKey: logs)
        #expect(ordered.allSatisfy { log in !Self.isLockFree(of: log) })
        lock.unlock()
        #expect(ordered.allSatisfy { log in Self.isLockFree(of: log) })
    }
}

// MARK: - Temporary directory

/// An empty temporary directory for one test. The directory is removed when the value ends.
///
/// The type is a class, because its `deinit` removes the directory.
final class TemporaryDirectory {
    /// The directory.
    let url: URL

    /// Makes an empty temporary directory.
    ///
    /// - Throws: An error from `FileManager` when the directory cannot be made.
    init() throws {
        url = FileManager.default.temporaryDirectory.appending(
            path: "EventLogTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
