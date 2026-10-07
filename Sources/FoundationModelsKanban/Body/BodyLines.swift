import Foundation

/// The line rules that the marker removes share: the dependency URL remove and the `#tag` remove (plan.md §6.1).
///
/// A remove edits only the lines that hold a marker. Each other line stays the same, byte for byte, with its own line
/// break. These are the rules of the Rust `remove_tag`.
enum BodyLines {
    /// The number of lines that a remove replaces when it empties the last line: the empty last line, and the line
    /// before it, which loses its line break.
    private static let emptiedLineCount = 2

    /// Splits a body into its lines. Each line keeps its line break, so the joined lines give the same body.
    ///
    /// - Parameter body: The body to split.
    /// - Returns: The lines, in text order. An empty body has no lines.
    static func lines(of body: String) -> [Substring] {
        Array(
            sequence(state: body.startIndex) { start -> Substring? in
                guard start < body.endIndex else {
                    return nil
                }
                let line = body.lineRange(for: start..<start)
                start = line.upperBound
                return body[line]
            }
        )
    }

    /// Gives the text of a line without its line break.
    ///
    /// - Parameter line: The line, with or without a line break.
    /// - Returns: The characters before the line break.
    static func content(of line: some StringProtocol) -> Substring {
        Substring(line.prefix { character in !character.isNewline })
    }

    /// Makes the edited form of a line: the new text without its trailing whitespace, and the line break of the old
    /// line. A remove leaves a hole, so the edited line loses its trailing whitespace.
    ///
    /// - Parameters:
    ///   - text: The new text of the line, without a line break.
    ///   - line: The old line, with its line break.
    /// - Returns: The edited line.
    static func editedLine(withText text: some StringProtocol, replacing line: Substring) -> String {
        let trimmed = String(text.reversed().drop(while: \.isWhitespace).reversed())
        return trimmed + line.dropFirst(content(of: line).count)
    }

    /// Joins the lines of a body, with the edited lines in place of the old lines.
    ///
    /// When the edit empties the last line, and that line has no line break, the line break before it also goes away.
    /// Thus, a marker that stood alone on the last line leaves no empty line at the end.
    ///
    /// - Parameters:
    ///   - lines: The lines of the body, from ``lines(of:)``.
    ///   - edits: For each line, the edited line, or `nil` when the line stays the same.
    /// - Returns: The body after the edit.
    static func body(joining lines: [Substring], with edits: [String?]) -> String {
        let result = zip(lines, edits).map { line, edit in
            edit ?? String(line)
        }
        guard edits.last == .some(""), let previous = result.dropLast().last else {
            return result.joined()
        }
        return result.dropLast(emptiedLineCount).joined() + content(of: previous)
    }
}
