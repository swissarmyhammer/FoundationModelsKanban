import ULID

/// The abort record of one transaction: a line of a node log that makes replay skip each event of the transaction in
/// that file (plan.md §5.1, §5.4 step 5.5).
///
/// A commit whose append or signature read fails appends this record to each log file that it wrote. The file only
/// grows: the lines of the failed transaction stay, and the record follows them. In a line, the record is
/// `{"abort":"<txn ULID>"}`.
struct TransactionAbort: Codable, Hashable, Sendable {
    /// The keys of the record in a line.
    private enum CodingKeys: String, CodingKey {
        case txn = "abort"
    }

    /// The transaction ULID that the record aborts.
    let txn: ULID
}
