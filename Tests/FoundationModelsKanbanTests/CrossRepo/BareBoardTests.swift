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
}
