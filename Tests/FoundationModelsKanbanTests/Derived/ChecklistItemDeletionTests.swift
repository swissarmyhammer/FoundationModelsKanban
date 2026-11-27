import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the line remove of `deleteChecklistItem` (``ChecklistItemDeletion``, divergence.md §32): the remove takes
/// away the line of one item and its line break, and each other line stays byte for byte.
@Suite("Checklist item deletion")
struct ChecklistItemDeletionTests {
    /// The task ref of the errors.
    static let task = "^aaaaaaa"

    /// The body of most tests: three open items.
    static let threeOpenItems = "- [ ] one\n- [ ] two\n- [ ] three"

    /// Gives the body after the remove of one item.
    ///
    /// - Parameters:
    ///   - reference: The item ref.
    ///   - body: The body before the remove.
    /// - Returns: The body after the remove.
    /// - Throws: The ``KanbanError`` of the remove.
    static func body(removing reference: String, from body: String = threeOpenItems) throws -> String {
        try ChecklistItemDeletion.body(body, removing: reference, ofTask: task)
    }

    /// Gives the error of a remove that must fail.
    ///
    /// - Parameters:
    ///   - reference: The item ref.
    ///   - body: The body before the remove.
    /// - Returns: The error.
    static func error(removing reference: String, from body: String) throws -> KanbanError {
        try KanbanErrorCapture.error { try Self.body(removing: reference, from: body) }
    }

    /// Gives the error items of the texts, with their indexes.
    ///
    /// - Parameter texts: The texts of the items, in text order.
    /// - Returns: The items of an error.
    static func matches(_ texts: [String]) -> [KanbanError.ChecklistMatch] {
        texts.enumerated().map { index, text in KanbanError.ChecklistMatch(index: index, text: text) }
    }

    // MARK: - Place of the item

    @Test("The remove of the first item keeps each other line")
    func firstItemRemoved() throws {
        #expect(try Self.body(removing: "one") == "- [ ] two\n- [ ] three")
    }

    @Test("The remove of a middle item keeps each other line")
    func middleItemRemoved() throws {
        #expect(try Self.body(removing: "two") == "- [ ] one\n- [ ] three")
    }

    @Test("The remove of the last line also removes the line break before it")
    func lastLineRemovesLineBreakBefore() throws {
        #expect(try Self.body(removing: "three") == "- [ ] one\n- [ ] two")
    }

    @Test("The remove of a last item with a line break keeps the line break of the line before it")
    func lastItemWithLineBreakKeepsLineBreakBefore() throws {
        #expect(try Self.body(removing: "two", from: "- [ ] one\n- [ ] two\n") == "- [ ] one\n")
    }

    @Test("The remove of the only line gives an empty body", arguments: ["- [ ] one", "- [ ] one\n"])
    func onlyLineGivesEmptyBody(body: String) throws {
        #expect(try Self.body(removing: "one", from: body) == "")
    }

    @Test("The remove keeps the text lines and the other items byte for byte")
    func otherLinesStay() throws {
        let body = "Intro  \r\n\n  - [X] one\n- [ ] two\nEnd"
        #expect(try Self.body(removing: "two", from: body) == "Intro  \r\n\n  - [X] one\nEnd")
    }

    @Test("The remove of an indented item takes its indent too")
    func indentedItemRemoved() throws {
        let body = "- [ ] parent\n  - [ ] child\n- [ ] next"
        #expect(try Self.body(removing: "child", from: body) == "- [ ] parent\n- [ ] next")
    }

    // MARK: - Ref

    @Test("An index names the item")
    func indexNamesItem() throws {
        #expect(try Self.body(removing: "1") == "- [ ] one\n- [ ] three")
    }

    @Test("A part of the text names the item")
    func partOfTextNamesItem() throws {
        #expect(try Self.body(removing: "HRE") == "- [ ] one\n- [ ] two")
    }

    // MARK: - Errors

    @Test("A ref that names no item gives NOT_FOUND with the current items")
    func noMatchGivesNotFound() throws {
        let expected = KanbanError.checklistItemNotFound(
            task: Self.task,
            item: "nine",
            items: Self.matches(["one", "two", "three"])
        )
        #expect(try Self.error(removing: "nine", from: Self.threeOpenItems) == expected)
    }

    @Test("A ref that names two items gives AMBIGUOUS_ITEM")
    func twoMatchesGiveAmbiguousItem() throws {
        let expected = KanbanError.ambiguousChecklistItem(
            task: Self.task,
            item: "same",
            matches: Self.matches(["same", "same"])
        )
        #expect(try Self.error(removing: "same", from: "- [ ] same\n- [x] same") == expected)
    }

    @Test("A body with no checklist item gives NOT_FOUND with no items")
    func noChecklistGivesNotFound() throws {
        let expected = KanbanError.checklistItemNotFound(task: Self.task, item: "0", items: [])
        #expect(try Self.error(removing: "0", from: "Only text\n") == expected)
    }
}
