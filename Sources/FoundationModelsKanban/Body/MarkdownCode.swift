import Foundation

/// The Markdown rule that the body markers share: the `#tag` markers and the dependency URLs (plan.md §6.1).
///
/// A marker in a fence line, in a fenced code block, in a heading line, or in inline code does not count. Thus an
/// example in a code block or a title in a heading does not change the tags or the dependencies of a task.
///
/// A fenced code block and an inline code span close as CommonMark closes them: a fence closes only on a fence line
/// with the same marker and a run that is not shorter, and a span closes only on a backtick run of the same length.
enum MarkdownCode {
    /// The scalar that opens and closes an inline code span.
    static let inlineCodeDelimiter: Unicode.Scalar = "`"

    /// The characters that make the run of a fence line, after the leading whitespace.
    static let fenceMarkers: Set<Character> = ["`", "~"]

    /// The smallest length of the run of a fence line.
    static let minimumFenceLength = 3

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
    /// A fence line, a line in a fenced code block, and a heading line do not count. The walk keeps the fence line
    /// that opens the current fenced code block from line to line, so it reads all the lines in order. Only a fence
    /// line that ``FenceLine/closes(_:)`` the open fence ends the block.
    ///
    /// - Parameter lines: The lines of the body, from ``BodyLines/lines(of:)``.
    /// - Returns: For each line, `true` when a marker on the line can count.
    static func markerBearingFlags(of lines: [Substring]) -> [Bool] {
        var openFence: FenceLine?
        return lines.map { line in
            let text = BodyLines.content(of: line).drop(while: \.isWhitespace)
            let fence = FenceLine(text: text)
            if let open = openFence {
                if let fence, fence.closes(open) {
                    openFence = nil
                }
                return false
            }
            guard let fence, fence.canOpen else {
                return !text.isHeadingLine
            }
            openFence = fence
            return false
        }
    }

    /// Gives the parts of the text of one line that are not in inline code.
    ///
    /// A span opens at a run of ``inlineCodeDelimiter`` and closes at the next run of the same length. A run of a
    /// different length is part of the span. A span that does not close goes to the end of the line. The delimiters
    /// are not in the result.
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
    /// The span closes at the first later run of delimiters with the same length as the run that opens it.
    ///
    /// - Parameters:
    ///   - scalars: The scalars of the line.
    ///   - start: The index of the first delimiter of the opening run.
    /// - Returns: The index after the closing run, or the end of the line when the span does not close.
    private static func inlineCodeEnd(
        in scalars: Substring.UnicodeScalarView,
        from start: String.Index
    ) -> String.Index {
        let openingEnd = delimiterRunEnd(in: scalars, from: start)
        let openingLength = scalars.distance(from: start, to: openingEnd)
        let runs = sequence(state: openingEnd) { searchStart -> Range<String.Index>? in
            guard let runStart = scalars[searchStart...].firstIndex(of: inlineCodeDelimiter) else {
                return nil
            }
            let run = runStart..<delimiterRunEnd(in: scalars, from: runStart)
            searchStart = run.upperBound
            return run
        }
        let closing = runs.first { run in scalars.distance(from: run.lowerBound, to: run.upperBound) == openingLength }
        return closing?.upperBound ?? scalars.endIndex
    }

    /// Finds the end of the run of ``inlineCodeDelimiter`` that starts at an index.
    ///
    /// - Parameters:
    ///   - scalars: The scalars of the line.
    ///   - start: The index of the first delimiter of the run.
    /// - Returns: The index after the last delimiter of the run.
    private static func delimiterRunEnd(
        in scalars: Substring.UnicodeScalarView,
        from start: String.Index
    ) -> String.Index {
        scalars[start...].firstIndex { scalar in scalar != inlineCodeDelimiter } ?? scalars.endIndex
    }
}

// MARK: - Fence lines

/// A line that can open or close a fenced code block: a run of one ``MarkdownCode/fenceMarkers`` character, with at
/// least ``MarkdownCode/minimumFenceLength`` characters, and the info string after the run.
private struct FenceLine {
    /// The character of the run.
    let marker: Character

    /// The number of characters in the run.
    let length: Int

    /// The text after the run.
    let info: Substring

    /// Reads a fence line.
    ///
    /// - Parameter text: The text of the line, after its leading whitespace.
    /// - Returns: `nil` when the text does not start with a run of a fence marker that is long enough.
    init?(text: Substring) {
        guard let marker = text.first, MarkdownCode.fenceMarkers.contains(marker) else {
            return nil
        }
        let run = text.prefix { character in character == marker }
        guard run.count >= MarkdownCode.minimumFenceLength else {
            return nil
        }
        self.marker = marker
        length = run.count
        info = text[run.endIndex...]
    }

    /// `true` when the line opens a fenced code block. A backtick run with a backtick in its info string is inline
    /// code, not a fence.
    var canOpen: Bool {
        marker != Character(MarkdownCode.inlineCodeDelimiter) || !info.contains(marker)
    }

    /// Tells if the line closes the fenced code block that a fence line opens.
    ///
    /// - Parameter open: The fence line that opens the block.
    /// - Returns: `true` when the line has the same marker, a run that is not shorter, and no info string.
    func closes(_ open: FenceLine) -> Bool {
        marker == open.marker && length >= open.length && info.allSatisfy(\.isWhitespace)
    }
}

// MARK: - Line kinds

extension Substring {
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
