import Foundation
import Logging
import libgit2

/// One open git repo of a folder, read and written with the libgit2 C API in the process (D128).
///
/// The key read (``BoardKey/read(fromRepoAt:)``) and the read of the worktree top (``BoardKey/worktreeTop(of:)``)
/// use this type. It starts no `git` program, so the reads work in the App Sandbox and on a Mac with no developer
/// tools.
///
/// A folder whose git state cannot be read gets the key of a folder outside git (divergence.md M9). Thus each
/// failure of a read is ``BoardKeyError/notARepo(path:)``. Only a failure of the write of the empty first commit is
/// ``BoardKeyError/gitFailed(message:)``.
///
/// The libgit2 objects are not `Sendable`. Each read opens the repo, uses it, and lets it go in one synchronous call.
/// Thus this type is a class with no `Sendable` conformance, and its `deinit` frees the handle one time.
final class BoardRepo {
    /// The kind of git work of a libgit2 call. The kind decides the error of a failure.
    private enum Work {
        /// A read of the git state. A failure gives the key of a folder outside git.
        case read

        /// The write of the empty first commit. A failure is a real error.
        case write
    }

    /// The `git_repository_open_flag_t` set of the search: no flag.
    ///
    /// With no flag, `git_repository_open_ext` searches each parent folder, stops at a file system boundary, and does
    /// not read `GIT_DIR` or other variables of the environment. This is the search of the `git` program.
    private static let discoveryFlags: UInt32 = 0

    /// The start count of libgit2, or a negative libgit2 error code. A `static let` is set one time, and the runtime
    /// makes the set safe across threads. Thus `git_libgit2_init` runs one time for the process.
    private static let libraryStartCount = git_libgit2_init()

    /// The text of an error when libgit2 recorded no error text.
    private static let missingErrorText = "libgit2 gave no error text"

    /// The value that a libgit2 test function returns for true, for example `git_repository_head_unborn`.
    private static let trueValue: Int32 = 1

    /// The `force` value of `git_reference_create` that does not replace a ref that exists.
    private static let keepExistingRef: Int32 = 0

    /// The git config key of the name of the author of a commit.
    private static let userNameKey = "user.name"

    /// The git config key of the email of the author of a commit.
    private static let userEmailKey = "user.email"

    /// The number of seconds in one minute. libgit2 gives the time zone of a signature in minutes.
    private static let secondsPerMinute = 60

    /// The folder where the search for the repo started. A failure of a read names it.
    let directory: URL

    /// The top folder of the work tree: the top folder of a clone or of a linked worktree. libgit2 gives the path
    /// with the symbolic links resolved (for example `/private/tmp/…` for `/tmp/…`).
    let workDirectory: URL

    /// The open `git_repository *`. This instance owns it.
    private let handle: OpaquePointer

    /// Opens the repo that holds a folder. The search starts at the folder and goes up through each parent folder.
    ///
    /// - Parameter directory: The folder.
    /// - Throws: ``BoardKeyError/notARepo(path:)`` when no repo holds the folder, when the repo has no work tree
    ///   (a bare repo), or when libgit2 cannot open the repo.
    init(discoveringFrom directory: URL) throws(BoardKeyError) {
        self.directory = directory
        guard Self.libraryStartCount >= GIT_OK.rawValue else {
            throw Self.failure(of: Self.libraryStartCount, in: .read, at: directory)
        }
        var opened: OpaquePointer?
        let status = git_repository_open_ext(&opened, directory.path, Self.discoveryFlags, nil)
        guard status == GIT_OK.rawValue, let opened else {
            throw Self.failure(of: status, in: .read, at: directory)
        }
        guard let workPath = git_repository_workdir(opened) else {
            git_repository_free(opened)
            throw Self.failure(of: GIT_EBAREREPO.rawValue, in: .read, at: directory)
        }
        handle = opened
        workDirectory = URL(filePath: String(cString: workPath), directoryHint: .isDirectory)
    }

    deinit {
        git_repository_free(handle)
    }

    // MARK: - Reads

    /// Reads one value of the git config of the repo, with each level of the config (the repo, the user, and the
    /// system). When the key has more than one value, the read gives the value that git gives.
    ///
    /// - Parameter key: The config key, for example `remote.origin.url`.
    /// - Returns: The value, or `nil` when the config does not have the key.
    /// - Throws: ``BoardKeyError/notARepo(path:)`` when the config cannot be read.
    func configValue(named key: String) throws(BoardKeyError) -> String? {
        let config = try makeHandle(in: .read) { config in git_repository_config_snapshot(&config, handle) }
        defer { git_config_free(config) }
        var value: UnsafePointer<CChar>?
        let status = git_config_get_string(&value, config, key)
        guard status != GIT_ENOTFOUND.rawValue else {
            return nil
        }
        guard status == GIT_OK.rawValue, let value else {
            throw failure(of: status, in: .read)
        }
        return String(cString: value)
    }

    /// `true` when ``BoardKey/headName`` names a commit. It names no commit in a repo with no commit.
    ///
    /// - Throws: ``BoardKeyError/notARepo(path:)`` when the current commit cannot be read.
    var hasHeadCommit: Bool {
        get throws(BoardKeyError) {
            let status = git_repository_head_unborn(handle)
            try check(status, in: .read)
            return status != Self.trueValue
        }
    }

    /// Reads the root commits of ``BoardKey/headName`` (the commits with no parent), and gives the lowest SHA. Thus
    /// the key is the same each time, also when the history has more than one root commit (divergence.md §16, M7).
    ///
    /// - Returns: The lowest SHA of a root commit, in lowercase hex.
    /// - Throws: ``BoardKeyError/notARepo(path:)`` when the history cannot be read, or has no root commit.
    func lowestRootCommit() throws(BoardKeyError) -> String {
        let walk = try makeHandle(in: .read) { walk in git_revwalk_new(&walk, handle) }
        defer { git_revwalk_free(walk) }
        try check(git_revwalk_push_head(walk), in: .read)
        var commitID = git_oid()
        var lowest: String?
        var status = git_revwalk_next(&commitID, walk)
        while status == GIT_OK.rawValue {
            if try isRootCommit(commitID) {
                let sha = Self.hexText(of: &commitID)
                lowest = min(lowest ?? sha, sha)
            }
            status = git_revwalk_next(&commitID, walk)
        }
        guard status == GIT_ITEROVER.rawValue else {
            throw failure(of: status, in: .read)
        }
        guard let lowest else {
            throw failure(of: GIT_ENOTFOUND.rawValue, in: .read)
        }
        return lowest
    }

    /// Tells if a commit has no parent.
    ///
    /// - Parameter commitID: The id of the commit.
    /// - Returns: `true` when the commit has no parent.
    /// - Throws: ``BoardKeyError/notARepo(path:)`` when the commit cannot be read.
    private func isRootCommit(_ commitID: git_oid) throws(BoardKeyError) -> Bool {
        var id = commitID
        let commit = try makeHandle(in: .read) { commit in git_commit_lookup(&commit, handle, &id) }
        defer { git_commit_free(commit) }
        return git_commit_parentcount(commit) == 0
    }

    /// Gives the hex text of an object id.
    ///
    /// - Parameter id: The object id.
    /// - Returns: The SHA in lowercase hex.
    private static func hexText(of id: inout git_oid) -> String {
        String(cString: git_oid_tostr_s(&id))
    }

    // MARK: - First commit

    /// Makes one empty first commit on the current branch, and sets the branch to it (divergence.md §16, M8).
    ///
    /// The commit has the empty tree and no parent. The author and the committer are `user.name` and `user.email`
    /// of the git config. The index and the working files do not change. The branch must not exist yet. When a
    /// different read made the first commit at the same time, the set of the branch fails, and the commit of the
    /// other read stays.
    ///
    /// - Parameters:
    ///   - message: The message of the commit.
    ///   - time: The time of the author and of the committer.
    /// - Throws: ``BoardKeyError/gitFailed(message:)`` with the reason when the commit cannot be made, for example
    ///   when the git config has no `user.name` or `user.email`, or when the branch cannot be set.
    func makeFirstCommit(message: String, at time: Date) throws(BoardKeyError) {
        let signature = try makeSignature(at: time)
        defer { git_signature_free(signature) }
        let tree = try makeEmptyTree()
        defer { git_tree_free(tree) }
        var commitID = git_oid()
        let status = git_commit_create(&commitID, handle, nil, signature, signature, nil, message, tree, 0, nil)
        try check(status, in: .write)
        try setCurrentBranch(to: &commitID)
    }

    /// Makes the signature of the first commit from the identity of the git config.
    ///
    /// - Parameter time: The time of the signature.
    /// - Returns: The signature. The caller frees it.
    /// - Throws: ``BoardKeyError/gitFailed(message:)`` when the config has no name or no email, or when libgit2
    ///   refuses them (for example an empty name). ``BoardKeyError/notARepo(path:)`` when the config cannot be read.
    private func makeSignature(at time: Date) throws(BoardKeyError) -> UnsafeMutablePointer<git_signature> {
        let name = try identityValue(named: Self.userNameKey)
        let email = try identityValue(named: Self.userEmailKey)
        let offset = Int32(TimeZone.current.secondsFromGMT(for: time) / Self.secondsPerMinute)
        var signature: UnsafeMutablePointer<git_signature>?
        let status = git_signature_new(&signature, name, email, git_time_t(time.timeIntervalSince1970), offset)
        guard status == GIT_OK.rawValue, let signature else {
            throw failure(of: status, in: .write)
        }
        return signature
    }

    /// Reads one value of the identity of a commit from the git config.
    ///
    /// - Parameter key: ``userNameKey`` or ``userEmailKey``.
    /// - Returns: The value.
    /// - Throws: ``BoardKeyError/gitFailed(message:)`` when the config does not have the key.
    ///   ``BoardKeyError/notARepo(path:)`` when the config cannot be read.
    private func identityValue(named key: String) throws(BoardKeyError) -> String {
        guard let value = try configValue(named: key) else {
            throw .gitFailed(message: "Author identity unknown: the git config has no \(key)")
        }
        return value
    }

    /// Writes the empty tree to the object database of the repo.
    ///
    /// - Returns: The empty tree. The caller frees it.
    /// - Throws: ``BoardKeyError/gitFailed(message:)`` when the tree cannot be written.
    private func makeEmptyTree() throws(BoardKeyError) -> OpaquePointer {
        let builder = try makeHandle(in: .write) { builder in git_treebuilder_new(&builder, handle, nil) }
        defer { git_treebuilder_free(builder) }
        var treeID = git_oid()
        try check(git_treebuilder_write(&treeID, builder), in: .write)
        return try makeHandle(in: .write) { tree in git_tree_lookup(&tree, handle, &treeID) }
    }

    /// Makes the branch that ``BoardKey/headName`` names, at a commit. The branch must not exist yet.
    ///
    /// - Parameter commitID: The id of the commit.
    /// - Throws: ``BoardKeyError/gitFailed(message:)`` when ``BoardKey/headName`` names no branch, or when the branch
    ///   cannot be made and ``BoardKey/headName`` still names no commit.
    private func setCurrentBranch(to commitID: inout git_oid) throws(BoardKeyError) {
        let head = try makeHandle(in: .write) { head in git_reference_lookup(&head, handle, BoardKey.headName) }
        defer { git_reference_free(head) }
        guard let branch = git_reference_symbolic_target(head) else {
            throw .gitFailed(message: "\(BoardKey.headName) names no branch")
        }
        var created: OpaquePointer?
        let status = git_reference_create(&created, handle, branch, &commitID, Self.keepExistingRef, nil)
        git_reference_free(created)
        guard status != GIT_OK.rawValue else {
            return
        }
        // Read the reason first: a later libgit2 call replaces it.
        let error = failure(of: status, in: .write)
        guard try hasHeadCommit else {
            throw error
        }
    }

    // MARK: - Errors

    /// Runs one libgit2 call that makes an object, and gives the object.
    ///
    /// - Parameters:
    ///   - work: The kind of work of the call. It decides the error of a failure.
    ///   - call: The libgit2 call. It writes the object into its argument, and returns the libgit2 status.
    /// - Returns: The object. The caller owns it and frees it.
    /// - Throws: The error of ``failure(of:in:)`` when the call fails or gives no object.
    private func makeHandle(
        in work: Work,
        _ call: (_ handle: inout OpaquePointer?) -> Int32
    ) throws(BoardKeyError) -> OpaquePointer {
        var made: OpaquePointer?
        let status = call(&made)
        guard status == GIT_OK.rawValue, let made else {
            throw failure(of: status, in: work)
        }
        return made
    }

    /// Throws when a libgit2 status is an error code.
    ///
    /// - Parameters:
    ///   - status: The status that the libgit2 call returned. A value below `GIT_OK` is an error.
    ///   - work: The kind of work of the call.
    /// - Throws: The error of ``failure(of:in:)`` when the status is an error code.
    private func check(_ status: Int32, in work: Work) throws(BoardKeyError) {
        guard status < GIT_OK.rawValue else {
            return
        }
        throw failure(of: status, in: work)
    }

    /// Gives the error of a failed libgit2 call on this repo. See ``failure(of:in:at:)``.
    ///
    /// - Parameters:
    ///   - status: The status that the libgit2 call returned.
    ///   - work: The kind of work of the call.
    /// - Returns: The error.
    private func failure(of status: Int32, in work: Work) -> BoardKeyError {
        Self.failure(of: status, in: work, at: directory)
    }

    /// Gives the error of a failed libgit2 call. Call it on the same thread, directly after the failed call: libgit2
    /// keeps the last error text for each thread.
    ///
    /// A failed read gives ``BoardKeyError/notARepo(path:)``: the folder gets the key of a folder outside git
    /// (divergence.md M9). When the folder is in a repo whose git state cannot be read, the read also logs a warning
    /// with the reason. A failed write gives ``BoardKeyError/gitFailed(message:)`` with the reason.
    ///
    /// - Parameters:
    ///   - status: The status that the libgit2 call returned.
    ///   - work: The kind of work of the call.
    ///   - directory: The folder where the search for the repo started.
    /// - Returns: The error.
    private static func failure(of status: Int32, in work: Work, at directory: URL) -> BoardKeyError {
        let reason = lastErrorText()
        switch work {
        case .write:
            return .gitFailed(message: reason)
        case .read:
            if status != GIT_ENOTFOUND.rawValue {
                Log.kanban.warning(
                    "The git state of a folder cannot be read, so the folder gets the key of a folder outside git",
                    metadata: ["path": "\(directory.path)", "status": "\(status)", "error": "\(reason)"]
                )
            }
            return .notARepo(path: directory.path)
        }
    }

    /// The text of the last libgit2 error on this thread.
    ///
    /// - Returns: The text, or ``missingErrorText`` when libgit2 recorded no text.
    private static func lastErrorText() -> String {
        guard let error = git_error_last(), let message = error.pointee.message else {
            return missingErrorText
        }
        return String(cString: message)
    }
}
