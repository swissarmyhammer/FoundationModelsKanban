import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the search for the board of a folder outside git (divergence.md M9) in a folder where no folder up to the
/// root of the file system has a `.kanban/`.
///
/// The folder is in the temporary folder of the user, which is not in a git repo. Its URL comes from
/// `FileManager.default.temporaryDirectory`. For a URL of that form, the parent of `file:///` is `file:///../`, so a
/// search up that does not standardize each parent does not stop at the root.
@Suite("Bare board: the search up for a .kanban/ stops at the root of the file system")
struct BareBoardTests {
    @Test("A folder with no .kanban/ up to the root has no board folder, and its board root is the folder itself")
    func folderWithNoBoardUpToRootIsItsOwnBoardRoot() throws {
        let directory = try TemporaryDirectory(in: FileManager.default.temporaryDirectory)
        #expect(BareBoard.nearestBoardFolder(from: directory.url, below: nil) == nil)
        #expect(BareBoard.root(of: directory.url) == directory.url)
    }

    @Test("A .kanban/ that the process cannot read is not a board folder, so the search goes on up")
    func unreadableBoardDirectoryIsSkipped() throws {
        let directory = try TemporaryDirectory(in: FileManager.default.temporaryDirectory)
        let outer = directory.url.appending(path: "outer", directoryHint: .isDirectory)
        let inner = outer.appending(path: "inner", directoryHint: .isDirectory)
        let unreadable = inner.appending(path: EventLog.directoryName, directoryHint: .isDirectory)
        let session = inner.appending(path: "session", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: outer.appending(path: EventLog.directoryName), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        // The App Sandbox refuses to read a folder that the user did not pick, for example the home folder. A folder
        // with no permissions gives the same refusal in a test.
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unreadable.path) }

        #expect(BareBoard.nearestBoardFolder(from: session, below: nil)?.standardizedFileURL == outer.standardizedFileURL)
    }
}
