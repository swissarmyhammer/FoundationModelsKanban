import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the `addChecklistItem` mutation (divergence.md §31): the call adds one checklist item to the body of a task.
/// The call writes the body diff of `updateTask`, so undo, the change stream, and the `#tag` markers work with it.
///
/// Each test uses the fixture logs of ``KanbanGraphTests``, and first gives the fixture task a body with
/// ``ChecklistItemMutationTests/bodySetup(_:of:)``. ``ChecklistItemAdditionTests`` tests each place rule.
@Suite("addChecklistItem mutation", .watcherBudget)
struct AddChecklistItemMutationTests {
    /// The name of the mutation.
    private static let mutationName = MutationName.addChecklistItem

    /// The body of most tests: two open items.
    private static let twoOpenItems = "- [ ] one\n- [ ] two"

    /// The selection of most fields of the tests.
    private static let bodySelection = "{ body }"

    // MARK: - Helpers

    /// Makes an `addChecklistItem` field.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task. The field names it by `^` and the short id.
    ///   - input: The other fields of the `input` object.
    ///   - name: The name of the field. The default is the canonical name.
    ///   - selection: The selection of the field.
    /// - Returns: The field.
    private static func addField(
        of task: ULID,
        with input: String,
        named name: String = mutationName,
        selecting selection: String = bodySelection
    ) -> String {
        TaskOperationTests.taskField(name, of: task, with: input, selecting: selection)
    }

    /// Runs one `addChecklistItem` field on a task with a body, and gives the body after the call.
    ///
    /// - Parameters:
    ///   - input: The fields of the `input` object, without `id`.
    ///   - body: The body of the task before the call.
    /// - Returns: The body that the field gives.
    private static func bodyAfter(_ input: String, on body: String) async throws -> String? {
        try await ChecklistItemMutationTests.bodyAfter(mutationName, on: body) { task in
            addField(of: task, with: input)
        }
    }

    /// Runs one `addChecklistItem` field on a task with a body, and gives the response.
    ///
    /// - Parameters:
    ///   - input: The fields of the `input` object, without `id`.
    ///   - body: The body of the task before the call.
    ///   - selection: The selection of the field.
    /// - Returns: The response JSON text.
    private static func response(
        of input: String,
        on body: String,
        selecting selection: String = bodySelection
    ) async throws -> String {
        let directory = try TemporaryDirectory()
        let fixture = try await ChecklistItemMutationTests.taskWithBody(body, in: directory)
        let field = addField(of: fixture.task, with: input, selecting: selection)
        let response = try await CommentTests.run(field, on: fixture.graph)
        await fixture.graph.close()
        withExtendedLifetime(directory) {}
        return response
    }

    // MARK: - Place

    @Test("No place puts the item after the last checklist item")
    func noPlaceAddsAtEndOfChecklist() async throws {
        let body = try await Self.bodyAfter(#"text: "three""#, on: Self.twoOpenItems)
        #expect(body == "- [ ] one\n- [ ] two\n- [ ] three")
    }

    @Test("An int literal after puts the item after the item at that index")
    func intLiteralAfterNamesItem() async throws {
        let body = try await Self.bodyAfter(#"text: "new", after: 0"#, on: Self.twoOpenItems)
        #expect(body == "- [ ] one\n- [ ] new\n- [ ] two")
    }

    @Test("A marker in the text gives the state of the new item")
    func markerInTextGivesState() async throws {
        #expect(try await Self.bodyAfter(#"text: "- [x] done""#, on: "") == "- [x] done")
    }

    // MARK: - Write path

    @Test("A new #tag marker in the text gives the task the tag")
    func tagMarkerGivesTag() async throws {
        let response = try await Self.response(of: #"text: "Fix #urgent""#, on: "", selecting: "{ tags { name } }")
        let tags = try KanbanGraphTests.object(named: Self.mutationName, in: response)["tags"] as? [[String: Any]]
        #expect(tags?.compactMap { tag in tag["name"] as? String } == ["urgent"], "\(response)")
    }

    @Test("A text that an item already has gives the DUPLICATE_ITEM_TEXT warning")
    func sameTextGivesWarning() async throws {
        let response = try await Self.response(of: #"text: "one""#, on: Self.twoOpenItems)
        let warnings = try ResponseWarningsTests.warnings(of: response)
        #expect(warnings.map(\.code) == [ChecklistItemAddition.sameTextWarningCode])
    }

    @Test("One undoChange of the call gives back the old body")
    func undoGivesBackOldBody() async throws {
        let task = try await ChecklistItemMutationTests.bodyAfterUndo(of: Self.twoOpenItems) { task in
            Self.addField(of: task, with: #"text: "three""#)
        }
        #expect(task == #"{"data":{"board":{"task":{"body":"- [ ] one\n- [ ] two"}}}}"#)
    }

    // MARK: - Names and errors

    @Test("addSubtask with item names addChecklistItem with text")
    func addSubtaskNamesMutation() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try await ChecklistItemMutationTests.taskWithBody(Self.twoOpenItems, in: directory)
        let field = Self.addField(of: fixture.task, with: #"item: "three""#, named: "addSubtask")
        let response = try await KanbanGraphTests.runWithoutTransaction(field, on: fixture.graph)
        await fixture.graph.close()
        withExtendedLifetime(directory) {}
        let body = try KanbanGraphTests.object(named: "addSubtask", in: response)["body"] as? String
        #expect(body == "- [ ] one\n- [ ] two\n- [ ] three")
    }

    @Test("A text with a line break gives INVALID_ITEM_TEXT and writes nothing")
    func multilineTextWritesNothing() async throws {
        let error = try await ChecklistItemMutationTests.failure(on: Self.twoOpenItems) { task in
            Self.addField(of: task, with: #"text: "a\nb""#)
        }
        #expect(error == .multilineChecklistItemText(text: "a\nb"))
    }
}
