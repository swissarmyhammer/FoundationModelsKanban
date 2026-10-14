import Testing

@testable import FoundationModelsKanban

/// Tests the Markdown rule that the body markers share: the parts of a line that are not in inline code
/// (plan.md §6.1).
@Suite("Markdown code")
struct MarkdownCodeTests {
    /// Each line with the text of each part that is not in inline code, in text order.
    static let proseCases: [(String, [String])] = [
        ("no code here", ["no code here"]),
        ("a `b` c", ["a ", " c"]),
        ("`b` c", ["", " c"]),
        ("a `b`", ["a "]),
        ("a `b` c `d` e", ["a ", " c ", " e"]),
        // A span that does not close goes to the end of the line.
        ("a `b c", ["a "]),
        ("", []),
    ]

    @Test("The prose ranges of a line leave out each inline code span", arguments: proseCases)
    func proseRangesLeaveOutInlineCode(line: String, expected: [String]) {
        let text = Substring(line)
        let parts = MarkdownCode.proseRanges(inLine: text).map { range in String(text.unicodeScalars[range]) }
        #expect(parts == expected)
    }
}
