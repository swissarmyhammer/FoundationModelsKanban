import Foundation
import OrderedCollections

/// One `#tag` marker in one line of a task body.
private struct TagMarker {
    /// The range of the marker text in the line: the `#` and the slug text after it.
    let range: Range<String.Index>

    /// The slug of the marker text. `#Bug` and `#bug` give the same slug.
    let slug: Slug
}

/// Finds and removes the `#tag` markers of a task body (plan.md §6.1, §12 item 7).
///
/// This is a port of the parse part of the Rust file `swissarmyhammer-kanban/src/tag_parser.rs`. A marker is a `#`,
/// then an ASCII letter or digit, then more ASCII letters, digits, and `-`. The `#` must not follow an ASCII letter,
/// an ASCII digit, or `_`. The Rust parse keeps the case of the text. This parse changes each marker to its slug, so
/// a marker names the same tag as the tag name rule gives (plan.md §3.2).
///
/// A marker in a fence line, in a fenced code block, in a heading line, or in inline code is not a tag.
enum TagMarkers {
    /// The scalar that starts a marker.
    static let markerPrefix: Unicode.Scalar = "#"

    /// The scalar that opens and closes an inline code span.
    static let inlineCodeDelimiter: Unicode.Scalar = "`"

    /// The scalar, other than an ASCII letter or digit, that glues a `#` to the word before it.
    static let wordJoiner: Unicode.Scalar = "_"

    /// The space that a remove takes away together with the marker, so that the text keeps no double space.
    static let adjacentSpace: Unicode.Scalar = " "

    /// The texts that start a fence line, after the leading whitespace.
    static let fencePrefixes = ["```", "~~~"]

    /// The character that starts a heading line, after the leading whitespace.
    static let headingPrefix: Character = "#"

    /// The character after the heading prefix that makes a heading line, for example `# Title`.
    static let headingSeparator: Character = " "

    /// Finds the slug of each marker in a body.
    ///
    /// - Parameter body: The Markdown body of a task.
    /// - Returns: The slugs, in text order. Each slug is in the result one time.
    static func slugs(in body: String) -> [Slug] {
        let lines = BodyLines.lines(of: body)
        let found = zip(lines, tagBearingFlags(of: lines)).flatMap { line, isTagBearing in
            isTagBearing ? markers(inLine: BodyLines.content(of: line)).map(\.slug) : []
        }
        return Array(OrderedSet(found))
    }

    /// Removes each marker of one tag from a body.
    ///
    /// The `untagTask` mutation uses it when the body also holds the marker of the tag. A marker whose slug is the
    /// slug of the tag goes away, in each case of its text. The remove also takes one adjacent space: the space after
    /// the marker, else the space before it. A line with no marker of the tag stays the same, byte for byte. The
    /// ``BodyLines`` rules apply to each line that loses a marker.
    ///
    /// - Parameters:
    ///   - slug: The slug of the tag whose markers to remove.
    ///   - body: The Markdown body of a task.
    /// - Returns: The body without the markers of the tag.
    static func removing(markersOf slug: Slug, from body: String) -> String {
        let lines = BodyLines.lines(of: body)
        let edits = zip(lines, tagBearingFlags(of: lines)).map { line, isTagBearing in
            isTagBearing ? editedLine(from: line, removingMarkersOf: slug) : nil
        }
        return BodyLines.body(joining: lines, with: edits)
    }

    /// Tells, for each line of a body, if a marker on the line counts as a tag.
    ///
    /// A fence line, a line in a fenced code block, and a heading line do not count. The walk keeps the fence state
    /// from line to line, so it reads all the lines in order.
    ///
    /// - Parameter lines: The lines of the body, from ``BodyLines/lines(of:)``.
    /// - Returns: For each line, `true` when a marker on the line counts as a tag.
    static func tagBearingFlags(of lines: [Substring]) -> [Bool] {
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
}

// MARK: - Find

extension TagMarkers {
    /// Finds each marker in the text of one line that counts as a tag.
    ///
    /// - Parameter text: The text of the line, without its line break.
    /// - Returns: The markers, in text order. A marker in inline code is not in the result.
    fileprivate static func markers(inLine text: Substring) -> [TagMarker] {
        let scalars = text.unicodeScalars
        return Array(
            sequence(state: scalars.startIndex) { start -> TagMarker? in
                guard let marker = nextMarker(in: scalars, from: start) else {
                    return nil
                }
                start = marker.range.upperBound
                return marker
            }
        )
    }

    /// Finds the first marker at or after an index, and skips each inline code span on the way.
    ///
    /// - Parameters:
    ///   - scalars: The scalars of the line.
    ///   - start: The index where the search starts.
    /// - Returns: The marker, or `nil` when the rest of the line has no marker.
    private static func nextMarker(in scalars: Substring.UnicodeScalarView, from start: String.Index) -> TagMarker? {
        var index = start
        while index < scalars.endIndex {
            if scalars[index] == inlineCodeDelimiter {
                index = inlineCodeEnd(in: scalars, from: index)
            } else if let marker = marker(in: scalars, at: index) {
                return marker
            } else {
                index = scalars.index(after: index)
            }
        }
        return nil
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

    /// Makes the marker that starts at an index, when one starts there.
    ///
    /// - Parameters:
    ///   - scalars: The scalars of the line.
    ///   - index: The index of a possible `#`.
    /// - Returns: The marker, or `nil` when the scalar is not a `#`, the `#` follows a word, or the scalar after the
    ///   `#` is not an ASCII letter or digit.
    private static func marker(in scalars: Substring.UnicodeScalarView, at index: String.Index) -> TagMarker? {
        guard scalars[index] == markerPrefix, !isGluedToWord(in: scalars, at: index) else {
            return nil
        }
        let slugStart = scalars.index(after: index)
        guard slugStart < scalars.endIndex, scalars[slugStart].isASCIIAlphanumeric else {
            return nil
        }
        let slugEnd = scalars[slugStart...].firstIndex { scalar in !scalar.isMarkerSlugScalar } ?? scalars.endIndex
        guard let slug = try? TagName(normalizing: String(Substring(scalars[slugStart..<slugEnd]))).slug else {
            return nil
        }
        return TagMarker(range: index..<slugEnd, slug: slug)
    }

    /// Tells if the scalar before an index glues a `#` at that index to a word.
    ///
    /// - Parameters:
    ///   - scalars: The scalars of the line.
    ///   - index: The index of the `#`.
    /// - Returns: `true` when the scalar before is an ASCII letter, an ASCII digit, or the ``wordJoiner``.
    private static func isGluedToWord(in scalars: Substring.UnicodeScalarView, at index: String.Index) -> Bool {
        guard index > scalars.startIndex else {
            return false
        }
        let previous = scalars[scalars.index(before: index)]
        return previous.isASCIIAlphanumeric || previous == wordJoiner
    }
}

extension Unicode.Scalar {
    /// `true` when the scalar can be in the slug text of a marker: an ASCII letter, an ASCII digit, or the slug
    /// separator.
    fileprivate var isMarkerSlugScalar: Bool {
        isASCIIAlphanumeric || Character(self) == Slug.separator
    }
}

// MARK: - Remove

extension TagMarkers {
    /// Removes the markers of one tag from one line.
    ///
    /// - Parameters:
    ///   - line: The line, with its line break.
    ///   - slug: The slug of the tag whose markers to remove.
    /// - Returns: The changed line with its line break, or `nil` when the line has no marker of the tag.
    private static func editedLine(from line: Substring, removingMarkersOf slug: Slug) -> String? {
        let text = BodyLines.content(of: line)
        let removed = markers(inLine: text).filter { marker in marker.slug == slug }
        guard !removed.isEmpty else {
            return nil
        }
        let kept = String(keptText(of: text.unicodeScalars, without: removed))
        return BodyLines.editedLine(withText: kept, replacing: line)
    }

    /// Gives the text of a line without some of its markers. Each removed marker also takes one adjacent space: the
    /// space after it, else the space before it.
    ///
    /// - Parameters:
    ///   - scalars: The scalars of the line.
    ///   - removed: The markers to remove, in text order.
    /// - Returns: The text that stays.
    private static func keptText(
        of scalars: Substring.UnicodeScalarView,
        without removed: [TagMarker]
    ) -> String.UnicodeScalarView {
        var kept = String.UnicodeScalarView()
        var index = scalars.startIndex
        for marker in removed {
            kept.append(contentsOf: scalars[index..<marker.range.lowerBound])
            index = marker.range.upperBound
            if index < scalars.endIndex, scalars[index] == adjacentSpace {
                index = scalars.index(after: index)
            } else if kept.last == adjacentSpace {
                kept.removeLast()
            }
        }
        kept.append(contentsOf: scalars[index...])
        return kept
    }
}

// MARK: - Line kinds

extension Substring {
    /// `true` when the text, after its leading whitespace, opens or closes a fenced code block.
    fileprivate var isFenceLine: Bool {
        TagMarkers.fencePrefixes.contains { prefix in hasPrefix(prefix) }
    }

    /// `true` when the text, after its leading whitespace, is a Markdown heading, for example `# Title` or `##`. A
    /// `#` followed by a letter, for example `#bug`, is a marker, not a heading.
    fileprivate var isHeadingLine: Bool {
        guard first == TagMarkers.headingPrefix else {
            return false
        }
        guard let next = dropFirst().first else {
            return true
        }
        return next == TagMarkers.headingPrefix || next == TagMarkers.headingSeparator
    }
}

// MARK: - Resolve

extension Graph {
    /// Gives the tags of a task at read time: `resolve(tags edges) ∪ resolve(#markers in the body)` (plan.md §6.1).
    ///
    /// The edges come first, in their stored order, and then the markers, in text order. The resolve of each edge and
    /// each marker follows the rename redirect (``renameTarget(ofTagAt:)``). A resolve that ends at a tombstone drops
    /// the tag. An edge or a marker to a tag that the graph does not have gives no tag. A tag is in the result one
    /// time.
    ///
    /// - Parameter task: The task, as this graph stores it, so that its edges hold slots.
    /// - Returns: The slots of the live tags of the task.
    func tagSlots(of task: TaskNode) -> [Int] {
        let edgeSlots = task.tags.compactMap { edge -> Int? in
            guard case .slot(let slot) = edge else {
                return nil
            }
            return slot
        }
        let markerSlots = TagMarkers.slugs(in: task.fields.body).compactMap { slug in
            slot(for: .tag(slug: slug.value))
        }
        return Array(OrderedSet((edgeSlots + markerSlots).compactMap(liveTagSlot(redirectedFrom:))))
    }

    /// Gives the tags that `Board.tags` lists (plan.md §6.2): each live tag with no rename, and each live tag where a
    /// rename cycle from a merge stops.
    ///
    /// These are the tags whose rename target is the tag itself. A tag with no rename is its own target, and the walk
    /// from a tag in a cycle stops at that tag.
    var boardTagSlots: [Int] {
        allSlots.filter { slot in
            liveTagSlot(redirectedFrom: slot) == slot
        }
    }

    /// Follows the `renamedTo` edges from a tag to the tag at the end of the chain (plan.md §6.2, §5.3 step 5).
    ///
    /// A tag with no `renamedTo` is the end. In a cycle from a merge, the walk stops at the first slug that repeats,
    /// and uses that tag. The walk also follows a tombstone, so that the caller can find a deleted target.
    ///
    /// - Parameter start: The slot of the first tag.
    /// - Returns: The slot of the tag at the end, or `nil` when a slot on the walk holds no tag, or a `renamedTo`
    ///   edge has no target in the graph.
    func renameTarget(ofTagAt start: Int) -> Int? {
        var visited: Set<Int> = []
        var current = start
        while visited.insert(current).inserted {
            guard let currentTag = tag(at: current) else {
                return nil
            }
            switch currentTag.renamedTo {
            case nil:
                return current
            case .slot(let next)?:
                current = next
            case .unresolved?:
                return nil
            }
        }
        return current
    }

    /// Follows the rename redirect from a tag, and keeps the result only when it is a live tag.
    ///
    /// - Parameter slot: The slot of the first tag.
    /// - Returns: The slot of the live tag at the end of the walk, or `nil` when the walk ends at a tombstone or
    ///   ends with no tag.
    private func liveTagSlot(redirectedFrom slot: Int) -> Int? {
        guard let target = renameTarget(ofTagAt: slot), tag(at: target)?.fields.isDeleted == false else {
            return nil
        }
        return target
    }

    /// Gives the tag in a slot.
    ///
    /// - Parameter slot: A slot that this graph gave.
    /// - Returns: The tag, or `nil` when the slot holds no node or a node that is not a tag.
    private func tag(at slot: Int) -> TagNode? {
        guard case .tag(let tag) = node(at: slot) else {
            return nil
        }
        return tag
    }
}
