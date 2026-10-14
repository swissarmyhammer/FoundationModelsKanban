import Foundation

/// The Markdown rule that the body markers share: the `#tag` markers and the dependency URLs (plan.md §6.1).
///
/// A marker in a fence line, in a fenced code block, in a heading line, or in inline code does not count. Thus an
/// example in a code block or a title in a heading does not change the tags or the dependencies of a task.
enum MarkdownCode {
    /// The scalar that opens and closes an inline code span.
    static let inlineCodeDelimiter: Unicode.Scalar = "`"

    /// The texts that start a fence line, after the leading whitespace.
    static let fencePrefixes = ["```", "~~~"]

    /// The character that starts a heading line, after the leading whitespace.
    static let headingPrefix: Character = "#"

    /// The character after the heading prefix that makes a heading line, for example `# Title`.
    static let headingSeparator: Character = " "

    /// Gives the text of each line of a body where a marker can count, in text order.
    ///
    /// - Parameter body: The Markdown body of a task.
    /// - Returns: The text of each line that is not a fence line, not in a fenced code block, and not a heading line,
    ///   without its line break.
    static func markerBearingLines(of body: String) -> [Substring] {
        let lines = BodyLines.lines(of: body)
        return zip(lines, markerBearingFlags(of: lines)).compactMap { line, isMarkerBearing in
            isMarkerBearing ? BodyLines.content(of: line) : nil
        }
    }

    /// Edits the lines of a body where a marker can count, and keeps each other line byte for byte.
    ///
    /// The ``BodyLines`` rules join the lines again.
    ///
    /// - Parameters:
    ///   - body: The Markdown body of a task.
    ///   - edit: Gives the edited form of one line, with its line break, or `nil` when the line stays the same.
    /// - Returns: The body after the edit.
    static func editingMarkerBearingLines(of body: String, with edit: (Substring) -> String?) -> String {
        let lines = BodyLines.lines(of: body)
        let edits = zip(lines, markerBearingFlags(of: lines)).map { line, isMarkerBearing in
            isMarkerBearing ? edit(line) : nil
        }
        return BodyLines.body(joining: lines, with: edits)
    }

    /// Tells, for each line of a body, if a marker on the line can count.
    ///
    /// A fence line, a line in a fenced code block, and a heading line do not count. The walk keeps the fence state
    /// from line to line, so it reads all the lines in order.
    ///
    /// - Parameter lines: The lines of the body, from ``BodyLines/lines(of:)``.
    /// - Returns: For each line, `true` when a marker on the line can count.
    static func markerBearingFlags(of lines: [Substring]) -> [Bool] {
        var isInFence = false
        return lines.map { line in
            let text = BodyLines.content(of: line).drop(while: \.isWhitespace)
            guard !text.isFenceLine else {
                isInFence.toggle()
                return false
            }
            return !isInFence && !text.isHeadingLine
        }
    }

    /// Gives the parts of the text of one line that are not in inline code.
    ///
    /// A span opens at a ``inlineCodeDelimiter`` and closes at the next one. A span that does not close goes to the
    /// end of the line. The delimiters are not in the result.
    ///
    /// - Parameter text: The text of the line, without its line break.
    /// - Returns: The ranges of the parts, in text order. A range can be empty.
    static func proseRanges(inLine text: Substring) -> [Range<String.Index>] {
        let scalars = text.unicodeScalars
        return Array(
            sequence(state: scalars.startIndex) { start -> Range<String.Index>? in
                guard start < scalars.endIndex else {
                    return nil
                }
                let end = scalars[start...].firstIndex(of: inlineCodeDelimiter) ?? scalars.endIndex
                let prose = start..<end
                start = end < scalars.endIndex ? inlineCodeEnd(in: scalars, from: end) : end
                return prose
            }
        )
    }

    /// Finds the end of the inline code span that opens at an index.
    ///
    /// - Parameters:
    ///   - scalars: The scalars of the line.
    ///   - start: The index of the opening delimiter.
    /// - Returns: The index after the closing delimiter, or the end of the line when the span does not close.
    private static func inlineCodeEnd(
        in scalars: Substring.UnicodeScalarView,
        from start: String.Index
    ) -> String.Index {
        let contentStart = scalars.index(after: start)
        guard let close = scalars[contentStart...].firstIndex(of: inlineCodeDelimiter) else {
            return scalars.endIndex
        }
        return scalars.index(after: close)
    }
}

// MARK: - Line kinds

extension Substring {
    /// `true` when the text, after its leading whitespace, opens or closes a fenced code block.
    fileprivate var isFenceLine: Bool {
        MarkdownCode.fencePrefixes.contains { prefix in hasPrefix(prefix) }
    }

    /// `true` when the text, after its leading whitespace, is a Markdown heading, for example `# Title` or `##`. A
    /// `#` followed by a letter, for example `#bug`, is a marker, not a heading.
    fileprivate var isHeadingLine: Bool {
        guard first == MarkdownCode.headingPrefix else {
            return false
        }
        guard let next = dropFirst().first else {
            return true
        }
        return next == MarkdownCode.headingPrefix || next == MarkdownCode.headingSeparator
    }
}
