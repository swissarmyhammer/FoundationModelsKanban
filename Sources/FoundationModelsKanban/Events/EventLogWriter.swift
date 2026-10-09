/// Appends events to the node logs of a board for the commit path (plan.md §5.4 step 5.3).
///
/// The commit appends through this seam, so that a test can give a writer that makes an append fail, and prove that
/// the commit then puts back each log file that it changed.
protocol EventLogWriter: Sendable {
    /// Appends events to the log file of one node of a board, one line for each event, in the order of the list.
    ///
    /// - Parameters:
    ///   - events: The events. Each event must change the node.
    ///   - ref: The local ref of the node.
    ///   - log: The event log of the board.
    /// - Throws: An ``EventLogError`` when an event cannot be a line, or a directory or a file cannot be written.
    func append(contentsOf events: [Event], toLogOf ref: LocalRef, in log: EventLog) throws(EventLogError)
}

/// The log writer of production: it appends with ``EventLog/append(contentsOf:toLogOf:)``.
struct FileEventLogWriter: EventLogWriter {
    /// Appends events to the log file of one node of a board.
    ///
    /// - Parameters:
    ///   - events: The events. Each event must change the node.
    ///   - ref: The local ref of the node.
    ///   - log: The event log of the board.
    /// - Throws: The error of ``EventLog/append(contentsOf:toLogOf:)``.
    func append(contentsOf events: [Event], toLogOf ref: LocalRef, in log: EventLog) throws(EventLogError) {
        try log.append(contentsOf: events, toLogOf: ref)
    }
}
