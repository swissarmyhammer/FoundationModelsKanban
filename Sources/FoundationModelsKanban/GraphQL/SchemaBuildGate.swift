import Synchronization

/// Runs the builds of the kanban GraphQL schemas one at a time.
///
/// GraphQL guards the properties of its types with process-wide concurrent dispatch queues, and a schema build reads
/// them with `sync` on the calling thread. When many builds run at the same time, a `sync` can wait for a drain of the
/// queue, and with a build blocked on each cooperative thread that drain did not come: `swift test` hung. One build at
/// a time leaves one builder on those queues, so its `sync` calls do not wait on each other.
///
/// A `Mutex` keeps the builds apart, and not an actor: a build and the initializers of the schemas are synchronous.
/// The lock guards no state. A build never waits on async work, so the wait of a caller ends when the builds before it
/// end.
enum SchemaBuildGate {
    /// The lock that a build holds while it runs.
    private static let lock = Mutex(())

    /// Runs one schema build while no other build runs.
    ///
    /// - Parameter make: Builds the schema. It must not start another build through the gate, because the lock is not
    ///   recursive.
    /// - Returns: The value that `make` gives.
    /// - Throws: The error of `make`.
    static func build<Built: Sendable>(_ make: () throws -> Built) throws -> Built {
        try lock.withLock { _ in try make() }
    }
}
