/// The body text after replay applies a diff, and its conflict state.
struct AppliedBody: Hashable, Sendable {
    /// The text after the apply.
    let text: String

    /// True when the text has a full conflict block (plan.md §5.5). The
    /// `CONFLICT` virtual tag uses this value. A block from an earlier event
    /// also counts, and a later edit that removes the block makes it false.
    let hasConflict: Bool
}

// MARK: - Apply

extension UnifiedDiff {
    /// Applies the diff to a body during replay (plan.md §5.5).
    ///
    /// Each hunk applies in order. A hunk applies at its line number if its
    /// context lines and `-` lines match the text there. If not, the hunk
    /// applies at the nearest position where they match exactly, as `patch`
    /// does with no fuzz. At equal distance, the earlier position wins. The
    /// line number of a hunk moves by the shift that the previous hunk had,
    /// and a hunk never matches lines that an earlier hunk used.
    ///
    /// A hunk that does not match at any position is not lost. A conflict
    /// block replaces the current lines at its line number. See
    /// ``ConflictBlock``.
    ///
    /// The result depends only on the arguments, so all clones give the same
    /// text.
    ///
    /// - Parameters:
    ///   - text: The current body.
    ///   - conflictLabel: The text after the end marker of a conflict block:
    ///     the id of the event that holds the diff.
    /// - Returns: The body after the diff, and its conflict state.
    func applied(to text: String, withConflictLabel conflictLabel: String) -> AppliedBody {
        let initial = HunkApplier(lines: TextLine.lines(in: text), conflictLabel: conflictLabel)
        let lines = hunks.reduce(into: initial) { $0.apply($1) }.finishedLines
        return AppliedBody(text: TextLine.text(joining: lines), hasConflict: ConflictBlock.isPresent(in: lines))
    }

    /// Applies the hunks of one diff to the lines of a text, one hunk at a
    /// time.
    private struct HunkApplier {
        /// The lines of the text before the diff.
        let lines: [TextLine]

        /// The text after the end marker of a conflict block.
        let conflictLabel: String

        /// The lines of the result so far.
        var result: [TextLine] = []

        /// The index of the first line of ``lines`` that is not in
        /// ``result`` yet.
        var cursor = 0

        /// The number of lines between the line number of the last hunk that
        /// matched and the position where it matched.
        var shift = 0

        /// The lines of the result, with the lines after the last hunk.
        var finishedLines: [TextLine] {
            result + lines[cursor...]
        }

        /// Applies one hunk at its nearest match, or puts a conflict block at
        /// its line number.
        ///
        /// - Parameter hunk: The next hunk of the diff.
        mutating func apply(_ hunk: Hunk) {
            let expected = hunk.oldOffset + shift
            guard let position = nearestMatch(of: hunk.oldLines, near: expected) else {
                insertConflict(for: hunk, near: expected)
                return
            }
            shift = position - hunk.oldOffset
            replace(position..<position + hunk.oldCount, with: hunk.newLines)
        }

        /// Finds the nearest position where the old lines of a hunk match the
        /// text exactly.
        ///
        /// - Parameters:
        ///   - oldLines: The context lines and the `-` lines of the hunk.
        ///   - expected: The index where the hunk is expected to match.
        /// - Returns: The index of the nearest match, or `nil` when the lines
        ///   do not match after ``cursor``.
        private func nearestMatch(of oldLines: [TextLine], near expected: Int) -> Int? {
            let last = lines.count - oldLines.count
            guard cursor <= last else {
                return nil
            }
            return (cursor...last)
                .filter { lines[$0..<$0 + oldLines.count].elementsEqual(oldLines) }
                .min { (abs($0 - expected), $0) < (abs($1 - expected), $1) }
        }

        /// Replaces the current lines at the line number of a hunk with a
        /// conflict block.
        ///
        /// - Parameters:
        ///   - hunk: The hunk that cannot apply.
        ///   - expected: The index where the hunk was expected to match.
        private mutating func insertConflict(for hunk: Hunk, near expected: Int) {
            let start = min(max(expected, cursor), lines.count)
            let end = min(start + hunk.oldCount, lines.count)
            let block = ConflictBlock.lines(
                between: Array(lines[start..<end]),
                and: hunk.newLines,
                withLabel: conflictLabel
            )
            replace(start..<end, with: block)
        }

        /// Copies the lines before a range to the result, then puts new lines
        /// in the place of the range.
        ///
        /// - Parameters:
        ///   - range: The range of ``lines`` to replace. It starts at or after
        ///     ``cursor``.
        ///   - newLines: The lines that replace the range.
        private mutating func replace(_ range: Range<Int>, with newLines: [TextLine]) {
            result += lines[cursor..<range.lowerBound]
            result += newLines
            cursor = range.upperBound
        }
    }
}

extension UnifiedDiff.Hunk {
    /// The number of lines of the old text before the old range. This is the
    /// index of the first old line, also for an empty old range.
    var oldOffset: Int {
        oldCount == 0 ? oldStart : oldStart - 1
    }
}

// MARK: - Conflict block

extension UnifiedDiff {
    /// The git-style block that replay puts into a body for a hunk that
    /// cannot apply (plan.md §5.5):
    ///
    /// ```
    /// <<<<<<< current
    /// (the current lines)
    /// =======
    /// (the lines that the hunk wanted)
    /// >>>>>>> (the event id)
    /// ```
    ///
    /// Each line of the block ends with a newline, also at the end of a text
    /// with no final newline. Thus, the markers always stay on lines of their
    /// own.
    enum ConflictBlock {
        /// The first line of a block.
        static let startMarker = "<<<<<<< current"

        /// The line between the current lines and the wanted lines.
        static let separator = "======="

        /// The start of the last line of a block. The conflict label follows
        /// it.
        static let endPrefix = ">>>>>>> "

        /// Makes the lines of a block.
        ///
        /// - Parameters:
        ///   - current: The lines of the text at the hunk position.
        ///   - wanted: The lines that the hunk wanted.
        ///   - label: The text after the end marker.
        /// - Returns: The lines of the block.
        static func lines(between current: [TextLine], and wanted: [TextLine], withLabel label: String) -> [TextLine] {
            let contents = [startMarker] + current.map(\.content) + [separator] + wanted.map(\.content)
            return (contents + [endPrefix + label]).map { TextLine(content: $0, hasNewline: true) }
        }

        /// Tells if lines hold a full block: a start marker, then a separator,
        /// then an end marker.
        ///
        /// - Parameter lines: The lines of a text.
        /// - Returns: True when the lines hold a full block.
        static func isPresent(in lines: [TextLine]) -> Bool {
            let contents = lines.map(\.content)
            guard let start = contents.firstIndex(of: startMarker),
                let middle = contents[start...].firstIndex(of: separator)
            else {
                return false
            }
            return contents[middle...].contains { $0.hasPrefix(endPrefix) }
        }
    }
}
