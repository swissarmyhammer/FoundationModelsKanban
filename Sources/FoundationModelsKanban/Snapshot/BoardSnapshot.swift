import Foundation

/// The result of a read of the board of a folder with no session (``KanbanHost/readBoard(inFolder:)``).
public enum BoardRead: Sendable, Hashable, Codable {
    /// The folder has no `.kanban/` folder.
    case noBoard

    /// The board of the folder.
    case board(BoardSnapshot)
}

/// The columns and the tasks of one board at the time of a read, as plain values (TestudoApp D214).
///
/// A snapshot holds no live state. It does not change when the board changes. A deleted column, a deleted task, and a
/// deleted comment are not in it.
public struct BoardSnapshot: Sendable, Hashable, Codable {
    /// The live columns of the board, in board order.
    public let columns: [Column]

    /// The live tasks of the board, in board order: by the position of the column where the task shows, then by
    /// ordinal, then by ULID.
    public let tasks: [Task]

    /// One live column of the board.
    public struct Column: Sendable, Hashable, Codable {
        /// The slug of the column, for example `todo`.
        public let id: String

        /// The name of the column, for example `To Do`.
        public let name: String

        /// The sort key of the column on the board.
        public let order: Int
    }

    /// One actor of the board: an assignee of a task, or the author of a comment.
    public struct Actor: Sendable, Hashable, Codable {
        /// The slug of the actor, for example `alice`.
        public let id: String

        /// The name of the actor, for example `Alice`.
        public let name: String
    }

    /// One live task of the board.
    public struct Task: Sendable, Hashable, Codable {
        /// The ULID of the task, as text.
        public let id: String

        /// The short id of the task: the last characters of its ULID, in lowercase.
        public let shortID: String

        /// The title of the task.
        public let title: String

        /// The Markdown body of the task.
        public let description: String

        /// The slug of the column where the task shows. A task with no live column shows in the first column. The
        /// value is `nil` only when the board has no live column.
        public let column: String?

        /// The names of the live tags of the task: its tags and the `#tag` markers of its body, in the order of the
        /// tag slugs.
        public let tags: [String]

        /// The live actors of this board that the task has as assignees. The read loads no other board, so an
        /// assignee that is an actor of a different board (a task that moved from that board) is not in the list.
        public let assignees: [Actor]

        /// The tasks that the task depends on: its `dependsOn` edges and the dependency markers of its body.
        ///
        /// - A live task of this board gives its ULID text. A deleted task of this board, and a ref to a task that
        ///   this board does not have, are not in the list.
        /// - A task of a different board gives its full URI text. The read loads no other board, so it cannot tell
        ///   if that task is deleted.
        /// - A dependency marker resolves in this board when its board key is the key that the board log recorded
        ///   at the last write. After a change of the git key with no later write, a marker with the new key gives
        ///   its URI text.
        public let dependsOn: [String]

        /// The live comments of the task, in time order.
        public let comments: [Comment]

        /// The time of the first change of the task.
        public let created: Date

        /// The time of the last change of the task.
        public let updated: Date

        /// `true` when the task shows in the terminal column of the board.
        public let isDone: Bool
    }

    /// One live comment of a task.
    public struct Comment: Sendable, Hashable, Codable {
        /// The ULID of the comment, as text.
        public let id: String

        /// The actor that wrote the comment, also when that actor is deleted, or `nil` when the board does not have
        /// the actor.
        public let author: Actor?

        /// The Markdown body of the comment.
        public let text: String

        /// The time when the comment was written.
        public let created: Date
    }
}

// MARK: - Read

extension BoardRead {
    /// Reads the board of a folder from its log files. The read opens no session, takes no lock, runs no git, and
    /// writes no file.
    ///
    /// The loader drops a torn last line of a log file, and it holds each transaction that is not complete in all
    /// its log files (divergence.md Q23). Thus a read while a session writes the same board gives the state of the
    /// board before that write.
    ///
    /// - Parameters:
    ///   - folder: The folder that holds `.kanban/`. The read does not go up to a parent folder.
    ///   - observer: Gets a call when each worker of the loader reads a file, or `nil` for no calls.
    /// - Throws: ``EventLogError/incompatibleBoard(directory:)`` when the `.kanban/` folder is a board of the old Rust
    ///   kanban. ``EventLogError/fileSystem(path:detail:)`` when a folder or a file is there and cannot be read.
    init(readingFolder folder: URL, reportingTo observer: (any LoaderWorkerObserver)?) async throws(EventLogError) {
        guard let directory = BoardWatcher.existingBoardDirectory(ofBoardAt: folder), Self.isFolder(directory) else {
            self = .noBoard
            return
        }
        let log = EventLog(repositoryAt: folder)
        try log.checkCompatibility()
        let joined = try await BoardLoader(reading: log, reportingTo: observer).join()
        self = .board(BoardSnapshot(of: joined.graph))
    }

    /// Tells if an item is a folder. A regular file with the name `.kanban` is not a board.
    ///
    /// - Parameter item: The item.
    /// - Returns: `true` when the item is there and is a folder.
    private static func isFolder(_ item: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

// MARK: - Graph values

extension BoardSnapshot {
    /// The board key of a graph whose board log records no key. With this key, no dependency marker resolves in the
    /// board.
    static let unrecordedBoardKey = ""

    /// Makes the snapshot of a graph.
    ///
    /// The key of the board is the key that the board log recorded at the last write: the git key, else the primary
    /// board ID. A dependency marker with this key resolves in the board. The read does not ask git for the key.
    ///
    /// - Parameter graph: The graph of the board.
    init(of graph: Graph) {
        let readiness = Readiness(of: graph, inBoard: Self.recordedKey(of: graph))
        columns = readiness.columnOrder.slots.compactMap { slot in
            graph.node(at: slot, as: ColumnNode.self).map(Column.init(of:))
        }
        tasks = readiness.taskOrder.compactMap { slot in Task(at: slot, by: readiness) }
    }

    /// Gives the key of the board that its board log recorded at the last write.
    ///
    /// - Parameter graph: The graph of the board.
    /// - Returns: The recorded git key, else the primary board ID, else ``unrecordedBoardKey``.
    static func recordedKey(of graph: Graph) -> String {
        let board = graph.boardNode
        return board?.gitKey ?? board?.ids.min()?.ulidString ?? unrecordedBoardKey
    }
}

extension BoardSnapshot.Column {
    /// Makes the value of a live column.
    ///
    /// - Parameter column: The column.
    init(of column: ColumnNode) {
        self.init(id: column.slug, name: column.name, order: column.order)
    }
}

extension BoardSnapshot.Actor {
    /// Makes the value of an actor.
    ///
    /// - Parameter actor: The actor.
    init(of actor: ActorNode) {
        self.init(id: actor.slug, name: actor.name)
    }

    /// Makes the value of the live actor at the target of an assignee edge.
    ///
    /// - Parameters:
    ///   - target: The target of the edge.
    ///   - graph: The graph of the board.
    /// - Returns: `nil` when the target is not a live actor of the board.
    init?(atLive target: EdgeTarget, in graph: Graph) {
        guard
            let slot = target.resolvedSlot,
            let actor = graph.node(at: slot, as: ActorNode.self),
            !actor.fields.isDeleted
        else {
            return nil
        }
        self.init(of: actor)
    }
}

extension BoardSnapshot.Task {
    /// Makes the value of the live task in a slot.
    ///
    /// - Parameters:
    ///   - slot: The slot of the task.
    ///   - readiness: The readiness of the board. It holds the graph and the column order.
    /// - Returns: `nil` when the slot holds no task, or holds a deleted task.
    init?(at slot: Int, by readiness: Readiness) {
        let graph = readiness.graph
        guard let task = graph.node(at: slot, as: TaskNode.self), !task.fields.isDeleted else {
            return nil
        }
        let columnSlot = readiness.column(ofTaskAt: slot)
        let dependencies = readiness.dependencies(ofTaskAt: slot)
        let comments = graph.comments(ofTaskAt: slot)
        self.init(
            id: task.id.ulidString,
            shortID: ShortID(of: task.id).value,
            title: task.title,
            description: task.fields.body,
            column: columnSlot.flatMap { column in graph.node(at: column, as: ColumnNode.self)?.slug },
            tags: graph.tagSlots(of: task).compactMap { tag in graph.node(at: tag, as: TagNode.self)?.name },
            assignees: task.assignees.compactMap { target in BoardSnapshot.Actor(atLive: target, in: graph) },
            dependsOn: dependencies.compactMap { target in Self.taskID(at: target, in: graph) },
            comments: comments.compactMap { comment in BoardSnapshot.Comment(at: comment, in: graph) },
            created: task.fields.created.date,
            updated: task.fields.updated.date,
            isDone: readiness.isDone(taskAt: slot)
        )
    }

    /// Gives the id of the task at the target of a dependency.
    ///
    /// - Parameters:
    ///   - target: The target of the dependency.
    ///   - graph: The graph of the board.
    /// - Returns: The ULID text of a live task of this board, the full URI text of a task of a different board, or
    ///   `nil` when the target is a deleted task, a node that is not a task, or a ref that this board does not have.
    ///   GraphQL `Task.dependsOn` also leaves out a ref that this board does not have.
    static func taskID(at target: EdgeTarget, in graph: Graph) -> String? {
        switch target {
        case .slot(let slot):
            graph.node(at: slot, as: TaskNode.self).flatMap { task in task.fields.isDeleted ? nil : task.id.ulidString }
        case .unresolved(.local):
            nil
        case .unresolved(.remote(let uri)):
            uri.description
        }
    }
}

extension BoardSnapshot.Comment {
    /// Makes the value of the comment in a slot.
    ///
    /// - Parameters:
    ///   - slot: The slot of the comment.
    ///   - graph: The graph of the board.
    /// - Returns: `nil` when the slot holds no comment.
    init?(at slot: Int, in graph: Graph) {
        guard let comment = graph.node(at: slot, as: CommentNode.self) else {
            return nil
        }
        self.init(
            id: comment.id.ulidString,
            author: graph.author(ofCommentAt: slot).map(BoardSnapshot.Actor.init(of:)),
            text: comment.fields.body,
            created: comment.fields.created.date
        )
    }
}
