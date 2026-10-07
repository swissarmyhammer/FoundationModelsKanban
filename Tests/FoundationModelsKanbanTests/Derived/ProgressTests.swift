import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the `progress` of a task: the count of the Markdown checklist lines in its body (plan.md §6, Progress). The
/// tests in the "Rust" section are the port of the progress tests of the Rust `task_helpers.rs`.
@Suite("Progress")
struct ProgressTests {
    /// The number of checklist lines in ``mixedBody``.
    static let mixedTotal = 4

    /// The number of checked lines in ``mixedBody``.
    static let mixedCompleted = 2

    /// A body with two open items, one item checked with `x`, and one item checked with `X`.
    static let mixedBody = "- [ ] one\n- [x] two\n- [X] three\n- [ ] four"

    /// The number of checklist lines in a test body with one open item and one checked item.
    static let pairTotal = 2

    /// The progress of a test body with one open item and one checked item.
    static let pairProgress = TaskProgress(total: pairTotal, completed: 1)

    /// The fraction of a test body with one open item and one checked item.
    static let pairFraction = 0.5

    /// The progress of a body with no checklist item.
    static let noProgress = TaskProgress(total: .zero, completed: .zero)

    // MARK: - Rust

    @Test("An empty body has no checklist items (Rust test_parse_checklist_counts, test_task_progress_no_field)")
    func emptyBodyHasNoItems() {
        let progress = TaskProgress(of: "")
        #expect(progress == Self.noProgress)
        #expect(progress.fraction == .zero)
    }

    @Test("Open items and items checked with x or X all count (Rust test_parse_checklist_counts)")
    func openAndCheckedItemsCount() {
        let expected = TaskProgress(total: Self.mixedTotal, completed: Self.mixedCompleted)
        #expect(TaskProgress(of: Self.mixedBody) == expected)
    }

    @Test("An indented item counts (Rust test_parse_checklist_counts)")
    func indentedItemCounts() {
        #expect(TaskProgress(of: "  - [ ] indented\n  - [x] done") == Self.pairProgress)
    }

    @Test("Plain text and a bullet with no box do not count (Rust test_parse_checklist_counts)")
    func plainLinesDoNotCount() {
        let progress = TaskProgress(of: "plain text\n- regular bullet\n- [ ] real item")
        #expect(progress == TaskProgress(total: 1, completed: .zero))
    }

    @Test("The fraction is the checked items divided by all items (Rust test_task_progress)")
    func fractionOfCheckedItems() {
        #expect(TaskProgress(of: "- [ ] one\n- [x] two").fraction == Self.pairFraction)
    }

    @Test("A body with no checklist has a fraction of zero (Rust test_task_progress_no_checklist)")
    func noChecklistHasZeroFraction() {
        let progress = TaskProgress(of: "No checklist here")
        #expect(progress == Self.noProgress)
        #expect(progress.fraction == .zero)
    }

    // MARK: - Line rules

    @Test("A box with no text after it counts")
    func bareBoxCounts() {
        #expect(TaskProgress(of: "- [x]\n- [ ]") == Self.pairProgress)
    }

    @Test("A box that text follows with no space does not count")
    func boxGluedToTextDoesNotCount() {
        #expect(TaskProgress(of: "- [x]done\n- [ ]open") == Self.noProgress)
    }

    @Test("A line with a CRLF line break counts")
    func crlfLineCounts() {
        #expect(TaskProgress(of: "- [x] one\r\n- [ ] two\r\n") == Self.pairProgress)
    }
}
