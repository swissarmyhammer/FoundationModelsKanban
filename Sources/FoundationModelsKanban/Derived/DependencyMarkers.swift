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

/// Finds and removes the dependency markers of a task body (plan.md §6.1, §12 item 7).
///
/// Only a full task URL is a marker. A short id, `^short`, a bare ULID, or a URL to a node that is not a task is
/// plain text. The text keeps the URL as the agent wrote it: the tool does not rewrite it.
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
        urlRanges(in: body).compactMap { range in
            marker(in: body, at: range)
        }
    }

    /// Removes each marker of one task from a body.
    ///
    /// The `updateTask(dependsOn:)` mutation uses it when it removes a dependency whose URL is also in the text. A
    /// line with no marker of the task stays the same, byte for byte. A line that loses a marker loses its trailing
    /// whitespace. When the last line has no line break and the remove makes it empty, the line break before it also
    /// goes away. These are the ``BodyLines`` rules.
    ///
    /// - Parameters:
    ///   - uri: The URI of the task whose markers to remove.
    ///   - body: The Markdown body of a task.
    /// - Returns: The body without the markers of the task.
    static func removing(markersOf uri: NodeURI, from body: String) -> String {
        let lines = BodyLines.lines(of: body)
        let edits = lines.map { line in
            editedLine(line, removingMarkersOf: uri)
        }
        return BodyLines.body(joining: lines, with: edits)
    }
}

// MARK: - Find

extension DependencyMarkers {
    /// Finds the range of each URL text that starts with the scheme.
    ///
    /// - Parameter body: The body to search.
    /// - Returns: The ranges, in text order. A range can hold a URL that is not a valid task URL.
    private static func urlRanges(in body: String) -> some Sequence<Range<String.Index>> {
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
    private static func urlEnd(in body: String, from start: String.Index) -> String.Index {
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
    private static func marker(in body: String, at range: Range<String.Index>) -> DependencyMarker? {
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
        let text = String(BodyLines.content(of: line))
        let ranges = all(in: text).filter { marker in marker.uri == uri }.map(\.range)
        guard !ranges.isEmpty else {
            return nil
        }
        var kept = text
        kept.removeSubranges(RangeSet(ranges))
        return BodyLines.editedLine(withText: kept, replacing: line)
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
