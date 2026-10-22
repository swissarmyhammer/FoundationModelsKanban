import Foundation
import FoundationModelsExtras
import ULID

/// The log files of one board: the `.kanban/` directory of a repo (plan.md §5.2).
///
/// Each node has its own log file, and each line of a file is one ``Event`` of that node. Each log file is a
/// ``JSONLFile``: it is written and read only through that type, and it is append-only.
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

    /// The `.kanban/` directory of the board.
    let directory: URL

    /// Makes the event log of the board of a repo. The directory does not have to exist.
    ///
    /// - Parameter root: The root directory of the repo.
    init(repositoryAt root: URL) {
        directory = root.appending(path: Self.directoryName, directoryHint: .isDirectory)
    }

    /// Gives the board log of a repo: the log file of the board node, `.kanban/board.jsonl`. Each reader of the board
    /// log of a repo gets its location here, so that the location is in one place.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The file. The file does not have to exist.
    static func boardLogURL(inRepositoryAt root: URL) -> URL {
        EventLog(repositoryAt: root).fileURL(for: .board)
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
    /// Each line goes through ``JSONLFile/append(_:)``: the file opens in append mode, the whole line goes to the disk
    /// in one write, and an fsync follows each line, so that a crash after the call does not lose a line
    /// (divergence.md Q23). The append makes the directories that are necessary, and the git files of the board that
    /// are not there. It does not change a byte that is in the file. When the file ends with a torn line (for example
    /// after a crash or a manual edit), the line break that ends it goes out in the write of the next line. An empty
    /// list writes nothing.
    ///
    /// - Parameters:
    ///   - events: The events. Each event must change the node.
    ///   - ref: The local ref of the node.
    /// - Throws: ``EventLogError/nodeMismatch(log:event:)`` when an event changes a different node, and
    ///   ``EventLogError/unencodable(_:)`` when an event cannot be a line. In both cases the append writes nothing.
    ///   ``EventLogError/fileSystem(path:detail:)`` when a directory or a file cannot be written.
    func append(contentsOf events: [Event], toLogOf ref: LocalRef) throws(EventLogError) {
        if let other = events.first(where: { event in event.patch.node != ref }) {
            throw .nodeMismatch(log: ref, event: other.patch.node)
        }
        guard !events.isEmpty else {
            return
        }
        try Self.checkEncoding(of: events)
        try prepareDirectory()
        let file = fileURL(for: ref)
        try Self.run(onFileAt: file) {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        let lines = JSONLFile(url: file)
        for event in events {
            do {
                try lines.append(event)
            } catch {
                throw Self.failure(of: error, onFileAt: file)
            }
        }
    }

    /// Appends the abort record of a transaction to the log file of one node, through ``JSONLFile/append(_:)``: one
    /// line, with an fsync after it (plan.md §5.4 step 5.5). Replay then skips each event of the transaction in the
    /// file, and each line that the transaction copied (``Event/copiedBy``). The append does not change a byte that is
    /// in the file. A node with no file has no line of the transaction, so the call writes nothing and makes no file.
    ///
    /// - Parameters:
    ///   - txn: The transaction ULID.
    ///   - ref: The local ref of the node.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the file cannot be read or written.
    func appendAbort(of txn: ULID, toLogOf ref: LocalRef) throws(EventLogError) {
        let file = fileURL(for: ref)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return
        }
        do {
            try JSONLFile(url: file).append(TransactionAbort(txn: txn))
        } catch {
            throw Self.failure(of: error, onFileAt: file)
        }
    }

    /// Checks that each event can be a line before the first line is written, so that an event that cannot be JSON
    /// writes no line of the list.
    ///
    /// - Parameter events: The events.
    /// - Throws: ``EventLogError/unencodable(_:)`` for the first event that cannot be JSON.
    private static func checkEncoding(of events: [Event]) throws(EventLogError) {
        for event in events {
            do {
                _ = try event.encodedLine()
            } catch {
                throw .unencodable(error)
            }
        }
    }

    /// Makes the directory of the board and each git file that is not there. A git file that is there does not
    /// change. A `.kanban/` with Rust files gets no new board (divergence.md Q6): the call checks it first
    /// (``checkCompatibility()``), and then makes nothing.
    ///
    /// - Throws: ``EventLogError/incompatibleBoard(directory:)`` when the `.kanban/` directory has a Rust-only path,
    ///   and then nothing is made. ``EventLogError/fileSystem(path:detail:)`` when the directory or a file cannot be
    ///   read or written.
    func prepareDirectory() throws(EventLogError) {
        try checkCompatibility()
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
}

// MARK: - Read

extension EventLog {
    /// Reads the log file of one node through ``JSONLFile/records(as:)``, and folds its events into the state of the
    /// node.
    ///
    /// Only a line feed ends a line, so a value that holds U+2028, U+2029 or U+0085 stays in its line. The read
    /// drops a torn final line, the bytes after the last line feed, and skips a whole line that does not decode; each
    /// of the two is recorded with swift-log. A line ends with a carriage return when a Windows editor wrote it, and
    /// JSON reads the carriage return as white space.
    ///
    /// A line can also be the abort record of a transaction (``TransactionAbort``). The read then skips each event of
    /// that transaction in the file, and each line that the transaction copied (``Event/copiedBy``), wherever its line
    /// is, and records the skip with swift-log (plan.md §5.4 step 5.5).
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The folded log. A node with no file gives a log with no events and no node.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the file is there and cannot be read.
    func readLog(of ref: LocalRef) throws(EventLogError) -> NodeLog {
        let lines = try Self.records(of: ReplayedLine.self, inFileAt: fileURL(for: ref))
        return NodeLog(replaying: ReplayedLine.events(of: lines, for: ref), for: ref)
    }

    /// Reads the records of one log file through ``JSONLFile/records(as:)``.
    ///
    /// - Parameters:
    ///   - type: The type of each line.
    ///   - file: The log file. It does not have to exist.
    /// - Returns: The records of the lines that decode, in file order. No records when the file is not there.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the file is there and cannot be read.
    private static func records<Record: Decodable>(
        of type: Record.Type,
        inFileAt file: URL
    ) throws(EventLogError) -> [Record] {
        do {
            return try JSONLFile(url: file).records(as: type)
        } catch {
            throw failure(of: error, onFileAt: file)
        }
    }

    /// Changes an error of a ``JSONLFile`` to an ``EventLogError``.
    ///
    /// - Parameters:
    ///   - error: The error of the JSONL file.
    ///   - file: The log file.
    /// - Returns: ``EventLogError/unencodable(_:)`` for a record that does not encode, and
    ///   ``EventLogError/fileSystem(path:detail:)`` for a failed system call or read.
    private static func failure(of error: JSONLFileError, onFileAt file: URL) -> EventLogError {
        switch error {
        case .encodingFailed(let description):
            .unencodable(.unencodable(detail: description))
        case .openFailed, .tailCheckFailed, .writeFailed, .shortWrite, .syncFailed, .closeFailed, .readFailed:
            .fileSystem(path: file.path, detail: String(describing: error))
        }
    }
}

/// One line of a node log, read for the replay: an event, or the abort record of a transaction.
///
/// An event leaves out each value of its patch that does not decode (``PatchValuePolicy/skip``). Replay never refuses
/// a log (plan.md §3.3, rule 7), so the other values of the line still apply.
private enum ReplayedLine: Decodable {
    /// A line that holds an event.
    case event(Event)

    /// A line that holds the abort record of a transaction (plan.md §5.4 step 5.5).
    case abort(TransactionAbort)

    /// The keys that tell the two kinds of line apart.
    private enum CodingKeys: String, CodingKey {
        case abort
    }

    /// Reads one line: an abort record when the line has the `abort` key, else an event with the
    /// ``PatchValuePolicy/skip`` policy.
    ///
    /// - Parameter decoder: The decoder of the line.
    /// - Throws: The decode error when the line is not a JSON object, when an abort record has no valid transaction,
    ///   or when the envelope, the `node` or the `type` of the patch of an event does not decode.
    init(from decoder: any Decoder) throws {
        guard try decoder.container(keyedBy: CodingKeys.self).contains(.abort) else {
            self = .event(
                try PatchValuePolicy.$current.withValue(.skip) {
                    try Event(from: decoder)
                }
            )
            return
        }
        self = .abort(try TransactionAbort(from: decoder))
    }

    /// Gives the events of the lines of one log file, without each line that an abort record of the file drops: an
    /// event of an aborted transaction, and a line that an aborted `collectBoards` transaction copied
    /// (``Event/copiedBy``). Each skipped event is recorded with swift-log. Each kept copy loses its `copiedBy` value,
    /// so that it is the same event as the line that it copies, and the fold applies the two one time.
    ///
    /// - Parameters:
    ///   - lines: The lines of the file, in file order.
    ///   - ref: The local ref of the node of the file.
    /// - Returns: The events that replay applies, in file order.
    static func events(of lines: [ReplayedLine], for ref: LocalRef) -> [Event] {
        let aborted = Set(lines.compactMap(\.abortedTransaction))
        let events = lines.compactMap(\.event)
        let skipped = events.filter { event in event.isDropped(byAborting: aborted) }
        if !skipped.isEmpty {
            Log.kanban.debug(
                "Replay skips the events of aborted transactions",
                metadata: ["node": "\(ref)", "events": "\(skipped.map(\.id.ulidString))"]
            )
        }
        return events.filter { event in !event.isDropped(byAborting: aborted) }.map { event in event.copied(by: nil) }
    }

    /// The event of the line, or `nil` for an abort record.
    private var event: Event? {
        guard case .event(let event) = self else {
            return nil
        }
        return event
    }

    /// The transaction that the line aborts, or `nil` for an event.
    private var abortedTransaction: ULID? {
        guard case .abort(let record) = self else {
            return nil
        }
        return record.txn
    }
}

extension Event {
    /// Tells if an abort record of the file of this line drops the line: the record aborts the transaction of the
    /// event, or the `collectBoards` transaction that copied the line (plan.md §5.4 step 5.5).
    ///
    /// - Parameter aborted: The transactions that the abort records of the file abort.
    /// - Returns: `true` when replay skips the line.
    fileprivate func isDropped(byAborting aborted: Set<ULID>) -> Bool {
        aborted.contains(txn) || copiedBy.map(aborted.contains) == true
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

    /// The id of the event of the last whole line of the file that has an event id, or `nil` when no whole line has
    /// one.
    let lastEventID: ULID?
}

extension EventLog {
    /// Calculates the signature of the log file of one node. The id of the last event comes from the read of the file
    /// through ``JSONLFile/records(as:)``, so a torn final line gives no id.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The signature, or `nil` when the node has no file.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the file is there and cannot be read.
    func signature(of ref: LocalRef) throws(EventLogError) -> FileSignature? {
        let file = fileURL(for: ref)
        let attributes = try Self.runIfPresent(onFileAt: file) { url in
            try FileManager.default.attributesOfItem(atPath: url.path)
        }
        guard let attributes else {
            return nil
        }
        return FileSignature(
            size: attributes[.size] as? Int ?? .zero,
            modified: attributes[.modificationDate] as? Date ?? .distantPast,
            lastEventID: try Self.records(of: EventIDLine.self, inFileAt: file).compactMap(\.id).last
        )
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
        return try Self.items(in: directory.appending(path: name, directoryHint: .isDirectory))
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
        guard let type = nodeType(ofDirectoryAt: folder) else {
            return nil
        }
        return Self.ref(ofFile: file, type: type)
    }

    /// Tells if a directory is a node directory of this board, for example `.kanban/tasks/`. A tool that moves a whole
    /// directory can make the file watcher report only the directory, and no file of it (plan.md §5.6).
    ///
    /// The directory does not have to exist, because a directory that was moved away is also a change. The compare
    /// of the directories resolves symbolic links, the same as ``ref(ofFileAt:)``.
    ///
    /// - Parameter folder: The directory.
    /// - Returns: `true` when the name of the directory is the log directory name of a node type, and its parent is
    ///   the `.kanban/` directory of this board.
    func isNodeDirectory(at folder: URL) -> Bool {
        nodeType(ofDirectoryAt: folder) != nil
    }

    /// Finds the node type of a node directory of this board.
    ///
    /// - Parameter folder: The directory.
    /// - Returns: The node type whose log directory name is the name of the directory, or `nil` when no node type
    ///   has that name or the parent of the directory is not the `.kanban/` directory of this board.
    private func nodeType(ofDirectoryAt folder: URL) -> PatchNodeType? {
        let type = PatchNodeType.allCases.first { type in type.logDirectoryName == folder.lastPathComponent }
        guard let type, isBoardDirectory(at: folder.deletingLastPathComponent()) else {
            return nil
        }
        return type
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
    /// The keys of the line that the signature reads.
    private enum CodingKeys: String, CodingKey {
        case id
        case abort
    }

    /// The event id, or `nil` for the abort record of a transaction (``TransactionAbort``), which has no id.
    let id: ULID?

    /// Reads the event id of one line. An abort record is a whole line with no id, not a line that does not decode.
    ///
    /// - Parameter decoder: The decoder of the line.
    /// - Throws: The decode error when the line is not a JSON object, or when a line that is not an abort record has
    ///   no valid event id.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.contains(.abort) ? nil : try container.decode(ULID.self, forKey: .id)
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

    /// Lists the items of a directory that does not have to exist. The list holds hidden items too.
    ///
    /// - Parameter folder: The directory.
    /// - Returns: The items, or an empty list when the directory is not there.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the directory is there and cannot be read.
    static func items(in folder: URL) throws(EventLogError) -> [URL] {
        let items = try runIfPresent(onFileAt: folder) { url in
            try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        }
        return items ?? []
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
/// The ``KanbanError`` catalog has no code for these errors, because the caller of the tool cannot correct them. The
/// one exception is ``incompatibleBoard(directory:)``: the engine gives it to the caller as
/// ``KanbanError/incompatibleBoard(directory:)``, because the caller can remove the old board.
enum EventLogError: Error, Hashable, Sendable {
    /// The `.kanban/` directory has a path of the old Rust kanban, so the log does not read or write it
    /// (divergence.md Q6). The directory is the path of the `.kanban/` directory.
    case incompatibleBoard(directory: String)

    /// An event of an append changes a different node than the node of the log file.
    case nodeMismatch(log: LocalRef, event: LocalRef)

    /// An event cannot be written as a line.
    case unencodable(EventError)

    /// A file or a directory cannot be read or written. The detail is the error of the file system.
    case fileSystem(path: String, detail: String)

    /// The lock file cannot be opened or locked. The code is the `errno` value.
    case lockFailed(path: String, code: Int32)
}
