import Foundation

/// The progress of a task: the counts of the Markdown checklist lines in its body (plan.md §4.1, §6, Progress).
///
/// ``ChecklistItem`` gives the rules of a checklist line. The type is not named `Progress`, because Foundation has a
/// type with that name.
struct TaskProgress: Hashable, Sendable {
    /// The number of checklist lines.
    let total: Int

    /// The number of checked checklist lines.
    let completed: Int

    /// The part of the checklist that is checked, from 0 to 1. A body with no checklist line gives 0.
    var fraction: Double {
        guard total > .zero else {
            return .zero
        }
        return Double(completed) / Double(total)
    }

    /// The part of the checklist that is checked, from 0 to 100: ``fraction`` times 100, not rounded (divergence.md
    /// Q19). A body with no checklist line gives 0. Rust gives a rounded whole number here.
    var percent: Double {
        fraction * .percentScale
    }
}

extension Double {
    /// The number of percent units in a whole.
    static let percentScale = 100.0
}

extension TaskProgress {
    /// Counts the checklist lines of a body.
    ///
    /// - Parameter body: The Markdown body of the task.
    init(of body: String) {
        let items = ChecklistItem.items(of: body)
        self.init(total: items.count, completed: items.filter(\.isChecked).count)
    }
}
