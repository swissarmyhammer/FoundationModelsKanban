import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the apply of a stored body diff during replay (plan.md §5.5).
@Suite("Diff apply")
struct DiffApplyTests {
    /// The number of lines in ``base``. The two changes of a merge test are
    /// far apart in a text of this size, so their hunks do not touch.
    static let baseLineCount = 20

    /// The lines 1 to ``baseLineCount``, each with a final newline.
    static let base = (1...baseLineCount).map { "\($0)\n" }.joined()

    /// The line that the exact apply tests change, from 1.
    static let checkedLine = 15

    /// The conflict label that the tests give, in the place of an event id.
    static let label = "01K6Z4EVENT"

    /// Gives ``base`` with one line changed.
    ///
    /// - Parameters:
    ///   - line: The line to change, from 1.
    ///   - content: The new content of the line, without its newline.
    /// - Returns: The changed text.
    static func base(changing line: Int, to content: String) -> String {
        (1...baseLineCount).map { $0 == line ? "\(content)\n" : "\($0)\n" }.joined()
    }

    // MARK: - Exact and shifted apply

    @Test("A diff applies to the text that it was made from")
    func exactApply() {
        let new = Self.base(changing: 5, to: "five")
        let applied = UnifiedDiff(from: Self.base, to: new).applied(to: Self.base, withConflictLabel: Self.label)
        #expect(applied.text == new)
        #expect(!applied.hasConflict)
    }

    @Test("A diff with no hunks gives the same text")
    func emptyDiffKeepsTheText() {
        let applied = UnifiedDiff(from: Self.base, to: Self.base).applied(to: Self.base, withConflictLabel: Self.label)
        #expect(applied.text == Self.base)
        #expect(!applied.hasConflict)
    }

    @Test("A hunk applies at the nearest position where it matches after lines move")
    func shiftedApply() {
        let diff = UnifiedDiff(from: Self.base, to: Self.base(changing: 15, to: "fifteen"))
        let shifted = "new a\nnew b\n" + Self.base
        let applied = diff.applied(to: shifted, withConflictLabel: Self.label)
        #expect(applied.text == "new a\nnew b\n" + Self.base(changing: 15, to: "fifteen"))
        #expect(!applied.hasConflict)
    }

    @Test("A hunk applies when lines before it were removed")
    func shiftedApplyAfterRemoval() {
        let diff = UnifiedDiff(from: Self.base, to: Self.base(changing: 15, to: "fifteen"))
        let shorter = Self.base.replacingOccurrences(of: "\n2\n3\n", with: "\n")
        let applied = diff.applied(to: shorter, withConflictLabel: Self.label)
        #expect(applied.text == Self.base(changing: 15, to: "fifteen").replacingOccurrences(of: "\n2\n3\n", with: "\n"))
        #expect(!applied.hasConflict)
    }

    @Test("Of two positions that match, the nearest one gets the change")
    func nearestMatchWins() {
        let diff = UnifiedDiff(from: "a\nb\n", to: "a\nc\n")
        let current = "z\nz\na\nb\nz\nz\nz\nz\na\nb\n"
        let applied = diff.applied(to: current, withConflictLabel: Self.label)
        #expect(applied.text == "z\nz\na\nc\nz\nz\nz\nz\na\nb\n")
        #expect(!applied.hasConflict)
    }

    @Test("A diff from the empty text applies to the empty text")
    func diffFromEmptyText() {
        let applied = UnifiedDiff(from: "", to: "a\nb\n").applied(to: "", withConflictLabel: Self.label)
        #expect(applied.text == "a\nb\n")
        #expect(!applied.hasConflict)
    }

    // MARK: - Merge

    @Test("Two diffs from one base that change different lines both apply, in either order")
    func differentLinesMergeInEitherOrder() {
        let first = UnifiedDiff(from: Self.base, to: Self.base(changing: 2, to: "two"))
        let second = UnifiedDiff(from: Self.base, to: Self.base(changing: 18, to: "eighteen"))
        let firstThenSecond = second.applied(
            to: first.applied(to: Self.base, withConflictLabel: "A").text,
            withConflictLabel: "B"
        )
        let secondThenFirst = first.applied(
            to: second.applied(to: Self.base, withConflictLabel: "B").text,
            withConflictLabel: "A"
        )
        let both = Self.base(changing: 2, to: "two").replacingOccurrences(of: "\n18\n", with: "\neighteen\n")
        #expect(firstThenSecond.text == both)
        #expect(secondThenFirst.text == both)
        #expect(!firstThenSecond.hasConflict)
        #expect(!secondThenFirst.hasConflict)
    }

    // MARK: - Conflict

    @Test("Two diffs that change the same line give one conflict block with the event id")
    func sameLineGivesOneConflictBlock() {
        let first = UnifiedDiff(from: Self.base, to: Self.base(changing: 5, to: "five"))
        let second = UnifiedDiff(from: Self.base, to: Self.base(changing: 5, to: "FIVE"))
        let current = first.applied(to: Self.base, withConflictLabel: "A").text
        let applied = second.applied(to: current, withConflictLabel: Self.label)
        let block = "<<<<<<< current\n2\n3\n4\nfive\n6\n7\n8\n=======\n2\n3\n4\nFIVE\n6\n7\n8\n>>>>>>> \(Self.label)\n"
        #expect(applied.text == "1\n" + block + (9...Self.baseLineCount).map { "\($0)\n" }.joined())
        #expect(applied.text.components(separatedBy: "<<<<<<< current\n").count == 2)
        #expect(applied.hasConflict)
    }

    @Test("Each line of a conflict block ends with a newline, also at the end of a text with no final newline")
    func conflictBlockAtTheEndHasNewlines() {
        let diff = UnifiedDiff(from: "a", to: "b")
        let applied = diff.applied(to: "c", withConflictLabel: Self.label)
        #expect(applied.text == "<<<<<<< current\nc\n=======\nb\n>>>>>>> \(Self.label)\n")
        #expect(applied.hasConflict)
    }

    @Test("A hunk that cannot apply keeps the hunks after it")
    func laterHunksApplyAfterAConflict() {
        let diff = UnifiedDiff(from: Self.base, to: Self.base(changing: 2, to: "two").replacingOccurrences(
            of: "\n18\n",
            with: "\neighteen\n"
        ))
        #expect(diff.hunks.count == 2)
        let current = Self.base.replacingOccurrences(of: "\n2\n", with: "\nTWO\n")
        let applied = diff.applied(to: current, withConflictLabel: Self.label)
        #expect(applied.hasConflict)
        #expect(applied.text.contains("\neighteen\n"))
        #expect(!applied.text.contains("\n18\n"))
    }

    @Test("A body update that removes the block clears the conflict")
    func removingTheBlockClearsTheConflict() {
        let conflicted = UnifiedDiff(from: "a\n", to: "b\n").applied(to: "c\n", withConflictLabel: Self.label).text
        let resolved = UnifiedDiff(from: conflicted, to: "b\n").applied(to: conflicted, withConflictLabel: Self.label)
        #expect(resolved.text == "b\n")
        #expect(!resolved.hasConflict)
    }

    @Test("A text with only a part of a conflict block has no conflict")
    func partialBlockIsNoConflict() {
        let diff = UnifiedDiff(from: "", to: "<<<<<<< current\n=======\n")
        let applied = diff.applied(to: "", withConflictLabel: Self.label)
        #expect(!applied.hasConflict)
    }

    // MARK: - Exact apply check

    @Test("A diff applies exactly to a text where each hunk matches after lines move")
    func diffAppliesExactlyAfterShift() {
        let diff = UnifiedDiff(from: Self.base, to: Self.base(changing: Self.checkedLine, to: "changed"))
        #expect(diff.applies(exactlyTo: "new a\nnew b\n" + Self.base))
    }

    @Test("A diff applies exactly to a text that has a conflict block in a different place")
    func diffAppliesExactlyBesideConflictBlock() {
        let diff = UnifiedDiff(from: Self.base, to: Self.base(changing: Self.checkedLine, to: "changed"))
        let conflicted = UnifiedDiff(from: "a\n", to: "b\n").applied(to: "c\n", withConflictLabel: Self.label).text
        #expect(diff.applies(exactlyTo: conflicted + Self.base))
    }

    @Test("A diff does not apply exactly to a text where one hunk does not match")
    func diffWithUnmatchedHunkDoesNotApplyExactly() {
        let diff = UnifiedDiff(from: Self.base, to: Self.base(changing: Self.checkedLine, to: "changed"))
        #expect(!diff.applies(exactlyTo: Self.base(changing: Self.checkedLine, to: "changed later")))
    }

    // MARK: - Determinism

    @Test("The same inputs always give the same output, and a diff applies to its own base")
    func applyIsDeterministic() {
        var generator = SplitMix64(seed: RandomText.seed)
        for _ in 0..<RandomText.caseCount {
            let base = RandomText.make(using: &generator)
            let oursText = RandomText.make(using: &generator)
            let ours = UnifiedDiff(from: base, to: oursText)
            let theirs = UnifiedDiff(from: base, to: RandomText.make(using: &generator))
            let applied = ours.applied(to: base, withConflictLabel: "A")
            let merged = theirs.applied(to: applied.text, withConflictLabel: "B")
            let again = theirs.applied(to: ours.applied(to: base, withConflictLabel: "A").text, withConflictLabel: "B")
            let pair = Comment(rawValue: "base: \(base.debugDescription) ours: \(oursText.debugDescription)")
            #expect(applied == AppliedBody(text: oursText, hasConflict: false), pair)
            #expect(merged == again, pair)
        }
    }
}
