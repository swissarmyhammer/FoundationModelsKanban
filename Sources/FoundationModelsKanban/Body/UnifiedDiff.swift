/// A line-based unified diff from one text to a different text.
///
/// The log stores each change to the body of a node as a unified diff, not as
/// the full text (plan.md §5.5). The diff has no file header lines (`---`,
/// `+++`). Each hunk has its `@@ -a,b +c,d @@` header and 3 lines of context.
/// A line with no final newline is followed by the marker
/// `\ No newline at end of file`, as in git.
///
/// The diff is calculated with `CollectionDifference` over the lines. Thus the
/// same two texts always give the same diff.
struct UnifiedDiff: Hashable, Sendable {
    /// The number of unchanged lines that a hunk shows before and after each
    /// change.
    static let contextLineCount = 3

    /// The largest number of unchanged lines between two changes that keeps
    /// the two changes in one hunk. At this gap, the context lines of the two
    /// changes touch, and git also writes one hunk. The gap holds the context
    /// lines after the first change and the context lines before the second
    /// change.
    static let largestMergedGap = contextLineCount + contextLineCount

    /// The hunks of the diff, in line order. A diff of two equal texts has no
    /// hunks.
    let hunks: [Hunk]

    /// The diff as text: each hunk with its header and its body lines. A diff
    /// with no hunks is the empty text.
    var text: String {
        hunks.map(\.text).joined()
    }

    /// Gives the diff that changes the new text back to the old text.
    ///
    /// The `-` lines and the `+` lines change places, and the two ranges of
    /// each hunk header change places.
    ///
    /// - Returns: The reversed diff.
    func reversed() -> UnifiedDiff {
        UnifiedDiff(hunks: hunks.map { $0.reversed() })
    }
}

// MARK: - Lines

extension UnifiedDiff {
    /// One line of a text, with its final newline state.
    ///
    /// Only the last line of a text can have no final newline. A change of
    /// only the final newline is thus a change of the last line, as in git.
    struct TextLine: Hashable, Sendable {
        /// The characters of the line, without the final newline. A carriage
        /// return before the newline stays here, as in git.
        let content: String

        /// True when a newline follows the line in the text.
        let hasNewline: Bool

        /// The line as text, with its final newline when it has one.
        var text: String {
            hasNewline ? content + "\n" : content
        }

        /// Splits a text into its lines.
        ///
        /// The split is on the Unicode scalar U+000A. A Swift `Character` holds
        /// "\r\n" as one character, so a split on `Character` does not find a
        /// CRLF line end.
        ///
        /// - Parameter text: The text to split.
        /// - Returns: The lines of the text. The empty text has no lines.
        static func lines(in text: String) -> [TextLine] {
            let pieces = text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
            let terminated = pieces.dropLast().map { TextLine(content: String(Substring($0)), hasNewline: true) }
            let last = pieces.last.map { String(Substring($0)) } ?? ""
            return last.isEmpty ? terminated : terminated + [TextLine(content: last, hasNewline: false)]
        }

        /// Joins lines into a text.
        ///
        /// - Parameter lines: The lines to join.
        /// - Returns: The text of the lines.
        static func text(joining lines: [TextLine]) -> String {
            lines.map(\.text).joined()
        }
    }

    /// One body line of a hunk: a text line and its marker.
    struct Line: Hashable, Sendable {
        /// The kind of a body line. The raw value is the marker at the start
        /// of the line in the diff text.
        enum Kind: Character, Sendable {
            /// A line that both texts have.
            case context = " "

            /// A line that only the old text has.
            case removed = "-"

            /// A line that only the new text has.
            case added = "+"

            /// The kind of the line in the reversed diff.
            var reversed: Kind {
                switch self {
                case .context: .context
                case .removed: .added
                case .added: .removed
                }
            }
        }

        /// The marker line that follows a line with no final newline.
        static let noNewlineMarker = "\\ No newline at end of file"

        /// The kind of the line.
        let kind: Kind

        /// The text line.
        let textLine: TextLine

        /// The line in the reversed diff.
        var reversed: Line {
            Line(kind: kind.reversed, textLine: textLine)
        }

        /// The line as diff text: the marker, the content, a newline, and the
        /// no-newline marker line when the text line has no final newline.
        var text: String {
            let line = "\(kind.rawValue)\(textLine.content)\n"
            return textLine.hasNewline ? line : line + Self.noNewlineMarker + "\n"
        }
    }
}

// MARK: - Hunks

extension UnifiedDiff {
    /// One hunk of a diff: a range of the old text, the same range of the new
    /// text, and the body lines that change one into the other.
    struct Hunk: Hashable, Sendable {
        /// The first line of the old range, from 1. When the old range has no
        /// lines, this is the line before the range, as in git (0 at the start
        /// of the text).
        let oldStart: Int

        /// The first line of the new range, with the same rule as
        /// ``oldStart``.
        let newStart: Int

        /// The body lines, in order.
        let lines: [Line]

        /// The lines of the old range: the context lines and the `-` lines.
        var oldLines: [TextLine] {
            lines.filter { $0.kind != .added }.map(\.textLine)
        }

        /// The lines of the new range: the context lines and the `+` lines.
        var newLines: [TextLine] {
            lines.filter { $0.kind != .removed }.map(\.textLine)
        }

        /// The number of lines in the old range.
        var oldCount: Int {
            oldLines.count
        }

        /// The number of lines in the new range.
        var newCount: Int {
            newLines.count
        }

        /// The header line, without its newline. The counts are always
        /// written, also a count of 1.
        var header: String {
            "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
        }

        /// The hunk as diff text: the header line and the body lines.
        var text: String {
            header + "\n" + lines.map(\.text).joined()
        }

        /// Gives the hunk that changes the new range back to the old range.
        ///
        /// In each group of changed lines, the `-` lines come before the `+`
        /// lines, as in a diff that is made from the two texts.
        ///
        /// - Returns: The reversed hunk.
        func reversed() -> Hunk {
            let lines = lines.map(\.reversed)
                .reduce(into: [[Line]](), Self.extendRun)
                .flatMap { run in run.filter { $0.kind == .removed } + run.filter { $0.kind != .removed } }
            return Hunk(oldStart: newStart, newStart: oldStart, lines: lines)
        }

        /// Adds a line to the runs of a hunk. Each context line is a run of
        /// its own. Changed lines that follow each other are one run.
        ///
        /// - Parameters:
        ///   - runs: The runs so far.
        ///   - line: The next line.
        private static func extendRun(_ runs: inout [[Line]], with line: Line) {
            guard line.kind != .context, let previous = runs.last?.last, previous.kind != .context else {
                runs.append([line])
                return
            }
            runs[runs.count - 1].append(line)
        }
    }
}

// MARK: - Make

extension UnifiedDiff {
    /// Makes the diff from an old text to a new text.
    ///
    /// - Parameters:
    ///   - old: The text before the change.
    ///   - new: The text after the change.
    init(from old: String, to new: String) {
        let script = EditScript(from: TextLine.lines(in: old), to: TextLine.lines(in: new))
        let edits = Array(IteratorSequence(script))
        let changes = edits.indices.filter { edits[$0].line.kind != .context }
        let groups = changes.reduce(into: [ClosedRange<Int>](), Self.extendGroup)
        self.init(hunks: groups.map { Self.hunk(of: edits, around: $0) })
    }

    /// Adds the index of a changed line to the groups of changes. A change
    /// joins the last group when at most ``largestMergedGap`` unchanged lines
    /// are between them. If not, the change starts a new group.
    ///
    /// - Parameters:
    ///   - groups: The groups so far, each from its first to its last change.
    ///   - change: The index of the next changed line in the edit script.
    private static func extendGroup(_ groups: inout [ClosedRange<Int>], with change: Int) {
        guard let last = groups.last, change - last.upperBound - 1 <= largestMergedGap else {
            groups.append(change...change)
            return
        }
        groups[groups.count - 1] = last.lowerBound...change
    }

    /// Makes the hunk of one group of changes, with the context lines around
    /// it.
    ///
    /// - Parameters:
    ///   - edits: The full edit script.
    ///   - group: The indices of the first and the last change of the group.
    /// - Returns: The hunk.
    private static func hunk(of edits: [Edit], around group: ClosedRange<Int>) -> Hunk {
        let first = max(edits.startIndex, group.lowerBound - contextLineCount)
        let last = min(edits.endIndex - 1, group.upperBound + contextLineCount)
        let lines = edits[first...last].map(\.line)
        let oldCount = lines.filter { $0.kind != .added }.count
        let newCount = lines.filter { $0.kind != .removed }.count
        return Hunk(
            oldStart: startLine(after: edits[first].oldOffset, count: oldCount),
            newStart: startLine(after: edits[first].newOffset, count: newCount),
            lines: lines
        )
    }

    /// Gives the start line of a hunk range with the git rule.
    ///
    /// - Parameters:
    ///   - offset: The number of lines of the text before the range.
    ///   - count: The number of lines in the range.
    /// - Returns: The first line of the range, from 1. For an empty range,
    ///   the line before the range.
    private static func startLine(after offset: Int, count: Int) -> Int {
        count == 0 ? offset : offset + 1
    }

    /// One line of the edit script, with its position in the two texts.
    private struct Edit {
        /// The body line.
        let line: Line

        /// The number of old lines before this line.
        let oldOffset: Int

        /// The number of new lines before this line.
        let newOffset: Int
    }

    /// The lines of both texts in order, each marked as context, removed, or
    /// added. The removals and the insertions come from `CollectionDifference`.
    /// At each change, the removed lines come before the added lines.
    private struct EditScript: IteratorProtocol {
        /// The lines of the old text.
        let old: [TextLine]

        /// The lines of the new text.
        let new: [TextLine]

        /// The offsets of the old lines that the new text does not have.
        let removals: Set<Int>

        /// The offsets of the new lines that the old text does not have.
        let insertions: Set<Int>

        /// The number of old lines that the script gave so far.
        var oldOffset = 0

        /// The number of new lines that the script gave so far.
        var newOffset = 0

        /// Makes the edit script from an old text to a new text.
        ///
        /// - Parameters:
        ///   - old: The lines of the old text.
        ///   - new: The lines of the new text.
        init(from old: [TextLine], to new: [TextLine]) {
            let difference = new.difference(from: old)
            self.old = old
            self.new = new
            removals = Set(difference.removals.map(Self.offset))
            insertions = Set(difference.insertions.map(Self.offset))
        }

        /// Gives the next line of the script.
        ///
        /// - Returns: The next edit, or `nil` after the last line of both
        ///   texts.
        mutating func next() -> Edit? {
            guard let kind = nextKind() else {
                return nil
            }
            let textLine = kind == .added ? new[newOffset] : old[oldOffset]
            let edit = Edit(line: Line(kind: kind, textLine: textLine), oldOffset: oldOffset, newOffset: newOffset)
            oldOffset += kind == .added ? 0 : 1
            newOffset += kind == .removed ? 0 : 1
            return edit
        }

        /// Gives the kind of the next line.
        ///
        /// - Returns: The kind, or `nil` after the last line of both texts.
        private func nextKind() -> Line.Kind? {
            if removals.contains(oldOffset) {
                return .removed
            }
            if insertions.contains(newOffset) {
                return .added
            }
            return oldOffset < old.count && newOffset < new.count ? .context : nil
        }

        /// Gives the offset of one change of a collection difference.
        ///
        /// - Parameter change: The change.
        /// - Returns: The offset of the change: in the old text for a removal,
        ///   and in the new text for an insertion.
        private static func offset(of change: CollectionDifference<TextLine>.Change) -> Int {
            switch change {
            case .insert(let offset, _, _): offset
            case .remove(let offset, _, _): offset
            }
        }
    }
}

// MARK: - Parse

/// An error from parsing the text of a unified diff.
enum UnifiedDiffError: Error, Hashable, Sendable {
    /// A line where a hunk header must be is not a hunk header. The value is
    /// the line.
    case malformedHeader(String)

    /// A body line does not start with a space, `-`, or `+`. The value is the
    /// line.
    case malformedLine(String)

    /// The text ends before the hunk has the lines that its header gives. The
    /// value is the header.
    case truncatedHunk(String)

    /// The body lines of a hunk do not have the line counts of its header. The
    /// value is the header.
    case countMismatch(String)
}

extension UnifiedDiff {
    /// Parses the text of a diff into its hunks.
    ///
    /// A header range with no count, for example `-2`, has a count of 1, as
    /// in git.
    ///
    /// - Parameter text: The diff text, as ``text`` writes it.
    /// - Throws: A ``UnifiedDiffError`` when the text is not a unified diff.
    init(parsing text: String) throws {
        var parser = DiffParser(lines: TextLine.lines(in: text).map(\.content))
        var hunks: [Hunk] = []
        while !parser.isAtEnd {
            try hunks.append(parser.parseHunk())
        }
        self.init(hunks: hunks)
    }

    /// Reads the hunks of a diff text, one line at a time.
    private struct DiffParser {
        /// The lines of the diff text, without their newlines.
        let lines: [String]

        /// The index of the next line to read.
        var index = 0

        /// True when all lines are read.
        var isAtEnd: Bool {
            index >= lines.count
        }

        /// Reads one hunk: its header and its body lines.
        ///
        /// - Returns: The hunk.
        /// - Throws: A ``UnifiedDiffError`` when the hunk is not correct.
        mutating func parseHunk() throws -> Hunk {
            let header = lines[index]
            index += 1
            let (old, new) = try Self.ranges(in: header)
            var body: [Line] = []
            while body.count(where: { $0.kind != .added }) < old.count
                || body.count(where: { $0.kind != .removed }) < new.count
            {
                guard !isAtEnd else {
                    throw UnifiedDiffError.truncatedHunk(header)
                }
                try body.append(parseLine())
            }
            let hunk = Hunk(oldStart: old.start, newStart: new.start, lines: body)
            guard hunk.oldCount == old.count, hunk.newCount == new.count else {
                throw UnifiedDiffError.countMismatch(header)
            }
            return hunk
        }

        /// Reads one body line, and the no-newline marker line that follows
        /// it, if there is one.
        ///
        /// - Returns: The body line.
        /// - Throws: ``UnifiedDiffError/malformedLine(_:)`` when the line does
        ///   not start with a space, `-`, or `+`.
        private mutating func parseLine() throws -> Line {
            let line = lines[index]
            index += 1
            guard let marker = line.first, let kind = Line.Kind(rawValue: marker) else {
                throw UnifiedDiffError.malformedLine(line)
            }
            let hasNewline = isAtEnd || !lines[index].hasPrefix("\\")
            index += hasNewline ? 0 : 1
            return Line(kind: kind, textLine: TextLine(content: String(line.dropFirst()), hasNewline: hasNewline))
        }

        /// Reads the two ranges of a hunk header.
        ///
        /// - Parameter header: The header line, for example `@@ -2,7 +2,7 @@`.
        /// - Returns: The old range and the new range.
        /// - Throws: ``UnifiedDiffError/malformedHeader(_:)`` when the line is
        ///   not a hunk header.
        private static func ranges(in header: String) throws -> (old: HeaderRange, new: HeaderRange) {
            let fields = header.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= HeaderRange.fieldCount,
                fields[HeaderRange.openIndex] == HeaderRange.fence,
                fields[HeaderRange.closeIndex] == HeaderRange.fence,
                let old = HeaderRange(fields[HeaderRange.oldIndex], sign: "-"),
                let new = HeaderRange(fields[HeaderRange.newIndex], sign: "+")
            else {
                throw UnifiedDiffError.malformedHeader(header)
            }
            return (old, new)
        }
    }

    /// One range of a hunk header, for example `-2,7`. It is `fileprivate`, so
    /// that the extension that reads a range field can see it.
    fileprivate struct HeaderRange {
        /// The fence before and after the two ranges of a header.
        static let fence = "@@"

        /// The number of space-separated fields of a header: the two fences
        /// and the two ranges. Text after the second fence is permitted.
        static let fieldCount = 4

        /// The index of the first fence in the fields of a header.
        static let openIndex = 0

        /// The index of the old range in the fields of a header.
        static let oldIndex = 1

        /// The index of the new range in the fields of a header.
        static let newIndex = 2

        /// The index of the second fence in the fields of a header.
        static let closeIndex = 3

        /// The first line of the range.
        let start: Int

        /// The number of lines in the range.
        let count: Int
    }
}

extension UnifiedDiff.HeaderRange {
    /// Reads a range field.
    ///
    /// - Parameters:
    ///   - field: The field, for example `-2,7` or `-2`.
    ///   - sign: The sign that the field must start with.
    /// - Returns: `nil` when the field is not a range with that sign.
    init?(_ field: Substring, sign: Character) {
        guard field.first == sign else {
            return nil
        }
        let numbers = field.dropFirst().split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard let start = numbers.first.flatMap({ Int($0) }), start >= 0 else {
            return nil
        }
        guard let countField = numbers.dropFirst().first else {
            self.init(start: start, count: 1)
            return
        }
        guard let count = Int(countField), count >= 0 else {
            return nil
        }
        self.init(start: start, count: count)
    }
}
