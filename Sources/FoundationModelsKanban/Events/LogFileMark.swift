import Foundation

/// The state of one log file before a commit appends to it: its size and its modification time, or no file (plan.md
/// §5.4 step 5.5).
///
/// A commit whose append fails puts each file that it changed back to its mark, while it holds the locks. Thus no file
/// keeps a part of the transaction. The size and the modification time come back exactly, so the signature of each
/// file (plan.md §5.6) is the same as before the commit, and the next commit check finds no change.
struct LogFileMark {
    /// The state of a file that is there.
    fileprivate struct FileState {
        /// The size of the file, in bytes.
        let size: off_t

        /// The modification time of the file, with the nanoseconds of the file system.
        let modified: timespec
    }

    /// The log file.
    let file: URL

    /// The state of the file, or `nil` when the file was not there.
    fileprivate let state: FileState?

    /// Puts the file back to its mark. A file that was not there is removed. Else the file is cut back to its size,
    /// and it gets its modification time back.
    ///
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the file cannot be removed, cut, or touched.
    func restore() throws(EventLogError) {
        guard let state else {
            guard unlink(file.path) == .zero || errno == ENOENT else {
                throw Self.lastError(at: file)
            }
            return
        }
        guard truncate(file.path, state.size) == .zero else {
            throw Self.lastError(at: file)
        }
        let keepAccessTime = timespec(tv_sec: .zero, tv_nsec: Int(UTIME_OMIT))
        guard utimensat(AT_FDCWD, file.path, [keepAccessTime, state.modified], .zero) == .zero else {
            throw Self.lastError(at: file)
        }
    }

    /// Gives the error of the last failed system call on a file.
    ///
    /// - Parameter file: The file of the call.
    /// - Returns: ``EventLogError/fileSystem(path:detail:)`` with the text of `errno`.
    fileprivate static func lastError(at file: URL) -> EventLogError {
        .fileSystem(path: file.path, detail: String(cString: strerror(errno)))
    }
}

extension EventLog {
    /// Records the state of the log file of one node before an append (plan.md §5.4 step 5.5).
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The mark of the file. The file does not have to exist.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the file is there and its state cannot be read.
    func mark(ofLogOf ref: LocalRef) throws(EventLogError) -> LogFileMark {
        let file = fileURL(for: ref)
        var info = stat()
        guard stat(file.path, &info) == .zero else {
            guard errno == ENOENT else {
                throw LogFileMark.lastError(at: file)
            }
            return LogFileMark(file: file, state: nil)
        }
        return LogFileMark(file: file, state: LogFileMark.FileState(size: info.st_size, modified: info.st_mtimespec))
    }
}
