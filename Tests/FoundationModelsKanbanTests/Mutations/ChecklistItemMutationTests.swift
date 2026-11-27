import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the `updateChecklistItem` mutation (divergence.md §30): the call sets the state of one checklist item of the
/// body of a task, and can change its text. The call writes the body diff of `updateTask`, so undo and the change
/// stream work with it.
///
/// Each test uses the fixture logs of ``KanbanGraphTests``, and first gives the fixture task a body with
/// ``bodySetup(_:)``.
@Suite("updateChecklistItem mutation", .watcherBudget)
struct ChecklistItemMutationTests {
    /// The name of the mutation.
    private static let mutationName = MutationName.updateChecklistItem

    /// The body of most tests: two open items.
    private static let twoOpenItems = "- [ ] one\n- [ ] two"

    /// The selection of each field of the tests.
    private static let bodySelection = "{ body }"

    // MARK: - Helpers

    /// Makes the setup document: an `updateTask` that gives the fixture task a body.
    ///
    /// - Parameters:
    ///   - body: The body. Each line break is a `\n` escape in the GraphQL string.
    ///   - task: The ULID of the fixture task.
    /// - Returns: The document.
    private static func bodySetup(_ body: String, of task: ULID) -> String {
        let escaped = body.replacingOccurrences(of: "\n", with: #"\n"#)
        return AddUpdateTaskTests.mutation(of: AddUpdateTaskTests.updateTask(task, with: #"body: "\#(escaped)""#))
    }

    /// Makes an `updateChecklistItem` field.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task. The field names it by `^` and the short id.
    ///   - input: The other fields of the `input` object.
    ///   - name: The name of the field. The default is the canonical name.
    /// - Returns: The field.
    private static func itemField(of task: ULID, with input: String, named name: String = mutationName) -> String {
        TaskOperationTests.taskField(name, of: task, with: input, selecting: bodySelection)
    }

    /// Makes a new engine of the fixture repo, and gives the fixture task a body.
    ///
    /// - Parameters:
    ///   - body: The body of the fixture task.
    ///   - directory: The temporary repo directory.
    /// - Returns: The engine and the ULID of the fixture task.
    private static func taskWithBody(
        _ body: String,
        in directory: TemporaryDirectory
    ) async throws -> (graph: KanbanGraph, task: ULID) {
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        _ = try await KanbanGraphTests.execute(bodySetup(body, of: fixture.task), on: fixture.graph)
        return fixture
    }

    /// Runs one `updateChecklistItem` field on a task with a body, and gives the body after the call.
    ///
    /// - Parameters:
    ///   - input: The fields of the `input` object, without `id`.
    ///   - body: The body of the task before the call.
    /// - Returns: The body that the field gives.
    private static func bodyAfter(_ input: String, on body: String) async throws -> String? {
        let directory = try TemporaryDirectory()
        let fixture = try await taskWithBody(body, in: directory)
        let response = try await CommentTests.run(itemField(of: fixture.task, with: input), on: fixture.graph)
        await fixture.graph.close()
        withExtendedLifetime(directory) {}
        return try KanbanGraphTests.object(named: mutationName, in: response)["body"] as? String
    }

    /// Runs one `updateChecklistItem` field that fails, and gives its error.
    ///
    /// - Parameters:
    ///   - input: The fields of the `input` object, without `id`.
    ///   - body: The body of the task before the call.
    /// - Returns: The error.
    private static func failure(of input: String, on body: String) async throws -> KanbanError {
        let task = try AddUpdateTaskTests.fixtureTask()
        return try await ColumnActorTests.failure(
            of: AddUpdateTaskTests.mutation(of: itemField(of: task, with: input)),
            after: bodySetup(body, of: task),
            in: try TemporaryDirectory()
        )
    }

    // MARK: - State

    @Test("checked: true checks the item and keeps each other line")
    func checkChecksItem() async throws {
        let body = try await Self.bodyAfter(#"item: "one", checked: true"#, on: Self.twoOpenItems)
        #expect(body == "- [x] one\n- [ ] two")
    }

    @Test("checked: false unchecks the item")
    func uncheckUnchecksItem() async throws {
        let body = try await Self.bodyAfter(#"item: "two", checked: false"#, on: "- [ ] one\n- [x] two")
        #expect(body == Self.twoOpenItems)
    }

    @Test("An indented item keeps its indent")
    func indentedItemKeepsIndent() async throws {
        #expect(try await Self.bodyAfter(#"item: "one", checked: true"#, on: "  - [ ] one\n") == "  - [x] one\n")
    }

    @Test("A text change of an item checked with X keeps [X]")
    func textChangeKeepsUppercaseBox() async throws {
        #expect(try await Self.bodyAfter(#"item: "one", text: "uno""#, on: "- [X] one") == "- [X] uno")
    }

    @Test("checked and text in one call check the item and change its text")
    func checkAndTextChange() async throws {
        let body = try await Self.bodyAfter(#"item: "two", checked: true, text: "deux""#, on: Self.twoOpenItems)
        #expect(body == "- [ ] one\n- [x] deux")
    }

    @Test("Each ref form names the second item", arguments: ["1", "two", "TWO", "tw", "- [ ] two"])
    func refFormsNameItem(reference: String) async throws {
        let body = try await Self.bodyAfter(#"item: "\#(reference)", checked: true"#, on: Self.twoOpenItems)
        #expect(body == "- [ ] one\n- [x] two")
    }

    @Test("An int literal index names the item")
    func intLiteralIndexNamesItem() async throws {
        let body = try await Self.bodyAfter("item: 1, checked: true", on: Self.twoOpenItems)
        #expect(body == "- [ ] one\n- [x] two")
    }

    // MARK: - No change

    @Test("checked: true on a checked item writes nothing and gives no error")
    func sameStateWritesNothing() async throws {
        let task = try AddUpdateTaskTests.fixtureTask()
        let response = try await ColumnActorTests.respondWritingNothing(
            to: AddUpdateTaskTests.mutation(of: Self.itemField(of: task, with: #"item: "one", checked: true"#)),
            after: Self.bodySetup("- [x] one", of: task),
            in: try TemporaryDirectory()
        )
        #expect(response == #"{"data":{"updateChecklistItem":{"body":"- [x] one"}}}"#)
    }

    @Test("An input with no checked and no text writes nothing and gives the NOTHING_TO_CHANGE warning")
    func emptyChangeGivesWarning() async throws {
        let task = try AddUpdateTaskTests.fixtureTask()
        let response = try await ColumnActorTests.respondWritingNothing(
            to: AddUpdateTaskTests.mutation(of: Self.itemField(of: task, with: #"item: "one""#)),
            after: Self.bodySetup(Self.twoOpenItems, of: task),
            in: try TemporaryDirectory()
        )
        let warnings = try ResponseWarningsTests.warnings(of: response)
        #expect(warnings.map(\.code) == [ChecklistItemUpdate.nothingToChangeWarningCode])
    }

    // MARK: - Undo and names

    @Test("One undoChange of the call gives back the old body")
    func undoGivesBackOldBody() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try await Self.taskWithBody(Self.twoOpenItems, in: directory)
        let field = Self.itemField(of: fixture.task, with: #"item: "0", checked: true"#)
        let document = AddUpdateTaskTests.mutation(of: field)
        let call = try await ResponseTransactionTests.run(document, on: fixture.graph, in: directory)
        let txn = try ResponseTransactionTests.transaction(of: call.response)
        #expect(call.written == [txn], "\(call.response)")
        let undo = UndoTests.reverseField(MutationName.undoChange, with: #"txn: "\#(txn)""#)
        _ = try await CommentTests.run(undo, on: fixture.graph)
        let task = try await CommentTests.respond(
            toQueryOf: fixture.task,
            selecting: Self.bodySelection,
            on: fixture.graph
        )
        await fixture.graph.close()
        #expect(task == #"{"data":{"board":{"task":{"body":"- [ ] one\n- [ ] two"}}}}"#)
    }

    @Test("checkSubtask names updateChecklistItem")
    func checkSubtaskNamesMutation() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try await Self.taskWithBody(Self.twoOpenItems, in: directory)
        let field = Self.itemField(of: fixture.task, with: #"subtask: "one", done: true"#, named: "checkSubtask")
        let response = try await KanbanGraphTests.runWithoutTransaction(field, on: fixture.graph)
        await fixture.graph.close()
        withExtendedLifetime(directory) {}
        let body = try KanbanGraphTests.object(named: "checkSubtask", in: response)["body"] as? String
        #expect(body == "- [x] one\n- [ ] two")
    }

    // MARK: - Errors

    @Test("A text of two items gives AMBIGUOUS_ITEM and writes nothing")
    func ambiguousTextWritesNothing() async throws {
        let task = try AddUpdateTaskTests.fixtureTask()
        let matches = [0, 1].map { index in KanbanError.ChecklistMatch(index: index, text: "same") }
        let expected = KanbanError.ambiguousChecklistItem(
            task: AddUpdateTaskTests.sigilRef(of: task),
            item: "same",
            matches: matches
        )
        #expect(try await Self.failure(of: #"item: "same", checked: true"#, on: "- [ ] same\n- [ ] same") == expected)
    }

    @Test("A text that no item has gives NOT_FOUND and writes nothing")
    func noMatchWritesNothing() async throws {
        let task = try AddUpdateTaskTests.fixtureTask()
        let items = ["one", "two"].enumerated().map { index, text in
            KanbanError.ChecklistMatch(index: index, text: text)
        }
        let expected = KanbanError.checklistItemNotFound(
            task: AddUpdateTaskTests.sigilRef(of: task),
            item: "nine",
            items: items
        )
        #expect(try await Self.failure(of: #"item: "nine", checked: true"#, on: Self.twoOpenItems) == expected)
    }
}
