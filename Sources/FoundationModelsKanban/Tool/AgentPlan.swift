import FoundationModelsExtras

// MARK: - The plan of one board

/// The ACP agent plan of a board (https://agentclientprotocol.com/protocol/v2/agent-plan, plan.md §7.3).
///
/// The plan of a board is the full list of its live tasks in board order: column order, then ordinal. The id of the
/// plan is the board key, so that the client replaces the plan of a board with each new post. The model never gets
/// the plan; it goes to the client.
extension PlanSnapshot {
    /// Makes the plan of a board: one entry for each live task, in board order. A tombstone is not in the plan.
    ///
    /// - Parameters:
    ///   - readiness: The readiness of the tasks of the board. It holds the graph and the board order.
    ///   - boardKey: The current key of the board: the id of the plan.
    init(of readiness: Readiness, inBoard boardKey: String) {
        let entries = readiness.taskOrder.compactMap { slot -> Entry? in
            guard let task = readiness.graph.node(at: slot, as: TaskNode.self), !task.fields.isDeleted else {
                return nil
            }
            return Entry(
                content: task.title,
                priority: Priority(ofTaskAt: slot, in: readiness),
                status: Status(ofTaskAt: slot, in: readiness)
            )
        }
        self.init(id: boardKey, entries: entries)
    }
}

extension PlanSnapshot.Priority {
    /// Gives the plan priority of a priority tier: `HIGH` is `high`, `MEDIUM` is `medium`, and `LOW` is `low`.
    ///
    /// - Parameter tier: The tier.
    init(_ tier: PriorityTier) {
        switch tier {
        case .high: self = .high
        case .medium: self = .medium
        case .low: self = .low
        }
    }

    /// Gives the plan priority of a live task: the priority of its tier. A done task has no tier, and the rule of
    /// the plan gives it `low`.
    ///
    /// - Parameters:
    ///   - slot: The slot of the live task.
    ///   - readiness: The readiness of the tasks of the board.
    fileprivate init(ofTaskAt slot: Int, in readiness: Readiness) {
        guard let tier = readiness.priorityTier(ofTaskAt: slot) else {
            self = .low
            return
        }
        self.init(tier)
    }
}

extension PlanSnapshot.Status {
    /// Gives the plan status of a live task: `completed` when the task is done, `pending` when it shows in the first
    /// column, and `inProgress` in each other column.
    ///
    /// - Parameters:
    ///   - slot: The slot of the live task.
    ///   - readiness: The readiness of the tasks of the board.
    fileprivate init(ofTaskAt slot: Int, in readiness: Readiness) {
        if readiness.isDone(taskAt: slot) {
            self = .completed
        } else if readiness.column(ofTaskAt: slot) == readiness.columnOrder.first {
            self = .pending
        } else {
            self = .inProgress
        }
    }
}

extension BoardSummary {
    /// The short text line of a plan post for the model, for example `3 of 7 tasks done`.
    var progressDetail: String {
        "\(done) of \(total) tasks done"
    }
}

// MARK: - Post

extension ToolContext {
    /// Posts the agent plan of each board whose tasks an operation changed: one `.progress` event for each board, in
    /// the sort order of the canonical path of its repo directory.
    ///
    /// A board is in the post when an event of its changes patches a task: an add, an update, a move, a delete, an
    /// undelete, an undo, or a redo of a task. A board whose changes patch no task, for example a new tag or a
    /// comment, gets no post.
    ///
    /// - Parameter changed: The changes of each loaded board that changed in the operation, by the canonical path of
    ///   its repo directory.
    func postAgentPlans(of changed: [String: BoardChanges]) async {
        for (_, board) in changed.sorted(by: { lhs, rhs in lhs.key < rhs.key }) where board.patchesTasks {
            let key = board.session.key.description
            let readiness = Readiness(of: board.session.live.graph, inBoard: key)
            await progress(readiness.summary.progressDetail, plan: PlanSnapshot(of: readiness, inBoard: key))
        }
    }
}

extension BoardChanges {
    /// `true` when an event of the changes patches a task.
    fileprivate var patchesTasks: Bool {
        changes.contains { change in
            change.events.contains { event in event.patch.node.nodeType == .task }
        }
    }
}
