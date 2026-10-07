import Foundation

// MARK: - Lock

extension EventLog {
    /// The permissions of a new lock file: the owner reads and writes, and all others read.
    static let lockFileMode: mode_t = 0o644

    /// Gets the exclusive write lock of the board: a `flock` on `.kanban/.lock`. The call waits while a different
    /// process or a different lock of this process holds the lock.
    ///
    /// The call makes the directory of the board, its git files, and the lock file when they are not there.
    ///
    /// - Returns: The lock. Release it with ``BoardLock/unlock()``.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the directory cannot be made.
    ///   ``EventLogError/lockFailed(path:code:)`` when the lock file cannot be opened or locked.
    func lock() throws(EventLogError) -> BoardLock {
        BoardLock(files: [try LockedFile(of: self)])
    }

    /// Gets the write locks of many boards, in the sort order of the board key. Each caller that locks more than one
    /// board uses this order, so that two callers cannot deadlock (plan.md §5.4 step 5).
    ///
    /// - Parameter logs: The event log of each board, by board key.
    /// - Returns: One lock that holds the locks of all the boards. When a lock fails, the locks that the call got
    ///   are released.
    /// - Throws: The error of ``lock()`` for the first board that cannot be locked.
    static func lock(sortedByKey logs: [BoardKey: EventLog]) throws(EventLogError) -> BoardLock {
        BoardLock(files: try lockOrder(of: logs).map { log throws(EventLogError) in try LockedFile(of: log) })
    }

    /// Gives the event logs of many boards in the order of the lock: the sort order of the board key text.
    ///
    /// - Parameter logs: The event log of each board, by board key.
    /// - Returns: The event logs, in lock order.
    static func lockOrder(of logs: [BoardKey: EventLog]) -> [EventLog] {
        logs.sorted { lhs, rhs in lhs.key.description < rhs.key.description }.map(\.value)
    }
}

/// The write locks of one or more boards (plan.md §5.4 step 5).
///
/// The value is not copyable, so it has one owner. The locks are released when the value ends: with
/// ``unlock()``, or when the owner goes out of scope.
struct BoardLock: ~Copyable, Sendable {
    /// The locked lock file of each board. The value keeps the files open, so that their locks stay held. No code
    /// reads the list: the end of the value releases it.
    // periphery:ignore
    fileprivate let files: [LockedFile]

    /// Releases the lock of each board. The end of the consumed value closes each lock file, and the close releases
    /// its `flock`.
    consuming func unlock() {}
}

/// One open lock file that holds an exclusive `flock`. The close of the file releases the lock.
///
/// The type is a class, because its `deinit` closes the file. A lock of many boards keeps one value for each board,
/// so that a failure after some locks releases the locks that were already held.
private final class LockedFile: Sendable {
    /// The file descriptor of the open lock file.
    let descriptor: Int32

    /// Opens the lock file of a board, and waits for its exclusive lock.
    ///
    /// - Parameter log: The event log of the board.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the directory cannot be made.
    ///   ``EventLogError/lockFailed(path:code:)`` when the file cannot be opened or locked.
    init(of log: EventLog) throws(EventLogError) {
        try log.prepareDirectory()
        let path = log.lockFileURL.path
        let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, EventLog.lockFileMode)
        guard descriptor >= 0 else {
            throw .lockFailed(path: path, code: errno)
        }
        let code = Self.waitForLock(on: descriptor)
        guard code == 0 else {
            close(descriptor)
            throw .lockFailed(path: path, code: code)
        }
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }

    /// Waits for the exclusive lock of an open file. A wait that a signal stops starts again.
    ///
    /// - Parameter descriptor: The file descriptor.
    /// - Returns: `0` when the lock is held, or the `errno` of the failure.
    private static func waitForLock(on descriptor: Int32) -> Int32 {
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else {
                return errno
            }
        }
        return 0
    }
}
