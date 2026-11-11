import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the board key: the normalization of a git remote URL, and the read of the key from a git repo (plan.md
/// §3.2, §12 item 4).
@Suite("Board keys", .watcherBudget)
struct BoardKeyTests {
    /// The key that each form of the test remote gives.
    static let expectedKey = "github.com/swissarmyhammer/FoundationModelsKanban"

    /// The HTTPS form of the test remote.
    static let httpsRemote = "https://github.com/swissarmyhammer/FoundationModelsKanban.git"

    /// The SSH form of the test remote.
    static let sshRemote = "git@github.com:swissarmyhammer/FoundationModelsKanban.git"

    /// The forms of one remote. Each form must give ``expectedKey``.
    static let remoteForms = [
        httpsRemote,
        sshRemote,
        "ssh://git@github.com/swissarmyhammer/FoundationModelsKanban.git",
        "ssh://git@github.com:22/swissarmyhammer/FoundationModelsKanban.git",
        "https://github.com/swissarmyhammer/FoundationModelsKanban",
        "https://GitHub.com/swissarmyhammer/FoundationModelsKanban.git/",
        "HTTPS://github.com/swissarmyhammer/FoundationModelsKanban.git",
        "https://reader@github.com:443/swissarmyhammer/FoundationModelsKanban.git",
        "git@github.com:/swissarmyhammer/FoundationModelsKanban.git",
        "github.com:swissarmyhammer/FoundationModelsKanban",
        "  git@github.com:swissarmyhammer/FoundationModelsKanban.git\n",
    ]

    /// The `origin` URLs with no host: local paths and a `file://` URL. Each one gives the key of a repo with no
    /// remote.
    static let localOrigins = ["/srv/git/repo.git", "../upstream", "file:///srv/git/repo.git"]

    /// The name of the subfolder of a repo in the subfolder test.
    static let subfolderName = "Sources"

    /// The `origin` of the repo in the subfolder test: no remote, and a remote with a host.
    static let subfolderOrigins: [String?] = [nil, httpsRemote]

    /// The name of the folder that is not in a git repo.
    static let plainFolderName = "plain-directory"

    /// An `origin` URL with a host but no path. ``BoardKey/init(remoteURL:)`` refuses it, so the repo gets the key
    /// of a repo with no remote.
    static let pathlessOrigin = "https://example.com/"

    /// The name of the config file in the git directory of a repo.
    static let gitConfigFileName = "config"

    /// The text of a git config file that git cannot read: one line that is not a section and not a key.
    static let brokenConfigText = "not a config line\n"

    /// The SHA of a commit, for the test of the text of a root commit key.
    static let sampleCommit = "c83fae4e58ced3b4cddb5c4bf9f151b0df1d379b"

    /// The name of the file that a test stages in a repo with no commit.
    static let stagedFileName = "notes.txt"

    /// The text of the file that a test stages in a repo with no commit.
    static let stagedText = "staged, not committed\n"

    /// The local config of a repo whose identity for a commit is empty: an empty name and an empty email. The
    /// local config wins over the config of the user, so the repo has no usable identity on each machine.
    static let emptyIdentityConfig = [("user.name", ""), ("user.email", "")]

    /// The time of the first commits in the test of two first commits at the same time.
    static let fixedFirstCommitTime = Date(timeIntervalSince1970: 1_767_225_600)

    /// The branch that a root-commit test makes with `git checkout --orphan`.
    static let orphanBranch = "other-history"

    /// The places of a merge in the test of two root commits: `true` merges the orphan branch into the first
    /// branch, and `false` merges the first branch into the orphan branch. The two merges list the two root commits
    /// in opposite orders, so a key that takes the first root commit of the list fails one of them.
    static let mergeIntoFirstBranch = [true, false]

    // MARK: - Normalization

    @Test("SSH, HTTPS, and ssh:// forms of one remote give the same key", arguments: remoteForms)
    func remoteFormsGiveSameKey(remote: String) throws {
        #expect(try BoardKey(remoteURL: remote).description == Self.expectedKey)
    }

    @Test("The host changes to lowercase, and the owner and the repo keep their case")
    func hostIsLowercaseAndPathKeepsCase() throws {
        let key = try BoardKey(remoteURL: "git@GitHub.COM:Owner/Repo.git")
        #expect(key.description == "github.com/Owner/Repo")
    }

    @Test("A remote with more than two path segments keeps each segment")
    func nestedGroupKeepsEachSegment() throws {
        let key = try BoardKey(remoteURL: "git@gitlab.com:group/subgroup/repo.git")
        #expect(key.description == "gitlab.com/group/subgroup/repo")
    }

    @Test(
        "A remote with no host, no path, or an empty path segment is an invalid remote URL",
        arguments: [
            "",
            "/srv/git/repo.git",
            "../repo.git",
            "file:///srv/git/repo.git",
            "https://github.com/",
            "https://github.com/.git",
            "git@github.com:",
            "https://github.com/owner//repo.git",
            "https:///owner/repo.git",
        ]
    )
    func remoteWithoutHostOrPathThrows(remote: String) {
        #expect(throws: BoardKeyError.invalidRemoteURL(url: remote)) {
            try BoardKey(remoteURL: remote)
        }
    }

    @Test("A repo with no remote has the key local/<first 12 hex digits of the root commit>")
    func localKeyHasTwelveDigitsOfRootCommit() {
        #expect(BoardKey(rootCommit: Self.sampleCommit).description == "local/c83fae4e58ce")
    }

    @Test("A key from a remote is a valid board key of a node URI")
    func keyMakesNodeURI() throws {
        let key = try BoardKey(remoteURL: Self.sshRemote)
        let uri = try NodeURI(parsing: "kanban://\(key)/column/doing")
        #expect(uri.boardKey == key.description)
    }

    // MARK: - Read from a repo

    @Test("A repo with no remote gives local/<root commit>")
    func repoWithoutRemoteGivesRootCommitKey() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "my-repo")
        #expect(try await BoardKey.read(fromRepoAt: repo) == sandbox.headKey(of: repo))
    }

    @Test("Two clones and a worktree of a repo with no remote have the same key")
    func clonesWithoutRemoteGiveSameKey() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "first-clone")
        let clone = try await sandbox.cloneRepo(repo, named: "second-clone")
        let worktree = try await sandbox.addWorktree(named: "feature-worktree", to: clone)
        let key = try await sandbox.headKey(of: repo)
        #expect(try await BoardKey.read(fromRepoAt: repo) == key)
        #expect(try await BoardKey.read(fromRepoAt: clone) == key)
        #expect(try await BoardKey.read(fromRepoAt: worktree) == key)
    }

    @Test("A repo with two root commits uses the lowest SHA", arguments: mergeIntoFirstBranch)
    func twoRootCommitsGiveLowestSHA(intoFirstBranch: Bool) async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeEmptyRepo(named: "merged-repo")
        try await sandbox.commit(message: "First history", in: repo)
        let firstBranch = try await GitSandbox.output(ofGit: ["symbolic-ref", "--short", "HEAD"], in: repo)
        let firstRoot = try await GitSandbox.headSHA(of: repo)
        try await GitSandbox.runGit(withArguments: ["checkout", "--quiet", "--orphan", Self.orphanBranch], in: repo)
        try await sandbox.commit(message: "Second history", in: repo)
        let secondRoot = try await GitSandbox.headSHA(of: repo)
        let (target, source) = intoFirstBranch ? (firstBranch, Self.orphanBranch) : (Self.orphanBranch, firstBranch)
        try await GitSandbox.runGit(withArguments: ["checkout", "--quiet", target], in: repo)
        try await sandbox.merge(source, in: repo)
        #expect(try await BoardKey.read(fromRepoAt: repo) == BoardKey(rootCommit: min(firstRoot, secondRoot)))
    }

    // MARK: - First commit

    @Test("A new repo with no commit gets one empty first commit on its branch, and the key comes from that commit")
    func repoWithoutCommitGetsEmptyFirstCommit() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeEmptyRepo(named: "new-repo")
        let branch = try await GitSandbox.output(ofGit: ["symbolic-ref", "HEAD"], in: repo)
        let key = try await BoardKey.read(fromRepoAt: repo)
        #expect(try await GitSandbox.output(ofGit: ["rev-list", "--count", branch], in: repo) == "1")
        #expect(try await GitSandbox.output(ofGit: ["ls-tree", "HEAD"], in: repo) == "")
        let message = try await GitSandbox.output(ofGit: ["log", "-1", "--format=%s"], in: repo)
        #expect(message == BoardKey.firstCommitMessage)
        #expect(try await key == sandbox.headKey(of: repo))
    }

    @Test("Two new repos that get their first commits at the same time, with the same author, get different keys")
    func firstCommitsAtSameTimeGiveDifferentKeys() async throws {
        let sandbox = try GitSandbox()
        let firstRepo = try await sandbox.makeEmptyRepo(named: "first-new-repo")
        let secondRepo = try await sandbox.makeEmptyRepo(named: "second-new-repo")
        async let firstKey = BoardKey.read(fromRepoAt: firstRepo, firstCommitTime: Self.fixedFirstCommitTime)
        async let secondKey = BoardKey.read(fromRepoAt: secondRepo, firstCommitTime: Self.fixedFirstCommitTime)
        #expect(try await firstKey != secondKey)
    }

    @Test("The first commit does not take the staged files, and the working files do not change")
    func firstCommitKeepsStagedFiles() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeEmptyRepo(named: "staged-repo")
        let file = repo.appending(path: Self.stagedFileName)
        try Self.stagedText.write(to: file, atomically: true, encoding: .utf8)
        try await GitSandbox.runGit(withArguments: ["add", Self.stagedFileName], in: repo)
        _ = try await BoardKey.read(fromRepoAt: repo)
        #expect(try await GitSandbox.output(ofGit: ["ls-tree", "-r", "--name-only", "HEAD"], in: repo) == "")
        let staged = try await GitSandbox.output(ofGit: ["diff", "--cached", "--name-only"], in: repo)
        #expect(staged == Self.stagedFileName)
        #expect(try String(contentsOf: file, encoding: .utf8) == Self.stagedText)
    }

    @Test("A repo with commits gets no new commit")
    func repoWithCommitsGetsNoNewCommit() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "old-repo")
        let head = try await GitSandbox.headSHA(of: repo)
        _ = try await BoardKey.read(fromRepoAt: repo)
        #expect(try await GitSandbox.headSHA(of: repo) == head)
        #expect(try await GitSandbox.output(ofGit: ["rev-list", "--count", "--all"], in: repo) == "1")
    }

    @Test("A repo with an empty identity in its config makes the first commit with the fallback identity")
    func firstCommitWithEmptyIdentityUsesFallback() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeEmptyRepo(named: "anonymous-repo", withIdentity: false)
        for (key, value) in Self.emptyIdentityConfig {
            try await GitSandbox.runGit(withArguments: ["config", key, value], in: repo)
        }
        _ = try await BoardKey.read(fromRepoAt: repo)
        #expect(try await Self.authorOfHead(in: repo) == Self.fallbackAuthor)
    }

    @Test("A repo with no commit and no git identity in each config gets the first commit with the fallback identity")
    func firstCommitWithNoIdentityAnywhereUsesFallback() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeEmptyRepo(named: "no-identity-repo", withIdentity: false)
        let home = try GitSandbox.makeFolder(named: Self.emptyHomeName, in: sandbox.root)
        await #expect(processExitsWith: .success) { [repo = repo as URL, home = home as URL] in
            BoardKeyTests.hideConfigOfUser(behind: home)
            let key = try? await BoardKey.read(fromRepoAt: repo)
            exit(key == nil ? EXIT_FAILURE : EXIT_SUCCESS)
        }
        #expect(try await Self.authorOfHead(in: repo) == Self.fallbackAuthor)
        #expect(try await BoardKey.read(fromRepoAt: repo) == sandbox.headKey(of: repo))
    }

    @Test("A repo with an identity in its config makes the first commit with that identity")
    func firstCommitUsesIdentityOfRepo() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeEmptyRepo(named: "identity-repo")
        _ = try await BoardKey.read(fromRepoAt: repo)
        #expect(try await Self.authorOfHead(in: repo) == "\(GitSandbox.userName) <\(GitSandbox.userEmail)>")
    }

    /// The name of the empty folder that is the home folder of the child process of the test with no git identity.
    static let emptyHomeName = "empty-home"

    /// The variables of the environment where libgit2 finds the config of the user: the home folder (`~/.gitconfig`)
    /// and the XDG config folder (`~/.config/git/config`).
    static let configOfUserVariables = ["HOME", "XDG_CONFIG_HOME"]

    /// The `overwrite` value of `setenv` that replaces a variable that exists.
    static let replaceVariable: Int32 = 1

    /// The author that the first commit has when no git config gives an identity: the full name of the macOS user
    /// (or the short name when the full name is empty), and an email from the short name.
    static var fallbackAuthor: String {
        let fullName = NSFullUserName()
        let name = fullName.isEmpty ? NSUserName() : fullName
        return "\(name) <\(NSUserName())@users.noreply.testudo.group>"
    }

    /// Points the config of the user for libgit2 to an empty folder, so libgit2 finds no global and no XDG config.
    /// The call is for the child process of an exit test only, before the first libgit2 call: libgit2 reads the
    /// variables one time, when it starts.
    ///
    /// - Parameter home: The empty folder.
    static func hideConfigOfUser(behind home: URL) {
        for variable in configOfUserVariables {
            setenv(variable, home.path, replaceVariable)
        }
    }

    /// Gives the author of the `HEAD` commit of a repo.
    ///
    /// - Parameter repo: The repo directory.
    /// - Returns: The author as `Name <email>`.
    /// - Throws: A ``GitProcessError`` when git cannot start, or an `ExpectationFailedError` when git fails.
    static func authorOfHead(in repo: URL) async throws -> String {
        try await GitSandbox.output(ofGit: ["log", "-1", "--format=%an <%ae>"], in: repo)
    }

    @Test("A read in a cancelled task throws cancelled")
    func readInCancelledTaskThrowsCancelled() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "cancelled-read")
        let read = Task {
            withUnsafeCurrentTask { task in task?.cancel() }
            return try await BoardKey.read(fromRepoAt: repo)
        }
        await #expect(throws: BoardKeyError.cancelled) { try await read.value }
    }

    @Test("A repo with an SSH origin and a repo with an HTTPS origin give the same key")
    func sshAndHTTPSOriginsGiveSameKey() async throws {
        let sandbox = try GitSandbox()
        let sshRepo = try await sandbox.makeRepo(named: "ssh-clone", origin: Self.sshRemote)
        let httpsRepo = try await sandbox.makeRepo(named: "https-clone", origin: Self.httpsRemote)
        #expect(try await BoardKey.read(fromRepoAt: sshRepo).description == Self.expectedKey)
        #expect(try await BoardKey.read(fromRepoAt: httpsRepo).description == Self.expectedKey)
    }

    @Test("A subfolder of a repo gives the key of the repo", arguments: subfolderOrigins)
    func subfolderGivesKeyOfRepo(origin: String?) async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "my-repo", origin: origin)
        let subfolder = try GitSandbox.makeFolder(named: Self.subfolderName, in: repo)
        #expect(try await BoardKey.read(fromRepoAt: subfolder) == BoardKey.read(fromRepoAt: repo))
    }

    @Test("A folder that is not in a git repo has no key: the read throws notARepo")
    func folderOutsideRepoThrowsNotARepo() async throws {
        let sandbox = try GitSandbox()
        let folder = try GitSandbox.makeFolder(named: Self.plainFolderName, in: sandbox.root)
        await #expect(throws: BoardKeyError.notARepo(path: folder.path)) {
            try await BoardKey.read(fromRepoAt: folder)
        }
    }

    // MARK: - Worktree top

    @Test("The worktree top of a subfolder of a repo is the top folder of the repo, with the path of the caller")
    func worktreeTopOfSubfolderIsRepo() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "my-repo")
        let subfolder = try GitSandbox.makeFolder(named: "\(Self.subfolderName)/Deep", in: repo)
        #expect(try await BoardKey.worktreeTop(of: subfolder).path == repo.standardizedFileURL.path)
    }

    @Test("The worktree top of a folder in a linked worktree is the top folder of that worktree")
    func worktreeTopOfLinkedWorktreeIsWorktree() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "main-clone")
        let worktree = try await sandbox.addWorktree(named: "feature-worktree", to: repo)
        let subfolder = try GitSandbox.makeFolder(named: Self.subfolderName, in: worktree)
        #expect(try await BoardKey.worktreeTop(of: subfolder).path == worktree.standardizedFileURL.path)
    }

    @Test("A folder that is not in a git repo has no worktree top: the read throws notARepo")
    func worktreeTopOutsideRepoThrowsNotARepo() async throws {
        let sandbox = try GitSandbox()
        let folder = try GitSandbox.makeFolder(named: Self.plainFolderName, in: sandbox.root)
        await #expect(throws: BoardKeyError.notARepo(path: folder.path)) {
            try await BoardKey.worktreeTop(of: folder)
        }
    }

    @Test("A repo whose git state cannot be read gets the key of a folder outside git: the read throws notARepo")
    func unreadableRepoThrowsNotARepo() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "broken-repo")
        let configFile = repo.appending(path: BoardKey.gitDirectoryName).appending(path: Self.gitConfigFileName)
        try Self.brokenConfigText.write(to: configFile, atomically: true, encoding: .utf8)
        await #expect(throws: BoardKeyError.notARepo(path: repo.path)) { try await BoardKey.read(fromRepoAt: repo) }
    }

    @Test("An origin with a host but no path gives local/<root commit>")
    func originWithoutPathGivesLocalKey() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "main-clone", origin: Self.pathlessOrigin)
        #expect(try await BoardKey.read(fromRepoAt: repo) == sandbox.headKey(of: repo))
    }

    @Test("An origin with no host gives local/<root commit>, also in a worktree", arguments: localOrigins)
    func originWithoutHostGivesLocalKey(origin: String) async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "main-clone", origin: origin)
        let worktree = try await sandbox.addWorktree(named: "feature-worktree", to: repo)
        let key = try await sandbox.headKey(of: repo)
        #expect(try await BoardKey.read(fromRepoAt: repo) == key)
        #expect(try await BoardKey.read(fromRepoAt: worktree) == key)
    }

    @Test("A worktree gives the same key as its main clone, with an origin")
    func worktreeWithOriginGivesKeyOfMainClone() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "main-clone", origin: Self.httpsRemote)
        let worktree = try await sandbox.addWorktree(named: "feature-worktree", to: repo)
        let worktreeKey = try await BoardKey.read(fromRepoAt: worktree)
        let mainCloneKey = try await BoardKey.read(fromRepoAt: repo)
        #expect(worktreeKey == mainCloneKey)
        #expect(worktreeKey.description == Self.expectedKey)
    }

    @Test("A worktree gives the same key as its main clone, with no remote")
    func worktreeWithoutRemoteGivesKeyOfMainClone() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "main-clone")
        let worktree = try await sandbox.addWorktree(named: "feature-worktree", to: repo)
        #expect(try await BoardKey.read(fromRepoAt: worktree) == sandbox.headKey(of: repo))
    }

    @Test("Each read gets the current origin, so a new remote gives a new key")
    func newOriginGivesNewKey() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "moved-repo", origin: Self.httpsRemote)
        let newOrigin = "git@gitlab.com:new-owner/moved-repo.git"
        try await GitSandbox.runGit(withArguments: ["remote", "set-url", "origin", newOrigin], in: repo)
        #expect(try await BoardKey.read(fromRepoAt: repo).description == "gitlab.com/new-owner/moved-repo")
    }

    // MARK: - Engine

    @Test("An engine in a repo whose origin has no host gives local/<root commit>", arguments: localOrigins)
    func engineWithLocalOriginGivesLocalKey(origin: String) async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "main-clone", origin: origin)
        let response = try await Self.keyResponse(ofEngineAt: repo)
        #expect(try await response == KanbanGraphTests.keyResponse(of: sandbox.headKey(of: repo)))
    }

    @Test("An engine in a new repo with no commit makes the first commit, and gives local/<root commit>")
    func engineInRepoWithoutCommitGivesRootCommitKey() async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeEmptyRepo(named: "new-repo")
        let response = try await Self.keyResponse(ofEngineAt: repo)
        #expect(try await response == KanbanGraphTests.keyResponse(of: sandbox.headKey(of: repo)))
    }

    @Test("An engine in a subfolder of a repo gives the key of the repo", arguments: subfolderOrigins)
    func engineInSubfolderGivesKeyOfRepo(origin: String?) async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "my-repo", origin: origin)
        let subfolder = try GitSandbox.makeFolder(named: Self.subfolderName, in: repo)
        let response = try await Self.keyResponse(ofEngineAt: subfolder)
        #expect(try await response == KanbanGraphTests.keyResponse(of: BoardKey.read(fromRepoAt: repo)))
    }

    @Test("The key of a board outside git before its first write is the board ID that the first write records")
    func engineOutsideRepoKeyIsRecordedBoardID() async throws {
        let sandbox = try GitSandbox()
        let folder = try GitSandbox.makeFolder(named: Self.plainFolderName, in: sandbox.root)
        let graph = try GitGraphFixture.makeGraph(at: folder)
        let key = try await KanbanGraphTests.execute(KanbanGraphTests.keyQuery, on: graph)
        try await CrossRepoUndoTests.runWithNoErrors(BoardIDTests.writeField, on: graph)
        await graph.close()
        let recorded = try BoardIDTests.boardID(inRepoAt: folder)
        #expect(key == KanbanGraphTests.keyResponse(of: BoardKey(boardID: try #require(ULID(ulidString: recorded)))))
        #expect(try await Self.keyResponse(ofEngineAt: folder) == key)
    }

    /// Runs ``KanbanGraphTests/keyQuery`` on an engine that reads the key from git, and closes the engine.
    ///
    /// - Parameter directory: The working directory of the engine.
    /// - Returns: The response JSON text.
    /// - Throws: An error when the engine cannot start or the query throws.
    private static func keyResponse(ofEngineAt directory: URL) async throws -> String {
        try await RepoBoardTests.respond(to: KanbanGraphTests.keyQuery, inWorkingDirectory: directory)
    }

    // MARK: - No git program

    /// The soft limit of the number of processes of the user in the child process of the test with no git program.
    /// With this limit, each start of a new process fails, so a read that starts `git` cannot read the key.
    static let noNewProcessLimit: rlim_t = 0

    @Test(
        "The key of a repo is read in a process that cannot start a child process, so the read runs no git program",
        arguments: subfolderOrigins
    )
    func keyIsReadWithNoGitProgram(origin: String?) async throws {
        let sandbox = try GitSandbox()
        let repo = try await sandbox.makeRepo(named: "no-git-program", origin: origin)
        let headKey = try await sandbox.headKey(of: repo)
        let expected = try origin.map(BoardKey.init(remoteURL:)) ?? headKey
        await #expect(processExitsWith: .success) {
            [repo = repo as URL, expected = expected.description as String] in
            BoardKeyTests.stopNewProcesses()
            let key = try? await BoardKey.read(fromRepoAt: repo)
            exit(key?.description == expected ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    /// Sets the soft limit of the number of processes of the user to ``noNewProcessLimit``. After this call, each
    /// start of a new process in this process fails. The call is for the child process of an exit test only.
    static func stopNewProcesses() {
        var limit = rlimit()
        getrlimit(RLIMIT_NPROC, &limit)
        limit.rlim_cur = noNewProcessLimit
        setrlimit(RLIMIT_NPROC, &limit)
    }
}

// MARK: - Temporary repos

/// A temporary directory that holds the git repos of one test. The directory is removed when the sandbox ends.
///
/// The sandbox is a class, because its `deinit` removes the directory.
final class GitSandbox {
    /// The name of the author of each commit that the sandbox makes.
    static let userName = "Board Key Tests"

    /// The email of the author of each commit that the sandbox makes.
    static let userEmail = "tests@example.invalid"

    /// The message of the one commit of each repo that ``makeRepo(named:origin:)`` makes.
    static let startCommitMessage = "Start"

    /// The local config of a repo that ``initializeRepo(at:withIdentity:)`` makes with an identity: the name and
    /// the email of the author, and no commit signatures, because the setup has no signing key.
    static let identityConfig = [
        ("user.name", userName),
        ("user.email", userEmail),
        ("commit.gpgsign", "false"),
    ]

    /// The time of each commit of ``commit(message:in:)`` and ``merge(_:in:)``. All commits have the same time, so
    /// `git rev-list` lists the parents of a merge in the order of the merge.
    static let fixedCommitDate = "2026-01-01T00:00:00Z"

    /// The variables that give each commit the time ``fixedCommitDate``.
    static let fixedDateVariables = ["GIT_AUTHOR_DATE": fixedCommitDate, "GIT_COMMITTER_DATE": fixedCommitDate]

    /// The temporary directory of the sandbox.
    let root: URL

    /// Makes an empty temporary directory in the folder of the ``TestFolderGroup/gitSandboxes`` group of the run folder
    /// of ``TestFolderRoot``.
    ///
    /// - Throws: An error from `FileManager` when the directory cannot be made.
    init() throws {
        let name = "BoardKeyTests-\(UUID().uuidString)"
        root = try TestFolderRoot.folder(of: .gitSandboxes).appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Makes a git repo with one commit in the sandbox.
    ///
    /// - Parameters:
    ///   - name: The name of the repo directory.
    ///   - origin: The URL of the `origin` remote, or `nil` for a repo with no remote.
    /// - Returns: The repo directory.
    /// - Throws: An error when the directory cannot be made, or when a git command cannot start or fails.
    func makeRepo(named name: String, origin: String? = nil) async throws -> URL {
        let repo = try await makeEmptyRepo(named: name)
        let commitArguments = ["commit", "--quiet", "--allow-empty", "-m", Self.startCommitMessage]
        try await Self.runGit(withArguments: commitArguments, in: repo)
        if let origin {
            try await Self.runGit(withArguments: ["remote", "add", "origin", origin], in: repo)
        }
        return repo
    }

    /// Makes an empty folder in a folder. The new folder is not a git repo.
    ///
    /// - Parameters:
    ///   - name: The name of the new folder.
    ///   - parent: The folder that holds the new folder.
    /// - Returns: The new folder.
    /// - Throws: An error from `FileManager` when the folder cannot be made.
    static func makeFolder(named name: String, in parent: URL) throws -> URL {
        let folder = parent.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Adds a worktree of a repo in the sandbox.
    ///
    /// - Parameters:
    ///   - name: The name of the worktree directory. It is also the name of the new branch.
    ///   - repo: The main clone.
    /// - Returns: The worktree directory.
    /// - Throws: An error when the git command cannot start or fails.
    func addWorktree(named name: String, to repo: URL) async throws -> URL {
        let worktree = root.appending(path: name, directoryHint: .isDirectory)
        try await Self.runGit(withArguments: ["worktree", "add", "--quiet", "-b", name, worktree.path], in: repo)
        return worktree
    }

    /// Runs a git command in a directory, and requires that it succeeds.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git`.
    ///   - directory: The directory where git runs.
    /// - Throws: A ``GitProcessError`` when git cannot start. An `ExpectationFailedError` when git exits with a failure
    ///   status.
    static func runGit(withArguments arguments: [String], in directory: URL) async throws {
        _ = try await output(ofGit: arguments, in: directory)
    }

    /// Runs a git command in a directory, requires that it succeeds, and gives its output.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git`.
    ///   - directory: The directory where git runs.
    ///   - environment: The environment of git, or `nil` for the environment of the test process.
    /// - Returns: The standard output of git, with no white space at the start and at the end.
    /// - Throws: A ``GitProcessError`` when git cannot start. An `ExpectationFailedError` when git exits with a failure
    ///   status.
    static func output(
        ofGit arguments: [String],
        in directory: URL,
        environment: [String: String]? = nil
    ) async throws -> String {
        let result = try await GitProcess.run(withArguments: arguments, inDirectory: directory, environment: environment)
        try #require(result.status == GitProcess.successStatus, "git \(arguments) failed: \(result.errorOutput)")
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Makes a git repo with no commit in the sandbox.
    ///
    /// - Parameters:
    ///   - name: The name of the repo directory.
    ///   - hasIdentity: `true` puts ``identityConfig`` in the config of the repo, so git can make a commit with no
    ///     global config. `false` gives a repo with no config of its own.
    /// - Returns: The repo directory.
    /// - Throws: An error when the directory cannot be made, or when a git command cannot start or fails.
    func makeEmptyRepo(named name: String, withIdentity hasIdentity: Bool = true) async throws -> URL {
        let repo = try Self.makeFolder(named: name, in: root)
        try await Self.initializeRepo(at: repo, withIdentity: hasIdentity)
        return repo
    }

    /// Runs `git init` in a folder, and puts the git identity in the config of the new repo. The repo has no commit.
    ///
    /// - Parameters:
    ///   - folder: The folder that becomes the repo. The folder must exist.
    ///   - hasIdentity: `true` puts ``identityConfig`` in the config of the repo, so git can make a commit with no
    ///     global config. `false` gives a repo with no config of its own.
    /// - Throws: A ``GitProcessError`` when git cannot start, or an `ExpectationFailedError` when git fails.
    static func initializeRepo(at folder: URL, withIdentity hasIdentity: Bool = true) async throws {
        try await runGit(withArguments: ["init", "--quiet"], in: folder)
        for (key, value) in identityConfig where hasIdentity {
            try await runGit(withArguments: ["config", key, value], in: folder)
        }
    }

    /// Makes an empty commit on the current branch of a repo, at ``fixedCommitDate``.
    ///
    /// - Parameters:
    ///   - message: The message of the commit.
    ///   - repo: The repo directory. Its config has ``identityConfig``.
    /// - Throws: A ``GitProcessError`` when git cannot start, or an `ExpectationFailedError` when git fails.
    func commit(message: String, in repo: URL) async throws {
        let arguments = ["commit", "--quiet", "--allow-empty", "-m", message]
        _ = try await Self.output(ofGit: arguments, in: repo, environment: Self.fixedDateEnvironment)
    }

    /// Merges a branch with an unrelated history into the current branch of a repo, at ``fixedCommitDate``.
    ///
    /// - Parameters:
    ///   - branch: The branch to merge.
    ///   - repo: The repo directory. Its config has ``identityConfig``.
    /// - Throws: A ``GitProcessError`` when git cannot start, or an `ExpectationFailedError` when git fails.
    func merge(_ branch: String, in repo: URL) async throws {
        let arguments = ["merge", "--quiet", "--no-edit", "--allow-unrelated-histories", branch]
        _ = try await Self.output(ofGit: arguments, in: repo, environment: Self.fixedDateEnvironment)
    }

    /// The environment of the test process, with the commit time ``fixedCommitDate``.
    static var fixedDateEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.merging(fixedDateVariables) { _, fixed in fixed }
    }

    /// Clones a repo into the sandbox. The `origin` of the clone is the path of the repo, which has no host.
    ///
    /// - Parameters:
    ///   - repo: The repo to clone.
    ///   - name: The name of the directory of the clone.
    /// - Returns: The directory of the clone.
    /// - Throws: A ``GitProcessError`` when git cannot start, or an `ExpectationFailedError` when git fails.
    func cloneRepo(_ repo: URL, named name: String) async throws -> URL {
        let clone = root.appending(path: name, directoryHint: .isDirectory)
        try await Self.runGit(withArguments: ["clone", "--quiet", repo.path, clone.path], in: root)
        return clone
    }

    /// Gives the root commit key of a repo whose `HEAD` commit is its one root commit.
    ///
    /// - Parameter repo: The repo directory.
    /// - Returns: The key `local/<first 12 hex digits of HEAD>`.
    /// - Throws: A ``GitProcessError`` when git cannot start, or an `ExpectationFailedError` when git fails.
    func headKey(of repo: URL) async throws -> BoardKey {
        BoardKey(rootCommit: try await Self.headSHA(of: repo))
    }

    /// Gives the SHA of the `HEAD` commit of a repo.
    ///
    /// - Parameter repo: The repo directory.
    /// - Returns: The full SHA of the commit that `HEAD` names.
    /// - Throws: A ``GitProcessError`` when git cannot start, or an `ExpectationFailedError` when git fails.
    static func headSHA(of repo: URL) async throws -> String {
        try await output(ofGit: ["rev-parse", "HEAD"], in: repo)
    }
}
