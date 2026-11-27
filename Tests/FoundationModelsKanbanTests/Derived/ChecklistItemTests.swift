import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the checklist item parser of a task body (``ChecklistItem``): the items, their lines, their states, and their
/// texts, and the edit of one item line. `TaskProgress` counts these items, so the rules are the rules of
/// ``ProgressTests``.
@Suite("Checklist items")
struct ChecklistItemTests {
    /// A body with a heading, an open item, a plain line, an item checked with `X`, and an indented item.
    static let body = "# Plan\n- [ ] Find the cause\nplain text\n- [X] Add a test\n  - [x] Indented\n"

    /// The line index of the item of ``body`` checked with `X`.
    static let checkedLine = 3

    /// The line index of the indented item of ``body``.
    static let indentedLine = 4

    /// The item index of the indented item of ``body``.
    static let indentedIndex = 2

    // MARK: - Parse

    @Test("The parser gives the text of each item, in body order")
    func parserGivesTexts() {
        #expect(ChecklistItem.items(of: Self.body).map(\.text) == ["Find the cause", "Add a test", "Indented"])
    }

    @Test("The parser gives the state of each item")
    func parserGivesStates() {
        #expect(ChecklistItem.items(of: Self.body).map(\.isChecked) == [false, true, true])
    }

    @Test("The parser gives the line index of each item")
    func parserGivesLineIndexes() {
        #expect(ChecklistItem.items(of: Self.body).map(\.line) == [1, Self.checkedLine, Self.indentedLine])
    }

    @Test("The parser gives the item index of each item")
    func parserGivesItemIndexes() {
        #expect(ChecklistItem.items(of: Self.body).map(\.index) == [0, 1, Self.indentedIndex])
    }

    @Test("A bare box is an item with an empty text")
    func bareBoxHasEmptyText() {
        #expect(ChecklistItem.items(of: "- [x]").map(\.text) == [""])
    }

    @Test("A box that text follows with no space is not an item")
    func boxGluedToTextIsNotItem() {
        #expect(ChecklistItem.items(of: "- [x]done\n- [ ]open").isEmpty)
    }

    // MARK: - Edit

    @Test("A check of an open item writes [x] and keeps the indent, the text, and the line break")
    func checkWritesLowercaseBox() throws {
        let item = try #require(ChecklistItem.items(of: "  - [ ] one\r\n").first)
        #expect(item.editedLine(checking: true, text: nil) == "  - [x] one\r\n")
    }

    @Test("An uncheck of an item checked with X writes an open box")
    func uncheckWritesOpenBox() throws {
        let item = try #require(ChecklistItem.items(of: "- [X] one").first)
        #expect(item.editedLine(checking: false, text: nil) == "- [ ] one")
    }

    @Test("A text change of an item checked with X keeps [X]")
    func textChangeKeepsUppercaseBox() throws {
        let item = try #require(ChecklistItem.items(of: "- [X] one\n").first)
        #expect(item.editedLine(checking: true, text: "two") == "- [X] two\n")
    }

    @Test("An empty new text leaves a bare box")
    func emptyTextLeavesBareBox() throws {
        let item = try #require(ChecklistItem.items(of: "- [ ] one\n").first)
        #expect(item.editedLine(checking: nil, text: "") == "- [ ]\n")
    }

    @Test("An edit with no change gives the line byte for byte")
    func noChangeKeepsLine() throws {
        let line = "\t- [X]  two spaces  \n"
        let item = try #require(ChecklistItem.items(of: line).first)
        #expect(item.editedLine(checking: nil, text: nil) == line)
    }
}
