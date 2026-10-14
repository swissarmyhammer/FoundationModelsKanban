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
/// the same sequence on each run. With the default sequence, the ULIDs of one source are in sort order. The last
/// bits of each ULID hold a different number, so each ULID has a different short id.
struct FixedULIDSource: ULIDSource {
    /// The time of each ULID of the source.
    let timestamp: Date

    /// The generator that gives the random part of each ULID.
    private var generator: SequenceNumberGenerator

    /// Makes a source whose ULIDs all have the time `timestamp`.
    ///
    /// - Parameters:
    ///   - timestamp: The time of each ULID.
    ///   - generator: The sequence that gives the random part of each ULID. The default sequence goes up, so each
    ///     ULID is greater than the ULID before it. ``SequenceNumberGenerator/descending`` makes each ULID smaller
    ///     than the ULID before it, as two random ids in one millisecond can be.
    init(at timestamp: Date, generator: SequenceNumberGenerator = SequenceNumberGenerator()) {
        self.timestamp = timestamp
        self.generator = generator
    }

    /// Makes the next ULID of the sequence.
    ///
    /// - Returns: A ULID with the fixed time and the next sequence numbers as its random part.
    mutating func makeULID() -> ULID {
        ULID(timestamp: timestamp, generator: &generator)
    }
}

/// A random number generator that gives a sequence of numbers with one fixed step: by default 0, 1, 2, and so on.
///
/// ``FixedULIDSource`` uses it so that the random part of each ULID is known before the test runs.
struct SequenceNumberGenerator: RandomNumberGenerator, Sendable {
    /// The step that, added with wrapping arithmetic, goes down by one: `UInt64.max` is -1 in two's complement.
    private static let stepDown = UInt64.max

    /// The sequence `UInt64.max`, `UInt64.max - 1`, and so on: each number is one smaller than the number before it.
    static let descending = SequenceNumberGenerator(startingAt: .max, step: stepDown)

    /// The number that the next call gives.
    private var nextNumber: UInt64

    /// The number that each call adds to ``nextNumber``, with wrapping arithmetic.
    private let step: UInt64

    /// Makes a sequence that starts at `first` and adds `step` for each number.
    ///
    /// - Parameters:
    ///   - first: The first number of the sequence.
    ///   - step: The number to add for each next number, with wrapping arithmetic.
    init(startingAt first: UInt64 = 0, step: UInt64 = 1) {
        nextNumber = first
        self.step = step
    }

    /// Gives the next number of the sequence.
    ///
    /// - Returns: The next number. The sequence wraps at the ends of `UInt64`.
    mutating func next() -> UInt64 {
        defer { nextNumber &+= step }
        return nextNumber
    }
}
