import Foundation
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the replay of one node: the parse and the sort of the lines of one log file, the fold of each patch part,
/// and the time values (plan.md §5.3 steps 1 to 3).
@Suite("Replay of one node")
struct ReplayTests {
    /// The ULID text of the test task.
    static let taskULID = "01K6Z3ABCDEFGHJKMNPQRSTVWX"

    /// The ULID text of the test comment.
    static let commentULID = "01K6Z5ABCDEFGHJKMNPQRSTVWX"

    /// The time of step 0 of a test log, in seconds since 1970. Each later step is one second after it.
    static let baseSeconds: TimeInterval = 1_791_000_000

    /// The number of random orders that the shuffle test folds.
    static let shuffleCount = 50

    /// The actor of each test event.
    static let actor = LocalRef.actor(slug: "claude-code")

    /// The ref of the `todo` column.
    static let todoColumn = LocalRef.column(slug: "todo")

    /// The ref of the `doing` column.
    static let doingColumn = LocalRef.column(slug: "doing")

    /// The ref of the `bug` tag.
    static let bugTag = LocalRef.tag(slug: "bug")

    /// The ref of the `ui` tag.
    static let uiTag = LocalRef.tag(slug: "ui")

    /// The first body of the edit tests.
    static let firstBody = "parse the filter\nport the evaluator\n"

    /// The second body of the edit tests: the first body with a changed last line.
    static let secondBody = "parse the filter\nport the parser\n"

    /// The ordinal of the ordinal tests: an ordinal that is not the default.
    static let ordinal = Ordinal(after: .first)

    /// The ordinal of the ordinal tests, as a patch value.
    static let ordinalValue = PatchValue.json(.string(ordinal.value))

    /// The ref of the test task.
    static func taskRef() throws -> LocalRef {
        .task(try #require(ULID(ulidString: taskULID)))
    }

    /// The ref of the test comment.
    static func commentRef() throws -> LocalRef {
        .comment(try #require(ULID(ulidString: commentULID)))
    }

    /// Gives the time of a step of a test log.
    ///
    /// - Parameter step: The step. A larger step is a later time.
    /// - Returns: The time.
    static func date(atStep step: Int) -> Date {
        Date(timeIntervalSince1970: baseSeconds + TimeInterval(step))
    }

    /// Gives the envelope time of a step of a test log.
    ///
    /// - Parameter step: The step.
    /// - Returns: The time, as the envelope `at` holds it.
    static func time(atStep step: Int) -> DateTime {
        DateTime(date(atStep: step))
    }

    /// Makes the log line of one patch. The event id and the time grow with the step, so the line of a larger step
    /// sorts later.
    ///
    /// - Parameters:
    ///   - step: The step of the event.
    ///   - patch: The patch of the event.
    /// - Returns: The text of the line.
    static func line(atStep step: Int, patch: PatchInput) throws -> String {
        let date = date(atStep: step)
        let event = Event(
            id: ULID(timestamp: date),
            txn: ULID(timestamp: date),
            ops: ["updateTask"],
            at: DateTime(date),
            actor: actor,
            patch: patch
        )
        return try event.encodedLine()
    }

    /// Folds lines into the test task.
    ///
    /// - Parameter lines: The lines of the task log.
    /// - Returns: The state of the task.
    static func task(folding lines: [String]) throws -> TaskNode {
        try state(as: TaskNode.self, of: taskRef(), folding: lines)
    }

    /// Folds lines into the state of one node.
    ///
    /// - Parameters:
    ///   - type: The node type that the lines must give.
    ///   - ref: The local ref of the node.
    ///   - lines: The lines of the node log.
    /// - Returns: The state of the node.
    static func state<State: NodeState>(
        as type: State.Type,
        of ref: LocalRef,
        folding lines: [String]
    ) throws -> State {
        try #require(NodeLog(parsing: lines, for: ref).node?.state as? State)
    }

    /// Folds one patch into the state of its node.
    ///
    /// - Parameters:
    ///   - type: The node type that the patch must give.
    ///   - patch: The patch.
    /// - Returns: The state of the node.
    static func state<State: NodeState>(as type: State.Type, folding patch: PatchInput) throws -> State {
        try state(as: type, of: patch.node, folding: [line(atStep: 1, patch: patch)])
    }

    /// Gives an edge that is not resolved yet.
    ///
    /// - Parameter ref: The local ref of the target.
    /// - Returns: The unresolved edge.
    static func edge(to ref: LocalRef) -> EdgeTarget {
        .unresolved(.local(ref))
    }

    /// Gives the diff text from one body to a different body.
    ///
    /// - Parameters:
    ///   - old: The body before the change.
    ///   - new: The body after the change.
    /// - Returns: The unified diff text.
    static func diff(from old: String, to new: String) -> String {
        UnifiedDiff(from: old, to: new).text
    }

    /// Makes a patch that sets the title of a task.
    ///
    /// - Parameters:
    ///   - title: The new title.
    ///   - ref: The local ref of the task. With no ref, the patch changes the test task.
    /// - Returns: The patch.
    static func titlePatch(setting title: String, of ref: LocalRef? = nil) throws -> PatchInput {
        try PatchInput(node: ref ?? taskRef(), set: ["title": .json(.string(title))])
    }

    /// Makes a patch of the test task with an edit of its body.
    ///
    /// - Parameters:
    ///   - old: The body before the change.
    ///   - new: The body after the change.
    /// - Returns: The patch.
    static func editPatch(from old: String, to new: String) throws -> PatchInput {
        try PatchInput(node: taskRef(), edit: PatchEdit(body: diff(from: old, to: new)))
    }

    /// Makes a patch that moves the test task to a column.
    ///
    /// - Parameter column: The local ref of the column.
    /// - Returns: The patch.
    static func movePatch(to column: LocalRef) throws -> PatchInput {
        try PatchInput(node: taskRef(), set: ["column": .ref(.local(column))])
    }

    // MARK: - Set and unset

    @Test("A set writes the value of a property")
    func setWritesValue() throws {
        let line = try Self.line(atStep: 1, patch: Self.titlePatch(setting: "Port the filter"))
        #expect(try Self.task(folding: [line]).title == "Port the filter")
    }

    @Test("Two set title patches give the value of the patch with the larger event id", arguments: [false, true])
    func laterSetWins(reversed: Bool) throws {
        let first = try Self.line(atStep: 1, patch: Self.titlePatch(setting: "first"))
        let second = try Self.line(atStep: 2, patch: Self.titlePatch(setting: "second"))
        let lines = reversed ? [second, first] : [first, second]
        #expect(try Self.task(folding: lines).title == "second")
    }

    @Test("An unset clears the value of a property")
    func unsetClearsValue() throws {
        let lines = [
            try Self.line(atStep: 1, patch: Self.titlePatch(setting: "old")),
            try Self.line(atStep: 2, patch: PatchInput(node: Self.taskRef(), set: ["ordinal": Self.ordinalValue])),
            try Self.line(atStep: 3, patch: PatchInput(node: Self.taskRef(), unset: ["title", "ordinal"])),
        ]
        let task = try Self.task(folding: lines)
        #expect(task.title.isEmpty)
        #expect(task.ordinal == .first)
    }

    @Test("A set of the ordinal and the column gives the typed values")
    func setGivesTypedValues() throws {
        let patch = try PatchInput(
            node: Self.taskRef(),
            set: ["ordinal": Self.ordinalValue, "column": .ref(.local(Self.todoColumn))]
        )
        let task = try Self.state(as: TaskNode.self, folding: patch)
        #expect(task.ordinal == Self.ordinal)
        #expect(task.column == Self.edge(to: Self.todoColumn))
    }

    // MARK: - Add and remove

    @Test("An add and a remove change the members of a set-valued property, in the order of the first add")
    func addAndRemoveChangeMembers() throws {
        let bug = StoredRef.local(Self.bugTag)
        let ui = StoredRef.local(Self.uiTag)
        let lines = [
            try Self.line(atStep: 1, patch: PatchInput(node: Self.taskRef(), add: ["tags": [bug, ui]])),
            try Self.line(atStep: 2, patch: PatchInput(node: Self.taskRef(), remove: ["tags": [bug]])),
            try Self.line(atStep: 3, patch: PatchInput(node: Self.taskRef(), add: ["tags": [ui, bug]])),
        ]
        #expect(try Self.task(folding: lines).tags == [Self.edge(to: Self.uiTag), Self.edge(to: Self.bugTag)])
    }

    @Test("An add gives the assignees and the dependencies of a task, also a dependency in a different board")
    func addGivesEdges() throws {
        let dependency = LocalRef.task(try #require(ULID(ulidString: Self.commentULID)))
        let remote = StoredRef.remote(NodeURI(boardKey: "github.com/o/other", ref: dependency))
        let patch = try PatchInput(
            node: Self.taskRef(),
            add: ["assignees": [.local(Self.actor)], "dependsOn": [.local(dependency), remote]]
        )
        let task = try Self.state(as: TaskNode.self, folding: patch)
        #expect(task.assignees == [Self.edge(to: Self.actor)])
        #expect(task.dependsOn == [Self.edge(to: dependency), .unresolved(remote)])
    }

    // MARK: - Delete

    @Test("A delete true makes a tombstone with the time of the last delete true")
    func deleteMakesTombstone() throws {
        let lines = [
            try Self.line(atStep: 1, patch: Self.titlePatch(setting: "gone")),
            try Self.line(atStep: 2, patch: PatchInput(node: Self.taskRef(), delete: true)),
            try Self.line(atStep: 3, patch: PatchInput(node: Self.taskRef(), delete: true)),
        ]
        let fields = try Self.task(folding: lines).fields
        #expect(fields.deleted == Self.time(atStep: 3))
        #expect(fields.isDeleted)
    }

    @Test("A delete false removes the tombstone and clears the deleted time")
    func undeleteRemovesTombstone() throws {
        let lines = [
            try Self.line(atStep: 1, patch: PatchInput(node: Self.taskRef(), delete: true)),
            try Self.line(atStep: 2, patch: PatchInput(node: Self.taskRef(), delete: false)),
        ]
        let fields = try Self.task(folding: lines).fields
        #expect(fields.deleted == nil)
        #expect(!fields.isDeleted)
    }

    // MARK: - Edit

    @Test("Each edit applies its diff to the current body, in event order")
    func editsApplyInOrder() throws {
        let lines = [
            try Self.line(atStep: 2, patch: Self.editPatch(from: Self.firstBody, to: Self.secondBody)),
            try Self.line(atStep: 1, patch: Self.editPatch(from: "", to: Self.firstBody)),
        ]
        let fields = try Self.task(folding: lines).fields
        #expect(fields.body == Self.secondBody)
        #expect(!fields.hasConflict)
    }

    @Test("An edit that cannot apply puts a conflict block with the event id into the body, and sets the flag")
    func editConflictSetsFlag() throws {
        let conflicting = try Self.line(atStep: 2, patch: Self.editPatch(from: "other\n", to: "changed\n"))
        let lines = [try Self.line(atStep: 1, patch: Self.editPatch(from: "", to: Self.firstBody)), conflicting]
        let eventID = try Event(parsing: conflicting).id.ulidString
        let fields = try Self.task(folding: lines).fields
        #expect(fields.hasConflict)
        #expect(fields.body.contains(UnifiedDiff.ConflictBlock.endPrefix + eventID))
    }

    @Test("An edit whose diff does not parse leaves the body, and the other parts of the patch still apply")
    func badDiffIsSkipped() throws {
        let badEdit = try PatchInput(
            node: Self.taskRef(),
            set: ["title": .json("kept")],
            edit: PatchEdit(body: "not a diff\n")
        )
        let lines = [
            try Self.line(atStep: 1, patch: Self.editPatch(from: "", to: Self.firstBody)),
            try Self.line(atStep: 2, patch: badEdit),
        ]
        let task = try Self.task(folding: lines)
        #expect(task.fields.body == Self.firstBody)
        #expect(task.title == "kept")
    }

    // MARK: - Time values

    @Test("The created time is the time of the first patch, and the updated time is the time of the last patch")
    func timesComeFromFirstAndLastPatch() throws {
        let lines = [
            try Self.line(atStep: 3, patch: Self.titlePatch(setting: "c")),
            try Self.line(atStep: 1, patch: Self.titlePatch(setting: "a")),
            try Self.line(atStep: 2, patch: Self.titlePatch(setting: "b")),
        ]
        let fields = try Self.task(folding: lines).fields
        #expect(fields.created == Self.time(atStep: 1))
        #expect(fields.updated == Self.time(atStep: 3))
    }

    @Test("Each set column of a task is recorded as a move with its time and its column")
    func setColumnRecordsMoves() throws {
        let lines = [
            try Self.line(atStep: 1, patch: Self.movePatch(to: Self.todoColumn)),
            try Self.line(atStep: 2, patch: Self.titlePatch(setting: "moved")),
            try Self.line(atStep: 3, patch: Self.movePatch(to: Self.doingColumn)),
        ]
        let task = try Self.task(folding: lines)
        #expect(
            task.columnMoves == [
                ColumnMove(at: Self.time(atStep: 1), column: Self.edge(to: Self.todoColumn)),
                ColumnMove(at: Self.time(atStep: 3), column: Self.edge(to: Self.doingColumn)),
            ]
        )
        #expect(task.column == Self.edge(to: Self.doingColumn))
    }

    // MARK: - Line order

    /// The lines of a log that uses each patch part, some of them more than one time.
    static func mixedLines() throws -> [String] {
        let bug = StoredRef.local(Self.bugTag)
        let ui = StoredRef.local(Self.uiTag)
        let patches: [PatchInput] = [
            try titlePatch(setting: "one"),
            try PatchInput(node: taskRef(), set: ["ordinal": ordinalValue]),
            try movePatch(to: todoColumn),
            try editPatch(from: "", to: firstBody),
            try PatchInput(node: taskRef(), add: ["tags": [bug, ui]]),
            try PatchInput(node: taskRef(), set: ["title": .json("two"), "points": .json(3)]),
            try PatchInput(node: taskRef(), remove: ["tags": [bug]], delete: true),
            try movePatch(to: doingColumn),
            try PatchInput(node: taskRef(), delete: false),
            try PatchInput(node: taskRef(), unset: ["ordinal"]),
            try editPatch(from: firstBody, to: secondBody),
            try PatchInput(node: taskRef(), add: ["watchers": [.local(actor)]], delete: true),
        ]
        return try patches.enumerated().map { step, patch in try line(atStep: step, patch: patch) }
    }

    @Test("Lines in random orders give the same events, the same state, and the same time values")
    func shuffledLinesFoldTheSame() throws {
        let lines = try Self.mixedLines()
        let expected = NodeLog(parsing: lines, for: try Self.taskRef())
        #expect(expected.node != nil)
        for _ in 0..<Self.shuffleCount {
            let shuffled = lines.shuffled()
            #expect(NodeLog(parsing: shuffled, for: try Self.taskRef()) == expected, "order: \(shuffled)")
        }
    }

    @Test("The events of a log are in the order of their event ids")
    func eventsAreSorted() throws {
        let lines = try Self.mixedLines()
        let log = NodeLog(parsing: lines.reversed(), for: try Self.taskRef())
        let ids = log.events.map(\.id)
        #expect(ids == ids.sorted())
        #expect(ids.count == lines.count)
    }

    // MARK: - Bad lines

    @Test("A line that does not decode is skipped, and the other lines still fold")
    func badLineIsSkipped() throws {
        let lines = [
            try Self.line(atStep: 1, patch: Self.titlePatch(setting: "first")),
            "{not json",
            "",
            #"{"id":"bad"}"#,
            try Self.line(atStep: 2, patch: Self.titlePatch(setting: "second")),
        ]
        let log = NodeLog(parsing: lines, for: try Self.taskRef())
        #expect(log.events.count == 2)
        #expect((log.node?.state as? TaskNode)?.title == "second")
    }

    @Test("A line whose patch changes a different node is skipped")
    func lineOfOtherNodeIsSkipped() throws {
        let lines = [
            try Self.line(atStep: 1, patch: Self.titlePatch(setting: "mine")),
            try Self.line(atStep: 2, patch: PatchInput(node: Self.commentRef(), set: ["title": .json("other")])),
        ]
        let log = NodeLog(parsing: lines, for: try Self.taskRef())
        #expect(log.events.count == 1)
        #expect((log.node?.state as? TaskNode)?.title == "mine")
    }

    @Test("A log with no line that decodes gives no node")
    func noEventGivesNoNode() throws {
        let log = NodeLog(parsing: ["{not json", ""], for: try Self.taskRef())
        #expect(log.events.isEmpty)
        #expect(log.node == nil)
    }

    @Test("A value of the wrong kind for a known property is not read, and the property has its default")
    func wrongKindIsIgnored() throws {
        let patch = try PatchInput(node: Self.todoColumn, set: ["name": .json(7), "order": .json("high")])
        let column = try Self.state(as: ColumnNode.self, folding: patch)
        #expect(column.name.isEmpty)
        #expect(column.order == 0)
    }

    @Test("An ordinal that does not parse is not read, and the task has the first ordinal")
    func badOrdinalIsIgnored() throws {
        let patch = try PatchInput(node: Self.taskRef(), set: ["ordinal": .json("not hex")])
        #expect(try Self.state(as: TaskNode.self, folding: patch).ordinal == .first)
    }

    // MARK: - Unknown properties

    @Test("A property that the node type does not know is kept, but no typed property reads it")
    func unknownPropertyIsKept() throws {
        let watchers: [String: [StoredRef]] = ["watchers": [.local(Self.actor)]]
        let patch = try PatchInput(node: Self.taskRef(), set: ["title": .json("t"), "points": .json(3)], add: watchers)
        let unknown = try Self.state(as: TaskNode.self, folding: patch).fields.unknownProperties
        #expect(unknown.values == ["points": .json(3)])
        #expect(unknown.members == watchers)
    }

    // MARK: - Node types

    @Test("A board log gives the board name")
    func boardHasName() throws {
        let patch = try PatchInput(node: .board, set: ["name": .json("Kanban")])
        let board = try Self.state(as: BoardNode.self, folding: patch)
        #expect(board.name == "Kanban")
    }

    @Test("A column log gives the column name and order")
    func columnHasNameAndOrder() throws {
        let patch = try PatchInput(node: Self.doingColumn, set: ["name": .json("Doing"), "order": .json(2)])
        let column = try Self.state(as: ColumnNode.self, folding: patch)
        #expect(column.name == "Doing")
        #expect(column.order == 2)
    }

    @Test("An actor log gives the actor name and color")
    func actorHasNameAndColor() throws {
        let patch = try PatchInput(node: Self.actor, set: ["name": .json("Claude"), "color": .json("ff8800")])
        let actor = try Self.state(as: ActorNode.self, folding: patch)
        #expect(actor.name == "Claude")
        #expect(actor.color == "ff8800")
    }

    @Test("A tag log gives the tag name, color, and rename target")
    func tagHasNameColorAndRename() throws {
        let patch = try PatchInput(
            node: Self.bugTag,
            set: ["name": .json("Bug"), "color": .json("d73a4a"), "renamedTo": .ref(.local(Self.uiTag))]
        )
        let tag = try Self.state(as: TagNode.self, folding: patch)
        #expect(tag.name == "Bug")
        #expect(tag.color == "d73a4a")
        #expect(tag.renamedTo == Self.edge(to: Self.uiTag))
    }

    @Test("A comment log gives the task and the author of the comment")
    func commentHasTaskAndAuthor() throws {
        let patch = try PatchInput(
            node: Self.commentRef(),
            set: ["task": .ref(.local(Self.taskRef())), "author": .ref(.local(Self.actor))]
        )
        let comment = try Self.state(as: CommentNode.self, folding: patch)
        #expect(comment.task == Self.edge(to: try Self.taskRef()))
        #expect(comment.author == Self.edge(to: Self.actor))
    }
}
