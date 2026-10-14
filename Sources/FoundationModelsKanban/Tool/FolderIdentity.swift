import Foundation

/// The file identity of a folder: the device and the inode number of the folder (divergence.md §16).
///
/// The host keys each board by the identity of the folder that holds its `.kanban/` directory, not by the text of
/// its path. Thus a symbolic link, `/tmp` against `/private/tmp`, a `..` in the path, or a different letter case on
/// APFS gives the same identity, and so the same board.
///
/// The identities have a fixed sort order. A call that holds the gates of many boards takes them in this order, so
/// that two calls cannot wait for each other.
struct FolderIdentity: Hashable, Comparable, Sendable {
    /// The device of the folder.
    let device: UInt64

    /// The inode number of the folder on its device.
    let inode: UInt64

    /// Reads the identity of a folder. A symbolic link gives the identity of the folder that it points to.
    ///
    /// - Parameter folder: The folder.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the folder cannot be read.
    init(of folder: URL) throws(EventLogError) {
        var status = stat()
        guard stat(folder.path, &status) == 0 else {
            let detail = String(cString: strerror(errno))
            throw .fileSystem(path: folder.path, detail: detail)
        }
        device = UInt64(bitPattern: Int64(status.st_dev))
        inode = UInt64(status.st_ino)
    }

    /// Orders two identities: by device, and then by inode number.
    ///
    /// - Parameters:
    ///   - lhs: The first identity.
    ///   - rhs: The second identity.
    /// - Returns: `true` when `lhs` sorts before `rhs`.
    static func < (lhs: FolderIdentity, rhs: FolderIdentity) -> Bool {
        (lhs.device, lhs.inode) < (rhs.device, rhs.inode)
    }
}
