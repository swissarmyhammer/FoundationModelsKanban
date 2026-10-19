import Foundation
import OrderedCollections

/// One dependency marker in a task body: a full `kanban://<board-key>/task/<ULID>` URL (plan.md §6.1).
struct DependencyMarker: Hashable, Sendable {
    /// The URI of the task that the marker names. The board key can be the key of this board or of a different
    /// board.
    let uri: NodeURI

    /// The range of the URL text in the body.
    let range: Range<String.Index>
}

/// Finds, removes, and replaces the dependency markers of a task body (plan.md §6.1, §12 item 7).
///
/// Only a full task URL is a marker. A short id, `^short`, a bare ULID, or a URL to a node that is not a task is
/// plain text. The text keeps the URL as the agent wrote it: only `repairLinks` rewrites a URL with an old board name
/// (divergence.md M9).
///
/// A URL in a fence line, in a fenced code block, in a heading line, or in inline code is not a marker
/// (``MarkdownCode``). Thus an example URL in a code block does not block a task, and does not make a cycle.
enum DependencyMarkers {
    /// The characters that end the URL text of a marker: Markdown and quote delimiters around a link.
    static let delimiters: Set<Character> = ["<", ">", "(", ")", "[", "]", "{", "}", "\"", "'", "`", "|", "\\"]

    /// The punctuation at the end of a sentence. A URL does not end with it, so the marker stops before it.
    static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?"]

    /// Finds each dependency marker in a body, in text order.
    ///
    /// The scheme ignores case. The URL text ends at a whitespace or a ``delimiters`` character, and the
    /// ``trailingPunctuation`` at its end is not part of it. The URL must parse as a ``NodeURI`` to a task.
    ///
    /// - Parameter body: The Markdown body of a task.
    /// - Returns: The markers. The same task can have more than one marker.
    static func all(in body: String) -> [DependencyMarker] {
        MarkdownCode.markerBearingLines(of: body).flatMap(markers(inLine:))
    }

    /// Removes each marker of one task from a body.
    ///
    /// The `updateTask(dependsOn:)` mutation uses it when it removes a dependency whose URL is also in the text. A URL
    /// that is not a marker, for example a URL in a code block, stays. A line with no marker of the task stays the
    /// same, byte for byte. A line that loses a marker loses its trailing whitespace. When the last line has no line
    /// break and the remove makes it empty, the line break before it also goes away. These are the ``BodyLines``
    /// rules.
    ///
    /// - Parameters:
    ///   - uri: The URI of the task whose markers to remove.
    ///   - body: The Markdown body of a task.
    /// - Returns: The body without the markers of the task.
    static func removing(markersOf uri: NodeURI, from body: String) -> String {
        MarkdownCode.editingMarkerBearingLines(of: body) { line in
            editedLine(line, removingMarkersOf: uri)
        }
    }
}

// MARK: - Find

extension DependencyMarkers {
    /// Finds each marker in the text of one line where a marker can count.
    ///
    /// - Parameter text: The text of the line, without its line break.
    /// - Returns: The markers, in text order. A URL in inline code is not in the result.
    private static func markers(inLine text: Substring) -> [DependencyMarker] {
        MarkdownCode.proseRanges(inLine: text).flatMap { range in
            let prose = Substring(text.unicodeScalars[range])
            return urlRanges(in: prose).compactMap { urlRange in
                marker(in: prose, at: urlRange)
            }
        }
    }

    /// Finds the range of each marker of one task in the text of one line.
    ///
    /// The remove and the replace of the markers of a task both use it, so the two edits find the same markers.
    ///
    /// - Parameters:
    ///   - uri: The URI of the task whose markers to find.
    ///   - text: The text of the line, without its line break.
    /// - Returns: The ranges, in text order. The result is empty when the line has no marker of the task.
    private static func markerRanges(of uri: NodeURI, inLine text: Substring) -> [Range<String.Index>] {
        markers(inLine: text).filter { marker in marker.uri == uri }.map(\.range)
    }

    /// Finds the range of each URL text that starts with the scheme.
    ///
    /// - Parameter body: The text to search. Its indices are the indices of the body.
    /// - Returns: The ranges, in text order. A range can hold a URL that is not a valid task URL.
    private static func urlRanges(in body: Substring) -> some Sequence<Range<String.Index>> {
        sequence(state: body.startIndex) { start -> Range<String.Index>? in
            guard
                let scheme = body.range(of: NodeURI.scheme, options: .caseInsensitive, range: start..<body.endIndex)
            else {
                return nil
            }
            let end = urlEnd(in: body, from: scheme.upperBound)
            start = end
            return scheme.lowerBound..<end
        }
    }

    /// Finds the end of a URL text.
    ///
    /// - Parameters:
    ///   - body: The body that holds the URL.
    ///   - start: The index after the scheme of the URL.
    /// - Returns: The index after the last character of the URL.
    private static func urlEnd(in body: Substring, from start: String.Index) -> String.Index {
        let tail = body[start...]
        let token = tail.prefix { character in
            !character.isWhitespace && !delimiters.contains(character)
        }
        let kept = token.reversed().drop { character in
            trailingPunctuation.contains(character)
        }
        return body.index(start, offsetBy: kept.count)
    }

    /// Makes the marker of one URL text, when the text is a full task URL.
    ///
    /// - Parameters:
    ///   - body: The body that holds the URL.
    ///   - range: The range of the URL text.
    /// - Returns: The marker, or `nil` when the text is not a valid URI or names a node that is not a task.
    private static func marker(in body: Substring, at range: Range<String.Index>) -> DependencyMarker? {
        guard let uri = try? NodeURI(parsing: String(body[range])), case .task = uri.ref else {
            return nil
        }
        return DependencyMarker(uri: uri, range: range)
    }
}

// MARK: - Remove

extension DependencyMarkers {
    /// Removes the markers of one task from one line.
    ///
    /// - Parameters:
    ///   - line: The line, with its line break.
    ///   - uri: The URI of the task whose markers to remove.
    /// - Returns: The changed line with its line break, or `nil` when the line has no marker of the task.
    private static func editedLine(_ line: Substring, removingMarkersOf uri: NodeURI) -> String? {
        let text = BodyLines.content(of: line)
        let ranges = markerRanges(of: uri, inLine: text)
        guard !ranges.isEmpty else {
            return nil
        }
        var kept = text
        kept.removeSubranges(RangeSet(ranges))
        return BodyLines.editedLine(withText: kept, replacing: line)
    }
}

// MARK: - Replace

extension DependencyMarkers {
    /// Replaces each marker of one task in a body with the URL of a different URI.
    ///
    /// The `repairLinks` mutation uses it when it rewrites a task URL with an old board name to the current name of
    /// the board (divergence.md M9). A URL that is not a marker, for example a URL in a code block, stays. A line with
    /// no marker of the task stays the same, byte for byte, and a changed line keeps its other text and its line break.
    ///
    /// - Parameters:
    ///   - old: The URI of the task whose markers to replace.
    ///   - new: The URI that each marker gets.
    ///   - body: The Markdown body of a task.
    /// - Returns: The body with the new URL in place of each marker of the old URI.
    static func replacing(markersOf old: NodeURI, with new: NodeURI, in body: String) -> String {
        MarkdownCode.editingMarkerBearingLines(of: body) { line in
            editedLine(line, replacingMarkersOf: old, with: new)
        }
    }

    /// Replaces the markers of one task in one line.
    ///
    /// - Parameters:
    ///   - line: The line, with its line break.
    ///   - old: The URI of the task whose markers to replace.
    ///   - new: The URI that each marker gets.
    /// - Returns: The changed line with its line break, or `nil` when the line has no marker of the task.
    private static func editedLine(
        _ line: Substring,
        replacingMarkersOf old: NodeURI,
        with new: NodeURI
    ) -> String? {
        let text = BodyLines.content(of: line)
        let ranges = markerRanges(of: old, inLine: text)
        guard let last = ranges.last else {
            return nil
        }
        let starts = [text.startIndex] + ranges.map(\.upperBound)
        let kept = zip(starts, ranges).map { start, range in String(text[start..<range.lowerBound]) }
        return kept.joined(separator: new.description) + new.description + text[last.upperBound...]
            + line[text.endIndex...]
    }
}

// MARK: - Resolve

extension Graph {
    /// Gives the dependencies of a task at read time: `resolve(dependsOn edges) ∪ resolve(markers in the body)`
    /// (plan.md §6.1).
    ///
    /// The edges come first, in their stored order, and then the markers, in text order. A target is in the result one
    /// time. A marker whose board key is the current key resolves in this board: to the slot of its task, or to an
    /// unresolved local ref when the graph has no live task for it. Each other marker is a cross-board ref
    /// (plan.md §6.6). A target that is not found counts as not done (plan.md §3.3, rule 4).
    ///
    /// - Parameters:
    ///   - task: The task, as this graph stores it, so that its edges hold slots.
    ///   - currentBoardKey: The current key of this board.
    /// - Returns: The targets of the dependencies.
    func dependencies(of task: TaskNode, inBoard currentBoardKey: String) -> [EdgeTarget] {
        let markerTargets = DependencyMarkers.all(in: task.fields.body).map { marker in
            edgeTarget(for: StoredRef(uri: marker.uri, inBoard: currentBoardKey))
        }
        return Array(OrderedSet(task.dependsOn + markerTargets))
    }

    /// Resolves a stored ref to the edge target that the graph gives it now.
    ///
    /// - Parameter ref: The stored ref.
    /// - Returns: The slot of a local ref whose node is live, else the unresolved ref.
    private func edgeTarget(for ref: StoredRef) -> EdgeTarget {
        guard case .local(let localRef) = ref, let slot = slot(for: localRef), node(at: slot) != nil else {
            return .unresolved(ref)
        }
        return .slot(slot)
    }
}
