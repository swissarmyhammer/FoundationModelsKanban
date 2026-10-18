import Foundation
import OrderedCollections

/// A change in a scan place that the file watcher of the place sees, and that can make the index of the scan out of
/// date (divergence.md §16, Gap 1).
///
/// The host keeps the index of a scan, also when a board ref names no board of the index, so that a read runs no scan
/// and no `git` (plan.md §6.6, index life). Only a change of a scan place makes the host scan again.
enum ScanChange: Hashable, Sendable {
    /// A repo folder, its `.git` entry, or its git config changed: a new or removed folder, a new or removed repo,
    /// or a changed remote. The key of the repo must be read again. The text is the canonical path of the repo
    /// folder.
    case repo(String)

    /// The `.kanban/` directory or the board log of a repo changed: the enabled state of its copy can change. The
    /// text is the canonical path of the repo folder.
    case board(inRepo: String)

    /// The refs of a repo changed, for example after its first commit. A repo whose key read failed can have a key
    /// now. The text is the canonical path of the repo folder.
    case commits(inRepo: String)

    /// The scan place itself changed, or the file watcher lost events: each repo of the place must be compared with
    /// the files that the scan or the record saw (``BoardIndex/resolving(_:)``, ``PathRefRecord/isExpired(by:)``).
    /// The text is the canonical path of the place.
    case place(String)
}

// MARK: - Watched place

/// A scan place, or the parent folder of the repo folder of a path ref (``FolderBoard/watchedRepo(ofFolderAt:)``), that
/// a file watcher watches: the canonical path that keys the place in the host, and the real path that FSEvents gives in
/// its events (for example `/private/var/…` for `/var/…`).
struct WatchedPlace: Hashable, Sendable {
    /// The canonical path of the place: ``Foundation/URL/canonicalPath`` of its folder.
    let path: String

    /// The real path of the place, with each symbolic link resolved, as FSEvents gives it.
    let realPath: String

    /// The path components of ``path`` and of ``realPath``. A changed path is in the place when it starts with one of
    /// them.
    private let bases: [[String]]

    /// Makes a watched place from its two paths.
    ///
    /// - Parameters:
    ///   - path: The canonical path of the place.
    ///   - realPath: The real path of the place.
    init(path: String, realPath: String) {
        self.path = path
        self.realPath = realPath
        bases = [realPath, path].map(Self.components(of:))
    }

    /// Makes the watched place of a folder.
    ///
    /// - Parameter folder: The folder of the place.
    init(watching folder: URL) {
        self.init(path: folder.canonicalPath, realPath: Self.realPath(of: folder))
    }

    /// Gives the change of one changed path of the place.
    ///
    /// - Parameter changedPath: The changed path, as FSEvents gives it.
    /// - Returns: The change, or `nil` when the path is not in the place, or when it changes no repo, no key, and no
    ///   board log.
    func change(at changedPath: String) -> ScanChange? {
        let components = Self.components(of: changedPath)
        guard let base = bases.first(where: components.starts(with:)) else {
            return nil
        }
        let relative = components.dropFirst(base.count)
        guard let name = relative.first else {
            return .place(path)
        }
        let repo = URL(filePath: path, directoryHint: .isDirectory).appending(path: name).path
        return ScanChangeRule.change(ofRepoAt: repo, inside: Array(relative.dropFirst()))
    }

    /// Gives the change of each changed path of one batch of the file watcher, with no change twice.
    ///
    /// - Parameter batch: The changed paths of the batch.
    /// - Returns: The changes, in the order of their first path.
    func changes(in batch: [URL]) -> [ScanChange] {
        Array(OrderedSet(batch.compactMap { url in change(at: url.path) }))
    }

    /// Gives the path components of a path as its text has them. The split reads no file: a standardized URL drops
    /// `/private` only when the path exists, so a removed folder and its place would not agree.
    ///
    /// - Parameter path: The path.
    /// - Returns: The components, for example `["/", "work", "src"]`.
    private static func components(of path: String) -> [String] {
        URL(filePath: path).pathComponents
    }

    /// Gives the real path of a folder: each symbolic link resolved, with no other change (`realpath(3)`).
    ///
    /// - Parameter folder: The folder.
    /// - Returns: The real path, or the standardized path when the folder does not exist.
    private static func realPath(of folder: URL) -> String {
        folder.withUnsafeFileSystemRepresentation { representation in
            guard let representation, let resolved = realpath(representation, nil) else {
                return folder.standardizedFileURL.path
            }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }
}

// MARK: - Rules

/// One rule of the changes of a repo folder: a path inside the repo and the change that it gives.
private struct ScanChangeRule: Sendable {
    /// The rules, in order. The first rule that matches gives the change.
    private static let rules: [ScanChangeRule] = [
        ScanChangeRule(exactly: [], make: ScanChange.repo),
        ScanChangeRule(exactly: [BoardKey.gitDirectoryName], make: ScanChange.repo),
        ScanChangeRule(exactly: [BoardKey.gitDirectoryName, GitEntryName.config], make: ScanChange.repo),
        ScanChangeRule(exactly: [EventLog.directoryName], make: ScanChange.board(inRepo:)),
        ScanChangeRule(exactly: [EventLog.directoryName, EventLog.boardFileName], make: ScanChange.board(inRepo:)),
        ScanChangeRule(under: [BoardKey.gitDirectoryName, GitEntryName.refs], make: ScanChange.commits(inRepo:)),
        ScanChangeRule(
            exactly: [BoardKey.gitDirectoryName, GitEntryName.packedRefs],
            make: ScanChange.commits(inRepo:)
        ),
    ]

    /// The path components inside the repo folder.
    let components: [String]

    /// `true` when a path in the directory of ``components`` matches too.
    let includesDeeperPaths: Bool

    /// Makes the change from the canonical path of the repo folder.
    let make: @Sendable (String) -> ScanChange

    /// Makes a rule for one path inside the repo folder.
    ///
    /// - Parameters:
    ///   - components: The path components inside the repo folder.
    ///   - make: Makes the change from the canonical path of the repo folder.
    private init(exactly components: [String], make: @escaping @Sendable (String) -> ScanChange) {
        self.components = components
        includesDeeperPaths = false
        self.make = make
    }

    /// Makes a rule for one directory inside the repo folder and each path in it.
    ///
    /// - Parameters:
    ///   - components: The path components of the directory inside the repo folder.
    ///   - make: Makes the change from the canonical path of the repo folder.
    private init(under components: [String], make: @escaping @Sendable (String) -> ScanChange) {
        self.components = components
        includesDeeperPaths = true
        self.make = make
    }

    /// Gives the change of a changed path in a repo folder.
    ///
    /// - Parameters:
    ///   - repo: The canonical path of the repo folder.
    ///   - inside: The path components of the changed path inside the repo folder.
    /// - Returns: The change, or `nil` when no rule matches.
    static func change(ofRepoAt repo: String, inside: [String]) -> ScanChange? {
        rules.first { rule in rule.matches(inside) }.map { rule in rule.make(repo) }
    }

    /// Tells if the rule matches the path components of a changed path inside a repo folder.
    ///
    /// - Parameter inside: The path components inside the repo folder.
    /// - Returns: `true` when the rule matches.
    private func matches(_ inside: [String]) -> Bool {
        includesDeeperPaths ? inside.starts(with: components) : inside == components
    }
}

// MARK: - Index

extension BoardIndex {
    /// Tells if a change makes the index out of date, so that the next call that needs the index scans again. A change
    /// whose files are the same as the scan saw them (``marks``) does not: FSEvents can give a change after the scan
    /// that occurred before the scan.
    ///
    /// - Parameter change: The change of a scan place of the index.
    /// - Returns: `true` when the files of the change are not the same as the scan saw them, and the change is a change
    ///   of a repo, of a board log, or of the place, or new commits of a repo whose key read failed.
    func isExpired(by change: ScanChange) -> Bool {
        guard marks?.isChanged(by: change) ?? true else {
            return false
        }
        return switch change {
        case .repo, .board, .place: true
        case .commits(let repo): unreadable.contains(repo)
        }
    }

    /// Gives the changes that one change stands for in the index. A change of a place itself, or a batch of lost events
    /// of a place, stands for the change of each repo of the place whose files are not the same as the scan saw them
    /// (``ScanMarks/changes(inPlaceAt:)``): a compare of each file gives the same changes as the events of the files.
    /// Each other change, and a change of a place that the scan did not read, stands for itself.
    ///
    /// - Parameter change: The change of a scan place of the index.
    /// - Returns: The changes.
    func resolving(_ change: ScanChange) -> [ScanChange] {
        guard case .place(let place) = change, let changes = marks?.changes(inPlaceAt: place) else {
            return [change]
        }
        return changes
    }

    /// Gives the index without the keys that a change makes unknown, so that the next scan reads them again.
    ///
    /// - A changed repo forgets the repo and each copy with the same key, for example a worktree, whose key comes
    ///   from the same git config.
    /// - New commits forget a failed key read of the repo.
    /// - A change of the place forgets each repo of the place.
    /// - A changed board log forgets no key: each scan reads the enabled state again.
    ///
    /// - Parameter change: The change.
    /// - Returns: The index without the forgotten repos.
    func forgetting(_ change: ScanChange) -> BoardIndex {
        switch change {
        case .repo(let repo):
            let keys = Set(copies.filter { copy in copy.directory.canonicalPath == repo }.map(\.key))
            return keeping(
                copies: { copy in copy.directory.canonicalPath != repo && !keys.contains(copy.key) },
                unreadable: { path in path != repo }
            )
        case .commits(let repo):
            return keeping(copies: { _ in true }, unreadable: { path in path != repo })
        case .place(let place):
            return keeping(
                copies: { copy in !Self.isRepo(copy.directory.canonicalPath, inPlace: place) },
                unreadable: { path in !Self.isRepo(path, inPlace: place) }
            )
        case .board:
            return self
        }
    }

    /// Gives the index with only the copies and the failed key reads that two filters keep.
    ///
    /// - Parameters:
    ///   - isKeptCopy: Tells if a copy stays.
    ///   - isKeptPath: Tells if the canonical path of a repo whose key read failed stays.
    /// - Returns: The index.
    private func keeping(
        copies isKeptCopy: (BoardCopy) -> Bool,
        unreadable isKeptPath: (String) -> Bool
    ) -> BoardIndex {
        BoardIndex(
            places: places,
            copies: copies.filter(isKeptCopy),
            unreadable: unreadable.filter(isKeptPath),
            marks: marks
        )
    }

    /// Tells if a repo folder is one level down in a place.
    ///
    /// - Parameters:
    ///   - repo: The canonical path of the repo folder.
    ///   - place: The canonical path of the place.
    /// - Returns: `true` when the parent directory of the repo is the place.
    private static func isRepo(_ repo: String, inPlace place: String) -> Bool {
        URL(filePath: repo).deletingLastPathComponent().path == URL(filePath: place).path
    }
}

// MARK: - Observer

/// Gets a call when the host scans the places for repos, when the file watcher of a scan place sees a change, and
/// when the file watcher of a folder that a path ref named sees a change that makes the result of the path ref out of
/// date.
///
/// A test uses it to count the scans, and to wait until the host saw a change of a scan place or of a folder that a
/// path ref named.
protocol BoardScanObserver: Sendable {
    /// Tells that a scan of the places starts.
    ///
    /// - Parameter places: The places of the scan, in scan order.
    func scanDidStart(inPlaces places: [URL])

    /// Tells that the host saw a change of a scan place, after the host applied it to its scan indexes.
    ///
    /// - Parameter change: The change.
    func scanPlaceDidChange(_ change: ScanChange)

    /// Tells that the host saw a change that can change the result of a path ref, after the host forgot what git told
    /// about the folder of the path ref (divergence.md §16, Gap 1; divergence.md X4).
    ///
    /// - Parameter change: The change (``PathRefRecord/isExpired(by:)``): ``ScanChange/repo(_:)`` of the
    ///   watched repo folder, ``ScanChange/commits(inRepo:)`` of a repo whose key read failed, or
    ///   ``ScanChange/place(_:)`` of the parent folder of the watched repo folder.
    func pathRefDidChange(_ change: ScanChange)
}
