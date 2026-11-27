import Foundation

/// One checklist item of the Markdown body of a task (plan.md §6, Progress; divergence.md §30).
///
/// A checklist line, after its leading whitespace, is a box marker alone, or a box marker and a space before more
/// text. The open box is `- [ ]`, and the checked box is `- [x]` or `- [X]`. These are the rules of the Rust
/// `parse_checklist_counts`. ``TaskProgress`` counts these items, and `updateChecklistItem` changes one of them, so
/// the two always agree. A line in a fenced code block counts, the same as in Rust.
struct ChecklistItem: Hashable, Sendable {
    /// The marker of an open checklist item.
    static let openMarker = "- [ ]"

    /// The marker that a check writes.
    static let checkedMarker = "- [x]"

    /// The markers of a checked checklist item.
    static let checkedMarkers = [checkedMarker, "- [X]"]

    /// The character between a checklist marker and the text of its item.
    static let markerSeparator = " "

    /// The place of the item among the items of the body, from 0.
    let index: Int

    /// The index of the line of the item in ``BodyLines/lines(of:)``.
    let line: Int

    /// The leading whitespace of the line.
    let indent: Substring

    /// The box marker of the item as the body writes it, for example `- [X]`.
    let marker: Substring

    /// The text after the marker and its separator. A bare box has an empty text.
    let text: Substring

    /// The line break of the line, or the empty text on the last line with no line break.
    let lineBreak: Substring

    /// `true` when the box of the item is checked.
    var isChecked: Bool {
        marker != Self.openMarker
    }
}

extension ChecklistItem {
    /// Gives the checklist items of a body.
    ///
    /// - Parameter body: The Markdown body of the task.
    /// - Returns: The items, in text order.
    static func items(of body: String) -> [ChecklistItem] {
        items(inLines: BodyLines.lines(of: body))
    }

    /// Gives the checklist items of the lines of a body.
    ///
    /// - Parameter lines: The lines of the body, from ``BodyLines/lines(of:)``.
    /// - Returns: The items, in text order. Each item has the index of its line in `lines`.
    static func items(inLines lines: [Substring]) -> [ChecklistItem] {
        lines.enumerated().reduce(into: []) { items, numbered in
            if let item = ChecklistItem(numbered.element, atLine: numbered.offset, index: items.count) {
                items.append(item)
            }
        }
    }

    /// Reads one line of a body as a checklist item.
    ///
    /// - Parameters:
    ///   - text: The line, with its line break.
    ///   - line: The index of the line.
    ///   - index: The place of the item among the items of the body.
    /// - Returns: `nil` when the line is not a checklist item.
    private init?(_ text: Substring, atLine line: Int, index: Int) {
        let content = BodyLines.content(of: text)
        let start = content.drop(while: \.isWhitespace)
        let markers = [Self.openMarker] + Self.checkedMarkers
        guard let marker = markers.first(where: { marker in start.hasPrefix(marker) }) else {
            return nil
        }
        let rest = start.dropFirst(marker.count)
        guard rest.isEmpty || rest.hasPrefix(Self.markerSeparator) else {
            return nil
        }
        self.init(
            index: index,
            line: line,
            indent: content[..<start.startIndex],
            marker: start.prefix(marker.count),
            text: rest.dropFirst(Self.markerSeparator.count),
            lineBreak: text[content.endIndex...]
        )
    }

    /// Gives the line of the item after a change of its state, its text, or both. The indent, the line break, and the
    /// marker of an unchanged state stay byte for byte. A new check writes ``checkedMarker``.
    ///
    /// - Parameters:
    ///   - isChecked: The new state, or `nil` for no change of the state.
    ///   - newText: The new text, or `nil` for no change of the text. An empty text gives a bare box.
    /// - Returns: The line, with its line break.
    func editedLine(checking isChecked: Bool?, text newText: String?) -> String {
        let changesState = isChecked.map { isChecked in isChecked != self.isChecked } ?? false
        let newMarker = changesState ? (self.isChecked ? Self.openMarker : Self.checkedMarker) : String(marker)
        let itemText = newText ?? String(text)
        let tail = itemText.isEmpty ? "" : Self.markerSeparator + itemText
        return String(indent) + newMarker + tail + lineBreak
    }
}
