import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the unified diff that the log stores for a body (plan.md §5.5).
@Suite("Unified diff")
struct UnifiedDiffTests {
    /// The lines 1 to 10, each with a final newline.
    static let tenLines = (1...10).map { "\($0)\n" }.joined()

    /// The text of ``tenLines`` with line 5 changed to `five`.
    static let tenLinesWithFive = tenLines.replacingOccurrences(of: "5\n", with: "five\n")

    // MARK: - Make

    @Test("The same text gives a diff with no hunks and no text")
    func sameTextGivesAnEmptyDiff() {
        let diff = UnifiedDiff(from: "a\nb\n", to: "a\nb\n")
        #expect(diff.hunks.isEmpty)
        #expect(diff.text.isEmpty)
    }

    @Test("A diff from the empty text holds all lines of the new text as + lines")
    func diffFromEmptyTextAddsEachLine() {
        let diff = UnifiedDiff(from: "", to: "a\nb\nc\n")
        #expect(diff.text == "@@ -0,0 +1,3 @@\n+a\n+b\n+c\n")
    }

    @Test("A diff to the empty text holds all lines of the old text as - lines")
    func diffToEmptyTextRemovesEachLine() {
        let diff = UnifiedDiff(from: "a\nb\n", to: "")
        #expect(diff.text == "@@ -1,2 +0,0 @@\n-a\n-b\n")
    }

    @Test("A hunk has 3 lines of context on each side of a change")
    func hunkHasThreeContextLines() {
        let diff = UnifiedDiff(from: Self.tenLines, to: Self.tenLinesWithFive)
        #expect(diff.text == "@@ -2,7 +2,7 @@\n 2\n 3\n 4\n-5\n+five\n 6\n 7\n 8\n")
    }

    @Test("Two changes with more than 6 lines between them give two hunks")
    func distantChangesGiveTwoHunks() {
        let old = (1...20).map { "\($0)\n" }.joined()
        let new = old.replacingOccurrences(of: "\n2\n", with: "\ntwo\n")
            .replacingOccurrences(of: "\n19\n", with: "\nnineteen\n")
        let diff = UnifiedDiff(from: old, to: new)
        #expect(
            diff.text
                == "@@ -1,5 +1,5 @@\n 1\n-2\n+two\n 3\n 4\n 5\n"
                + "@@ -16,5 +16,5 @@\n 16\n 17\n 18\n-19\n+nineteen\n 20\n"
        )
    }

    @Test("Two changes with 6 lines between them give one hunk")
    func nearChangesGiveOneHunk() {
        let new = Self.tenLines.replacingOccurrences(of: "\n2\n", with: "\ntwo\n")
            .replacingOccurrences(of: "9\n", with: "nine\n")
        let diff = UnifiedDiff(from: Self.tenLines, to: new)
        #expect(diff.hunks.count == 1)
        #expect(diff.text.hasPrefix("@@ -1,10 +1,10 @@\n 1\n-2\n+two\n"))
    }

    @Test("A text with no final newline marks its last line as git does")
    func missingFinalNewlineIsMarked() {
        let diff = UnifiedDiff(from: "a\n", to: "a\nb")
        #expect(diff.text == "@@ -1,1 +1,2 @@\n a\n+b\n\\ No newline at end of file\n")
    }

    @Test("A change of only the final newline removes and adds the last line")
    func finalNewlineChangeIsALineChange() {
        let diff = UnifiedDiff(from: "a", to: "a\n")
        #expect(diff.text == "@@ -1,1 +1,1 @@\n-a\n\\ No newline at end of file\n+a\n")
    }

    @Test("A carriage return stays part of the line, as in git")
    func carriageReturnStaysInTheLine() {
        let diff = UnifiedDiff(from: "a\r\nb\r\n", to: "a\r\nc\r\n")
        #expect(diff.text == "@@ -1,2 +1,2 @@\n a\r\n-b\r\n+c\r\n")
    }

    @Test(
        "Text with and without a final newline round-trips",
        arguments: [("a\nb", "a\nc"), ("a\nb\n", "a\nc"), ("a\nb", "a\nc\n"), ("a\nb\n", "a\nc\n")]
    )
    func finalNewlineRoundTrips(old: String, new: String) throws {
        let diff = UnifiedDiff(from: old, to: new)
        #expect(try ExactApply.apply(diff, to: old) == new)
        #expect(try ExactApply.apply(diff.reversed(), to: new) == old)
        #expect(try UnifiedDiff(parsing: diff.text) == diff)
    }

    // MARK: - Reverse

    @Test("A reversed diff swaps the - and + lines and the header ranges")
    func reversedSwapsLinesAndRanges() {
        let diff = UnifiedDiff(from: "a\nb\nc\n", to: "a\nx\ny\nc\n").reversed()
        #expect(diff.text == "@@ -1,4 +1,3 @@\n a\n-x\n-y\n+b\n c\n")
    }

    @Test("A reversed diff is the diff that its reverse gives back")
    func reversingTwiceGivesTheSameDiff() {
        let diff = UnifiedDiff(from: Self.tenLines, to: Self.tenLinesWithFive)
        #expect(diff.reversed().reversed() == diff)
    }

    // MARK: - Parse

    @Test("The text of a diff parses back to the same hunks")
    func textParsesToTheSameHunks() throws {
        let diff = UnifiedDiff(from: Self.tenLines, to: Self.tenLinesWithFive)
        let parsed = try UnifiedDiff(parsing: diff.text)
        #expect(parsed == diff)
        #expect(parsed.hunks.first?.oldStart == 2)
        #expect(parsed.hunks.first?.oldCount == 7)
    }

    @Test("The empty text parses to a diff with no hunks")
    func emptyTextParsesToNoHunks() throws {
        #expect(try UnifiedDiff(parsing: "").hunks.isEmpty)
    }

    @Test("A header range with no count has a count of 1")
    func rangeWithNoCountHasCountOne() throws {
        let diff = try UnifiedDiff(parsing: "@@ -2 +2 @@\n-b\n+c\n")
        #expect(diff.hunks.first?.oldCount == 1)
        #expect(diff.hunks.first?.newCount == 1)
        #expect(diff.text == "@@ -2,1 +2,1 @@\n-b\n+c\n")
    }

    @Test("A line that is not a hunk header gives an error")
    func badHeaderThrows() {
        #expect(throws: UnifiedDiffError.malformedHeader("not a header")) {
            try UnifiedDiff(parsing: "not a header\n")
        }
    }

    @Test("A body line with an unknown marker gives an error")
    func badMarkerThrows() {
        #expect(throws: UnifiedDiffError.malformedLine("*a")) {
            try UnifiedDiff(parsing: "@@ -1,1 +1,1 @@\n*a\n")
        }
    }

    @Test("A hunk with fewer lines than its header gives an error")
    func shortHunkThrows() {
        #expect(throws: UnifiedDiffError.truncatedHunk("@@ -1,2 +1,2 @@")) {
            try UnifiedDiff(parsing: "@@ -1,2 +1,2 @@\n a\n")
        }
    }

    @Test("A hunk with more lines of one kind than its header gives an error")
    func overfullHunkThrows() {
        #expect(throws: UnifiedDiffError.countMismatch("@@ -1,1 +1,1 @@")) {
            try UnifiedDiff(parsing: "@@ -1,1 +1,1 @@\n-a\n-b\n+c\n")
        }
    }

    @Test("A no-newline marker with no line before it gives an error")
    func misplacedNoNewlineMarkerThrows() {
        #expect(throws: UnifiedDiffError.malformedHeader("\\ No newline at end of file")) {
            try UnifiedDiff(parsing: "\\ No newline at end of file\n")
        }
    }

    // MARK: - Properties

    @Test("Make, apply, reverse, and parse agree for random texts")
    func randomTextsRoundTrip() throws {
        var generator = SplitMix64(seed: RandomText.seed)
        for _ in 0..<RandomText.caseCount {
            let old = RandomText.make(using: &generator)
            let new = RandomText.make(using: &generator)
            let diff = UnifiedDiff(from: old, to: new)
            let pair = Comment(rawValue: "old: \(old.debugDescription) new: \(new.debugDescription)")
            #expect(try ExactApply.apply(diff, to: old) == new, pair)
            #expect(try ExactApply.apply(diff.reversed(), to: new) == old, pair)
            #expect(try UnifiedDiff(parsing: diff.text) == diff, pair)
            #expect(UnifiedDiff(from: old, to: new).text == diff.text, pair)
        }
    }
}

/// Applies a diff only at the exact line numbers of its hunks. This is the
/// simple apply that the tests use to check a diff. The replay apply, which
/// looks for the nearest match, is a different type.
enum ExactApply {
    /// Applies each hunk of a diff at its line number.
    ///
    /// - Parameters:
    ///   - diff: The diff to apply.
    ///   - text: The text that the diff was made from.
    /// - Returns: The text after the diff.
    /// - Throws: An `ExpectationFailedError` when the context and `-` lines of
    ///   a hunk do not match the text at the line number of the hunk.
    static func apply(_ diff: UnifiedDiff, to text: String) throws -> String {
        let lines = UnifiedDiff.TextLine.lines(in: text)
        let initial: (result: [UnifiedDiff.TextLine], cursor: Int) = ([], 0)
        let applied = try diff.hunks.reduce(into: initial) { state, hunk in
            let start = hunk.oldCount == 0 ? hunk.oldStart : hunk.oldStart - 1
            let end = start + hunk.oldCount
            try #require(state.cursor <= start && end <= lines.count)
            try #require(Array(lines[start..<end]) == hunk.oldLines)
            state.result += lines[state.cursor..<start] + hunk.newLines
            state.cursor = end
        }
        return UnifiedDiff.TextLine.text(joining: applied.result + lines[applied.cursor...])
    }
}

/// Makes random texts for the property test.
enum RandomText {
    /// The seed of the generator, so that each run tests the same texts.
    static let seed: UInt64 = 0x5EED_D1FF

    /// The number of random text pairs that the property test checks.
    static let caseCount = 500

    /// The largest number of lines in one random text.
    static let maximumLineCount = 12

    /// The lines that a random text holds. A small set makes many lines the
    /// same, so that the diffs have context lines and repeated lines.
    static let vocabulary = ["alpha", "beta", "gamma", "delta", ""]

    /// Makes one random text. The text has a final newline or not, at random.
    ///
    /// - Parameter generator: The source of random numbers.
    /// - Returns: The random text.
    static func make(using generator: inout SplitMix64) -> String {
        let count = Int.random(in: 0...maximumLineCount, using: &generator)
        let lines = (0..<count).map { _ in vocabulary.randomElement(using: &generator) ?? "" }
        let body = lines.joined(separator: "\n")
        return count == 0 || Bool.random(using: &generator) ? body : body + "\n"
    }
}

/// A small seeded random number generator, so that the property test is
/// deterministic. This is the SplitMix64 algorithm.
struct SplitMix64: RandomNumberGenerator {
    /// The step that the algorithm adds to the state for each value.
    private static let increment: UInt64 = 0x9E37_79B9_7F4A_7C15

    /// The first multiplier of the output mix.
    private static let firstMultiplier: UInt64 = 0xBF58_476D_1CE4_E5B9

    /// The second multiplier of the output mix.
    private static let secondMultiplier: UInt64 = 0x94D0_49BB_1331_11EB

    /// The first shift of the output mix.
    private static let firstShift: UInt64 = 30

    /// The second shift of the output mix.
    private static let secondShift: UInt64 = 27

    /// The third shift of the output mix.
    private static let thirdShift: UInt64 = 31

    /// The state of the generator.
    private var state: UInt64

    /// Makes a generator.
    ///
    /// - Parameter seed: The first state.
    init(seed: UInt64) {
        state = seed
    }

    /// Gives the next random value.
    ///
    /// - Returns: A random 64-bit value.
    mutating func next() -> UInt64 {
        state &+= Self.increment
        var value = state
        value = (value ^ (value >> Self.firstShift)) &* Self.firstMultiplier
        value = (value ^ (value >> Self.secondShift)) &* Self.secondMultiplier
        return value ^ (value >> Self.thirdShift)
    }
}
