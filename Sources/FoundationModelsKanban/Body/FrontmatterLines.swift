/// The lines of the YAML frontmatter of a body, for a write of one top-level key that keeps each other line as it is
/// (divergence.md §22).
///
/// A write does not encode the YAML again. Thus the other keys keep their order, their form, and their comments, and a
/// git merge of two writes of different keys does not conflict. The write also works on a frontmatter with bad YAML.
struct FrontmatterLines {
    /// The line end that each line gets in ``text``.
    private let lineEnd: String

    /// The lines of the frontmatter, with no line end.
    private var lines: [Substring]

    /// Makes the lines of a frontmatter text.
    ///
    /// - Parameters:
    ///   - text: The text between the two `---` fence lines, with the line end of its last line. `""` for no
    ///     frontmatter.
    ///   - lineEnd: The line end of the lines that ``text`` gives, for example the line end of the opening fence.
    init(text: String, lineEnd: String) {
        self.lineEnd = lineEnd
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        self.lines = lines
    }

    /// The frontmatter text: each line with ``lineEnd``.
    var text: String {
        lines.map { line in line + lineEnd }.joined()
    }

    /// `true` when no line has a character that is not white space.
    var isBlank: Bool {
        lines.allSatisfy { line in line.allSatisfy(\.isWhitespace) }
    }

    /// Sets a top-level key to a value, or removes the key.
    ///
    /// The new line goes in the place of the first line of the key, or after the last line when the frontmatter does
    /// not have the key. Each line of the key goes: the key line, and the indented lines after it that hold the rest
    /// of its value. Thus a second line of the same key also goes, and the frontmatter has no duplicate key.
    ///
    /// - Parameters:
    ///   - key: The key, for example `trigger`.
    ///   - value: The YAML text of the value on the key line, or `nil` to remove the key.
    mutating func set(_ key: String, to value: String?) {
        let firstKeyLine = lines.firstIndex { line in Self.line(line, holdsKey: key) }
        lines = removingLines(of: key)
        guard let value else {
            return
        }
        lines.insert(Substring("\(key): \(value)"), at: firstKeyLine ?? lines.endIndex)
    }

    /// Gives the lines with no line of a key. The lines before the first line of the key keep their places, so the
    /// index of that line is the place of a new key line.
    ///
    /// - Parameter key: The key.
    /// - Returns: The lines with no key line and no indented line after a key line.
    private func removingLines(of key: String) -> [Substring] {
        var kept: [Substring] = []
        var isInValue = false
        for line in lines {
            if Self.line(line, holdsKey: key) {
                isInValue = true
            } else if !(isInValue && Self.isIndented(line)) {
                isInValue = false
                kept.append(line)
            }
        }
        return kept
    }

    /// The forms of a key at the start of its line: plain, in double quotes, and in single quotes.
    ///
    /// - Parameter key: The key.
    /// - Returns: The forms.
    private static func forms(of key: String) -> [String] {
        [key, "\"\(key)\"", "'\(key)'"]
    }

    /// Tells if a line is the line of a top-level key: the key at the start, white space, and a colon at the end of
    /// the line or before white space.
    ///
    /// - Parameters:
    ///   - line: The line, with no line end.
    ///   - key: The key.
    /// - Returns: `true` when the line holds the key.
    private static func line(_ line: Substring, holdsKey key: String) -> Bool {
        forms(of: key).contains { form in
            guard line.hasPrefix(form) else {
                return false
            }
            let rest = line.dropFirst(form.count).drop { character in character == " " || character == "\t" }
            guard rest.first == ":" else {
                return false
            }
            return rest.dropFirst().first.map(\.isWhitespace) ?? true
        }
    }

    /// Tells if a line starts with a space or a tab: a line of the value of the key line before it.
    ///
    /// - Parameter line: The line, with no line end.
    /// - Returns: `true` when the line is indented.
    private static func isIndented(_ line: Substring) -> Bool {
        line.first == " " || line.first == "\t"
    }
}
