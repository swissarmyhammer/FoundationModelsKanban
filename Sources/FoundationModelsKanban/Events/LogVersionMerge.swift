import Foundation
import ULID

/// The merge of the versions of one log file into one file (TestudoApp D179).
///
/// A board in iCloud Drive can get conflict versions of a log file when two Macs write the same log. A person must
/// never resolve such a conflict. The merge uses the same rule as the `merge=union` git attribute and
/// ``EventMerge/merged(_:)``: the merged file holds each line of each version one time.
///
/// - Each version loses its torn tail: the bytes after its last line feed. This is the same rule as the read of a log
///   (``EventLog/readLog(of:)``).
/// - A line with an event id is in the merge one time for each id. A line with an abort record is in the merge one
///   time for each transaction. When two versions have different bytes for the same id, the merge keeps the line of
///   the first version.
/// - The lines with an id come first, in the order of their ids. Event ids are ULIDs, so this is the time order.
/// - A whole line that does not decode stays one time for each text, after the lines with an id, in the order that
///   the merge finds them. The read of a log skips such a line, but the merge does not remove data.
enum LogVersionMerge {
    /// The byte that ends each line.
    private static let lineFeed = UInt8(ascii: "\n")

    /// The key that orders one line in the merge, and that finds the same line in two versions.
    private enum LineKey: Hashable, Comparable {
        /// A line with an event: the event id.
        case event(ULID)

        /// A line with the abort record of a transaction: the transaction id.
        case abort(ULID)

        /// The ULID that gives the order of the line.
        private var order: ULID {
            switch self {
            case .event(let id), .abort(let id): id
            }
        }

        /// `0` for an event, `1` for an abort record, so that an event and an abort record with the same ULID keep a
        /// fixed order.
        private var kind: Int {
            switch self {
            case .event: 0
            case .abort: 1
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.order, lhs.kind) < (rhs.order, rhs.kind)
        }
    }

    /// The keys that the merge reads from a line. The merge does not decode the full event, so a line whose patch does
    /// not decode still has its id.
    private struct LineKeys: Decodable {
        /// The event id, or `nil` for an abort record.
        let id: ULID?

        /// The transaction that an abort record aborts, or `nil` for an event.
        let abort: ULID?

        /// The key of the line, or `nil` when the line has no id.
        var key: LineKey? {
            if let id {
                return .event(id)
            }
            return abort.map(LineKey.abort)
        }
    }

    /// Merges the versions of one log file.
    ///
    /// - Parameter versions: The bytes of each version. Put the current version first, so that its line wins when
    ///   two versions have different bytes for the same id.
    /// - Returns: The bytes of the merged file. Each line ends with a line feed. No whole line gives no bytes.
    static func merged(_ versions: [Data]) -> Data {
        let decoder = JSONDecoder()
        var keyed: [LineKey: Data] = [:]
        var unkeyed: [Data] = []
        var unkeyedSeen: Set<Data> = []
        for line in versions.flatMap(wholeLines) {
            if let key = (try? decoder.decode(LineKeys.self, from: line))?.key {
                if keyed[key] == nil {
                    keyed[key] = line
                }
            } else if unkeyedSeen.insert(line).inserted {
                unkeyed.append(line)
            }
        }
        let ordered = keyed.keys.sorted().compactMap { key in keyed[key] } + unkeyed
        return ordered.reduce(into: Data()) { file, line in
            file.append(line)
            file.append(lineFeed)
        }
    }

    /// Gives the whole lines of one version, without their line feeds. The bytes after the last line feed are a torn
    /// tail, and an empty line has no data, so neither is a line.
    ///
    /// - Parameter version: The bytes of the version.
    /// - Returns: The whole lines that are not empty, in file order.
    private static func wholeLines(of version: Data) -> [Data] {
        version.split(separator: lineFeed, omittingEmptySubsequences: false).dropLast()
            .filter { line in !line.isEmpty }
            .map { line in Data(line) }
    }

    /// Merges the version files of one log file into the log file, with one `NSFileCoordinator` write. The write reads
    /// the current log in the coordinated block, so the current version is in the merge.
    ///
    /// The merge replaces the file in one atomic write. This is the only write of a log that is not an append. Hold
    /// the board lock (``EventLog/lock()``), so that no append of this process or of a different process on this Mac
    /// is lost.
    ///
    /// - Parameters:
    ///   - versionFiles: The files of the other versions, for example the `url` of each conflict `NSFileVersion`.
    ///   - file: The log file. It does not have to exist. Its folder must exist.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a file cannot be read or written.
    static func merge(versionsAt versionFiles: [URL], intoLogAt file: URL) throws(EventLogError) {
        let others = try versionFiles.map { version throws(EventLogError) in try contents(of: version) ?? Data() }
        var failure: EventLogError?
        var coordination: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: file,
            options: .forMerging,
            error: &coordination
        ) { target in
            do throws(EventLogError) {
                let current = try contents(of: target) ?? Data()
                let merged = merged([current] + others)
                try write(merged, to: target)
            } catch {
                failure = error
            }
        }
        if let coordination {
            throw .fileSystem(path: file.path, detail: String(describing: coordination))
        }
        if let failure {
            throw failure
        }
    }

    /// Reads the bytes of one file.
    ///
    /// - Parameter file: The file.
    /// - Returns: The bytes, or `nil` when the file is not there.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the file is there and cannot be read.
    private static func contents(of file: URL) throws(EventLogError) -> Data? {
        do {
            return try Data(contentsOf: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw .fileSystem(path: file.path, detail: String(describing: error))
        }
    }

    /// Writes the bytes of one file in one atomic write.
    ///
    /// - Parameters:
    ///   - data: The bytes.
    ///   - file: The file.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the file cannot be written.
    private static func write(_ data: Data, to file: URL) throws(EventLogError) {
        do {
            try data.write(to: file, options: .atomic)
        } catch {
            throw .fileSystem(path: file.path, detail: String(describing: error))
        }
    }
}

// MARK: - Conflict versions

/// Gives the conflict versions of a file, and marks them resolved. The engine uses ``ICloudFileVersions``. A test
/// uses a source that gives plain files, because only a ubiquitous item has real conflict versions.
protocol FileVersionSource {
    /// One conflict version of a file.
    associatedtype Version

    /// Gives the conflict versions of a file that are not resolved.
    ///
    /// - Parameter file: The file.
    /// - Returns: The conflict versions. No versions when the file has no conflict, or is not in iCloud Drive.
    func conflictVersions(of file: URL) -> [Version]

    /// Gives the file that holds the bytes of one version.
    ///
    /// - Parameter version: The version.
    /// - Returns: The file of the version.
    func contentsURL(of version: Version) -> URL

    /// Marks conflict versions of a file resolved, and removes the versions that are not current.
    ///
    /// - Parameters:
    ///   - versions: The conflict versions that the merge read.
    ///   - file: The file.
    /// - Throws: The error of the version store when it cannot remove the versions.
    func markResolved(_ versions: [Version], of file: URL) throws
}

/// The conflict versions of iCloud Drive, through `NSFileVersion`. Each call is thin, so that the merge logic stays
/// in ``LogVersionMerge``, where a test can reach it.
struct ICloudFileVersions: FileVersionSource {
    func conflictVersions(of file: URL) -> [NSFileVersion] {
        NSFileVersion.unresolvedConflictVersionsOfItem(at: file) ?? []
    }

    func contentsURL(of version: NSFileVersion) -> URL {
        version.url
    }

    /// Marks the versions resolved. The other versions are removed only when no conflict version that the merge did
    /// not read came in during the merge. The next check then merges that version.
    ///
    /// - Parameters:
    ///   - versions: The conflict versions that the merge read.
    ///   - file: The file.
    /// - Throws: The error of `NSFileVersion.removeOtherVersionsOfItem(at:)`.
    func markResolved(_ versions: [NSFileVersion], of file: URL) throws {
        for version in versions {
            version.isResolved = true
        }
        guard conflictVersions(of: file).isEmpty else {
            return
        }
        try NSFileVersion.removeOtherVersionsOfItem(at: file)
    }
}

extension EventLog {
    /// Merges the conflict versions of the changed files of the board, and marks them resolved (TestudoApp D179).
    ///
    /// A log file (`.jsonl`) gets the merge of its current version and each conflict version
    /// (``LogVersionMerge/merge(versionsAt:intoLogAt:)``). A different file of the board keeps its current version.
    /// When a path is the board directory, the call checks each file of the board, for example after FSEvents lost
    /// events, or after the start of a watcher. A path outside the board directory, and the lock file, are not
    /// checked.
    ///
    /// The call gets the board lock only when a file has a conflict version, so a board with no conflict pays only for
    /// the version queries.
    ///
    /// - Parameters:
    ///   - paths: The changed paths.
    ///   - source: The version store.
    /// - Returns: The files whose conflict versions were resolved, in the order of the paths.
    /// - Throws: ``EventLogError/lockFailed(path:code:)`` when the lock cannot be got,
    ///   ``EventLogError/fileSystem(path:detail:)`` when a file cannot be read or written, or when the version store
    ///   cannot resolve a version.
    func resolveConflicts(
        ofFilesAt paths: [URL],
        with source: some FileVersionSource
    ) async throws(EventLogError) -> [URL] {
        let candidates = checkedFiles(among: paths)
        guard candidates.contains(where: { file in !source.conflictVersions(of: file).isEmpty }) else {
            return []
        }
        let lock = try await lock()
        let resolved = Result { () throws(EventLogError) in try Self.resolve(candidates, with: source) }
        lock.unlock()
        return try resolved.get()
    }

    /// Merges and resolves the conflict versions of some files. The caller holds the board lock.
    ///
    /// - Parameters:
    ///   - candidates: The files to check.
    ///   - source: The version store.
    /// - Returns: The files whose conflict versions were resolved, in the order of the candidates.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a file cannot be read or written, or when the version
    ///   store cannot resolve a version.
    private static func resolve(
        _ candidates: [URL],
        with source: some FileVersionSource
    ) throws(EventLogError) -> [URL] {
        var resolved: [URL] = []
        for file in candidates {
            let versions = source.conflictVersions(of: file)
            guard !versions.isEmpty else {
                continue
            }
            if file.pathExtension == Self.logExtension {
                try LogVersionMerge.merge(versionsAt: versions.map(source.contentsURL), intoLogAt: file)
            }
            do {
                try source.markResolved(versions, of: file)
            } catch {
                throw .fileSystem(path: file.path, detail: String(describing: error))
            }
            Log.kanban.info("A conflict of a board file in iCloud Drive is resolved", metadata: ["path": "\(file.path)"])
            resolved.append(file)
        }
        return resolved
    }

    /// Gives the files that a conflict check reads for some changed paths: each path in the board directory that is
    /// not the lock file, and each file of the board for the board directory itself. Each file is in the list one
    /// time.
    ///
    /// - Parameter paths: The changed paths.
    /// - Returns: The files, in the order of the paths.
    private func checkedFiles(among paths: [URL]) -> [URL] {
        let boardPath = directory.canonicalPath
        var seen: Set<String> = []
        var files: [URL] = []
        for path in paths {
            let canonical = path.canonicalPath
            let found = canonical == boardPath ? allFiles() : (canonical.hasPrefix(boardPath + "/") ? [path] : [])
            for file in found where file.lastPathComponent != Self.lockFileName {
                if seen.insert(file.canonicalPath).inserted {
                    files.append(file)
                }
            }
        }
        return files
    }

    /// Gives each regular file in the board directory and in its folders.
    ///
    /// - Returns: The files, in the sort order of their paths. No files when the directory cannot be read.
    private func allFiles() -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walk = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else {
            return []
        }
        return walk.compactMap { item in item as? URL }
            .filter { file in (try? file.resourceValues(forKeys: Set(keys)).isRegularFile) == true }
            .sorted { lhs, rhs in lhs.path < rhs.path }
    }
}
