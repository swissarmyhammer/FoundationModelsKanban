import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the forgiving read of the text of a new checklist item (``ChecklistItemDraft``) and the place of the new item
/// in the body (``ChecklistItemAddition``) of `addChecklistItem` (divergence.md §31).
@Suite("Checklist item addition")
struct ChecklistItemAdditionTests {
    /// The task ref of the errors.
    static let task = "^aaaaaaa"

    /// The body of most tests: two open items.
    static let twoOpenItems = "- [ ] one\n- [ ] two"

    /// The text of the new item of most tests.
    static let newText = "new"

    /// The open draft with ``newText``.
    static let openDraft = ChecklistItemDraft(text: newText, isChecked: false)

    /// Gives the body after the addition of ``openDraft``.
    ///
    /// - Parameters:
    ///   - body: The body before the addition.
    ///   - before: The `before` ref, or `nil` for none.
    ///   - after: The `after` ref, or `nil` for none.
    /// - Returns: The body after the addition.
    /// - Throws: The ``KanbanError`` of the addition.
    static func body(adding body: String, before: String? = nil, after: String? = nil) throws -> String {
        try addition(to: body, before: before, after: after).body
    }

    /// Gives the addition of ``openDraft`` to a body.
    ///
    /// - Parameters:
    ///   - body: The body before the addition.
    ///   - before: The `before` ref, or `nil` for none.
    ///   - after: The `after` ref, or `nil` for none.
    /// - Returns: The addition.
    /// - Throws: The ``KanbanError`` of the addition.
    static func addition(
        to body: String,
        before: String? = nil,
        after: String? = nil
    ) throws -> ChecklistItemAddition {
        try ChecklistItemAddition(adding: openDraft, to: body, before: before, after: after, ofTask: task)
    }

    /// Gives the error of a draft text that is not one item.
    ///
    /// - Parameters:
    ///   - text: The text as the call wrote it.
    ///   - checked: The `checked` value of the call.
    /// - Returns: The error.
    static func draftError(of text: String, checked: Bool? = nil) throws -> KanbanError {
        try KanbanErrorCapture.error { try ChecklistItemDraft(reading: text, checked: checked) }
    }

    // MARK: - Draft

    @Test("A plain text gives an open item with that text")
    func plainTextGivesOpenItem() throws {
        let draft = try ChecklistItemDraft(reading: "Add a test", checked: nil)
        #expect(draft == .init(text: "Add a test", isChecked: false))
    }

    @Test("checked: true gives a checked item")
    func checkedGivesCheckedItem() throws {
        #expect(try ChecklistItemDraft(reading: "a", checked: true) == .init(text: "a", isChecked: true))
    }

    @Test(
        "A marker at the start of the text is removed, and gives the state",
        arguments: [
            ("- [ ] a", false), ("- [x] a", true), ("- [X] a", true), ("[ ] a", false), ("[x] a", true),
            ("[X] a", true), ("- a", false),
        ]
    )
    func markerGivesState(text: String, isChecked: Bool) throws {
        #expect(try ChecklistItemDraft(reading: text, checked: nil) == .init(text: "a", isChecked: isChecked))
    }

    @Test("A marker and the same state in checked give that state")
    func markerAndSameState() throws {
        #expect(try ChecklistItemDraft(reading: "- [x] a", checked: true) == .init(text: "a", isChecked: true))
    }

    @Test("A text with no space after the dash keeps the dash")
    func dashWithoutSpaceStays() throws {
        #expect(try ChecklistItemDraft(reading: "-a", checked: nil).text == "-a")
    }

    @Test("White space and line breaks around the text are removed")
    func surroundingWhitespaceIsRemoved() throws {
        #expect(try ChecklistItemDraft(reading: "  a b \n", checked: nil).text == "a b")
    }

    @Test("A checked marker and checked: false give CONFLICTING_ITEM_STATE")
    func markerStateConflict() throws {
        let expected = KanbanError.conflictingChecklistItemState(text: "- [x] a", checked: false)
        #expect(try Self.draftError(of: "- [x] a", checked: false) == expected)
    }

    @Test("An empty text gives INVALID_ITEM_TEXT", arguments: ["", "  ", "- [ ]", "[x] "])
    func emptyTextIsInvalid(text: String) throws {
        #expect(try Self.draftError(of: text) == .emptyChecklistItemText)
    }

    @Test("A text with a line break gives INVALID_ITEM_TEXT")
    func multilineTextIsInvalid() throws {
        #expect(try Self.draftError(of: "a\nb") == .multilineChecklistItemText(text: "a\nb"))
    }

    // MARK: - End of the checklist

    @Test("No place puts the item after the last item, before the text after the checklist")
    func noPlaceGoesAfterLastItem() throws {
        let body = "intro\n- [ ] one\n- [ ] two\n\nmore"
        #expect(try Self.body(adding: body) == "intro\n- [ ] one\n- [ ] two\n- [ ] new\n\nmore")
    }

    @Test("No place on a last item with no line break adds a line break before the new item")
    func noPlaceAfterLastLine() throws {
        #expect(try Self.body(adding: Self.twoOpenItems) == "- [ ] one\n- [ ] two\n- [ ] new")
    }

    @Test("No place gives the new item the indent of the last item")
    func noPlaceKeepsIndentOfLastItem() throws {
        #expect(try Self.body(adding: "- [ ] a\n  - [ ] b\n") == "- [ ] a\n  - [ ] b\n  - [ ] new\n")
    }

    @Test("The index of an item at the end is the count of the items before it")
    func endIndexIsItemCount() throws {
        #expect(try Self.addition(to: Self.twoOpenItems).index == 2)
    }

    @Test("A checked draft writes the checked box")
    func checkedDraftWritesCheckedBox() throws {
        let draft = ChecklistItemDraft(text: Self.newText, isChecked: true)
        let addition = try ChecklistItemAddition(adding: draft, to: "", before: nil, after: nil, ofTask: Self.task)
        #expect(addition.body == "- [x] new")
    }

    // MARK: - No checklist

    @Test("An empty body becomes the new item")
    func emptyBodyBecomesItem() throws {
        #expect(try Self.body(adding: "") == "- [ ] new")
    }

    @Test(
        "A body with no checklist gets the item at its end, after one blank line",
        arguments: [
            ("Text", "Text\n\n- [ ] new"), ("Text\n", "Text\n\n- [ ] new\n"), ("Text\n\n", "Text\n\n- [ ] new\n"),
        ]
    )
    func bodyWithoutChecklistGetsItemAtEnd(body: String, expected: String) throws {
        #expect(try Self.body(adding: body) == expected)
    }

    // MARK: - Before and after

    @Test("before an index puts the item before that item")
    func beforeIndex() throws {
        #expect(try Self.body(adding: Self.twoOpenItems, before: "1") == "- [ ] one\n- [ ] new\n- [ ] two")
    }

    @Test("before a text puts the item before that item")
    func beforeText() throws {
        #expect(try Self.body(adding: Self.twoOpenItems, before: "one") == "- [ ] new\n- [ ] one\n- [ ] two")
    }

    @Test("after an index puts the item after that item")
    func afterIndex() throws {
        #expect(try Self.body(adding: Self.twoOpenItems, after: "0") == "- [ ] one\n- [ ] new\n- [ ] two")
    }

    @Test("after a text on the last line puts the item at the end")
    func afterTextOnLastLine() throws {
        #expect(try Self.body(adding: Self.twoOpenItems, after: "two") == "- [ ] one\n- [ ] two\n- [ ] new")
    }

    @Test("before gives the new item the indent of that item")
    func beforeKeepsIndent() throws {
        #expect(try Self.body(adding: "- [ ] a\n  - [ ] b", before: "b") == "- [ ] a\n  - [ ] new\n  - [ ] b")
    }

    @Test("The index of an item before an item is the index of that item")
    func beforeIndexIsItemIndex() throws {
        #expect(try Self.addition(to: Self.twoOpenItems, before: "two").index == 1)
    }

    @Test("before and after that name the same place put the item there")
    func beforeAndAfterSamePlace() throws {
        let body = try Self.body(adding: Self.twoOpenItems, before: "two", after: "one")
        #expect(body == "- [ ] one\n- [ ] new\n- [ ] two")
    }

    @Test("before and after that name different places give CONFLICTING_PLACEMENT")
    func beforeAndAfterDifferentPlaces() throws {
        let expected = KanbanError.conflictingChecklistPlacement(task: Self.task, before: "one", after: "two")
        #expect(throws: expected) { try Self.addition(to: Self.twoOpenItems, before: "one", after: "two") }
    }

    @Test("A before ref that names no item gives NOT_FOUND for the field before")
    func beforeNotFound() throws {
        let items = ["one", "two"].enumerated().map { index, text in
            KanbanError.ChecklistMatch(index: index, text: text)
        }
        let expected = KanbanError.checklistItemNotFound(task: Self.task, item: "nine", items: items, field: "before")
        #expect(throws: expected) { try Self.addition(to: Self.twoOpenItems, before: "nine") }
    }

    // MARK: - Same text

    @Test("An item with the same text, in a different case, is in sameText")
    func sameTextListsMatchingItems() throws {
        let addition = try Self.addition(to: "- [ ] New\n- [ ] other")
        #expect(addition.sameText == [KanbanError.ChecklistMatch(index: 0, text: "New")])
    }

    @Test("An item with the same text after the new item has its index in the new body")
    func sameTextHasIndexOfNewBody() throws {
        let addition = try Self.addition(to: "- [ ] new", before: "0")
        #expect(addition.sameText == [KanbanError.ChecklistMatch(index: 1, text: Self.newText)])
    }

    @Test("No item with the same text gives an empty sameText")
    func differentTextGivesNoSameText() throws {
        #expect(try Self.addition(to: Self.twoOpenItems).sameText.isEmpty)
    }
}
