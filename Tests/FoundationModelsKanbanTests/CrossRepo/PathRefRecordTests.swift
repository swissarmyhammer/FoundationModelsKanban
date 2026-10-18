import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests that the record of a folder that a path ref named compares the files of a change with the files of its
/// watched repo (divergence.md §16, Gap 1).
///
/// FSEvents gives an event id when fseventsd reads the change from the kernel, not when the change occurs. Thus the
/// file watcher of the parent folder of the watched repo can give a change that occurred before the record. Such a
/// change must not make the record out of date. Each test makes a real repo folder in a ``TemporaryDirectory`` and
/// gives the change to the record directly, so no test needs a file watcher.
@Suite("Path ref record: a change of files that the record already saw keeps the record")
struct PathRefRecordTests {
    /// The name of the repo folder of each test.
    static let repoName = "repo"

    /// The `origin` that a test writes into the git config of the repo.
    static let changedOrigin = "https://github.com/example/changed.git"

    @Test("A repo change of the watched repo whose files did not change keeps the record")
    func unchangedRepoKeepsRecord() throws {
        let directory = try TemporaryDirectory()
        let repo = try ScanPlace.makeRepoFolder(named: Self.repoName, in: directory.url)
        let record = Self.record(of: .unreadableKey(top: repo), ofFolderAt: repo)
        #expect(!record.isExpired(by: .repo(repo.canonicalPath)))
    }

    @Test("A repo change after a write of the git config of the watched repo expires the record")
    func changedConfigExpiresRecord() throws {
        let directory = try TemporaryDirectory()
        let repo = try ScanPlace.makeRepoFolder(named: Self.repoName, in: directory.url)
        let record = Self.record(of: .unreadableKey(top: repo), ofFolderAt: repo)
        try ScanCacheTests.writeOrigin(Self.changedOrigin, intoConfigOfRepoAt: repo)
        #expect(record.isExpired(by: .repo(repo.canonicalPath)))
    }

    @Test("A commits change after the first commit in a repo whose key read failed expires the record")
    func firstCommitExpiresRecord() throws {
        let directory = try TemporaryDirectory()
        let repo = try ScanPlace.makeRepoFolder(named: Self.repoName, in: directory.url)
        let record = Self.record(of: .unreadableKey(top: repo), ofFolderAt: repo)
        try PathRefCacheTests.makeFirstCommit(inRepoAt: repo)
        #expect(record.isExpired(by: .commits(inRepo: repo.canonicalPath)))
    }

    @Test("A place change of the parent folder whose watched repo did not change keeps the record")
    func unchangedPlaceKeepsRecord() throws {
        let directory = try TemporaryDirectory()
        let repo = try ScanPlace.makeRepoFolder(named: Self.repoName, in: directory.url)
        let record = Self.record(of: .unreadableKey(top: repo), ofFolderAt: repo)
        #expect(!record.isExpired(by: .place(directory.url.canonicalPath)))
    }

    @Test("A place change after a new board log in the watched repo keeps the record, the same as a board change")
    func newBoardLogKeepsRecordAtPlaceChange() throws {
        let directory = try TemporaryDirectory()
        let repo = try ScanPlace.makeRepoFolder(named: Self.repoName, in: directory.url)
        let record = Self.record(of: .unreadableKey(top: repo), ofFolderAt: repo)
        _ = try KanbanGraphTests.writeFixture(inRepoAt: repo)
        #expect(!record.isExpired(by: .place(directory.url.canonicalPath)))
    }

    @Test("A place change after the first commit in a repo whose key git read keeps the record, as a commits change")
    func firstCommitOfReadableKeyKeepsRecordAtPlaceChange() throws {
        let directory = try TemporaryDirectory()
        let repo = try ScanPlace.makeRepoFolder(named: Self.repoName, in: directory.url)
        let record = try Self.readableRecord(ofRepo: repo)
        try PathRefCacheTests.makeFirstCommit(inRepoAt: repo)
        #expect(!record.isExpired(by: .place(directory.url.canonicalPath)))
    }

    @Test("A place change after a write of the git config of the watched repo expires the record, as a repo change")
    func changedConfigExpiresRecordAtPlaceChange() throws {
        let directory = try TemporaryDirectory()
        let repo = try ScanPlace.makeRepoFolder(named: Self.repoName, in: directory.url)
        let record = try Self.readableRecord(ofRepo: repo)
        try ScanCacheTests.writeOrigin(Self.changedOrigin, intoConfigOfRepoAt: repo)
        #expect(record.isExpired(by: .place(directory.url.canonicalPath)))
    }

    @Test("A git init in a folder that was not a repo expires the record with a repo change")
    func gitInitExpiresRecord() throws {
        let directory = try TemporaryDirectory()
        let folder = try GitSandbox.makeFolder(named: Self.repoName, in: directory.url)
        let record = Self.record(of: .notARepo(path: folder.path), ofFolderAt: folder)
        _ = try GitSandbox.makeFolder(named: BoardKey.gitDirectoryName, in: folder)
        #expect(record.isExpired(by: .repo(folder.canonicalPath)))
    }

    // MARK: - Helpers

    /// Makes the record of a folder, with the mark of the folder read now, the same as the host reads it before the
    /// read of git.
    ///
    /// - Parameters:
    ///   - board: What git told about the folder.
    ///   - folder: The folder that the path ref named.
    /// - Returns: The record.
    static func record(of board: FolderBoard, ofFolderAt folder: URL) -> PathRefRecord {
        PathRefRecord(board: board, ofFolderAt: folder, folderMark: RepoMark(ofRepoAt: folder))
    }

    /// Makes the record of a repo folder whose key git read: the board of the repo with the key of
    /// ``ScanCacheTests/libOrigin``.
    ///
    /// - Parameter repo: The repo folder that the path ref named.
    /// - Returns: The record.
    /// - Throws: An error when the key cannot be made from the `origin`.
    static func readableRecord(ofRepo repo: URL) throws -> PathRefRecord {
        let key = try BoardKey(remoteURL: ScanCacheTests.libOrigin)
        return record(of: .board(BoardCopy(directory: repo, key: key)), ofFolderAt: repo)
    }
}
