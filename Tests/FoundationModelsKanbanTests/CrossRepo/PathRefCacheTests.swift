import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the memory of the host for a path board ref (divergence.md §16, Gap 1): the second call with the same path ref
/// runs no git, for a folder that is not in a git repo, for a repo whose key read fails, and for a repo with a board. A
/// change of the folder, its `.git` entry, its git config, or its parent folder makes the next call read git again. New
/// commits make the next call read git again for a repo whose key read failed.
///
/// Each test makes the current repo in a ``ScanPlace``, and the folder of the path ref in a second
/// ``TemporaryDirectory``, where the scan does not look. A ``ScanKeyReader`` gives the worktree tops and the keys, and
/// counts each read, so a test runs git only to make a repo. No test uses the `.kanban/` directory of this repo.
@Suite("Cross-repo: the result of a path board ref stays in memory", .watcherBudget)
struct PathRefCacheTests {
    /// The number of calls after the first call that each test makes with the same path ref.
    static let repeatCount = 3

    /// The `origin` that a test gives to the repo of a path ref after the first call: the key of the repo after its
    /// first commit, or the key of the repo that replaces it.
    static let laterOrigin = "https://github.com/example/later.git"

    /// The path components of the branch ref that the first commit of a repo writes in its `.git` directory.
    static let firstBranchRef = ["refs", "heads", "main"]

    /// The commit that the branch ref of ``makeFirstCommit(inRepoAt:)`` names.
    static let firstCommitSHA = "0123456789abcdef0123456789abcdef01234567"

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

    @Test("After the first commit in a repo whose key read failed, the next call with the path ref finds the board")
    func firstCommitFindsBoard() async throws {
        let place = try ScanPlace.make()
        let outside = try TemporaryDirectory()
        let folder = try ScanPlace.makeRepoFolder(named: ScanCacheTests.brokenName, in: outside.url)
        let reader = ScanKeyReader()
        let recorder = ScanRecorder()
        let host = ScanCacheTests.makeHost(reading: reader, recordedBy: recorder)
        let session = try await host.session(workingDirectory: place.app, actor: KanbanHostTests.firstActor)
        #expect(try await !ScanCacheTests.hasBoard(of: folder.path, on: session))
        reader.setOrigin(Self.laterOrigin, ofRepoNamed: ScanCacheTests.brokenName)
        try Self.makeFirstCommit(inRepoAt: folder)
        try await recorder.waitForChange(.commits(inRepo: folder.canonicalPath)) {
            try await ScanCacheTests.hasBoard(of: folder.path, on: session)
        }
        let key = try CrossRepoFixture.keyText(of: Self.laterOrigin)
        #expect(try await CrossRepoReadTests.board("key", of: folder.path, on: session) == key)
        await host.close()
    }

    @Test("After the repo of a path ref is replaced in its changed parent folder, the next call reads git again")
    func replacedRepoIsReadAgain() async throws {
        let repo = try await PathRepo.make()
        let oldKey = try CrossRepoFixture.keyText(of: ScanCacheTests.newOrigin)
        #expect(try await CrossRepoReadTests.board("key", of: repo.folder.path, on: repo.session) == oldKey)
        let gitCalls = repo.reader.count
        let newKey = try await repo.replace()
        #expect(repo.reader.count > gitCalls)
        #expect(try await CrossRepoReadTests.board("key", of: repo.folder.path, on: repo.session) == newKey)
        await repo.host.close()
    }

    // MARK: - Helpers

    /// Writes the branch ref that the first commit of a repo writes, so that the file watcher sees new commits in the
    /// repo (``ScanChange/commits(inRepo:)``). The repo is a folder with an empty `.git` directory, so no git runs.
    ///
    /// - Parameter repo: The repo folder.
    /// - Throws: An error from `FileManager` when the ref cannot be written.
    static func makeFirstCommit(inRepoAt repo: URL) throws {
        let ref = firstBranchRef.reduce(repo.appending(path: BoardKey.gitDirectoryName)) { url, name in
            url.appending(path: name)
        }
        try FileManager.default.createDirectory(at: ref.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(firstCommitSHA.utf8).write(to: ref)
    }

    /// Replaces a repo folder with a new repo folder of the same name. The parent folder changes first, so that the file
    /// watcher of the parent folder sees a change of the parent folder itself (``ScanChange/place(_:)``) before each
    /// change of the repo folder.
    ///
    /// - Parameters:
    ///   - repo: The repo folder.
    ///   - staging: The folder that gets the old repo folder.
    /// - Throws: An error from `FileManager` when a folder cannot change.
    static func replaceRepo(at repo: URL, movingOldRepoInto staging: URL) throws {
        let parent = repo.deletingLastPathComponent()
        try FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: parent.path)
        try FileManager.default.moveItem(at: repo, to: staging.appending(path: repo.lastPathComponent))
        _ = try ScanPlace.makeRepoFolder(named: repo.lastPathComponent, in: parent)
    }
}
