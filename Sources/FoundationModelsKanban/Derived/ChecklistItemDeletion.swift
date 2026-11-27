import Foundation

/// The line remove of `deleteChecklistItem` (divergence.md §32).
///
/// The remove takes away the line of one item, with its indent and its line break. Each other line stays byte for
/// byte. When the line of the item is the last line and has no line break, the line break of the line before it also
/// goes away, so that the body does not end with a new empty line. This is the rule of
/// ``DependencyMarkers/removing(markersOf:from:)``.
enum ChecklistItemDeletion {
    /// Gives the body after the remove of one checklist item.
    ///
    /// - Parameters:
    ///   - body: The current body of the task.
    ///   - reference: The item ref as the call wrote it.
    ///   - task: The task ref as the call wrote it, for an error.
    /// - Returns: The new body.
    /// - Throws: The errors of ``ChecklistItemMatch/item(for:among:ofTask:field:)``.
    static func body(_ body: String, removing reference: String, ofTask task: String) throws(KanbanError) -> String {
        let lines = BodyLines.lines(of: body)
        let item = try ChecklistItemMatch.item(for: reference, among: ChecklistItem.items(inLines: lines), ofTask: task)
        let kept = lines.indices.filter { line in line != item.line }.map { line in lines[line] }
        guard item.lineBreak.isEmpty, let previous = kept.last else {
            return kept.joined()
        }
        return kept.dropLast().joined() + BodyLines.content(of: previous)
    }
}
