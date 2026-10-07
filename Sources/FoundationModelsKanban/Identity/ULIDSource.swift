import Foundation
import ULID

/// A source of new ULIDs.
///
/// Each new task, comment, event and transaction gets a ULID from a source (plan.md §3.2, §5.1). Production code
/// uses ``SystemULIDSource``. Tests use ``FixedULIDSource``, so that the ids and the event output are the same on
/// each run (plan.md §11).
protocol ULIDSource: Sendable {
    /// Makes the next ULID of the source.
    ///
    /// - Returns: A new ULID.
    mutating func makeULID() -> ULID
}

/// The ULID source of production: the system clock and the system random number generator.
struct SystemULIDSource: ULIDSource {
    /// Makes a ULID with the current time and random bits.
    ///
    /// - Returns: A new ULID.
    func makeULID() -> ULID {
        ULID()
    }
}

/// A ULID source for tests: a fixed clock and a sequence number in place of the random bits.
///
/// Each ULID has the fixed time. The random part comes from ``SequenceNumberGenerator``, so the same source gives
/// the same sequence on each run. The ULIDs of one source are in sort order, and the last bits of each ULID hold a
/// different number, so each ULID has a different short id.
struct FixedULIDSource: ULIDSource {
    /// The time of each ULID of the source.
    let timestamp: Date

    /// The generator that gives the random part of each ULID.
    private var generator = SequenceNumberGenerator()

    /// Makes a source whose ULIDs all have the time `timestamp`.
    ///
    /// - Parameter timestamp: The time of each ULID.
    init(at timestamp: Date) {
        self.timestamp = timestamp
    }

    /// Makes the next ULID of the sequence.
    ///
    /// - Returns: A ULID with the fixed time and the next sequence numbers as its random part.
    mutating func makeULID() -> ULID {
        ULID(timestamp: timestamp, generator: &generator)
    }
}

/// A random number generator that gives 0, 1, 2, and so on, in sequence.
///
/// ``FixedULIDSource`` uses it so that the random part of each ULID is known before the test runs.
struct SequenceNumberGenerator: RandomNumberGenerator, Sendable {
    /// The number that the next call gives.
    private var nextNumber: UInt64 = 0

    /// Gives the next number of the sequence.
    ///
    /// - Returns: The next number. After `UInt64.max`, the sequence starts again at 0.
    mutating func next() -> UInt64 {
        defer { nextNumber &+= 1 }
        return nextNumber
    }
}
