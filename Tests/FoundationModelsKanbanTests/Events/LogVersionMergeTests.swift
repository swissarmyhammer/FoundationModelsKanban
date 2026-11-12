import Foundation
import Synchronization
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the merge of the versions of one log file: the iCloud conflict versions of a board in iCloud Drive (TestudoApp
/// D179). A unit test cannot make a real conflict version, because only a ubiquitous item has them. Thus the tests use
/// plain version files and a ``FileVersionSource`` that a test controls.
@Suite("Merge of the versions of a log file")
struct LogVersionMergeTests {
    /// The line feed that ends each line.
    static let lineFeed = "\n"

    /// A whole line that is not JSON.
    static let badLine = "not json"

    /// Makes the text of a log file from its lines. Each line ends with a line feed.
    ///
    /// - Parameter lines: The lines.
    /// - Returns: The text of the file.
    static func file(_ lines: [String]) -> Data {
        Data(lines.map { line in line + lineFeed }.joined().utf8)
    }

    /// Makes the line of the event of one step of the test task.
    ///
    /// - Parameter step: The step. A larger step gives a later event id.
    /// - Returns: The line, with no line feed.
    static func line(atStep step: Int) throws -> String {
        try EventLogTests.titleEvent(atStep: step, setting: "title \(step)").encodedLine()
    }

    /// Gives the lines of a merged file.
    ///
    /// - Parameter data: The merged file.
    /// - Returns: The lines, with no line feed.
    static func lines(of data: Data) -> [String] {
        String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).dropLast()
            .map(String.init)
    }

    @Test("Each event is in the merge one time, in the order of the event ids")
    func eachEventOneTimeInIDOrder() throws {
        let one = try Self.line(atStep: 1)
        let two = try Self.line(atStep: 2)
        let three = try Self.line(atStep: 3)
        let four = try Self.line(atStep: 4)

        let merged = LogVersionMerge.merged([Self.file([one, two, four]), Self.file([one, three, two])])

        #expect(Self.lines(of: merged) == [one, two, three, four])
    }

    @Test("A torn last line of a version is not in the merge, and the other lines of the version are")
    func tornTailIsDropped() throws {
        let one = try Self.line(atStep: 1)
        let two = try Self.line(atStep: 2)
        let three = try Self.line(atStep: 3)
        let torn = Self.file([one, two]) + Data(three.prefix(three.count / 2).utf8)

        let merged = LogVersionMerge.merged([torn, Self.file([one])])

        #expect(Self.lines(of: merged) == [one, two])
    }

    @Test("A torn last line of one version does not hide the whole line of a different version")
    func tornTailWithWholeLineElsewhere() throws {
        let one = try Self.line(atStep: 1)
        let two = try Self.line(atStep: 2)
        let torn = Self.file([one]) + Data(two.prefix(two.count / 2).utf8)

        let merged = LogVersionMerge.merged([torn, Self.file([two])])

        #expect(Self.lines(of: merged) == [one, two])
    }

    @Test("An abort record is in the merge one time, in the order of its transaction id")
    func abortRecordOneTime() throws {
        let one = try Self.line(atStep: 1)
        let three = try Self.line(atStep: 3)
        let abortTxn = ULID(timestamp: ReplayTests.date(atStep: 2))
        let abort = String(decoding: try JSONEncoder().encode(TransactionAbort(txn: abortTxn)), as: UTF8.self)

        let merged = LogVersionMerge.merged([Self.file([one, abort]), Self.file([three, abort])])

        #expect(Self.lines(of: merged) == [one, abort, three])
    }

    @Test("A whole line that does not decode stays one time, after the lines with an id")
    func undecodedLineStays() throws {
        let one = try Self.line(atStep: 1)
        let two = try Self.line(atStep: 2)

        let merged = LogVersionMerge.merged([Self.file([Self.badLine, two]), Self.file([one, Self.badLine])])

        #expect(Self.lines(of: merged) == [one, two, Self.badLine])
    }

    @Test("Versions with no whole line give an empty file")
    func noLinesGiveEmptyFile() {
        #expect(LogVersionMerge.merged([Data(), Data("{\"id\"".utf8)]).isEmpty)
        #expect(LogVersionMerge.merged([]).isEmpty)
    }

    @Test("A merge of version files writes the log, and the log reads each event of all versions")
    func mergeOfFilesWritesTheLog() throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let first = try EventLogTests.titleEvent(atStep: 1, setting: "first")
        let second = try EventLogTests.titleEvent(atStep: 2, setting: "second")
        let ref = first.patch.node
        try log.append(contentsOf: [first], toLogOf: ref)
        let version = directory.url.appending(path: "conflict.jsonl", directoryHint: .notDirectory)
        try Self.file([try first.encodedLine(), try second.encodedLine()]).write(to: version)

        try LogVersionMerge.merge(versionsAt: [version], intoLogAt: log.fileURL(for: ref))

        let read = try log.readLog(of: ref)
        #expect(read.events.map(\.id) == [first.id, second.id])
        #expect((read.node?.state as? TaskNode)?.title == "second")
    }

    @Test("A merge into a log that is not there makes the log from the versions")
    func mergeIntoMissingLog() throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let first = try EventLogTests.titleEvent(atStep: 1, setting: "first")
        let ref = first.patch.node
        let file = log.fileURL(for: ref)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let version = directory.url.appending(path: "conflict.jsonl", directoryHint: .notDirectory)
        try Self.file([try first.encodedLine()]).write(to: version)

        try LogVersionMerge.merge(versionsAt: [version], intoLogAt: file)

        #expect(try log.readLog(of: ref).events.map(\.id) == [first.id])
    }

    @Test("The resolve merges a log with conflict versions, and then marks the versions resolved")
    func resolveMergesAndMarksResolved() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let first = try EventLogTests.titleEvent(atStep: 1, setting: "first")
        let second = try EventLogTests.titleEvent(atStep: 2, setting: "second")
        let ref = first.patch.node
        try log.append(contentsOf: [first], toLogOf: ref)
        let file = log.fileURL(for: ref)
        let version = directory.url.appending(path: "conflict.jsonl", directoryHint: .notDirectory)
        try Self.file([try second.encodedLine()]).write(to: version)
        let source = FakeFileVersionSource(conflicts: [file.canonicalPath: [version]])

        let resolved = try await log.resolveConflicts(ofFilesAt: [file], with: source)

        #expect(resolved == [file])
        #expect(try log.readLog(of: ref).events.map(\.id) == [first.id, second.id])
        #expect(source.resolvedPaths == [file.canonicalPath])
    }

    @Test("The resolve does not change a log with no conflict versions")
    func resolveWithoutConflicts() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let first = try EventLogTests.titleEvent(atStep: 1, setting: "first")
        let ref = first.patch.node
        try log.append(contentsOf: [first], toLogOf: ref)
        let file = log.fileURL(for: ref)
        let before = try Data(contentsOf: file)
        let source = FakeFileVersionSource(conflicts: [:])

        let resolved = try await log.resolveConflicts(ofFilesAt: [file], with: source)

        #expect(resolved.isEmpty)
        #expect(try Data(contentsOf: file) == before)
        #expect(source.resolvedPaths.isEmpty)
    }

    @Test("A file of the board that is not a log keeps its current version, and its conflict versions are resolved")
    func resolveOfOtherFileKeepsCurrent() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        try log.prepareDirectory()
        let file = log.directory.appending(path: EventLog.gitattributesFileName, directoryHint: .notDirectory)
        let before = try Data(contentsOf: file)
        let version = directory.url.appending(path: "conflict.txt", directoryHint: .notDirectory)
        try Data("other\n".utf8).write(to: version)
        let source = FakeFileVersionSource(conflicts: [file.canonicalPath: [version]])

        let resolved = try await log.resolveConflicts(ofFilesAt: [file], with: source)

        #expect(resolved == [file])
        #expect(try Data(contentsOf: file) == before)
        #expect(source.resolvedPaths == [file.canonicalPath])
    }

    @Test("A batch that holds the board directory checks each log file of the board")
    func boardDirectoryChecksEachLog() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let first = try EventLogTests.titleEvent(atStep: 1, setting: "first")
        let second = try EventLogTests.titleEvent(atStep: 2, setting: "second")
        let ref = first.patch.node
        try log.append(contentsOf: [first], toLogOf: ref)
        let file = log.fileURL(for: ref)
        let version = directory.url.appending(path: "conflict.jsonl", directoryHint: .notDirectory)
        try Self.file([try second.encodedLine()]).write(to: version)
        let source = FakeFileVersionSource(conflicts: [file.canonicalPath: [version]])

        let resolved = try await log.resolveConflicts(ofFilesAt: [log.directory], with: source)

        #expect(resolved.map(\.canonicalPath) == [file.canonicalPath])
        #expect(try log.readLog(of: ref).events.map(\.id) == [first.id, second.id])
    }
}

/// A ``FileVersionSource`` that a test controls: it gives fixed conflict version files, and records each resolve.
final class FakeFileVersionSource: FileVersionSource {
    /// The conflict version files of each file, by the canonical path of the file.
    private let conflicts: [String: [URL]]

    /// The canonical path of each file whose conflict versions were resolved, in the order of the calls.
    private let resolved = Mutex<[String]>([])

    /// Makes the source.
    ///
    /// - Parameter conflicts: The conflict version files of each file, by the canonical path of the file.
    init(conflicts: [String: [URL]]) {
        self.conflicts = conflicts
    }

    /// The canonical path of each file whose conflict versions were resolved, in the order of the calls.
    var resolvedPaths: [String] {
        resolved.withLock { paths in paths }
    }

    func conflictVersions(of file: URL) -> [URL] {
        resolved.withLock { paths in paths.contains(file.canonicalPath) } ? [] : conflicts[file.canonicalPath, default: []]
    }

    func contentsURL(of version: URL) -> URL {
        version
    }

    func markResolved(_ versions: [URL], of file: URL) throws {
        resolved.withLock { paths in paths.append(file.canonicalPath) }
    }
}
