import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the stamp of the board of a folder: ``KanbanHost/boardStamp(ofFolder:)`` (TestudoApp D214).
///
/// Each test uses a temporary folder with the fixture board of ``KanbanGraphTests``: the board node, the `todo`
/// column, and one task. The stamp must change when a log file changes, and it must stay the same when no log file
/// changes.
@Suite("Board stamp: the cheap stamp of the board of a folder")
struct BoardStampTests {
    /// The title of the task that the new-file test adds.
    static let addedTitle = "Add the stamp"

    /// The name that the column test gives to the `todo` column.
    static let renamedColumn = "Next"

    /// The file mode that gives no permission to read or write a file.
    static let noAccessMode: Int16 = 0o000

    /// The file mode that gives the owner permission to read and write a file.
    static let ownerAccessMode: Int16 = 0o600

    /// The temporary folder of a test, with the fixture board in it.
    let directory: TemporaryDirectory

    /// The ULID of the fixture task.
    let task: ULID

    /// The ULID source that wrote the fixture. A test writes its next events from it.
    var ids: FixedULIDSource

    /// Writes the fixture board to a new temporary folder.
    ///
    /// - Throws: An error when the folder cannot be made or a write fails.
    init() throws {
        directory = try TemporaryDirectory()
        (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
    }

    /// The event log of the fixture board.
    var log: EventLog {
        EventLog(repositoryAt: directory.url)
    }

    /// Gives the stamp of the fixture board.
    ///
    /// - Returns: The stamp.
    /// - Throws: An error when the folder gives no stamp.
    func stamp() throws -> BoardStamp {
        try #require(KanbanHost.shared.boardStamp(ofFolder: directory.url))
    }

    // MARK: - No board

    @Test("A folder with no .kanban folder gives no board")
    func folderWithNoBoardGivesNil() throws {
        let empty = try TemporaryDirectory()
        #expect(KanbanHost.shared.boardStamp(ofFolder: empty.url) == nil)
    }

    @Test("A file with the name .kanban, not a folder, gives no board")
    func kanbanFileGivesNil() throws {
        let folder = try TemporaryDirectory()
        let file = EventLog(repositoryAt: folder.url).directory.path
        try #require(FileManager.default.createFile(atPath: file, contents: Data()))
        #expect(KanbanHost.shared.boardStamp(ofFolder: folder.url) == nil)
    }

    // MARK: - No change

    @Test("The stamp is the same after a read with no change")
    func readKeepsStamp() async throws {
        let before = try stamp()
        _ = try await KanbanHost.shared.readBoard(inFolder: directory.url)
        #expect(try stamp() == before)
    }

    @Test("The lock of a session does not change the stamp")
    func lockKeepsStamp() async throws {
        let before = try stamp()
        let lock = try await log.lock()
        let during = try stamp()
        lock.unlock()
        #expect(during == before)
    }

    @Test("The snapshot of a read holds the stamp of the board when nothing changed after the read")
    func snapshotHoldsStamp() async throws {
        let snapshot = try #require(try await KanbanHost.shared.readBoard(inFolder: directory.url).snapshot)
        #expect(snapshot.stamp == (try stamp()))
    }

    // MARK: - Changes

    @Test("A new line in the log of a task changes the stamp")
    mutating func taskChangeChangesStamp() throws {
        let before = try stamp()
        try BoardWatcherTests.writeLaterTitle(to: task, mintingFrom: &ids, in: log)
        #expect(try stamp() != before)
    }

    @Test("A new line in the log of a column changes the stamp")
    mutating func columnChangeChangesStamp() throws {
        let before = try stamp()
        let rename = try PatchInput(node: KanbanGraphTests.todoColumn, set: ["name": .json(.string(Self.renamedColumn))])
        try KanbanGraphTests.append(rename, mintingFrom: &ids, to: log)
        #expect(try stamp() != before)
    }

    @Test("A new task file changes the stamp")
    mutating func newTaskChangesStamp() throws {
        let before = try stamp()
        _ = try KanbanGraphTests.writeTask(titled: Self.addedTitle, mintingFrom: &ids, to: log)
        #expect(try stamp() != before)
    }

    @Test("The removal of a task file changes the stamp")
    func taskRemovalChangesStamp() throws {
        let before = try stamp()
        try FileManager.default.removeItem(at: log.fileURL(for: .task(task)))
        #expect(try stamp() != before)
    }

    @Test("A rewrite in place that keeps the size of a task file changes the stamp")
    func sameSizeRewriteChangesStamp() throws {
        let file = log.fileURL(for: .task(task))
        let contents = try Data(contentsOf: file)
        let before = try stamp()
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: contents)
        try handle.close()
        #expect(try stamp() != before)
    }

    // MARK: - No read

    @Test("A task file with no read permission still has its entry in the stamp")
    func unreadableTaskFileHasEntry() throws {
        let file = log.fileURL(for: .task(task))
        let key = try #require(PatchNodeType.task.logDirectoryName) + "/" + file.lastPathComponent
        try FileManager.default.setAttributes([.posixPermissions: Self.noAccessMode], ofItemAtPath: file.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: Self.ownerAccessMode], ofItemAtPath: file.path)
        }
        #expect(BoardStamp.entries(ofBoardAt: directory.url)?[key] != nil)
    }
}
