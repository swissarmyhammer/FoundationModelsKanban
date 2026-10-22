import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests that replay skips only a bad value of a log line, and drops the full line only when its envelope does not
/// decode (plan.md §3.3 rule 7, divergence.md S4). Each test writes the log files in a temporary folder and loads the
/// board from it.
@Suite("Replay of a log line with a bad value", .watcherBudget)
struct ReplayBadValueTests {
    /// The title that a good value of a bad line sets.
    static let keptTitle = "kept"

    /// The JSON text of a value of the wrong kind: a number where the property holds text or a ref.
    static let numberText = "7"

    // MARK: - Fixture

    /// Changes one part of a log line.
    ///
    /// - Parameters:
    ///   - line: The text of a good line.
    ///   - good: The text in the line to change. The line must hold it.
    ///   - bad: The new text.
    /// - Returns: The changed line.
    static func line(_ line: String, replacing good: String, with bad: String) throws -> String {
        try #require(line.contains(good), "the line holds no \(good)")
        return line.replacingOccurrences(of: good, with: bad)
    }

    /// Appends one line of text, with its line break, to the log file of a node. The file must exist.
    ///
    /// - Parameters:
    ///   - text: The text of the line.
    ///   - ref: The local ref of the node.
    ///   - log: The event log of the board.
    static func appendLine(_ text: String, toLogOf ref: LocalRef, in log: EventLog) throws {
        let handle = try FileHandle(forWritingTo: log.fileURL(for: ref))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((text + ReplayTests.lineBreak).utf8))
    }

    /// Loads a board, and gives the state of one task.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the task.
    ///   - log: The event log of the board.
    /// - Returns: The state of the task.
    static func task(_ ref: LocalRef, loadedFrom log: EventLog) async throws -> TaskNode {
        let graph = try await BoardLoader(reading: log).load().graph
        return try #require(try LoaderTests.node(of: ref, in: graph).state as? TaskNode)
    }

    /// Writes a task in the `todo` column, and gives the event log of the board.
    ///
    /// - Parameter directory: The temporary folder of the board.
    /// - Returns: The event log of the board.
    static func logWithTaskInTodo(in directory: TemporaryDirectory) throws -> EventLog {
        let log = EventLog(repositoryAt: directory.url)
        try LoaderTests.append(ReplayTests.movePatch(to: ReplayTests.todoColumn), atStep: 1, to: log)
        return log
    }

    /// Gives the line of a patch that moves the test task to the `doing` column and sets its title to
    /// ``keptTitle``, with the column value changed to a number.
    ///
    /// - Parameter step: The step of the event.
    /// - Returns: The text of the line.
    static func lineWithNumberColumn(atStep step: Int) throws -> String {
        let patch = try PatchInput(
            node: ReplayTests.taskRef(),
            set: ["title": .json(.string(keptTitle)), "column": .ref(.local(ReplayTests.doingColumn))]
        )
        let good = try ReplayTests.line(atStep: step, patch: patch)
        return try line(good, replacing: #""column":"column/doing""#, with: #""column":\#(numberText)"#)
    }

    // MARK: - One bad value

    @Test("A set line with a good title and a column that is a number applies the title, and the column stays")
    func numberColumnIsSkipped() async throws {
        let directory = try TemporaryDirectory()
        let log = try Self.logWithTaskInTodo(in: directory)
        try Self.appendLine(Self.lineWithNumberColumn(atStep: 2), toLogOf: ReplayTests.taskRef(), in: log)
        let task = try await Self.task(ReplayTests.taskRef(), loadedFrom: log)
        #expect(task.title == Self.keptTitle)
        #expect(task.column == ReplayTests.edge(to: ReplayTests.todoColumn))
        #expect(task.columnMoves.count == 1)
    }

    @Test("A line with two bad values and one good value applies the good value")
    func twoBadValuesAreSkipped() async throws {
        let directory = try TemporaryDirectory()
        let log = try Self.logWithTaskInTodo(in: directory)
        let numberColumn = try Self.lineWithNumberColumn(atStep: 2)
        let bad = try Self.line(numberColumn, replacing: #""set":"#, with: #""delete":"yes","set":"#)
        try Self.appendLine(bad, toLogOf: ReplayTests.taskRef(), in: log)
        let task = try await Self.task(ReplayTests.taskRef(), loadedFrom: log)
        #expect(task.title == Self.keptTitle)
        #expect(task.column == ReplayTests.edge(to: ReplayTests.todoColumn))
        #expect(!task.fields.isDeleted)
    }

    @Test("An added member that is not a ref is skipped, and the other members apply")
    func badAddedMemberIsSkipped() async throws {
        let directory = try TemporaryDirectory()
        let log = try Self.logWithTaskInTodo(in: directory)
        let tags: [StoredRef] = [.local(ReplayTests.bugTag), .local(ReplayTests.uiTag)]
        let good = try ReplayTests.line(atStep: 2, patch: PatchInput(node: ReplayTests.taskRef(), add: ["tags": tags]))
        let bad = try Self.line(good, replacing: #""tag/ui""#, with: Self.numberText)
        try Self.appendLine(bad, toLogOf: ReplayTests.taskRef(), in: log)
        let task = try await Self.task(ReplayTests.taskRef(), loadedFrom: log)
        #expect(task.tags == [ReplayTests.edge(to: ReplayTests.bugTag)])
    }

    @Test("A set of a time value is skipped, and the other values of the line apply")
    func timeValueIsSkipped() async throws {
        let directory = try TemporaryDirectory()
        let log = try Self.logWithTaskInTodo(in: directory)
        let patch = try PatchInput(
            node: ReplayTests.taskRef(),
            set: ["title": .json(.string(Self.keptTitle)), "points": .json(3)]
        )
        let good = try ReplayTests.line(atStep: 2, patch: patch)
        let bad = try Self.line(good, replacing: #""points":3"#, with: #""created":"\#(EventTests.atText)""#)
        try Self.appendLine(bad, toLogOf: ReplayTests.taskRef(), in: log)
        let task = try await Self.task(ReplayTests.taskRef(), loadedFrom: log)
        #expect(task.title == Self.keptTitle)
        #expect(task.fields.created == ReplayTests.time(atStep: 1))
        #expect(task.fields.unknownProperties.values.isEmpty)
    }

    @Test("An unset name that is not text is skipped, and the other names of the line clear")
    func badUnsetNameIsSkipped() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let ref = try ReplayTests.taskRef()
        let values: [String: PatchValue] = [
            "title": .json(.string(Self.keptTitle)), "ordinal": ReplayTests.ordinalValue,
        ]
        try LoaderTests.append(PatchInput(node: ref, set: values), atStep: 1, to: log)
        let good = try ReplayTests.line(atStep: 2, patch: PatchInput(node: ref, unset: ["ordinal", "title"]))
        let bad = try Self.line(good, replacing: #"["ordinal","#, with: "[\(Self.numberText),")
        try Self.appendLine(bad, toLogOf: ref, in: log)
        let task = try await Self.task(ref, loadedFrom: log)
        #expect(task.title.isEmpty)
        #expect(task.ordinal == ReplayTests.ordinal)
    }

    // MARK: - Bad envelope

    @Test("A line whose envelope cannot decode is dropped, and the load continues")
    func badEnvelopeDropsLine() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let ref = try ReplayTests.taskRef()
        let other = LocalRef.task(ULID())
        try LoaderTests.append(ReplayTests.titlePatch(setting: "first"), atStep: 1, to: log)
        let good = try ReplayTests.line(atStep: 2, patch: ReplayTests.titlePatch(setting: "second"))
        let bad = try Self.line(good, replacing: #""actor":"actor/claude-code""#, with: #""actor":"robot/claude-code""#)
        try Self.appendLine(bad, toLogOf: ref, in: log)
        try LoaderTests.append(ReplayTests.titlePatch(setting: "other", of: other), atStep: 3, to: log)
        let loaded = try await BoardLoader(reading: log).load()
        let task = try #require(try LoaderTests.node(of: ref, in: loaded.graph).state as? TaskNode)
        let otherTask = try #require(try LoaderTests.node(of: other, in: loaded.graph).state as? TaskNode)
        #expect(task.title == "first")
        #expect(otherTask.title == "other")
        #expect(loaded.events.count == 2)
    }
}
