import Foundation

// MARK: - Lock

extension EventLog {
    /// The permissions of a new lock file: the owner reads and writes, and all others read.
    static let lockFileMode: mode_t = 0o644

    /// Gets the exclusive write lock of the board: a `flock` on `.kanban/.lock`. The call waits while a different
    /// process or a different lock of this process holds the lock. The wait has no time limit (divergence.md Q24).
    ///
    /// The wait blocks no thread of the Swift cooperative pool: a busy lock is waited for on a thread of its own. A
    /// cancel of the task does not stop the wait. The call always returns the lock to the caller, or releases what it
    /// opened, so a cancel cannot leak the lock or the thread.
    ///
    /// The call makes the directory of the board, its git files, and the lock file when they are not there.
    ///
    /// - Returns: The lock. Release it with ``BoardLock/unlock()``.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the directory cannot be made.
    ///   ``EventLogError/lockFailed(path:code:)`` when the lock file cannot be opened or locked.
    func lock() async throws(EventLogError) -> BoardLock {
        BoardLock(files: [try await LockedFile.lock(of: self)])
    }

    /// Gets the write locks of many boards, in the sort order of the board key. Each caller that locks more than one
    /// board uses this order, so that two callers cannot deadlock (plan.md §5.4 step 5).
    ///
    /// - Parameter logs: The event log of each board, with its board key. Two copies of one repo have the same key,
    ///   and each copy gets its own lock.
    /// - Returns: One lock that holds the locks of all the boards. When a lock fails, the locks that the call got
    ///   are released.
    /// - Throws: The error of ``lock()`` for the first board that cannot be locked.
    static func lock(
        sortedByKey logs: some Sequence<(key: BoardKey, value: EventLog)>
    ) async throws(EventLogError) -> BoardLock {
        var files: [LockedFile] = []
        for log in lockOrder(of: logs) {
            files.append(try await LockedFile.lock(of: log))
        }
        return BoardLock(files: files)
    }

    /// Gives the event logs of many boards in the order of the lock: the sort order of the board key text, and then
    /// the sort order of the path of the board directory for two copies with the same key.
    ///
    /// - Parameter logs: The event log of each board, with its board key.
    /// - Returns: The event logs, in lock order.
    static func lockOrder(of logs: some Sequence<(key: BoardKey, value: EventLog)>) -> [EventLog] {
        logs.sorted { lhs, rhs in
            (lhs.key.description, lhs.value.directory.path) < (rhs.key.description, rhs.value.directory.path)
        }
        .map(\.value)
    }

    /// Opens the lock file of the board, and makes the file when it is not there. The call does not lock the file and
    /// does not make the directory of the board: ``lock()`` makes the directory first. Each open of the lock file uses
    /// this call, so that each open uses the same flags and the same file mode.
    ///
    /// - Returns: The file descriptor of the open lock file. The caller owns it and closes it.
    /// - Throws: ``EventLogError/lockFailed(path:code:)`` when the file cannot be opened.
    func openLockFile() throws(EventLogError) -> Int32 {
        let path = lockFileURL.path
        let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, Self.lockFileMode)
        guard descriptor >= 0 else {
            throw .lockFailed(path: path, code: errno)
        }
        return descriptor
    }

    /// Tries to get the exclusive lock of an open lock file, with no wait. Each lock try uses this call, so that each
    /// try uses the same lock mode.
    ///
    /// - Parameter descriptor: The file descriptor of the open lock file.
    /// - Returns: `0` when the lock is held, `EWOULDBLOCK` when a different lock holds it, or the `errno` of a
    ///   different failure.
    static func tryLock(on descriptor: Int32) -> Int32 {
        callFlock(on: descriptor, operation: LOCK_EX | LOCK_NB)
    }

    /// Calls `flock` on an open file. A call that a signal stops starts again.
    ///
    /// - Parameters:
    ///   - descriptor: The file descriptor.
    ///   - operation: The `flock` operation, for example `LOCK_EX`.
    /// - Returns: `0` when the call succeeds, or the `errno` of the failure.
    fileprivate static func callFlock(on descriptor: Int32, operation: Int32) -> Int32 {
        while flock(descriptor, operation) != 0 {
            guard errno == EINTR else {
                return errno
            }
        }
        return 0
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

    /// Keeps an open file descriptor that holds its exclusive lock.
    ///
    /// - Parameter descriptor: The file descriptor. The new value owns it and closes it.
    private init(holding descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }

    /// Opens the lock file of a board, and waits for its exclusive lock.
    ///
    /// - Parameter log: The event log of the board.
    /// - Returns: The open lock file, which holds the lock.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the directory cannot be made.
    ///   ``EventLogError/lockFailed(path:code:)`` when the file cannot be opened or locked.
    static func lock(of log: EventLog) async throws(EventLogError) -> LockedFile {
        try log.prepareDirectory()
        let descriptor = try log.openLockFile()
        let code = await waitForLock(on: descriptor)
        guard code == 0 else {
            close(descriptor)
            throw .lockFailed(path: log.lockFileURL.path, code: code)
        }
        return LockedFile(holding: descriptor)
    }

    /// Waits for the exclusive lock of an open file, and blocks no thread of the Swift cooperative pool.
    ///
    /// The call first tries the lock with no wait. When a different lock holds it, a new thread of its own waits with
    /// a blocking `flock`, and its end resumes the caller. The thread always resumes the caller with its result, also
    /// when the task is cancelled, so the caller always gets the lock that the thread got.
    ///
    /// - Parameter descriptor: The file descriptor.
    /// - Returns: `0` when the lock is held, or the `errno` of the failure.
    private static func waitForLock(on descriptor: Int32) async -> Int32 {
        let code = EventLog.tryLock(on: descriptor)
        guard code == EWOULDBLOCK else {
            return code
        }
        return await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(returning: EventLog.callFlock(on: descriptor, operation: LOCK_EX))
            }
        }
    }
}
