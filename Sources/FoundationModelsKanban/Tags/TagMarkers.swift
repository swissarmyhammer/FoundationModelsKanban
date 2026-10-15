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
/// then an ASCII letter or digit, then more ASCII letters, digits, and ``slugPunctuation``. The `#` must not follow an
/// ASCII letter, an ASCII digit, or `_`. The Rust parse keeps the case of the text. This parse changes each marker to
/// its slug, so a marker names the same tag as the tag name rule gives (plan.md §3.2). The Rust parse stops a marker
/// at `_`. This parse does not, because the tag name rule writes `_` for each run of spaces (plan.md §6): the marker
/// `#needs_review` names the tag `needs review`, with the slug `needs-review`.
///
/// A marker in a fence line, in a fenced code block, in a heading line, or in inline code is not a tag
/// (``MarkdownCode``).
enum TagMarkers {
    /// The scalar that starts a marker.
    static let markerPrefix: Unicode.Scalar = "#"

    /// The scalar, other than an ASCII letter or digit, that glues a `#` to the word before it.
    static let wordJoiner: Unicode.Scalar = "_"

    /// The characters, other than an ASCII letter or digit, that the slug text of a marker can hold: the slug
    /// separator, and the character that the tag name rule writes for each run of spaces. Thus the text of each tag
    /// name is one marker.
    static let slugPunctuation: Set<Character> = [Slug.separator, TagName.spaceReplacement]

    /// The space that a remove takes away together with the marker, so that the text keeps no double space.
    static let adjacentSpace: Unicode.Scalar = " "

    /// Finds the slug of each marker in a body.
    ///
    /// - Parameter body: The Markdown body of a task.
    /// - Returns: The slugs, in text order. Each slug is in the result one time.
    static func slugs(in body: String) -> [Slug] {
        let found = MarkdownCode.markerBearingLines(of: body).flatMap { text in
            markers(inLine: text).map(\.slug)
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
        MarkdownCode.editingMarkerBearingLines(of: body) { line in
            editedLine(from: line, removingMarkersOf: slug)
        }
    }
}

// MARK: - Find

extension TagMarkers {
    /// Finds each marker in the text of one line that counts as a tag.
    ///
    /// - Parameter text: The text of the line, without its line break.
    /// - Returns: The markers, in text order. A marker in inline code is not in the result.
    private static func markers(inLine text: Substring) -> [TagMarker] {
        MarkdownCode.proseRanges(inLine: text).flatMap { range in
            markers(inProse: text.unicodeScalars[range])
        }
    }

    /// Finds each marker in one part of a line that is not in inline code.
    ///
    /// - Parameter scalars: The scalars of the part. Its indices are the indices of the line.
    /// - Returns: The markers, in text order.
    private static func markers(inProse scalars: Substring.UnicodeScalarView) -> [TagMarker] {
        Array(
            sequence(state: scalars.startIndex) { start -> TagMarker? in
                guard let marker = nextMarker(in: scalars, from: start) else {
                    return nil
                }
                start = marker.range.upperBound
                return marker
            }
        )
    }

    /// Finds the first marker at or after an index.
    ///
    /// - Parameters:
    ///   - scalars: The scalars of one part of a line that is not in inline code.
    ///   - start: The index where the search starts.
    /// - Returns: The marker, or `nil` when the rest of the part has no marker.
    private static func nextMarker(in scalars: Substring.UnicodeScalarView, from start: String.Index) -> TagMarker? {
        scalars[start...].indices.lazy.compactMap { index in marker(in: scalars, at: index) }.first
    }

    /// Makes the marker that starts at an index, when one starts there.
    ///
    /// - Parameters:
    ///   - scalars: The scalars of one part of a line that is not in inline code.
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
    ///   - scalars: The scalars of one part of a line that is not in inline code. A `#` at the start of the part
    ///     follows no word.
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
    /// `true` when the scalar can be in the slug text of a marker: an ASCII letter, an ASCII digit, or a character of
    /// ``TagMarkers/slugPunctuation``.
    fileprivate var isMarkerSlugScalar: Bool {
        isASCIIAlphanumeric || TagMarkers.slugPunctuation.contains(Character(self))
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

// MARK: - Resolve

extension Graph {
    /// Gives the tags of a task at read time: `resolve(tags edges) ∪ resolve(#markers in the body)` (plan.md §6.1).
    ///
    /// The result is sorted by the slug of each tag, as the Rust kanban sorts the tags (divergence.md F9). The
    /// resolve of each edge and each marker follows the rename redirect (``renameTarget(ofTagAt:)``), and the sort
    /// uses the slug of the tag at the end of the redirect. A resolve that ends at a tombstone drops the tag. An edge
    /// or a marker to a tag that the graph does not have gives no tag. A tag is in the result one time.
    ///
    /// - Parameter task: The task, as this graph stores it, so that its edges hold slots.
    /// - Returns: The slots of the live tags of the task, in slug order.
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
        let liveSlots = OrderedSet((edgeSlots + markerSlots).compactMap(liveTagSlot(redirectedFrom:)))
        let liveTags = liveSlots.compactMap { slot in
            node(at: slot, as: TagNode.self).map { tag in (slot: slot, slug: tag.slug) }
        }
        return liveTags.sorted { left, right in left.slug < right.slug }.map(\.slot)
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
            guard let currentTag = node(at: current, as: TagNode.self) else {
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

    /// Follows the rename redirect from the local ref of a tag (plan.md §6.2).
    ///
    /// - Parameter ref: The local ref of the first tag.
    /// - Returns: The local ref of the tag at the end of the rename chain, live or tombstoned, or `ref` when the graph
    ///   does not have the tag or the walk ends with no tag.
    func tagRef(redirectedFrom ref: LocalRef) -> LocalRef {
        slot(for: ref).flatMap(renameTarget(ofTagAt:)).flatMap(node(at:))?.ref ?? ref
    }

    /// Follows the rename redirect from a tag, and keeps the result only when it is a live tag.
    ///
    /// - Parameter slot: The slot of the first tag.
    /// - Returns: The slot of the live tag at the end of the walk, or `nil` when the walk ends at a tombstone or
    ///   ends with no tag.
    private func liveTagSlot(redirectedFrom slot: Int) -> Int? {
        guard let target = renameTarget(ofTagAt: slot),
            node(at: target, as: TagNode.self)?.fields.isDeleted == false
        else {
            return nil
        }
        return target
    }
}
