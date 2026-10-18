import Foundation

/// The root folder of the folders that the tests make on the disk.
///
/// The folders are not in the temporary folder of the user (`/var/folders/…/T`). In a probe with no package code,
/// FSEvents gave the event of a write in that folder after 60 to 144 s, and the event of a write in `/private/tmp`
/// after 2.5 to 2.9 s. A test that waits for an FSEvents event has a time limit of 60 s (``FolderEventWait``), thus
/// the folders of the tests are in `/private/tmp`.
///
/// The path of each folder starts with `/tmp`, the symbolic link to `/private/tmp`. This is the form of
/// `URL.canonicalPath`, which the package uses for each path that it gives and compares: `resolvingSymlinksInPath()`
/// removes `/private` from a path that exists. Thus a path that a test expects agrees with a path that the package
/// gives. FSEvents gives `/private/tmp/…`, and the package matches that form to the watched folders, the same as
/// `/private/var/…` for `/var/…` before. With the real path `/private/tmp/…`, the package gives `/tmp/…` for some
/// paths and `/private/tmp/…` for others, and many tests fail on the path compare.
///
/// Each test process has one run folder, `<basePath>/<run id>`. Each test removes its own folder at the end. The run
/// folder is removed at the exit of the process when it is empty.
enum TestFolderRoot {
    /// The base folder of the run folders.
    static let basePath = "/tmp/fmk-tests"

    /// The run folder of this test process, or the error that stopped its make. The folder is made at the first use.
    private static let made = Result { try makeRunFolder() }

    /// Gives the run folder of this test process. Its path is its canonical path (`URL.canonicalPath`).
    ///
    /// - Returns: The run folder.
    /// - Throws: An error from `FileManager` when the folder cannot be made.
    static func runFolder() throws -> URL {
        try made.get()
    }

    /// Makes the run folder of this test process, and removes it at the exit of the process when it is empty.
    ///
    /// - Returns: The run folder.
    /// - Throws: An error from `FileManager` when the folder cannot be made.
    private static func makeRunFolder() throws -> URL {
        let runID = UUID().uuidString
        let folder = URL(filePath: basePath, directoryHint: .isDirectory).appending(
            path: runID,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        atexit { TestFolderRoot.removeRunFolderIfEmpty() }
        return folder
    }

    /// Gives the folder of a group in the run folder, and makes it when it does not exist.
    ///
    /// - Parameter group: The group.
    /// - Returns: The folder of the group.
    /// - Throws: An error from `FileManager` when a folder cannot be made.
    static func folder(of group: TestFolderGroup) throws -> URL {
        let folder = try runFolder().appending(path: group.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Removes each empty group folder, and then the run folder when it is empty. `rmdir(2)` removes no folder that
    /// holds an entry.
    private static func removeRunFolderIfEmpty() {
        guard case .success(let folder) = made else {
            return
        }
        for group in TestFolderGroup.allCases {
            rmdir(folder.appending(path: group.rawValue, directoryHint: .isDirectory).path)
        }
        rmdir(folder.path)
    }
}

/// A group of test folders in the run folder of ``TestFolderRoot``. The raw value is the name of the group folder.
///
/// The groups keep a parent scan small: a test that uses a ``TemporaryDirectory`` as a repo root makes the engine
/// scan the parent folder (plan.md §6.6), and the parent holds only the other temporary directories.
enum TestFolderGroup: String, CaseIterable {
    /// The folders of ``TemporaryDirectory``.
    case temporaryDirectories = "TemporaryDirectory"

    /// The folders of ``GitSandbox``.
    case gitSandboxes = "GitSandbox"
}
