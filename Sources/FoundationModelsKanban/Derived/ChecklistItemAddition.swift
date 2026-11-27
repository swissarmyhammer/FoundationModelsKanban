import Foundation

/// The text and the state of a new checklist item of `addChecklistItem`, after the forgiving read of the text
/// (divergence.md §31).
struct ChecklistItemDraft: Hashable, Sendable {
    /// The text of the item, after its box. It is not empty, and it has no line break.
    let text: String

    /// `true` when the box of the item is checked.
    let isChecked: Bool
}

extension ChecklistItemDraft {
    /// One box or bullet that the text of a new item can start with, and the state that it gives.
    private struct TextMarker {
        /// The marker, for example `- [x]` or `[ ]`.
        let marker: String

        /// The state that the marker gives, or `nil` for a bullet with no box.
        let isChecked: Bool?

        /// Reads the marker at the start of a text.
        ///
        /// - Parameter text: The text, with no white space around it.
        /// - Returns: The text after the marker, and the state of the marker. `nil` when the text does not start with
        ///   the marker alone, or with the marker and white space.
        func read(_ text: String) -> (text: Substring, isChecked: Bool?)? {
            guard text.hasPrefix(marker) else {
                return nil
            }
            let rest = text.dropFirst(marker.count)
            guard rest.first?.isWhitespace ?? true else {
                return nil
            }
            return (rest, isChecked)
        }
    }

    /// The bullet of a Markdown list item: the start of each list box, and a marker of its own.
    private static let bullet = "-"

    /// The boxes of a checklist line, for example `- [x]`, with the state of each box.
    private static let listBoxes = [TextMarker(marker: ChecklistItem.openMarker, isChecked: false)]
        + ChecklistItem.checkedMarkers.map { marker in TextMarker(marker: marker, isChecked: true) }

    /// The markers that a text can start with, in match order: the list boxes, the same boxes with no bullet, for
    /// example `[x]`, and the bullet alone. A box comes before the bullet, because the bullet is a prefix of the box.
    private static let textMarkers = listBoxes
        + listBoxes.map { box in
            TextMarker(
                marker: String(box.marker.dropFirst(bullet.count)).trimmingCharacters(in: .whitespaces),
                isChecked: box.isChecked
            )
        }
        + [TextMarker(marker: bullet, isChecked: nil)]

    /// Reads the text of a new item as the call wrote it. White space and line breaks around the text are removed. A
    /// box or a bullet at the start, for example `- [ ] `, `[x] `, or `- `, is removed, and a box gives the state when
    /// `checked` has no value.
    ///
    /// - Parameters:
    ///   - text: The text as the call wrote it.
    ///   - checked: The `checked` value of the call, or `nil` for no value.
    /// - Throws: ``KanbanError/multilineChecklistItemText(text:)`` when the text has a line break.
    ///   ``KanbanError/emptyChecklistItemText`` when no text stays after the marker.
    ///   ``KanbanError/conflictingChecklistItemState(text:checked:)`` when the box and `checked` give two states.
    init(reading text: String, checked: Bool?) throws(KanbanError) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isNewline) else {
            throw .multilineChecklistItemText(text: text)
        }
        let marked = Self.textMarkers.lazy.compactMap { marker in marker.read(trimmed) }.first
        let itemText = (marked?.text ?? Substring(trimmed)).trimmingCharacters(in: .whitespaces)
        guard !itemText.isEmpty else {
            throw .emptyChecklistItemText
        }
        let boxState = marked?.isChecked
        if let boxState, let checked, boxState != checked {
            throw .conflictingChecklistItemState(text: text, checked: checked)
        }
        self.init(text: itemText, isChecked: checked ?? boxState ?? false)
    }

    /// The checklist line of the item, with no line break.
    ///
    /// - Parameter indent: The leading white space of the line.
    /// - Returns: The line, for example `  - [ ] Add a test`.
    func line(indentedBy indent: Substring) -> String {
        let marker = isChecked ? ChecklistItem.checkedMarker : ChecklistItem.openMarker
        return indent + marker + ChecklistItem.markerSeparator + text
    }
}

/// The body after `addChecklistItem` adds one checklist item, and the facts of the new item (divergence.md §31).
///
/// The place of the new item, in order of the rules:
///
/// - `before` alone: before the line of that item.
/// - `after` alone: after the line of that item.
/// - `before` and `after` that name two items next to each other: after the line of the `after` item.
/// - Neither: after the line of the last checklist item.
/// - Neither, in a body with no checklist item: at the end of the body, after one blank line when the body is not
///   empty.
///
/// The new item gets the indent of the item that names its place. Each other line stays byte for byte.
struct ChecklistItemAddition: Hashable, Sendable {
    /// The body with the new item.
    let body: String

    /// The index of the new item among the items of the new body, from 0.
    let index: Int

    /// The other items whose text is the same as the text of the new item, with case and white space ignored, with
    /// their indexes in the new body. A later text ref of the new item matches these items too.
    let sameText: [KanbanError.ChecklistMatch]
}

extension ChecklistItemAddition {
    /// The input field of the item to put the new item before.
    static let beforeField = "before"

    /// The input field of the item to put the new item after.
    static let afterField = "after"

    /// The line break of a new line, when the item that names the place has no line break.
    private static let lineBreak = "\n"

    /// The line breaks between the text of a body with no checklist and the new item: one blank line.
    private static let blankLineBreakCount = 2

    /// The place of the new item in the body.
    private enum Place {
        /// Before the line of the item.
        case before(ChecklistItem)

        /// After the line of the item.
        case after(ChecklistItem)

        /// At the end of a body with no checklist item.
        case endOfBody
    }

    /// Adds one item to a body.
    ///
    /// - Parameters:
    ///   - draft: The new item.
    ///   - body: The current body of the task.
    ///   - before: The ref of the item to put the new item before, or `nil` for none.
    ///   - after: The ref of the item to put the new item after, or `nil` for none.
    ///   - task: The task ref as the call wrote it, for an error.
    /// - Throws: The errors of ``ChecklistItemMatch/item(for:among:ofTask:field:)`` for `before` and `after`.
    ///   ``KanbanError/conflictingChecklistPlacement(task:before:after:)`` when the two items are not next to each
    ///   other.
    init(
        adding draft: ChecklistItemDraft,
        to body: String,
        before: String?,
        after: String?,
        ofTask task: String
    ) throws(KanbanError) {
        let lines = BodyLines.lines(of: body)
        let items = ChecklistItem.items(inLines: lines)
        let place = try Self.place(before: before, after: after, among: items, ofTask: task)
        let addition = Self.inserting(draft, at: place, in: lines, of: body)
        let sameText = ChecklistItemMatch.items(withTextLike: draft.text, among: items).map { item in
            let newIndex = item.index < addition.index ? item.index : item.index + 1
            return KanbanError.ChecklistMatch(index: newIndex, text: String(item.text))
        }
        self.init(body: addition.body, index: addition.index, sameText: sameText)
    }

    /// Puts the line of a new item at its place.
    ///
    /// - Parameters:
    ///   - draft: The new item.
    ///   - place: The place of the new item.
    ///   - lines: The lines of the body, from ``BodyLines/lines(of:)``.
    ///   - body: The body.
    /// - Returns: The body with the new item, and the index of the new item.
    private static func inserting(
        _ draft: ChecklistItemDraft,
        at place: Place,
        in lines: [Substring],
        of body: String
    ) -> (body: String, index: Int) {
        switch place {
        case .before(let item):
            let line = draft.line(indentedBy: item.indent) + lineBreak(of: item)
            return (inserting(line, atLine: item.line, of: lines), item.index)
        case .after(let item):
            let content = draft.line(indentedBy: item.indent)
            let line = item.lineBreak.isEmpty ? lineBreak + content : content + item.lineBreak
            return (inserting(line, atLine: item.line + 1, of: lines), item.index + 1)
        case .endOfBody:
            return (appending(draft.line(indentedBy: ""), to: body), .zero)
        }
    }

    /// Finds the place of the new item.
    ///
    /// - Parameters:
    ///   - before: The `before` ref, or `nil` for none.
    ///   - after: The `after` ref, or `nil` for none.
    ///   - items: The checklist items of the body.
    ///   - task: The task ref as the call wrote it, for an error.
    /// - Returns: The place.
    /// - Throws: The errors of the match of each ref, and
    ///   ``KanbanError/conflictingChecklistPlacement(task:before:after:)``.
    private static func place(
        before: String?,
        after: String?,
        among items: [ChecklistItem],
        ofTask task: String
    ) throws(KanbanError) -> Place {
        let next = try match(of: before, among: items, ofTask: task, field: beforeField)
        let previous = try match(of: after, among: items, ofTask: task, field: afterField)
        switch (previous, next) {
        case (nil, nil):
            return items.last.map(Place.after) ?? .endOfBody
        case (let previous?, nil):
            return .after(previous.item)
        case (nil, let next?):
            return .before(next.item)
        case (let previous?, let next?):
            guard previous.item.index + 1 == next.item.index else {
                throw .conflictingChecklistPlacement(task: task, before: next.reference, after: previous.reference)
            }
            return .after(previous.item)
        }
    }

    /// Finds the item of an optional ref.
    ///
    /// - Parameters:
    ///   - reference: The ref, or `nil` for none.
    ///   - items: The checklist items of the body.
    ///   - task: The task ref as the call wrote it, for an error.
    ///   - field: The input field of the ref, for an error.
    /// - Returns: The ref and its item, or `nil` for no ref.
    /// - Throws: The errors of ``ChecklistItemMatch/item(for:among:ofTask:field:)``.
    private static func match(
        of reference: String?,
        among items: [ChecklistItem],
        ofTask task: String,
        field: String
    ) throws(KanbanError) -> (reference: String, item: ChecklistItem)? {
        guard let reference else {
            return nil
        }
        return (reference, try ChecklistItemMatch.item(for: reference, among: items, ofTask: task, field: field))
    }

    /// Gives the line break of a new line next to an item: the line break of the item, or ``lineBreak`` when the item
    /// is on the last line and has none.
    ///
    /// - Parameter item: The item.
    /// - Returns: The line break.
    private static func lineBreak(of item: ChecklistItem) -> String {
        item.lineBreak.isEmpty ? lineBreak : String(item.lineBreak)
    }

    /// Puts a new line in a body.
    ///
    /// - Parameters:
    ///   - line: The new text, with its line breaks.
    ///   - position: The index of the line that the new text goes before. The count of the lines puts it at the end.
    ///   - lines: The lines of the body, from ``BodyLines/lines(of:)``.
    /// - Returns: The body with the new text.
    private static func inserting(_ line: String, atLine position: Int, of lines: [Substring]) -> String {
        lines[..<position].joined() + line + lines[position...].joined()
    }

    /// Puts a new item at the end of a body with no checklist item, after one blank line when the body is not empty.
    /// A body that ends with a line break keeps a line break at its end.
    ///
    /// - Parameters:
    ///   - line: The checklist line of the item, with no line break.
    ///   - body: The body.
    /// - Returns: The body with the new item.
    private static func appending(_ line: String, to body: String) -> String {
        guard !body.isEmpty else {
            return line
        }
        let trailingBreakCount = body.reversed().prefix(while: \.isNewline).count
        let separator = String(repeating: lineBreak, count: max(.zero, blankLineBreakCount - trailingBreakCount))
        let end = trailingBreakCount == .zero ? "" : lineBreak
        return body + separator + line + end
    }
}
