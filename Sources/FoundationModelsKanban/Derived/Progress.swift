import Foundation

/// The progress of a task: the counts of the Markdown checklist lines in its body (plan.md §4.1, §6, Progress).
///
/// A checklist line, after its leading whitespace, is a box marker alone, or a box marker and a space before more
/// text. The open box is `- [ ]`, and the checked box is `- [x]` or `- [X]`. These are the rules of the Rust
/// `parse_checklist_counts`. The type is not named `Progress`, because Foundation has a type with that name.
struct TaskProgress: Hashable, Sendable {
    /// The marker of an open checklist item.
    private static let openMarker = "- [ ]"

    /// The markers of a checked checklist item.
    private static let checkedMarkers = ["- [x]", "- [X]"]

    /// The number of checklist lines.
    let total: Int

    /// The number of checked checklist lines.
    let completed: Int

    /// The part of the checklist that is checked, from 0 to 1. A body with no checklist line gives 0.
    var fraction: Double {
        guard total > .zero else {
            return .zero
        }
        return Double(completed) / Double(total)
    }
}

extension TaskProgress {
    /// Counts the checklist lines of a body.
    ///
    /// - Parameter body: The Markdown body of the task.
    init(of body: String) {
        let lines = BodyLines.lines(of: body).map { line in
            BodyLines.content(of: line).drop(while: \.isWhitespace)
        }
        let checked = lines.filter { line in
            Self.checkedMarkers.contains { marker in line.startsChecklistItem(withMarker: marker) }
        }
        let open = lines.filter { line in
            line.startsChecklistItem(withMarker: Self.openMarker)
        }
        self.init(total: open.count + checked.count, completed: checked.count)
    }
}

extension Substring {
    /// The character between a checklist marker and the text of its item.
    private static let checklistMarkerSeparator = " "

    /// Tells if this line is a checklist item with a marker.
    ///
    /// - Parameter marker: The marker, for example `- [ ]`.
    /// - Returns: `true` when the line is the marker alone, or the marker and a space before more text. The line must
    ///   not have its leading whitespace or its line break.
    fileprivate func startsChecklistItem(withMarker marker: String) -> Bool {
        self == marker || hasPrefix(marker + Self.checklistMarkerSeparator)
    }
}
