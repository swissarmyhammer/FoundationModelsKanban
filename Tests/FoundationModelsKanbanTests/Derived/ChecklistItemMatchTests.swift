import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the forgiving match of a checklist item ref (``ChecklistItemMatch``): an index in range, then the exact text,
/// then the text with case and whitespace ignored, then one prefix, then one substring. Two or more matches at one step
/// give `AMBIGUOUS_ITEM`, and no match gives `NOT_FOUND`.
@Suite("Checklist item match")
struct ChecklistItemMatchTests {
    /// The task ref of the errors.
    static let task = "^aaaaaaa"

    /// A body with four items. Two items start with "Add a", and one item has the text "2".
    static let body = "- [ ] Find the cause\n- [ ] Add a test\n- [x] Add a doc\n- [ ] 2\n"

    /// The item index of the item "Add a test".
    static let testIndex = 1

    /// The item index of the item "Add a doc".
    static let docIndex = 2

    /// The item index of the item "2".
    static let twoIndex = 3

    /// The matches of each item of ``body``, as an error lists them.
    static let allMatches = [
        KanbanError.ChecklistMatch(index: 0, text: "Find the cause"),
        KanbanError.ChecklistMatch(index: testIndex, text: "Add a test"),
        KanbanError.ChecklistMatch(index: docIndex, text: "Add a doc"),
        KanbanError.ChecklistMatch(index: twoIndex, text: "2"),
    ]

    /// Gives the item index that a ref matches in ``body``.
    ///
    /// - Parameter reference: The item ref as the caller wrote it.
    /// - Returns: The item index of the match.
    /// - Throws: The ``KanbanError`` of the match.
    static func index(for reference: String) throws -> Int {
        try ChecklistItemMatch.item(for: reference, among: ChecklistItem.items(of: body), ofTask: task).index
    }

    /// Gives the error of a ref that does not name one item of ``body``.
    ///
    /// - Parameter reference: The item ref as the caller wrote it.
    /// - Returns: The error.
    static func error(for reference: String) throws -> KanbanError {
        let error = #expect(throws: KanbanError.self) { try index(for: reference) }
        return try #require(error)
    }

    // MARK: - Steps

    @Test("An index in range names the item at that index")
    func indexInRange() throws {
        #expect(try Self.index(for: "1") == Self.testIndex)
    }

    @Test("An index with white space around it names the item at that index")
    func indexWithWhitespace() throws {
        #expect(try Self.index(for: " 2 ") == Self.docIndex)
    }

    @Test("The exact text names the item")
    func exactText() throws {
        #expect(try Self.index(for: "Add a doc") == Self.docIndex)
    }

    @Test("The text in a different case names the item")
    func caseInsensitiveText() throws {
        #expect(try Self.index(for: "add A TEST") == Self.testIndex)
    }

    @Test("The text with different white space names the item")
    func whitespaceInsensitiveText() throws {
        #expect(try Self.index(for: "  Find  the\tcause ") == 0)
    }

    @Test("A prefix of one item names the item")
    func uniquePrefix() throws {
        #expect(try Self.index(for: "find") == 0)
    }

    @Test("A substring of one item names the item")
    func uniqueSubstring() throws {
        #expect(try Self.index(for: "doc") == Self.docIndex)
    }

    @Test("The full checklist line names the item")
    func fullLine() throws {
        #expect(try Self.index(for: "- [x] Add a doc") == Self.docIndex)
    }

    @Test("An index out of range that is the text of an item names that item")
    func indexOutOfRangeFallsToText() throws {
        let items = ChecklistItem.items(of: "- [ ] Find\n- [ ] 7\n")
        #expect(try ChecklistItemMatch.item(for: "7", among: items, ofTask: Self.task).index == 1)
    }

    // MARK: - Errors

    @Test("A prefix of two items gives AMBIGUOUS_ITEM with the two items and their indexes")
    func ambiguousPrefix() throws {
        let expected = KanbanError.ambiguousChecklistItem(
            task: Self.task,
            item: "add a",
            matches: [Self.allMatches[Self.testIndex], Self.allMatches[Self.docIndex]]
        )
        #expect(try Self.error(for: "add a") == expected)
    }

    @Test("The exact text of two items gives AMBIGUOUS_ITEM")
    func ambiguousExactText() throws {
        let items = ChecklistItem.items(of: "- [ ] Same\n- [x] Same\n")
        let matches = [0, 1].map { index in KanbanError.ChecklistMatch(index: index, text: "Same") }
        let expected = KanbanError.ambiguousChecklistItem(task: Self.task, item: "Same", matches: matches)
        #expect(throws: expected) { try ChecklistItemMatch.item(for: "Same", among: items, ofTask: Self.task) }
    }

    @Test("A text that no item has gives NOT_FOUND with each item")
    func noMatch() throws {
        let expected = KanbanError.checklistItemNotFound(task: Self.task, item: "deploy", items: Self.allMatches)
        #expect(try Self.error(for: "deploy") == expected)
    }

    @Test("An index out of range gives NOT_FOUND with each item")
    func indexOutOfRange() throws {
        let expected = KanbanError.checklistItemNotFound(task: Self.task, item: "9", items: Self.allMatches)
        #expect(try Self.error(for: "9") == expected)
    }

    @Test("An empty ref gives NOT_FOUND")
    func emptyReference() throws {
        let expected = KanbanError.checklistItemNotFound(task: Self.task, item: " ", items: Self.allMatches)
        #expect(try Self.error(for: " ") == expected)
    }
}
