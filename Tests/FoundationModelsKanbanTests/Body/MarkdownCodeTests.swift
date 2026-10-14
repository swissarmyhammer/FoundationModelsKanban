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
        // A span closes only at a backtick run of the same length as the run that opens it.
        ("a ``b ` c`` d", ["a ", " d"]),
        ("a ``b``` c`` d", ["a ", " d"]),
        ("a ```b`` c``` d `e` f", ["a ", " d ", " f"]),
        ("a ``b ` c", ["a "]),
    ]

    /// Each body with the flag of each line that tells if a marker on the line can count.
    static let fenceCases: [(String, [Bool])] = [
        ("a\n```\nb\n```\nc", [true, false, false, false, true]),
        ("a\n~~~\nb\n~~~\nc", [true, false, false, false, true]),
        // A fence closes only on a fence line with the same marker as the fence line that opens it.
        ("```\n~~~\nb\n```\nc", [false, false, false, false, true]),
        ("~~~\n```\nb\n~~~\nc", [false, false, false, false, true]),
        // A fence closes only on a run that is not shorter than the run that opens it.
        ("````\n```\nb\n````\nc", [false, false, false, false, true]),
        ("```\n`````\nc", [false, false, true]),
        // A fence line with an info string opens a fence, but does not close one.
        ("```swift\n```swift\nb\n```\nc", [false, false, false, false, true]),
        ("```\nb\n```  \nc", [false, false, false, true]),
        // A backtick run with a backtick in its info string does not open a fence.
        ("```a`b\nc", [true, true]),
    ]

    @Test("The prose ranges of a line leave out each inline code span", arguments: proseCases)
    func proseRangesLeaveOutInlineCode(line: String, expected: [String]) {
        let text = Substring(line)
        let parts = MarkdownCode.proseRanges(inLine: text).map { range in String(text.unicodeScalars[range]) }
        #expect(parts == expected)
    }

    @Test("A fence closes only on a fence line that matches the fence line that opens it", arguments: fenceCases)
    func fenceClosesOnMatchingFence(body: String, expected: [Bool]) {
        #expect(MarkdownCode.markerBearingFlags(of: BodyLines.lines(of: body)) == expected)
    }
}
