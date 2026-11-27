import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the `deleteChecklistItem` mutation (divergence.md §32): the call removes one checklist item from the body of
/// a task. The call writes the body diff of `updateTask`, so undo and the change stream work with it.
///
/// Each test uses the fixture logs of ``KanbanGraphTests``, and first gives the fixture task a body with
/// ``ChecklistItemMutationTests/bodySetup(_:of:)``. ``ChecklistItemDeletionTests`` tests each line rule.
@Suite("deleteChecklistItem mutation", .watcherBudget)
struct DeleteChecklistItemMutationTests {
    /// The name of the mutation.
    private static let mutationName = MutationName.deleteChecklistItem

    /// The body of most tests: two open items.
    private static let twoOpenItems = "- [ ] one\n- [ ] two"

    // MARK: - Helpers

    /// Makes a `deleteChecklistItem` field.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task. The field names it by `^` and the short id.
    ///   - input: The other fields of the `input` object.
    ///   - name: The name of the field. The default is the canonical name.
    /// - Returns: The field.
    private static func deleteField(of task: ULID, with input: String, named name: String = mutationName) -> String {
        TaskOperationTests.taskField(name, of: task, with: input, selecting: "{ body }")
    }

    /// Runs one `deleteChecklistItem` field on a task with a body, and gives the body after the call.
    ///
    /// - Parameters:
    ///   - input: The fields of the `input` object, without `id`.
    ///   - body: The body of the task before the call.
    ///   - name: The name of the field. The default is the canonical name.
    /// - Returns: The body that the field gives.
    private static func bodyAfter(
        _ input: String,
        on body: String,
        named name: String = mutationName
    ) async throws -> String? {
        try await ChecklistItemMutationTests.bodyAfter(name, on: body) { task in
            deleteField(of: task, with: input, named: name)
        }
    }

    /// Runs one `deleteChecklistItem` field that fails, and gives its error.
    ///
    /// - Parameters:
    ///   - input: The fields of the `input` object, without `id`.
    ///   - body: The body of the task before the call.
    /// - Returns: The error.
    private static func failure(of input: String, on body: String) async throws -> KanbanError {
        try await ChecklistItemMutationTests.failure(on: body) { task in deleteField(of: task, with: input) }
    }

    // MARK: - Remove

    @Test("A text ref removes the line of the item")
    func textRefRemovesItem() async throws {
        #expect(try await Self.bodyAfter(#"item: "one""#, on: Self.twoOpenItems) == "- [ ] two")
    }

    @Test("An int literal index removes the item at that index")
    func intLiteralIndexRemovesItem() async throws {
        #expect(try await Self.bodyAfter("item: 1", on: Self.twoOpenItems) == "- [ ] one")
    }

    @Test("removeSubtask with subtask names deleteChecklistItem with item")
    func removeSubtaskNamesMutation() async throws {
        let body = try await Self.bodyAfter(#"subtask: "two""#, on: Self.twoOpenItems, named: "removeSubtask")
        #expect(body == "- [ ] one")
    }

    // MARK: - Undo

    @Test("One undoChange of the call gives back the line")
    func undoGivesBackLine() async throws {
        let task = try await ChecklistItemMutationTests.bodyAfterUndo(of: Self.twoOpenItems) { task in
            Self.deleteField(of: task, with: #"item: "two""#)
        }
        #expect(task == #"{"data":{"board":{"task":{"body":"- [ ] one\n- [ ] two"}}}}"#)
    }

    // MARK: - Errors

    @Test("A text that no item has gives NOT_FOUND with the current items and writes nothing")
    func noMatchWritesNothing() async throws {
        let task = try AddUpdateTaskTests.sigilRef(of: AddUpdateTaskTests.fixtureTask())
        let items = ChecklistItemDeletionTests.matches(["one", "two"])
        let expected = KanbanError.checklistItemNotFound(task: task, item: "nine", items: items)
        #expect(try await Self.failure(of: #"item: "nine""#, on: Self.twoOpenItems) == expected)
    }

    @Test("A text of two items gives AMBIGUOUS_ITEM and writes nothing")
    func ambiguousTextWritesNothing() async throws {
        let task = try AddUpdateTaskTests.sigilRef(of: AddUpdateTaskTests.fixtureTask())
        let matches = ChecklistItemDeletionTests.matches(["same", "same"])
        let expected = KanbanError.ambiguousChecklistItem(task: task, item: "same", matches: matches)
        #expect(try await Self.failure(of: #"item: "same""#, on: "- [ ] same\n- [ ] same") == expected)
    }
}
