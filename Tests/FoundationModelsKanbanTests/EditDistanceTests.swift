import Testing

@testable import FoundationModelsKanban

/// Tests the edit distance of two texts: the least number of inserts, deletes, and substitutions of one character that
/// change one text to the other.
@Suite("Edit distance")
struct EditDistanceTests {
    /// Two texts, and the edit distance between them.
    struct Pair: Sendable, CustomTestStringConvertible {
        /// The first text.
        let source: String

        /// The second text.
        let target: String

        /// The edit distance between the two texts.
        let distance: Int

        /// The text of the pair in the test output.
        var testDescription: String {
            "\"\(source)\" to \"\(target)\""
        }
    }

    /// The pairs: equal texts, an empty text, one insert, one delete, one substitution, two characters in the wrong
    /// order, and the classic example of three edits.
    static let pairs = [
        Pair(source: "bug", target: "bug", distance: 0),
        Pair(source: "", target: "bug", distance: 3),
        Pair(source: "bug", target: "", distance: 3),
        Pair(source: "urgnt", target: "urgent", distance: 1),
        Pair(source: "urgent", target: "urgnt", distance: 1),
        Pair(source: "bug", target: "bag", distance: 1),
        Pair(source: "doign", target: "doing", distance: 2),
        Pair(source: "kitten", target: "sitting", distance: 3),
    ]

    @Test("The edit distance is the least number of one-character edits", arguments: pairs)
    func distanceOfPair(_ pair: Pair) {
        #expect(pair.source.editDistance(to: pair.target) == pair.distance)
    }
}
