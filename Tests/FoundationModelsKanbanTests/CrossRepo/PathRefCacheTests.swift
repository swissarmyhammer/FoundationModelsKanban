import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the memory of the host for a path board ref (divergence.md §16, Gap 1): the second call with the same path ref
/// runs no git, for a folder that is not in a git repo, for a repo whose key read fails, and for a repo with a board. A
/// change of the folder, its `.git` entry, or its git config makes the next call read git again.
///
/// Each test makes the current repo in a ``ScanPlace``, and the folder of the path ref in a second
/// ``TemporaryDirectory``, where the scan does not look. A ``ScanKeyReader`` gives the worktree tops and the keys, and
/// counts each read, so a test runs git only to make a repo. No test uses the `.kanban/` directory of this repo.
@Suite("Cross-repo: the result of a path board ref stays in memory", .watcherBudget, .timeLimit(.minutes(1)))
struct PathRefCacheTests {
    /// The number of calls after the first call that each test makes with the same path ref.
    static let repeatCount = 3

    /// Gives the query of the name of the board that a path ref names.
    ///
    /// - Parameter folder: The folder that the path ref names.
    /// - Returns: The query.
    static func nameQuery(ofBoardAt folder: URL) -> String {
        #"{ board(id: "\#(folder.path)") { name } }"#
    }

    /// Runs the query of ``nameQuery(ofBoardAt:)`` one time, and then ``repeatCount`` times more, and checks that the
    /// calls after the first give the same response and read no worktree top and no key.
    ///
    /// - Parameters:
    ///   - folder: The folder that the path ref names.
    ///   - session: The session view of the current repo.
    ///   - reader: The reader of the worktree tops and the keys of the host of the session.
    /// - Returns: The response of the first call.
    /// - Throws: An error when a call cannot run.
    static func expectRepeatedCallsRunNoGit(
        naming folder: URL,
        on session: KanbanGraph,
        readingWith reader: ScanKeyReader
    ) async throws -> String {
        let query = nameQuery(ofBoardAt: folder)
        let first = try await KanbanGraphTests.execute(query, on: session)
        let gitCalls = reader.count
        for _ in 0..<repeatCount {
            #expect(try await KanbanGraphTests.execute(query, on: session) == first)
        }
        #expect(reader.count == gitCalls)
        return first
    }

    // MARK: - No git on a repeated path ref

    @Test("A second call with the same path ref to a folder that is not in a git repo runs no git")
    func notARepoRunsNoGit() async throws {
        let place = try ScanPlace.make()
        let outside = try TemporaryDirectory()
        let folder = try GitSandbox.makeFolder(named: ScanCacheTests.newName, in: outside.url)
        let reader = ScanKeyReader()
        let host = ScanCacheTests.makeHost(reading: reader, recordedBy: ScanRecorder())
        let session = try await host.session(workingDirectory: place.app, actor: KanbanHostTests.firstActor)
        let response = try await Self.expectRepeatedCallsRunNoGit(naming: folder, on: session, readingWith: reader)
        let expected = KanbanError.notARepo(path: folder.standardizedFileURL.path)
        try ErrorCoverageTests.expectFailure(of: "board", in: response, giving: expected, coded: "NOT_A_REPO")
        await host.close()
    }

    @Test("A second call with the same path ref to a repo whose key read fails runs no git")
    func failedKeyReadRunsNoGit() async throws {
        let place = try ScanPlace.make()
        let outside = try TemporaryDirectory()
        let folder = try ScanPlace.makeRepoFolder(named: ScanCacheTests.brokenName, in: outside.url)
        let reader = ScanKeyReader()
        let host = ScanCacheTests.makeHost(reading: reader, recordedBy: ScanRecorder())
        let session = try await host.session(workingDirectory: place.app, actor: KanbanHostTests.firstActor)
        let response = try await Self.expectRepeatedCallsRunNoGit(naming: folder, on: session, readingWith: reader)
        #expect(try KanbanGraphTests.data(of: response)["board"] is NSNull)
        await host.close()
    }

    @Test("A second call with the same path ref to a repo with a key runs no git")
    func boardRunsNoGit() async throws {
        let place = try ScanPlace.make()
        let outside = try TemporaryDirectory()
        let folder = try ScanPlace.makeRepoFolder(named: ScanCacheTests.newName, in: outside.url)
        let reader = ScanKeyReader()
        let host = ScanCacheTests.makeHost(reading: reader, recordedBy: ScanRecorder())
        let session = try await host.session(workingDirectory: place.app, actor: KanbanHostTests.firstActor)
        _ = try await Self.expectRepeatedCallsRunNoGit(naming: folder, on: session, readingWith: reader)
        #expect(try await CrossRepoReadTests.board("path", of: folder.path, on: session) == folder.path)
        await host.close()
    }

    // MARK: - Watcher

    @Test("After git init in a folder that a path ref named, the next call with the path ref finds the board")
    func gitInitFindsBoard() async throws {
        let place = try ScanPlace.make()
        let outside = try TemporaryDirectory()
        let folder = try GitSandbox.makeFolder(named: ScanCacheTests.newName, in: outside.url)
        let recorder = ScanRecorder()
        let host = ScanCacheTests.makeHost(reading: ScanKeyReader(), recordedBy: recorder)
        let session = try await host.session(workingDirectory: place.app, actor: KanbanHostTests.firstActor)
        #expect(try await !ScanCacheTests.hasBoard(of: folder.path, on: session))
        try await GitSandbox.initializeRepo(at: folder, withIdentity: false)
        try await recorder.waitForChange(.repo(folder.canonicalPath)) {
            try await ScanCacheTests.hasBoard(of: folder.path, on: session)
        }
        #expect(try await CrossRepoReadTests.board("path", of: folder.path, on: session) == folder.path)
        await host.close()
    }
}
