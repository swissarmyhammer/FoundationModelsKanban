import Foundation
import ULID

/// The log files of one board: the `.kanban/` directory of a repo (plan.md §5.2).
///
/// Each node has its own log file, and each line of a file is one ``Event`` of that node:
///
/// ```
/// .kanban/
///   board.jsonl
///   columns/<slug>.jsonl
///   actors/<slug>.jsonl
///   tags/<slug>.jsonl
///   tasks/<ULID>.jsonl
///   comments/<ULID>.jsonl
///   .gitattributes            # *.jsonl merge=union
///   .gitignore                # .lock
///   .lock                     # the write lock
/// ```
///
/// A write appends lines and never changes a line that is in a file. A writer holds the exclusive lock of the board
/// (``lock()``) while it checks the file signatures and appends (plan.md §5.4 step 5).
struct EventLog: Hashable, Sendable {
    /// The name of the directory of the board in the repo.
    static let directoryName = ".kanban"

    /// The extension of each log file.
    static let logExtension = "jsonl"

    /// The name of the log file of the board node.
    static let boardFileName = "\(PatchNodeType.board.pathSegment).\(logExtension)"

    /// The name of the lock file.
    static let lockFileName = ".lock"

    /// The name of the git attributes file of the board.
    static let gitattributesFileName = ".gitattributes"

    /// The name of the git ignore file of the board.
    static let gitignoreFileName = ".gitignore"

    /// The git files that the first write makes, by file name. The `union` merge driver keeps the lines of both
    /// sides when two branches change the same log (plan.md §12 item 5). Git does not track the lock file.
    static let gitFiles = [
        gitattributesFileName: "*.\(logExtension) merge=union\n",
        gitignoreFileName: "\(lockFileName)\n",
    ]

    /// The character at the end of each line.
    static let lineBreak = "\n"

    /// The characters that end a line when a log file is read: ``lineBreak``, and the carriage return and line feed
    /// of a file that a Windows editor wrote. Swift keeps the two characters of `"\r\n"` as one `Character`.
    private static let lineBreaks: Set<Character> = [Character(lineBreak), "\r\n"]

    /// The `.kanban/` directory of the board.
    let directory: URL

    /// Makes the event log of the board of a repo. The directory does not have to exist.
    ///
    /// - Parameter root: The root directory of the repo.
    init(repositoryAt root: URL) {
        directory = root.appending(path: Self.directoryName, directoryHint: .isDirectory)
    }

    /// The lock file of the board.
    var lockFileURL: URL {
        directory.appending(path: Self.lockFileName, directoryHint: .notDirectory)
    }

    /// Gives the log file of one node.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The file, for example `.kanban/tasks/<ULID>.jsonl`. The file does not have to exist.
    func fileURL(for ref: LocalRef) -> URL {
        guard let localID = ref.localID, let name = ref.nodeType.logDirectoryName else {
            return directory.appending(path: Self.boardFileName, directoryHint: .notDirectory)
        }
        return directory
            .appending(path: name, directoryHint: .isDirectory)
            .appending(path: localID, directoryHint: .notDirectory)
            .appendingPathExtension(Self.logExtension)
    }
}

// MARK: - Append

extension EventLog {
    /// Appends events to the log file of one node, one line for each event, in the order of the list.
    ///
    /// The append makes the directories that are necessary, and the git files of the board that are not there. It
    /// does not change a line that is in the file. When the last line of the file has no line break (for example
    /// after a manual edit), the append adds the line break first. An empty list writes nothing.
    ///
    /// - Parameters:
    ///   - events: The events. Each event must change the node.
    ///   - ref: The local ref of the node.
    /// - Throws: ``EventLogError/nodeMismatch(log:event:)`` when an event changes a different node, and then the
    ///   append writes nothing. ``EventLogError/unencodable(_:)`` when an event cannot be a line.
    ///   ``EventLogError/fileSystem(path:detail:)`` when a directory or a file cannot be written.
    func append(contentsOf events: [Event], toLogOf ref: LocalRef) throws(EventLogError) {
        if let other = events.first(where: { event in event.patch.node != ref }) {
            throw .nodeMismatch(log: ref, event: other.patch.node)
        }
        let lines = try events.map { event throws(EventLogError) in try Self.line(of: event) }
        guard !lines.isEmpty else {
            return
        }
        try prepareDirectory()
        let file = fileURL(for: ref)
        try Self.run(onFileAt: file) {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.write(appending: lines.joined(), to: file)
        }
    }

    /// Writes an event as one line, with its line break.
    ///
    /// - Parameter event: The event.
    /// - Returns: The text of the line.
    /// - Throws: ``EventLogError/unencodable(_:)`` when the event cannot be JSON.
    private static func line(of event: Event) throws(EventLogError) -> String {
        do {
            return try event.encodedLine() + lineBreak
        } catch {
            throw .unencodable(error)
        }
    }

    /// Makes the directory of the board and each git file that is not there. A git file that is there does not
    /// change.
    ///
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the directory or a file cannot be written.
    func prepareDirectory() throws(EventLogError) {
        try Self.run(onFileAt: directory) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for (name, text) in Self.gitFiles.sorted(by: { $0.key < $1.key }) {
            let file = directory.appending(path: name, directoryHint: .notDirectory)
            try Self.run(onFileAt: file) {
                guard !FileManager.default.fileExists(atPath: file.path) else {
                    return
                }
                try Data(text.utf8).write(to: file, options: .atomic)
            }
        }
    }

    /// Appends text at the end of a file. The file is made when it is not there.
    ///
    /// - Parameters:
    ///   - text: The lines to add, each with its line break.
    ///   - file: The file.
    /// - Throws: An error from `FileHandle` when the file cannot be read or written.
    private static func write(appending text: String, to file: URL) throws {
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        let handle = try FileHandle(forUpdating: file)
        defer { try? handle.close() }
        let prefix = try hasLineBreakAtEnd(of: handle) ? "" : lineBreak
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((prefix + text).utf8))
    }

    /// Tells if a file is empty or ends with a line break.
    ///
    /// - Parameter handle: The open file.
    /// - Returns: `true` when the next line can start at the end of the file.
    /// - Throws: An error from `FileHandle` when the file cannot be read.
    private static func hasLineBreakAtEnd(of handle: FileHandle) throws -> Bool {
        let end = try handle.seekToEnd()
        guard end > 0 else {
            return true
        }
        try handle.seek(toOffset: end - 1)
        return try handle.read(upToCount: 1) == Data(lineBreak.utf8)
    }
}

// MARK: - Read

extension EventLog {
    /// Reads the log file of one node, and folds its lines into the state of the node.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The folded log. A node with no file gives a log with no events and no node.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the file is there and cannot be read.
    func readLog(of ref: LocalRef) throws(EventLogError) -> NodeLog {
        let data = try Self.runIfPresent(onFileAt: fileURL(for: ref)) { file in try Data(contentsOf: file) }
        return NodeLog(parsing: Self.lines(of: data ?? Data()).map(String.init), for: ref)
    }

    /// Splits the data of a log file into its lines. A line that holds only white space is not in the result.
    ///
    /// Only a line feed, or a carriage return and a line feed, ends a line. `JSONEncoder` does not escape U+2028,
    /// U+2029 or U+0085, so these characters can be in a JSON line, and they must not split it. The replay and the
    /// file signature use this one split.
    ///
    /// - Parameter data: The data of the file.
    /// - Returns: The lines, in file order, with no line break.
    private static func lines(of data: Data) -> [Substring] {
        String(decoding: data, as: UTF8.self)
            .split { character in lineBreaks.contains(character) }
            .filter { line in !line.allSatisfy(\.isWhitespace) }
    }
}

// MARK: - Signatures

/// The signature of one log file: the size, the modification time, and the id of the last event (plan.md §5.6).
///
/// The live graph records the signature of each file that it read. A watcher event for a file with the same
/// signature is ignored, and the commit check compares the signatures under the lock (plan.md §5.4 step 5).
struct FileSignature: Hashable, Sendable {
    /// The size of the file, in bytes.
    let size: Int

    /// The time of the last change of the file.
    let modified: Date

    /// The id of the event of the last line of the file, or `nil` when the file has no line, or its last line does
    /// not have an event id.
    let lastEventID: ULID?
}

extension EventLog {
    /// Calculates the signature of the log file of one node.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The signature, or `nil` when the node has no file.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the file is there and cannot be read.
    func signature(of ref: LocalRef) throws(EventLogError) -> FileSignature? {
        try Self.runIfPresent(onFileAt: fileURL(for: ref)) { file in
            let data = try Data(contentsOf: file)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            return FileSignature(
                size: data.count,
                modified: attributes[.modificationDate] as? Date ?? .distantPast,
                lastEventID: Self.lines(of: data).last.flatMap(EventIDLine.id(of:))
            )
        }
    }

    /// Lists each node file of the board with its signature. A file in a node directory that is not a log, or whose
    /// name is not a valid local id, is not in the list.
    ///
    /// - Returns: The signature of each node file, by the local ref of its node. A board with no directory gives an
    ///   empty list.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a directory or a file cannot be read.
    func nodeFileSignatures() throws(EventLogError) -> [LocalRef: FileSignature] {
        let directoryRefs = try PatchNodeType.allCases.map { type throws(EventLogError) in
            try nodeRefs(ofType: type)
        }
        let refs = [LocalRef.board] + directoryRefs.joined()
        let signatures = try refs.map { ref throws(EventLogError) in (ref, try signature(of: ref)) }
        return Dictionary(
            uniqueKeysWithValues: signatures.compactMap { ref, signature in signature.map { found in (ref, found) } }
        )
    }

    /// Lists the refs of the nodes that have a file in the directory of a node type.
    ///
    /// - Parameter type: The node type.
    /// - Returns: The refs. The board type has no directory, so it gives no ref.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the directory is there and cannot be read.
    func nodeRefs(ofType type: PatchNodeType) throws(EventLogError) -> [LocalRef] {
        guard let name = type.logDirectoryName else {
            return []
        }
        let folder = directory.appending(path: name, directoryHint: .isDirectory)
        let files = try Self.runIfPresent(onFileAt: folder) { url in
            try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        }
        return (files ?? [])
            .filter { file in file.pathExtension == Self.logExtension }
            .compactMap { file in Self.ref(ofFile: file, type: type) }
    }

    /// Finds the node of a changed file of the board, for example a path that the file watcher reports (plan.md
    /// §5.6).
    ///
    /// The file does not have to exist, because a removed file is also a change. The compare of the directories
    /// resolves symbolic links, so `/var/…` and `/private/var/…` give the same board.
    ///
    /// - Parameter file: The changed file.
    /// - Returns: The local ref of the node of the file, or `nil` when the file is not a node log of this board (for
    ///   example the lock file, a file in a different directory, or a name that is not a valid local id).
    func ref(ofFileAt file: URL) -> LocalRef? {
        guard file.pathExtension == Self.logExtension else {
            return nil
        }
        let folder = file.deletingLastPathComponent()
        if file.lastPathComponent == Self.boardFileName, isBoardDirectory(at: folder) {
            return .board
        }
        let type = PatchNodeType.allCases.first { type in type.logDirectoryName == folder.lastPathComponent }
        guard let type, isBoardDirectory(at: folder.deletingLastPathComponent()) else {
            return nil
        }
        return Self.ref(ofFile: file, type: type)
    }

    /// Tells if a directory is the `.kanban/` directory of this board.
    ///
    /// - Parameter folder: The directory.
    /// - Returns: `true` when the two paths are the same after the symbolic links resolve.
    func isBoardDirectory(at folder: URL) -> Bool {
        folder.resolvingSymlinksInPath().path == directory.resolvingSymlinksInPath().path
    }

    /// Reads the local ref of a log file from its name.
    ///
    /// - Parameters:
    ///   - file: The log file.
    ///   - type: The node type of the directory of the file.
    /// - Returns: The ref, or `nil` when the name is not a valid local id. The skip is recorded with swift-log.
    private static func ref(ofFile file: URL, type: PatchNodeType) -> LocalRef? {
        let text = "\(type.pathSegment)\(LocalRef.separator)\(file.deletingPathExtension().lastPathComponent)"
        do {
            return try LocalRef(parsing: text)
        } catch {
            Log.kanban.warning(
                "The event log skips a file whose name is not a valid local id",
                metadata: ["file": "\(file.path)", "error": "\(error)"]
            )
            return nil
        }
    }
}

/// The event id of one log line. The signature reads only this field, so a line whose patch breaks a rule still
/// gives its id.
private struct EventIDLine: Decodable {
    /// The event id.
    let id: ULID

    /// Reads the event id of one line.
    ///
    /// - Parameter line: The text of the line.
    /// - Returns: The event id, or `nil` when the line is not JSON or has no valid `id`.
    static func id(of line: Substring) -> ULID? {
        try? JSONDecoder().decode(Self.self, from: Data(line.utf8)).id
    }
}

// MARK: - File system calls

extension EventLog {
    /// Runs a file system call, and changes its error to an ``EventLogError``.
    ///
    /// - Parameters:
    ///   - url: The file or the directory of the call, for the error.
    ///   - call: The call.
    /// - Returns: The result of the call.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the call fails.
    private static func run<Value>(onFileAt url: URL, _ call: () throws -> Value) throws(EventLogError) -> Value {
        do {
            return try call()
        } catch {
            throw .fileSystem(path: url.path, detail: String(describing: error))
        }
    }

    /// Runs a file system call that reads a file or a directory that does not have to exist.
    ///
    /// - Parameters:
    ///   - url: The file or the directory to read.
    ///   - call: The call. It gets `url`.
    /// - Returns: The result of the call, or `nil` when the file or the directory is not there.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the call fails for a different reason.
    private static func runIfPresent<Value>(
        onFileAt url: URL,
        _ call: (URL) throws -> Value
    ) throws(EventLogError) -> Value? {
        try run(onFileAt: url) {
            do {
                return try call(url)
            } catch CocoaError.fileReadNoSuchFile {
                return nil
            }
        }
    }
}

// MARK: - Directories

extension PatchNodeType {
    /// The name of the directory of the log files of this node type, or `nil` for the board, whose one log file is
    /// in the `.kanban/` directory (plan.md §5.2).
    var logDirectoryName: String? {
        switch self {
        case .board: nil
        case .column: "columns"
        case .task: "tasks"
        case .actor: "actors"
        case .tag: "tags"
        case .comment: "comments"
        }
    }
}

// MARK: - Errors

/// An error from the read or the write of the log files of a board.
///
/// The ``KanbanError`` catalog has no code for these errors, because the caller of the tool cannot correct them.
enum EventLogError: Error, Hashable, Sendable {
    /// An event of an append changes a different node than the node of the log file.
    case nodeMismatch(log: LocalRef, event: LocalRef)

    /// An event cannot be written as a line.
    case unencodable(EventError)

    /// A file or a directory cannot be read or written. The detail is the error of the file system.
    case fileSystem(path: String, detail: String)

    /// The lock file cannot be opened or locked. The code is the `errno` value.
    case lockFailed(path: String, code: Int32)
}
