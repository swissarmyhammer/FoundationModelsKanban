import Foundation
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the format of one log line: the envelope and the `PatchInput` of the internal `patch` mutation (plan.md
/// §5.1, §5.5, §12 item 28).
@Suite("Event lines")
struct EventTests {
    /// The ULID text of the test event.
    static let eventULID = "01K6Z4V2D8F3G5H7J9KMNPQRST"

    /// The ULID text of the transaction of the test event.
    static let txnULID = "01K6Z4V2D8F3G5H7J9KMNPQRSV"

    /// The ULID text of the task that the test patches change.
    static let taskULID = "01K6Z3ABCDEFGHJKMNPQRSTVWX"

    /// The ULID text of a task in the same board, as a dependency.
    static let dependencyULID = "01K6Y9ABCDEFGHJKMNPQRSTVWX"

    /// The ULID text of a task in a different board, as a dependency.
    static let remoteULID = "01K6X2ABCDEFGHJKMNPQRSTVWX"

    /// The key of the board of the test log.
    static let currentKey = "github.com/swissarmyhammer/FoundationModelsKanban"

    /// The key of a different board.
    static let otherKey = "github.com/o/other"

    /// The time of the test event.
    static let atText = "2026-10-06T14:49:10.690Z"

    /// The example line of plan.md §5.1, with full ULIDs in place of the elided ids. The keys are in the order of
    /// the plan, not in sorted order.
    static let planLine = #"{"id":"\#(eventULID)","txn":"\#(txnULID)","ops":["addTask"],"#
        + #""at":"\#(atText)","actor":"actor/claude-code","#
        + #""query":"mutation($p: PatchInput!) { patch(input: $p) }","#
        + #""variables":{"p":{"node":"task/\#(taskULID)","type":"Task","#
        + #""set":{"title":"Port the filter DSL","column":"column/todo","ordinal":"80"},"#
        + #""add":{"tags":["tag/kanban"],"#
        + #""dependsOn":["task/\#(dependencyULID)","kanban://\#(otherKey)/task/\#(remoteULID)"]}}}}"#

    /// A line in the canonical form, with sorted keys, that uses each optional part of the envelope and the patch.
    static let canonicalLine = #"{"actor":"actor/claude-code","at":"\#(atText)","boards":["\#(otherKey)"],"#
        + #""id":"\#(eventULID)","ops":["undo"],"query":"mutation($p: PatchInput!) { patch(input: $p) }","#
        + #""txn":"\#(txnULID)","undoes":"\#(taskULID)","#
        + #""variables":{"p":{"delete":false,"edit":{"body":"@@ -1,1 +1,1 @@\n-old\n+new\n"},"#
        + #""node":"task/\#(taskULID)","remove":{"tags":["tag/bug"]},"#
        + #""set":{"column":"column/doing","open":true,"points":3},"type":"Task","unset":["ordinal"]}}}"#

    /// The names of the time values, which no patch can set (plan.md §5.3, §12 item 20).
    static let timeNames = ["created", "updated", "deleted", "started", "completed"]

    /// Reads a ULID from its text.
    static func ulid(_ text: String) throws -> ULID {
        try #require(ULID(ulidString: text))
    }

    /// The task ref of the test patches.
    static func taskRef() throws -> LocalRef {
        .task(try ulid(taskULID))
    }

    /// Makes the test event with a patch: the test ids, the test time, and the actor `claude-code`.
    static func makeEvent(ops: [String], patch: PatchInput) throws -> Event {
        Event(
            id: try ulid(eventULID),
            txn: try ulid(txnULID),
            ops: ops,
            at: try DateTime(rfc3339: atText),
            actor: .actor(slug: "claude-code"),
            patch: patch
        )
    }

    /// Tells if an error is a ``EventError/malformed(detail:)`` error.
    static func isMalformed(_ error: EventError?) -> Bool {
        switch error {
        case .malformed?: true
        default: false
        }
    }

    /// Tells if an error is a ``EventError/unencodable(detail:)`` error.
    static func isUnencodable(_ error: EventError?) -> Bool {
        switch error {
        case .unencodable?: true
        default: false
        }
    }

    // MARK: - Round trip

    @Test("A canonical line round-trips from line to event to line with the same bytes")
    func lineRoundTrips() throws {
        let event = try Event(parsing: Self.canonicalLine)
        #expect(try event.encodedLine() == Self.canonicalLine)
    }

    @Test("An event made in code round-trips from event to line to event")
    func eventRoundTrips() throws {
        let patch = try PatchInput(
            node: Self.taskRef(),
            set: ["column": .ref(.local(.column(slug: "doing"))), "title": .json("Port")],
            add: ["assignees": [.local(.actor(slug: "claude-code"))]],
            edit: PatchEdit(body: "@@ -0,0 +1,1 @@\n+text\n")
        )
        let event = try Self.makeEvent(ops: ["addTask"], patch: patch)
        #expect(try Event(parsing: event.encodedLine()) == event)
    }

    @Test("A line uses sorted keys, no escaped slashes, and the query of the patch mutation")
    func lineIsCanonical() throws {
        let event = try Self.makeEvent(ops: ["deleteTask"], patch: PatchInput(node: Self.taskRef(), delete: true))
        let expected = #"{"actor":"actor/claude-code","at":"\#(Self.atText)","id":"\#(Self.eventULID)","#
            + #""ops":["deleteTask"],"query":"mutation($p: PatchInput!) { patch(input: $p) }","#
            + #""txn":"\#(Self.txnULID)","variables":{"p":{"delete":true,"node":"task/\#(Self.taskULID)","#
            + #""type":"Task"}}}"#
        #expect(try event.encodedLine() == expected)
    }

    // MARK: - The plan example

    @Test("The example line of plan.md §5.1 decodes")
    func planExampleDecodes() throws {
        let event = try Event(parsing: Self.planLine)
        #expect(event.id == (try Self.ulid(Self.eventULID)))
        #expect(event.txn == (try Self.ulid(Self.txnULID)))
        #expect(event.ops == ["addTask"])
        #expect(event.at == (try DateTime(rfc3339: Self.atText)))
        #expect(event.actor == .actor(slug: "claude-code"))
        #expect(event.boards == nil)
        #expect(event.undoes == nil)
        #expect(event.query == Event.patchQuery)
        #expect(event.patch.node == (try Self.taskRef()))
        #expect(event.patch.type == .task)
    }

    @Test("The patch of the plan example holds its refs in the stored form")
    func planExampleHoldsStoredRefs() throws {
        let patch = try Event(parsing: Self.planLine).patch
        let remote = NodeURI(boardKey: Self.otherKey, ref: .task(try Self.ulid(Self.remoteULID)))
        #expect(patch.set["column"] == .ref(.local(.column(slug: "todo"))))
        #expect(patch.set["title"] == .json("Port the filter DSL"))
        #expect(patch.set["ordinal"] == .json("80"))
        #expect(patch.add["tags"] == [.local(.tag(slug: "kanban"))])
        #expect(patch.add["dependsOn"] == [.local(.task(try Self.ulid(Self.dependencyULID))), .remote(remote)])
    }

    // MARK: - The board key

    @Test("A line never holds the key of its own board")
    func lineHoldsNoOwnBoardKey() throws {
        let ownTask = NodeURI(boardKey: Self.currentKey, ref: .task(try Self.ulid(Self.dependencyULID)))
        let otherTask = NodeURI(boardKey: Self.otherKey, ref: .task(try Self.ulid(Self.remoteULID)))
        let dependencies = [ownTask, otherTask].map { StoredRef(uri: $0, inBoard: Self.currentKey) }
        let patch = try PatchInput(node: Self.taskRef(), add: ["dependsOn": dependencies])
        let line = try Self.makeEvent(ops: ["updateTask"], patch: patch).encodedLine()
        #expect(!line.contains(Self.currentKey))
        #expect(line.contains(#""dependsOn":["task/\#(Self.dependencyULID)","kanban://\#(Self.otherKey)/task/"#))
    }

    @Test("An event whose patch holds a value that JSON cannot write gives an encode error")
    func unencodableValueIsRefused() throws {
        let patch = try PatchInput(node: Self.taskRef(), set: ["points": .json(.number(Number(Double.nan)))])
        let event = try Self.makeEvent(ops: ["updateTask"], patch: patch)
        let error = #expect(throws: EventError.self) { try event.encodedLine() }
        #expect(Self.isUnencodable(error))
    }

    // MARK: - Bad lines

    @Test("A line that is not JSON gives a malformed-line error")
    func notJSONIsMalformed() {
        let error = #expect(throws: EventError.self) { try Event(parsing: "not json") }
        #expect(Self.isMalformed(error))
    }

    @Test("A line with no event id gives a malformed-line error")
    func missingIDIsMalformed() {
        let line = Self.canonicalLine.replacingOccurrences(of: #""id":"\#(Self.eventULID)","#, with: "")
        let error = #expect(throws: EventError.self) { try Event(parsing: line) }
        #expect(Self.isMalformed(error))
    }

    @Test("A line with an empty text gives a malformed-line error")
    func emptyLineIsMalformed() {
        let error = #expect(throws: EventError.self) { try Event(parsing: "") }
        #expect(Self.isMalformed(error))
    }

    @Test("A line whose node is not a local ref gives a ref error")
    func badNodeGivesRefError() {
        let line = Self.canonicalLine.replacingOccurrences(of: "task/\(Self.taskULID)", with: "task/not-a-ulid")
        #expect(throws: EventError.invalidRef(.invalidULID(ref: "task/not-a-ulid"))) {
            try Event(parsing: line)
        }
    }

    @Test("A line whose actor is not a local ref gives a ref error")
    func badActorGivesRefError() {
        let line = Self.canonicalLine.replacingOccurrences(of: "actor/claude-code", with: "robot/claude-code")
        #expect(throws: EventError.invalidRef(.invalidLocalRef(ref: "robot/claude-code"))) {
            try Event(parsing: line)
        }
    }

    @Test("A line whose type is not the type of its node gives a type error")
    func typeMismatchIsRefused() throws {
        let line = Self.canonicalLine.replacingOccurrences(of: #""type":"Task""#, with: #""type":"Tag""#)
        #expect(throws: EventError.typeMismatch(node: try Self.taskRef(), type: .tag)) {
            try Event(parsing: line)
        }
    }

    @Test("A line that sets a ref property to a value that is not text gives a ref error")
    func refPropertyMustBeText() {
        let line = Self.canonicalLine.replacingOccurrences(of: #""column":"column/doing""#, with: #""column":7"#)
        #expect(throws: EventError.refMismatch(property: "column")) { try Event(parsing: line) }
    }

    @Test("A line whose set-valued property holds a bad ref gives a ref error")
    func badAddedRefGivesRefError() {
        let line = Self.canonicalLine.replacingOccurrences(of: "tag/bug", with: "tag/")
        #expect(throws: EventError.invalidRef(.invalidLocalRef(ref: "tag/"))) { try Event(parsing: line) }
    }

    // MARK: - Refused set names

    @Test("A patch cannot set a time value", arguments: timeNames)
    func patchRefusesTimeValue(name: String) throws {
        let taskRef = try Self.taskRef()
        #expect(throws: EventError.timeProperty(name: name)) {
            try PatchInput(node: taskRef, set: [name: .json(.string(Self.atText))])
        }
    }

    @Test("A line that sets a time value gives a time error", arguments: timeNames)
    func lineRefusesTimeValue(name: String) {
        let line = Self.canonicalLine.replacingOccurrences(of: #""open":true"#, with: #""\#(name)":"\#(Self.atText)""#)
        #expect(throws: EventError.timeProperty(name: name)) { try Event(parsing: line) }
    }

    @Test("A patch cannot set a ref property to a plain value")
    func patchRefusesPlainValueForRef() throws {
        let taskRef = try Self.taskRef()
        #expect(throws: EventError.refMismatch(property: "column")) {
            try PatchInput(node: taskRef, set: ["column": .json("column/doing")])
        }
    }

    @Test("A patch cannot set a plain property to a ref")
    func patchRefusesRefForPlainValue() throws {
        let taskRef = try Self.taskRef()
        #expect(throws: EventError.refMismatch(property: "title")) {
            try PatchInput(node: taskRef, set: ["title": .ref(.local(.tag(slug: "bug")))])
        }
    }
}
