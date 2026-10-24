import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests that ``Foundation/URL/canonicalPath`` gives one path for one folder, also after the folder is removed.
///
/// The package uses the canonical path as the key of each board. The root of a board comes from git, which gives
/// the real path, for example `/private/tmp/…`. When the canonical path of that root changes while a change round
/// reads it two times, the keys of the round do not agree, and the round stops the debug build.
@Suite("Canonical path: one folder gives one path, also after the folder is removed")
struct CanonicalPathTests {
    /// The name of the folder in the temporary directory.
    static let folderName = "my-project"

    @Test("The canonical path of the real path of a folder stays the same after the folder is removed")
    func realPathKeepsCanonicalPathAfterRemoval() throws {
        let directory = try TemporaryDirectory()
        let folder = try GitSandbox.makeFolder(named: Self.folderName, in: directory.url)
        let realFolder = URL(filePath: FolderStreams.eventPath(of: folder), directoryHint: .isDirectory)
        #expect(realFolder.canonicalPath == folder.path)
        try FileManager.default.removeItem(at: folder)
        #expect(realFolder.canonicalPath == folder.path)
    }
}
