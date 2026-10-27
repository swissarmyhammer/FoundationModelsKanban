import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests when ``KanbanHost/publish(_:)`` restarts the change log of a board (KANBAN-7). The log of a board restarts
/// only when the board had changes in a round that no session view logged. A write to one board does not restart the
/// log of a board that did not change, so a cursor of that board stays valid.
@Suite("Change log restart: only a board with changes that no view logged gets a new log", .watcherBudget)
struct ChangeLogRestartTests {
    /// The number of boards of the test with interleaved writes.
    static let boardCount = 16

    /// The number of rounds of each board in the test with interleaved writes. Each round opens a new session view,
    /// so that views register while the writes of the other boards publish their changes.
    static let roundCount = 4

    /// Reads a cursor of a board, writes to the board, subscribes after the cursor, and gives the transaction of the
    /// write and the first event of the subscription.
    ///
    /// - Parameters:
    ///   - task: The ULID of a task of the board.
    ///   - title: The new title of the task. It must not be the current title, so that the write changes the board.
    ///   - graph: A session view of the board.
    ///   - root: The root directory of the repo of the board.
    /// - Returns: The transaction of the write, and the first event after the cursor.
    static func writeAfterCursor(
        retitling task: ULID,
        to title: String,
        on graph: KanbanGraph,
        inRepoAt root: URL
    ) async throws -> (txn: String, event: String) {
        let cursor = try await ChangeCursorTests.cursor(on: graph)
        let txn = try await ChangeCursorTests.retitle(task, to: title, on: graph)
        let stream = try await ChangeCursorTests.subscribe(after: cursor, on: graph)
        let events = try await SubscriptionTests.events(1, of: stream, afterChangeAt: root)
        return (txn, events[0])
    }

    @Test("A write to a board does not restart the log of a loaded board with no view, and its cursor stays valid")
    func writeKeepsLogOfUnchangedBoard() async throws {
        let first = try TemporaryDirectory()
        let second = try TemporaryDirectory()
        let firstTask = try KanbanGraphTests.writeFixture(inRepoAt: first.url).task
        let secondTask = try KanbanGraphTests.writeFixture(inRepoAt: second.url).task
        let host = HostFixture.makeHost()
        let reader = try await host.session(workingDirectory: first.url, actor: ChangeCursorTests.firstActor)
        let cursor = try await ChangeCursorTests.cursor(on: reader)
        await reader.close()
        let writer = try await host.session(workingDirectory: second.url, actor: ChangeCursorTests.secondActor)
        _ = try await ChangeCursorTests.retitle(secondTask, to: KanbanGraphTests.laterTitle, on: writer)
        let resumed = try await host.session(workingDirectory: first.url, actor: ChangeCursorTests.firstActor)
        let stream = try await ChangeCursorTests.subscribe(after: cursor, on: resumed)
        let later = try await ChangeCursorTests.retitle(firstTask, to: KanbanGraphTests.laterTitle, on: resumed)
        let events = try await SubscriptionTests.events(1, of: stream, afterChangeAt: first.url)
        #expect(try ChangeCursorTests.text("txn", of: events[0]) == later, "\(events[0])")
        await host.close()
    }

    @Test("Many boards with interleaved writes and new views: each cursor stays valid, and no log restarts")
    func interleavedWritesKeepEachCursor() async throws {
        let directories = try (0..<Self.boardCount).map { _ in try TemporaryDirectory() }
        let tasks = try directories.map { directory in try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task }
        let host = HostFixture.makeHost()
        let results = try await withThrowingTaskGroup(of: [(txn: String, event: String)].self) { group in
            for (root, task) in zip(directories.map(\.url), tasks) {
                group.addTask {
                    var results: [(txn: String, event: String)] = []
                    for round in 0..<Self.roundCount {
                        let graph = try await host.session(workingDirectory: root, actor: ChangeCursorTests.firstActor)
                        let written = try await Self.writeAfterCursor(
                            retitling: task,
                            to: "Title of round \(round)",
                            on: graph,
                            inRepoAt: root
                        )
                        results.append(written)
                        await graph.close()
                    }
                    return results
                }
            }
            return try await group.reduce(into: []) { results, result in results += result }
        }
        #expect(results.count == Self.boardCount * Self.roundCount)
        for result in results {
            #expect(try ChangeCursorTests.text("txn", of: result.event) == result.txn, "\(result.event)")
        }
        await host.close()
    }
}
