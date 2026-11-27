import Foundation

/// The forgiving match of an item ref: the `item` of `updateChecklistItem`, and the `before` and the `after` of
/// `addChecklistItem` (divergence.md §30, §31).
///
/// The match tries each step in order, and the first step with one match wins:
///
/// 1. An index in range, from 0, with or without white space around it.
/// 2. The exact text of the item.
/// 3. The text with case and white space ignored.
/// 4. A prefix of the text, with case and white space ignored.
/// 5. A part of the text, with case and white space ignored.
///
/// A ref that is a full checklist line, for example `- [ ] Add a test`, names the item by its text. Two or more matches
/// at one step give ``KanbanError/ambiguousChecklistItem(task:item:matches:field:)``. No match at each step gives
/// ``KanbanError/checklistItemNotFound(task:item:items:field:)``. An empty ref names no item by text.
enum ChecklistItemMatch {
    /// Finds the item that a ref names.
    ///
    /// - Parameters:
    ///   - reference: The item ref as the caller wrote it.
    ///   - items: The checklist items of the body, from ``ChecklistItem/items(of:)``.
    ///   - task: The task ref as the caller wrote it, for an error.
    ///   - field: The input field of the ref, for an error.
    /// - Returns: The item.
    /// - Throws: ``KanbanError/ambiguousChecklistItem(task:item:matches:field:)`` when two or more items match at the
    ///   first step that has a match. ``KanbanError/checklistItemNotFound(task:item:items:field:)`` when no item
    ///   matches.
    static func item(
        for reference: String,
        among items: [ChecklistItem],
        ofTask task: String,
        field: String = KanbanError.checklistItemField
    ) throws(KanbanError) -> ChecklistItem {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = Int(trimmed), items.indices.contains(index) {
            return items[index]
        }
        for step in textSteps(for: itemText(of: trimmed)) {
            let matches = items.filter(step)
            if matches.count > 1 {
                let listed = matches.map(KanbanError.ChecklistMatch.init)
                throw .ambiguousChecklistItem(task: task, item: reference, matches: listed, field: field)
            }
            if let match = matches.first {
                return match
            }
        }
        let listed = items.map(KanbanError.ChecklistMatch.init)
        throw .checklistItemNotFound(task: task, item: reference, items: listed, field: field)
    }

    /// Gives the text steps of the match, in order: the exact text, the text with case and white space ignored, a
    /// prefix, and a part. An empty text gives no step.
    ///
    /// - Parameter text: The text of the ref.
    /// - Returns: The test of an item at each step.
    private static func textSteps(for text: String) -> [(ChecklistItem) -> Bool] {
        let key = comparisonKey(of: text)
        guard !key.isEmpty else {
            return []
        }
        return [
            { item in item.text == text },
            { item in hasSameText(item, key: key) },
            { item in comparisonKey(of: item.text).hasPrefix(key) },
            { item in comparisonKey(of: item.text).contains(key) },
        ]
    }

    /// Gives the item text of a ref: the text after the box marker when the ref is one checklist line, else the ref.
    ///
    /// - Parameter reference: The trimmed ref.
    /// - Returns: The text to match.
    private static func itemText(of reference: String) -> String {
        guard let item = ChecklistItem.items(of: reference).first, item.line == .zero else {
            return reference
        }
        return String(item.text)
    }

    /// Gives the items whose text is the same as a text, with case and white space ignored. A text ref of each of
    /// these items matches two or more items at the step of the text with case and white space ignored.
    ///
    /// - Parameters:
    ///   - text: The text.
    ///   - items: The checklist items of the body.
    /// - Returns: The items with the same text, in text order.
    static func items(withTextLike text: String, among items: [ChecklistItem]) -> [ChecklistItem] {
        let key = comparisonKey(of: text)
        return items.filter { item in hasSameText(item, key: key) }
    }

    /// Tells if the text of an item is the same as a text, with case and white space ignored.
    ///
    /// - Parameters:
    ///   - item: The checklist item.
    ///   - key: The ``comparisonKey(of:)`` of the text.
    /// - Returns: True when the comparison key of the item text is the key.
    private static func hasSameText(_ item: ChecklistItem, key: String) -> Bool {
        comparisonKey(of: item.text) == key
    }

    /// Gives the form of a text for a match with case and white space ignored.
    ///
    /// - Parameter text: The text.
    /// - Returns: The text in lowercase, with no white space.
    private static func comparisonKey(of text: some StringProtocol) -> String {
        String(text.lowercased().filter { character in !character.isWhitespace })
    }
}
