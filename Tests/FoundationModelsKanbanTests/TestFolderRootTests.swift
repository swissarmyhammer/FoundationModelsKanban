import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests that the folders of the tests are in the run folder of ``TestFolderRoot``, and not in the temporary folder
/// of the user. FSEvents can give the events of a path in the temporary folder of the user very late (60 to 144 s in
/// a probe), and the events of a path in `/private/tmp` in a few seconds.
@Suite("Test folder root: the folders of the tests are in a run folder in /private/tmp")
struct TestFolderRootTests {
    /// The folder that holds `/tmp`, with a slash at the end. FSEvents gives the paths of `/tmp` in this folder.
    static let privateTemporaryPrefix = "/private/tmp/"

    /// The path of the temporary folder of the user as FSEvents gives it, with a slash at the end.
    static var userTemporaryPrefix: String {
        FolderStreams.eventPath(of: FileManager.default.temporaryDirectory) + "/"
    }

    /// Gives the path of the run folder with a slash at the end.
    ///
    /// - Returns: The path.
    /// - Throws: An error when the run folder cannot be made.
    static func runFolderPrefix() throws -> String {
        try TestFolderRoot.runFolder().path + "/"
    }

    @Test("FSEvents gives the run folder in /private/tmp, and not in the temporary folder of the user")
    func runFolderEventPathIsInPrivateTemporaryFolder() throws {
        let folder = try TestFolderRoot.runFolder()
        #expect(folder.path.hasPrefix(TestFolderRoot.basePath + "/"))
        let eventPath = FolderStreams.eventPath(of: folder)
        #expect(eventPath.hasPrefix(Self.privateTemporaryPrefix))
        #expect(!eventPath.hasPrefix(Self.userTemporaryPrefix))
    }

    @Test("The path of the run folder is its canonical path, the form of each path that the package gives")
    func runFolderPathIsCanonicalPath() throws {
        let folder = try TestFolderRoot.runFolder()
        #expect(folder.canonicalPath == folder.path)
    }

    @Test("A temporary directory is in the run folder")
    func temporaryDirectoryIsInRunFolder() throws {
        let directory = try TemporaryDirectory()
        #expect(directory.url.path.hasPrefix(try Self.runFolderPrefix()))
    }

    @Test("A git sandbox is in the run folder")
    func gitSandboxIsInRunFolder() throws {
        let sandbox = try GitSandbox()
        #expect(sandbox.root.path.hasPrefix(try Self.runFolderPrefix()))
    }
}
