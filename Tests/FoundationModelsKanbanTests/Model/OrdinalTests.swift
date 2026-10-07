import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the ordinal: the fractional index that gives the order of a task in its column (plan.md §6).
///
/// The behavior cases are a port of the tests in the Rust file `swissarmyhammer-kanban/src/types/position.rs`. The
/// byte cases are a port of the tests of the Rust crate `fractional_index` 2.0.2, which the Rust file uses. Each byte
/// case is written as the hex text of the ordinal, with the terminator `80` at the end.
@Suite("Ordinals")
struct OrdinalTests {
    /// The number of ordinals that a repeated-step test makes, the same as in the Rust tests.
    static let repeatCount = 20

    /// The number of inserts at the same position that must keep a strict order.
    static let sameSpotInsertCount = 1000

    /// The seed of the generator of the random-insert test, so that each run tests the same inserts.
    static let randomSeed: UInt64 = 0x0D0D_1A15

    /// The number of random inserts that the property test makes.
    static let randomInsertCount = 2000

    /// Each ordinal text, with the text of the ordinal that `Ordinal(before:)` gives.
    static let beforeCases: [(String, String)] = [
        ("80", "7f80"),
        ("7f80", "7e80"),
        ("64640380", "6380"),
        ("6380", "6280"),
        ("000080", "00007f80"),
        ("00007f80", "00007e80"),
        ("0080", "007f80"),
    ]

    /// Each ordinal text, with the text of the ordinal that `Ordinal(after:)` gives.
    static let afterCases: [(String, String)] = [
        ("80", "8180"),
        ("8180", "8280"),
        ("f0f00380", "f180"),
        ("f180", "f280"),
        ("ffff80", "ffff8180"),
        ("ffff8180", "ffff8280"),
        ("ff80", "ff8180"),
    ]

    /// Each pair of ordinal texts in order, with the text of the ordinal that `Ordinal(between:and:)` gives.
    static let betweenCases: [(String, String, String)] = [
        ("6480", "7780", "6d80"),
        ("646480", "646880", "646680"),
        ("646480", "646780", "646580"),
        ("646480", "646680", "646580"),
        ("6c80", "6d80", "6c8180"),
        ("7f8080", "80", "7f8180"),
        ("7f8180", "80", "7f8280"),
        ("7f80", "80", "7f8180"),
        ("6480", "6580", "648180"),
        ("6480", "649080", "64907f80"),
        ("647a80", "6480", "647a8180"),
        ("647a80", "648080", "647d80"),
        ("80", "80c080", "8080"),
    ]

    /// Texts that are not a valid ordinal: empty, a legacy Rust ordinal, other text, no terminator at the end, an
    /// odd number of hex digits, uppercase hex digits, and characters that are not ASCII.
    static let invalidTexts = ["", "a0", "not-a-valid-ordinal", "81", "8", "808", "7F80", "ff8", "é80", "80 "]

    // MARK: - First

    @Test("The first ordinal is the default text 80")
    func firstIsDefault() {
        #expect(Ordinal.first.value == Ordinal.defaultText)
        #expect(Ordinal.defaultText == "80")
    }

    @Test("The description of an ordinal is its value")
    func descriptionIsValue() {
        #expect(Ordinal.first.description == Ordinal.first.value)
    }

    // MARK: - After and before

    @Test("An ordinal after an other sorts after it")
    func afterSortsAfter() {
        let first = Ordinal.first
        let second = Ordinal(after: first)
        let third = Ordinal(after: second)
        #expect(second > first)
        #expect(third > second)
        #expect(third > first)
    }

    @Test("An ordinal before an other sorts before it")
    func beforeSortsBefore() {
        #expect(Ordinal(before: Ordinal.first) < Ordinal.first)
    }

    @Test("Each repeated before sorts lower")
    func repeatedBeforeSortsLower() {
        var current = Ordinal.first
        for _ in 0..<Self.repeatCount {
            let previous = Ordinal(before: current)
            #expect(previous < current, "\(previous) must sort before \(current)")
            current = previous
        }
    }

    @Test("Each repeated after sorts higher")
    func repeatedAfterSortsHigher() {
        var current = Ordinal.first
        for _ in 0..<Self.repeatCount {
            let next = Ordinal(after: current)
            #expect(next > current, "\(next) must sort after \(current)")
            current = next
        }
    }

    @Test("Before gives the Figma algorithm text", arguments: beforeCases)
    func beforeGivesAlgorithmText(text: String, expected: String) throws {
        #expect(Ordinal(before: try Ordinal(parsing: text)).value == expected)
    }

    @Test("After gives the Figma algorithm text", arguments: afterCases)
    func afterGivesAlgorithmText(text: String, expected: String) throws {
        #expect(Ordinal(after: try Ordinal(parsing: text)).value == expected)
    }

    // MARK: - Between

    @Test("An ordinal between two others sorts between them")
    func betweenSortsBetween() {
        let first = Ordinal.first
        let third = Ordinal(after: Ordinal(after: first))
        let second = Ordinal(between: first, and: third)
        #expect(second > first)
        #expect(second < third)
    }

    @Test("An ordinal between two adjacent ordinals sorts between them")
    func betweenAdjacentSortsBetween() {
        let lower = Ordinal.first
        let upper = Ordinal(after: lower)
        let middle = Ordinal(between: lower, and: upper)
        #expect(middle > lower, "\(middle) must sort after \(lower)")
        #expect(middle < upper, "\(middle) must sort before \(upper)")
    }

    @Test("Each repeated between sorts between its bounds")
    func repeatedBetweenSortsBetween() {
        var lower = Ordinal.first
        let upper = Ordinal(after: Ordinal(after: lower))
        for _ in 0..<Self.repeatCount {
            let middle = Ordinal(between: lower, and: upper)
            #expect(middle > lower, "\(middle) must sort after \(lower)")
            #expect(middle < upper, "\(middle) must sort before \(upper)")
            lower = middle
        }
    }

    @Test("Between gives the Figma algorithm text", arguments: betweenCases)
    func betweenGivesAlgorithmText(lowerText: String, upperText: String, expected: String) throws {
        let lower = try Ordinal(parsing: lowerText)
        let upper = try Ordinal(parsing: upperText)
        let middle = Ordinal(between: lower, and: upper)
        #expect(middle.value == expected)
        #expect(lower < middle)
        #expect(middle < upper)
    }

    @Test("Between two equal ordinals sorts before the upper bound")
    func betweenEqualSortsBeforeUpper() {
        let lower = Ordinal.first
        let upper = Ordinal.first
        let result = Ordinal(between: lower, and: upper)
        #expect(result < upper, "between equal ordinals gave \(result), which does not sort before \(upper)")
        #expect(result == Ordinal(before: upper))
    }

    @Test("Between two ordinals in the wrong order sorts before the upper bound")
    func betweenMisorderedSortsBeforeUpper() {
        let lower = Ordinal(after: Ordinal.first)
        let upper = Ordinal.first
        let result = Ordinal(between: lower, and: upper)
        #expect(result < upper)
        #expect(result == Ordinal(before: upper))
    }

    @Test("A thousand inserts at the same position keep a strict order")
    func sameSpotInsertsKeepStrictOrder() {
        let bounds = [Ordinal.first, Ordinal(after: Ordinal.first)]
        var ordinals = bounds
        for _ in 0..<Self.sameSpotInsertCount {
            ordinals.insert(Ordinal(between: ordinals[0], and: ordinals[1]), at: 1)
        }
        #expect(ordinals.count == bounds.count + Self.sameSpotInsertCount)
        #expect(ordinals.isStrictlyAscending)
    }

    @Test("Random inserts keep a strict order")
    func randomInsertsKeepStrictOrder() throws {
        var generator = SplitMix64(seed: Self.randomSeed)
        var ordinals = [Ordinal.first]
        for _ in 0..<Self.randomInsertCount {
            let index = Int.random(in: 0...ordinals.count, using: &generator)
            let inserted = Self.ordinal(forInsertAt: index, into: ordinals)
            ordinals.insert(inserted, at: index)
            #expect(try Ordinal(parsing: inserted.value) == inserted)
        }
        #expect(ordinals.isStrictlyAscending)
        #expect(ordinals.map(\.value).sorted() == ordinals.map(\.value))
    }

    // MARK: - Order

    @Test("Ordinals compare in the order they were made")
    func orderFollowsSteps() {
        let first = Ordinal.first
        let second = Ordinal(after: first)
        let third = Ordinal(after: second)
        #expect(first < second)
        #expect(second < third)
        #expect(first < third)
    }

    // MARK: - Parse

    @Test("The default text is a valid ordinal")
    func defaultTextIsValid() throws {
        #expect(try Ordinal(parsing: Ordinal.defaultText) == Ordinal.first)
    }

    @Test("The text of an ordinal parses to the same ordinal")
    func textRoundTrips() throws {
        let ordinals = [Ordinal.first, Ordinal(after: Ordinal.first), Ordinal(before: Ordinal.first)]
        for ordinal in ordinals {
            let parsed = try Ordinal(parsing: ordinal.value)
            #expect(parsed == ordinal)
            #expect(parsed.value == ordinal.value)
        }
    }

    @Test("A text that is not a fractional index gives INVALID_ORDINAL", arguments: invalidTexts)
    func invalidTextIsRefused(text: String) {
        #expect(throws: KanbanError.invalidOrdinal(ordinal: text)) {
            try Ordinal(parsing: text)
        }
        #expect(KanbanError.invalidOrdinal(ordinal: text).code == "INVALID_ORDINAL")
    }

    // MARK: - Helpers

    /// Makes the ordinal for an insert into an ordered list, as a move with `before` or `after` a neighbor does.
    ///
    /// - Parameters:
    ///   - index: The position of the insert, from 0 to the count of the list.
    ///   - ordinals: The ordered list, which must not be empty.
    /// - Returns: An ordinal that sorts between the neighbors at the position.
    static func ordinal(forInsertAt index: Int, into ordinals: [Ordinal]) -> Ordinal {
        if index == 0 {
            return Ordinal(before: ordinals[index])
        }
        if index == ordinals.count {
            return Ordinal(after: ordinals[index - 1])
        }
        let inserted = Ordinal(between: ordinals[index - 1], and: ordinals[index])
        #expect(ordinals[index - 1] < inserted)
        #expect(inserted < ordinals[index])
        return inserted
    }
}

extension [Ordinal] {
    /// `true` when each ordinal of the list sorts strictly before the next ordinal.
    fileprivate var isStrictlyAscending: Bool {
        zip(self, dropFirst()).allSatisfy { $0 < $1 }
    }
}
